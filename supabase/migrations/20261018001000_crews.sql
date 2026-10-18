-- R11 Crews (docs/CREWS.md). A GAME MECHANIC: abstract job names and flavour only. Nothing here describes how any real crime is done,
-- and no real cult or gang name is used (a blocklist in Settings -> Crews keeps real names out of crew names and tags).
--   1. Settings `crew.*` (game_config, Settings -> Crews).
--   2. crews, crew_members (Boss / Lieutenant / Member / Prospect), crew_invites, crew_bank_log, crew_cooldowns (rejoin), crew_messages
--      (the crew chat: there is no group-chat concept in Messages, "Groups" there is place chat), crew_reports.
--   3. crew_levels + crew_jobs (admin tables, Content -> Crew levels / Crew jobs): the crew's XP comes from paid jobs, a Boss or Lieutenant
--      pays the level's cost from the crew bank to level up (more members, better jobs, a loot bonus).
--   4. Jobs: crew_runs + crew_run_members. A Boss / Lieutenant opens a lobby, online members standing at a meeting spot (Settings) join, it
--      runs when ready (or when the countdown ends) and rolls ONCE. Members' skills (the job's skills) lower the caught chance. Caught = every
--      participant gets a jail case through the existing jail flow (jail_cases: bail, go to jail, escape) and the crew bank pays a fine.
--      Paid = the pot (reward range x level bonus x member bonus) splits into the crew bank (the Boss's %, default 30) and the members' cash.
--      Crew jobs never take money from another player.
--   5. Weekly "Top crews" (jobs done, loot): the first call after a week closes settles it; prizes go to the crew bank. Ranks app tab.
--   6. Crew tag shows next to names: players_here (places), get_public_profile (profiles), bl_chat_row + a trigger (chat), bl_friend_card.
--   7. Ledger: crew_deposit, crew_fee, crew_job (supplies), crew_refund are NOT earned; crew_payout (the loot share) IS earned
--      (added once to leaderboard.earn_reasons). Crew bank money is not a player ledger line, it is crew_bank_log.
--   8. Admin: Crews list (member view is audited), disband, rename; Content tabs; Settings.
-- Idempotent and safe on a non-empty DB: tables `if not exists`, seeds `on conflict do nothing` (admin edits survive), functions
-- `create or replace`, live functions patched ONLY through a guarded replace on pg_get_functiondef (raises when the marker is missing,
-- skips when already applied; create or replace keeps the grants). Private bl_* helpers are revoked from anon / authenticated.

create or replace function pg_temp.bl_patch1(p_sig text, p_done text, p_marker text, p_new text) returns void
language plpgsql as $$
declare v_def text; v_n int;
begin
  select pg_get_functiondef(p_sig::regprocedure) into v_def;
  if position(p_done in v_def) > 0 then return; end if;
  v_n := (length(v_def) - length(replace(v_def, p_marker, ''))) / length(p_marker);
  if v_n = 0 then raise exception '% : marker not found: %', p_sig, p_marker; end if;
  if v_n > 1 then raise exception '% : marker not unique (% times): %', p_sig, v_n, p_marker; end if;
  execute replace(v_def, p_marker, p_new);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 1. Settings
-- ---------------------------------------------------------------------------------------------
insert into public.game_config (key, value, category, label, description, kind, min, max) values
('crew.enabled', 'true', 'crews', 'Crews on',
 'R11 (docs/CREWS.md): players can found and join crews and run crew jobs. Off = founding, joining, inviting and new jobs are refused (running jobs still finish; leaving and chat still work).', 'bool', null, null),
('crew.found_fee', '500000', 'crews', 'Founding fee',
 'R11: what it costs to found a crew (bank first, then cash). Ledger crew_fee.', 'naira', 0, 1000000000),
('crew.found_min_charisma', '2', 'crews', 'Founder needs Charisma level',
 'R11: a founder needs this Charisma level OR the account age below (either one is enough). 0 or 1 = no skill rule. Needs Settings -> skills.enabled.', 'number', 0, 10),
('crew.found_min_account_hours', '72', 'crews', 'Founder needs account age (hours)',
 'R11: a founder needs this Charisma level (above) OR an account at least this many real hours old. 0 = anybody can found.', 'number', 0, 100000),
('crew.join_min_account_hours', '24', 'crews', 'Joining needs account age (hours)',
 'R11: anti-abuse: accounts younger than this cannot join a crew or be invited (a founder is covered by the rule above).', 'number', 0, 100000),
('crew.rejoin_cooldown_hours', '48', 'crews', 'Rejoin cooldown (hours)',
 'R11: after leaving or being kicked, a player cannot join or found any crew for this long.', 'number', 0, 8760),
('crew.invite_expire_hours', '48', 'crews', 'Invite lasts (hours)', 'R11: an unanswered invite expires after this long.', 'number', 1, 720),
('crew.invite_daily_cap', '20', 'crews', 'Invites per crew per day', 'R11: rate limit on invites sent by one crew in 24 real hours.', 'number', 1, 500),
('crew.max_lieutenants', '3', 'crews', 'Most Lieutenants per crew', 'R11: the Boss can promote this many Lieutenants.', 'number', 0, 20),
('crew.new_member_rank', '"prospect"', 'crews', 'Rank new recruits start at', 'R11: prospect (on trial, smaller share) or member. The Boss and Lieutenants promote Prospects.', 'text', null, null),
('crew.default_bank_pct', '30', 'crews', 'Default bank share of loot (%)', 'R11: a new crew puts this % of every payout into the crew bank. The Boss can change it inside the limits below.', 'percent', 0, 100),
('crew.bank_pct_min', '10', 'crews', 'Lowest bank share the Boss can set (%)', 'R11: so a crew always funds its bank a little.', 'percent', 0, 100),
('crew.bank_pct_max', '80', 'crews', 'Highest bank share the Boss can set (%)', 'R11: so members always get a real cut.', 'percent', 0, 100),
('crew.prospect_share_pct', '50', 'crews', 'Prospect share of a payout (%)', 'R11: a Prospect (on trial) takes this % of an ordinary member''s share. The rest goes to the others.', 'percent', 0, 100),
('crew.min_deposit', '1000', 'crews', 'Smallest bank deposit', 'R11: the least a member can put into the crew bank at once.', 'naira', 1, 1000000000),
('crew.rename_fee', '100000', 'crews', 'Rename fee (paid from the crew bank)', 'R11: the Boss renames the crew once per cooldown; the crew bank pays this.', 'naira', 0, 1000000000),
('crew.rename_cooldown_days', '7', 'crews', 'Rename cooldown (days)', 'R11: the least time between two renames.', 'number', 0, 365),
('crew.meeting_places', '"upper_sakponba,third_east,siluko_rd"', 'crews', 'Meeting spots (place ids)',
 'R11: comma-separated place ids where members must stand to join a crew job (default three street corners, no CCTV). A crew hideout was not built: crews meet at a public place.', 'text', null, null),
('crew.lobby_seconds', '120', 'crews', 'Job lobby countdown (seconds)', 'R11: how long a lobby waits for members before the job starts (or is cancelled when too few joined).', 'number', 10, 3600),
('crew.max_jobs_per_day', '8', 'crews', 'Jobs per crew per day', 'R11: rate limit: jobs one crew can start in 24 real hours (on top of each job''s own cooldown).', 'number', 1, 200),
('crew.member_bonus_pct', '8', 'crews', 'Pot: + % per extra member', 'R11: the pot grows by this % for every member after the first (5 members and 8 = pot x 1.32).', 'percent', 0, 500),
('crew.skill_cut_per_level', '1.5', 'crews', 'Skill cut: % per average level above 1', 'R11: the crew''s caught chance falls by this % (relative) for every average level above 1 of the job''s skills across the crew.', 'number', 0, 20),
('crew.skill_cut_cap', '30', 'crews', 'Skill cut: most (%)', 'R11: the skills can never cut the caught chance by more than this %.', 'percent', 0, 100),
('crew.jail_seconds', '120', 'crews', 'Jail time after a busted job (seconds)', 'R11: the cell time every participant gets (the normal jail flow: bail, go to jail or escape).', 'number', 5, 86400),
('crew.bail_base', '20000000', 'crews', 'Bail after a busted job', 'R11: the bail on every participant''s jail case (escape attempts double it as usual).', 'naira', 0, 100000000000),
('crew.bust_fine_pct', '15', 'crews', 'Busted job: crew bank fine (%)', 'R11: part of the crew bank is lost to legal fees when a job is busted.', 'percent', 0, 100),
('crew.bust_fine_max', '2000000', 'crews', 'Busted job: biggest fine', 'R11: the fine never goes above this.', 'naira', 0, 100000000000),
('crew.chat_max_len', '300', 'crews', 'Crew chat: longest message', 'R11: characters.', 'number', 20, 2000),
('crew.chat_rate_seconds', '2', 'crews', 'Crew chat: seconds between messages', 'R11: rate limit per player.', 'number', 0, 60),
('crew.chat_burst_per_minute', '20', 'crews', 'Crew chat: messages per minute', 'R11: rate limit per player.', 'number', 1, 600),
('crew.chat_retention_hours', '168', 'crews', 'Crew chat: keep messages (hours)', 'R11: older messages are deleted a few at a time.', 'number', 1, 8760),
('crew.report_flag_count', '3', 'crews', 'Reports that flag a crew', 'R11: a crew with this many open reports is highlighted in Admin -> Crews.', 'number', 1, 100),
('crew.blocked_names', '"eiye,black axe,blackaxe,aiye,ayee,neo black,maphite,buccaneer,vikings,icelander,mafia,cult"', 'crews', 'Blocked words in crew names',
 'R11: comma-separated. Real cult and gang names must never be used, so a crew name that contains any of these (ignoring spaces and punctuation) is refused. Add more as you hear them.', 'text', null, null),
('crew.blocked_tags', '"NBM,BAX,EIYE,AIYE,CULT"', 'crews', 'Blocked tags', 'R11: comma-separated, 3 or 4 letters. A crew tag in this list is refused.', 'text', null, null),
('crew.emblems', '"🦁,🐺,🦈,🐆,🦊,🐘,🔥,💎,👑,⚡,🌙,⭐,🚀,🎯,🍀,🌴"', 'crews', 'Emblems players can pick', 'R11: comma-separated emoji. Anything else is refused. Keep real cult symbols out.', 'text', null, null),
('crew.weekly_enabled', 'true', 'crews', 'Top crews weekly prize on', 'R11: the Ranks -> Top crews board and the weekly prizes (paid into the crew bank when the week closes, Monday 00:00 Benin time).', 'bool', null, null),
('crew.weekly_prize_1', '500000', 'crews', 'Top crews prize: 1st', 'R11: paid into the winning crew''s bank.', 'naira', 0, 1000000000),
('crew.weekly_prize_2', '250000', 'crews', 'Top crews prize: 2nd', 'R11: paid into the crew bank.', 'naira', 0, 1000000000),
('crew.weekly_prize_3', '100000', 'crews', 'Top crews prize: 3rd', 'R11: paid into the crew bank.', 'naira', 0, 1000000000),
('crew.weekly_min_jobs', '2', 'crews', 'Jobs a crew needs for a prize', 'R11: a crew needs at least this many paid jobs in the week to take a prize.', 'number', 0, 1000)
on conflict (key) do nothing;

-- crew_payout (the loot share) is earned money (weekly top earners, challenge "earn"). Deposits, fees, supplies and refunds are not.
-- Added once: an admin who removes it later stays removed.
do $$
begin
  if not exists (select 1 from public.game_config where key = 'crew.earn_seeded') then
    update public.game_config
       set value = to_jsonb(rtrim((value #>> '{}'), ',') || ',crew_payout')
     where key = 'leaderboard.earn_reasons' and position('crew_payout' in (value #>> '{}')) = 0;
    insert into public.game_config (key, value, category, label, description, kind)
    values ('crew.earn_seeded', 'true', 'crews', 'Crew loot counted as earned (seeded)',
            'R11: set once by the migration so crew_payout is in leaderboard.earn_reasons. Leave it.', 'bool');
  end if;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 2. Tables
-- ---------------------------------------------------------------------------------------------
create table if not exists public.crew_levels (
  level        int primary key check (level >= 1 and level <= 20),
  name         text not null,
  xp_needed    bigint not null default 0 check (xp_needed >= 0),          -- crew XP needed to be allowed to reach this level
  upgrade_cost bigint not null default 0 check (upgrade_cost >= 0),       -- paid from the crew bank to reach this level
  max_members  int not null default 6 check (max_members between 1 and 100),
  bonus_pct    numeric not null default 0 check (bonus_pct >= 0),         -- extra loot on every pot at this level
  perks        text not null default ''
);
insert into public.crew_levels (level, name, xp_needed, upgrade_cost, max_members, bonus_pct, perks) values
(1, 'Street crew',   0,       0,        6,  0,  'Starter jobs. Up to 6 members.'),
(2, 'Block crew',    100,     1000000,  10, 5,  'Port and warehouse jobs. 10 members. +5% loot.'),
(3, 'District crew', 300,     3000000,  15, 10, '15 members. +10% loot.'),
(4, 'City crew',     700,     8000000,  20, 15, 'The bank van job. 20 members. +15% loot.'),
(5, 'Big name crew', 1500,    20000000, 30, 20, '30 members. +20% loot. Everybody sabi una.')
on conflict (level) do nothing;

create table if not exists public.crew_jobs (
  id               text primary key,
  name             text not null,
  icon             text not null default '💼',
  blurb            text not null default '',
  min_members      int not null default 2 check (min_members between 1 and 30),
  max_members      int not null default 4 check (max_members between 1 and 30),
  min_crew_level   int not null default 1 check (min_crew_level between 1 and 20),
  duration_seconds int not null default 90 check (duration_seconds between 1 and 3600),
  reward_min       bigint not null default 0 check (reward_min >= 0),     -- the whole pot, before the bonuses
  reward_max       bigint not null default 0 check (reward_max >= 0),
  caught_pct       numeric not null default 25 check (caught_pct between 0 and 100),
  cooldown_seconds int not null default 1200 check (cooldown_seconds between 0 and 2592000),   -- per crew
  buy_in           bigint not null default 0 check (buy_in >= 0),         -- supplies: each participant pays it when the job starts (lost if busted)
  skills           text[] not null default '{}',                          -- skill ids whose average level cuts the chance
  xp               int not null default 20 check (xp >= 0),               -- crew XP for a paid job
  sort             int not null default 0,
  active           boolean not null default true
);
insert into public.crew_jobs (id, name, icon, blurb, min_members, max_members, min_crew_level, duration_seconds, reward_min, reward_max, caught_pct, cooldown_seconds, buy_in, skills, xp, sort) values
('market_shakedown', 'Night market shakedown', '🌙', 'Easy rounds after the stalls close. Look fierce, collect "dues" and go. Starter job.', 2, 4, 1, 60, 300000, 900000, 22, 1200, 0, '{charisma}', 20, 1),
('port_container', 'Hit a container at the port', '🚢', 'One container, one night, one big crew. Everybody must show face.', 3, 5, 2, 90, 1200000, 3500000, 30, 2700, 20000, '{fitness,driving}', 40, 2),
('ring_road_warehouse', 'Ring Road warehouse job', '🏭', 'A warehouse on Ring Road with more stock than guards.', 3, 6, 2, 90, 2000000, 5000000, 32, 3600, 30000, '{fitness,charisma}', 50, 3),
('bank_van', 'Bank van job', '🚐', 'The big one. Drivers, muscle and a smooth talker. Police will not play.', 4, 8, 4, 150, 8000000, 25000000, 40, 10800, 100000, '{driving,fitness,charisma}', 120, 4)
on conflict (id) do nothing;

-- skill XP for crew jobs (kind 'crew'): every participant of a PAID job
do $$
declare r record;
begin
  for r in select c.conname from pg_constraint c
            where c.contype = 'c' and c.conrelid = 'public.skill_sources'::regclass
              and pg_get_constraintdef(c.oid) like '%hustle%' and pg_get_constraintdef(c.oid) not like '%crew%' loop
    execute format('alter table public.skill_sources drop constraint %I', r.conname);
    alter table public.skill_sources add constraint skill_sources_kind_check check (kind in ('hustle', 'yahoo', 'career', 'activity', 'crew'));
  end loop;
end $$;
insert into public.skill_sources (id, kind, ref, skill_id, xp, note) values
('crew:market_shakedown:charisma', 'crew', 'market_shakedown', 'charisma', 5, 'Night market shakedown (crew job)'),
('crew:port_container:fitness', 'crew', 'port_container', 'fitness', 6, 'Port container (crew job)'),
('crew:port_container:driving', 'crew', 'port_container', 'driving', 4, 'Port container (crew job)'),
('crew:ring_road_warehouse:fitness', 'crew', 'ring_road_warehouse', 'fitness', 5, 'Ring Road warehouse (crew job)'),
('crew:ring_road_warehouse:charisma', 'crew', 'ring_road_warehouse', 'charisma', 5, 'Ring Road warehouse (crew job)'),
('crew:bank_van:driving', 'crew', 'bank_van', 'driving', 10, 'Bank van job (crew job)'),
('crew:bank_van:fitness', 'crew', 'bank_van', 'fitness', 6, 'Bank van job (crew job)'),
('crew:bank_van:charisma', 'crew', 'bank_van', 'charisma', 6, 'Bank van job (crew job)')
on conflict (id) do nothing;

create table if not exists public.crews (
  id              bigserial primary key,
  name            text not null,
  tag             text not null,
  color           text not null default '#c9a227',
  emblem          text not null default '🦁',
  level           int not null default 1 check (level >= 1),
  xp              bigint not null default 0 check (xp >= 0),
  bank            bigint not null default 0 check (bank >= 0),
  split_bank_pct  numeric not null default 30 check (split_bank_pct between 0 and 100),
  recruiting      boolean not null default false,
  jobs_done       int not null default 0,
  jobs_caught     int not null default 0,
  loot_total      bigint not null default 0,
  renamed_at      timestamptz,
  created_by      uuid references public.profiles(id) on delete set null,
  created_at      timestamptz not null default now(),
  disbanded_at    timestamptz,
  disbanded_reason text
);
create unique index if not exists crews_name_uq on public.crews (lower(name)) where disbanded_at is null;
create unique index if not exists crews_tag_uq on public.crews (upper(tag)) where disbanded_at is null;
create index if not exists crews_active_idx on public.crews (level desc, id) where disbanded_at is null;
create index if not exists crews_created_by_idx on public.crews (created_by) where created_by is not null;

create table if not exists public.crew_members (
  user_id    uuid primary key references public.profiles(id) on delete cascade,
  crew_id    bigint not null references public.crews(id) on delete cascade,
  rank       text not null default 'prospect' check (rank in ('boss', 'lieutenant', 'member', 'prospect')),
  joined_at  timestamptz not null default now(),
  deposited  bigint not null default 0,
  jobs       int not null default 0,
  earned     bigint not null default 0
);
create index if not exists crew_members_crew_idx on public.crew_members (crew_id);
create unique index if not exists crew_members_one_boss on public.crew_members (crew_id) where rank = 'boss';

create table if not exists public.crew_invites (
  id         bigserial primary key,
  crew_id    bigint not null references public.crews(id) on delete cascade,
  to_user    uuid not null references public.profiles(id) on delete cascade,
  from_user  uuid references public.profiles(id) on delete set null,
  status     text not null default 'pending' check (status in ('pending', 'accepted', 'declined', 'cancelled', 'expired')),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null
);
create unique index if not exists crew_invites_pending_uq on public.crew_invites (crew_id, to_user) where status = 'pending';
create index if not exists crew_invites_to_idx on public.crew_invites (to_user, id desc) where status = 'pending';
create index if not exists crew_invites_crew_idx on public.crew_invites (crew_id, created_at desc);
create index if not exists crew_invites_from_idx on public.crew_invites (from_user) where from_user is not null;

create table if not exists public.crew_bank_log (
  id            bigserial primary key,
  crew_id       bigint not null references public.crews(id) on delete cascade,
  user_id       uuid references public.profiles(id) on delete set null,
  kind          text not null,                -- deposit, upgrade, job, fine, prize, fee, refund
  amount        bigint not null,              -- signed: + into the bank, - out of it
  balance_after bigint not null,
  note          text not null default '',
  created_at    timestamptz not null default now()
);
create index if not exists crew_bank_log_crew_idx on public.crew_bank_log (crew_id, id desc);
create index if not exists crew_bank_log_user_idx on public.crew_bank_log (user_id) where user_id is not null;

create table if not exists public.crew_cooldowns (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  until   timestamptz not null,
  reason  text not null default 'left'
);

create table if not exists public.crew_messages (
  id         bigserial primary key,
  crew_id    bigint not null references public.crews(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  username   text not null,
  body       text not null check (char_length(body) between 1 and 2000),
  created_at timestamptz not null default now()
);
create index if not exists crew_messages_crew_idx on public.crew_messages (crew_id, id desc);
create index if not exists crew_messages_user_idx on public.crew_messages (user_id, created_at desc);

create table if not exists public.crew_reports (
  id          bigserial primary key,
  crew_id     bigint not null references public.crews(id) on delete cascade,
  reporter_id uuid references public.profiles(id) on delete set null,
  reason      text not null default '',
  status      text not null default 'open' check (status in ('open', 'reviewed')),
  created_at  timestamptz not null default now()
);
create unique index if not exists crew_reports_once_uq on public.crew_reports (crew_id, reporter_id) where reporter_id is not null;
create index if not exists crew_reports_open_idx on public.crew_reports (crew_id) where status = 'open';

create table if not exists public.crew_runs (
  id             bigserial primary key,
  crew_id        bigint not null references public.crews(id) on delete cascade,
  job_id         text not null references public.crew_jobs(id) on update cascade,
  job_name       text,
  started_by     uuid references public.profiles(id) on delete set null,
  status         text not null default 'lobby' check (status in ('lobby', 'running', 'paid', 'caught', 'cancelled')),
  created_at     timestamptz not null default now(),
  lobby_until    timestamptz not null,
  started_at     timestamptz,
  resolve_at     timestamptz,
  resolved_at    timestamptz,
  base_pct       numeric,                       -- the job's own caught %
  caught_pct     numeric,                       -- after the skill cut, fixed when it starts
  skill_cut_pct  numeric not null default 0,
  member_count   int not null default 0,
  split_bank_pct numeric,
  pot            bigint not null default 0,
  bank_share     bigint not null default 0,
  fine           bigint not null default 0,     -- crew bank fine when busted
  note           text
);
create index if not exists crew_runs_crew_idx on public.crew_runs (crew_id, id desc);
create index if not exists crew_runs_open_idx on public.crew_runs (status) where status in ('lobby', 'running');
create index if not exists crew_runs_week_idx on public.crew_runs (resolved_at) where status = 'paid';
create index if not exists crew_runs_job_idx on public.crew_runs (job_id);
create index if not exists crew_runs_started_by_idx on public.crew_runs (started_by) where started_by is not null;

create table if not exists public.crew_run_members (
  run_id      bigint not null references public.crew_runs(id) on delete cascade,
  user_id     uuid not null references public.profiles(id) on delete cascade,
  rank        text,
  joined_at   timestamptz not null default now(),
  buy_in      bigint not null default 0,
  payout      bigint not null default 0,
  jail_case   bigint,
  primary key (run_id, user_id)
);
create index if not exists crew_run_members_user_idx on public.crew_run_members (user_id, run_id desc);

create table if not exists public.crew_weeks (
  week_start  date primary key,
  settled_at  timestamptz not null default now(),
  skipped     boolean not null default false
);
create table if not exists public.crew_week_winners (
  week_start date not null,
  rank       int not null,
  crew_id    bigint references public.crews(id) on delete set null,
  crew_name  text not null,
  tag        text not null,
  jobs       int not null default 0,
  loot       bigint not null default 0,
  prize      bigint not null default 0,
  primary key (week_start, rank)
);
create index if not exists crew_week_winners_crew_idx on public.crew_week_winners (crew_id) where crew_id is not null;

-- the crew tag in chat: stamped on every chat message when it is written (realtime rows carry it too)
alter table public.chat_messages add column if not exists crew_tag text;

alter table public.crew_levels enable row level security;
alter table public.crew_jobs enable row level security;
alter table public.crews enable row level security;
alter table public.crew_members enable row level security;
alter table public.crew_invites enable row level security;
alter table public.crew_bank_log enable row level security;
alter table public.crew_cooldowns enable row level security;
alter table public.crew_messages enable row level security;
alter table public.crew_reports enable row level security;
alter table public.crew_runs enable row level security;
alter table public.crew_run_members enable row level security;
alter table public.crew_weeks enable row level security;
alter table public.crew_week_winners enable row level security;
revoke all on table public.crew_levels, public.crew_jobs, public.crews, public.crew_members, public.crew_invites, public.crew_bank_log,
  public.crew_cooldowns, public.crew_messages, public.crew_reports, public.crew_runs, public.crew_run_members, public.crew_weeks,
  public.crew_week_winners from public, anon, authenticated;
revoke all on sequence public.crews_id_seq, public.crew_invites_id_seq, public.crew_bank_log_id_seq, public.crew_messages_id_seq,
  public.crew_reports_id_seq, public.crew_runs_id_seq from public, anon, authenticated;
-- the two catalogues are read by signed-in players (admins write through admin_row_upsert); everything else is server-only
grant select on table public.crew_levels, public.crew_jobs to authenticated;
drop policy if exists crew_levels_read on public.crew_levels;
create policy crew_levels_read on public.crew_levels for select to authenticated using (true);
drop policy if exists crew_jobs_read on public.crew_jobs;
create policy crew_jobs_read on public.crew_jobs for select to authenticated using (true);

-- the week the feature started: the week that just closed is not paid retroactively
insert into public.crew_weeks (week_start, settled_at, skipped)
select public.bl_week_start() - 7, now(), true
 where not exists (select 1 from public.crew_weeks)
on conflict (week_start) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 3. Private helpers
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_crew_num(p_key text, p_default numeric) returns numeric
language sql stable set search_path = public as $$
  select coalesce((select (value #>> '{}')::numeric from game_config where key = p_key), p_default);
$$;

create or replace function public.bl_crew_text(p_key text, p_default text) returns text
language sql stable set search_path = public as $$
  select coalesce((select value #>> '{}' from game_config where key = p_key), p_default);
$$;

create or replace function public.bl_crew_on() returns boolean
language sql stable set search_path = public as $$
  select coalesce((select (value #>> '{}')::boolean from game_config where key = 'crew.enabled'), true);
$$;

-- a comma-separated setting as a clean array
create or replace function public.bl_crew_list(p_key text, p_default text) returns text[]
language sql stable set search_path = public as $$
  select coalesce(array(select btrim(x) from unnest(string_to_array(bl_crew_text(p_key, p_default), ',')) x where btrim(x) <> ''), '{}');
$$;

-- rank ladder: boss 3, lieutenant 2, member 1, prospect 0
create or replace function public.bl_crew_rank_n(p_rank text) returns int
language sql immutable set search_path = public as $$
  select case p_rank when 'boss' then 3 when 'lieutenant' then 2 when 'member' then 1 else 0 end;
$$;

-- the tag, colour and emblem shown next to a name (null when the player has no crew)
create or replace function public.bl_crew_badge(p_uid uuid) returns jsonb
language sql stable set search_path = public as $$
  select jsonb_build_object('tag', c.tag, 'color', c.color, 'emblem', c.emblem, 'name', c.name)
    from crew_members m join crews c on c.id = m.crew_id
   where m.user_id = p_uid and c.disbanded_at is null;
$$;

-- stamp the crew tag on a chat message when it is written
create or replace function public.bl_crew_chat_tag() returns trigger
language plpgsql set search_path = public as $$
begin
  new.crew_tag := (select c.tag from crew_members m join crews c on c.id = m.crew_id where m.user_id = new.user_id and c.disbanded_at is null);
  return new;
end $$;
drop trigger if exists bl_crew_chat_tag_trg on public.chat_messages;
create trigger bl_crew_chat_tag_trg before insert on public.chat_messages for each row execute function public.bl_crew_chat_tag();

-- a crew bank line: + into the bank, - out of it. The bank can never go below 0.
create or replace function public.bl_crew_bank(p_crew bigint, p_user uuid, p_delta bigint, p_kind text, p_note text) returns bigint
language plpgsql set search_path = public as $$
declare v_bal bigint;
begin
  update crews set bank = bank + p_delta where id = p_crew and bank + p_delta >= 0 returning bank into v_bal;
  if not found then
    raise exception 'The crew bank no reach for that.' using errcode = 'P0001', hint = 'bank_short';
  end if;
  if p_delta <> 0 then
    insert into crew_bank_log (crew_id, user_id, kind, amount, balance_after, note, created_at)
    values (p_crew, p_user, p_kind, p_delta, v_bal, coalesce(p_note, ''), bl_now());
  end if;
  return v_bal;
end $$;

-- a player pays the system: bank first, then cash (the same rule as every other purchase)
create or replace function public.bl_crew_pay(p_uid uuid, p_amount bigint, p_reason text, p_meta jsonb) returns void
language plpgsql set search_path = public as $$
declare v_bank bigint; v_cash bigint; v_now profiles;
begin
  if p_amount <= 0 then return; end if;
  select * into v_now from profiles where id = p_uid;
  if v_now.cash + greatest(v_now.bank, 0) < p_amount then
    raise exception 'Not enough money. This costs % and you have % (bank % + cash %).', bl_naira(p_amount),
      bl_naira(v_now.cash + greatest(v_now.bank, 0)), bl_naira(greatest(v_now.bank, 0)), bl_naira(v_now.cash)
      using errcode = 'P0001', hint = 'not_enough_cash';
  end if;
  v_bank := least(greatest(v_now.bank, 0), p_amount);
  v_cash := p_amount - v_bank;
  if v_bank > 0 then perform bl_add_money(p_uid, 'bank', -v_bank, p_reason, p_meta); end if;
  if v_cash > 0 then perform bl_add_money(p_uid, 'cash', -v_cash, p_reason, p_meta); end if;
end $$;

-- alert every member (and optionally a push in the friends category)
create or replace function public.bl_crew_notify(p_crew bigint, p_except uuid, p_kind text, p_title text, p_body text, p_push boolean, p_data jsonb default '{}'::jsonb) returns void
language plpgsql set search_path = public as $$
declare r record;
begin
  for r in select user_id from crew_members where crew_id = p_crew and user_id is distinct from p_except order by user_id loop
    perform bl_event(r.user_id, p_kind, p_title, p_body, coalesce(p_data, '{}'::jsonb) || jsonb_build_object('crew', p_crew));
    if p_push then
      perform bl_push_enqueue(r.user_id, 'friends', p_kind, p_title, p_body, '/play?go=crew', p_except);
    end if;
  end loop;
end $$;

-- A rejoin cooldown after leaving or being kicked
create or replace function public.bl_crew_cool_left(p_uid uuid) returns timestamptz
language sql stable set search_path = public as $$
  select case when c.until > bl_now() then c.until end from crew_cooldowns c where c.user_id = p_uid;
$$;

-- Lazy invite expiry: a few at a time, no cron
create or replace function public.bl_crew_expire_invites() returns void
language sql set search_path = public as $$
  update crew_invites set status = 'expired' where id in (select id from crew_invites where status = 'pending' and expires_at <= bl_now() limit 200);
$$;

-- Validate a name and a tag (no write). {ok, name, tag, hint, message}. p_exclude = the crew being renamed (its own name is fine).
create or replace function public.bl_crew_name_check(p_name text, p_tag text, p_exclude bigint default null) returns jsonb
language plpgsql stable set search_path = public as $$
declare
  v_name text := bl_chat_clean(coalesce(p_name, ''));
  v_tag  text := upper(btrim(coalesce(p_tag, '')));
  v_norm text := regexp_replace(lower(v_name), '[^a-z0-9]', '', 'g');
  w      text;
begin
  if p_name is not null then
    if char_length(v_name) < 3 or char_length(v_name) > 20 or v_name !~ '^[A-Za-z0-9][A-Za-z0-9 ''\-]*[A-Za-z0-9]$' then
      return jsonb_build_object('ok', false, 'hint', 'bad_name', 'message', 'Crew name must be 3 to 20 letters or numbers.');
    end if;
    if bl_chat_mask(v_name) <> v_name then
      return jsonb_build_object('ok', false, 'hint', 'bad_name', 'message', 'Choose a cleaner name for your crew.');
    end if;
    foreach w in array bl_crew_list('crew.blocked_names', '') loop
      if regexp_replace(lower(w), '[^a-z0-9]', '', 'g') <> '' and position(regexp_replace(lower(w), '[^a-z0-9]', '', 'g') in v_norm) > 0 then
        return jsonb_build_object('ok', false, 'hint', 'blocked_name', 'message', 'That name no fit. Real groups are not allowed here. Choose another one.');
      end if;
    end loop;
    if exists (select 1 from crews c where lower(c.name) = lower(v_name) and c.disbanded_at is null and c.id is distinct from p_exclude) then
      return jsonb_build_object('ok', false, 'hint', 'name_taken', 'message', 'Another crew already uses that name.');
    end if;
  end if;
  if p_tag is not null then
    if v_tag !~ '^[A-Z]{3,4}$' then
      return jsonb_build_object('ok', false, 'hint', 'bad_tag', 'message', 'The tag must be 3 or 4 letters.');
    end if;
    if bl_chat_mask(lower(v_tag)) <> lower(v_tag) or v_tag = any (array(select upper(x) from unnest(bl_crew_list('crew.blocked_tags', '')) x)) then
      return jsonb_build_object('ok', false, 'hint', 'blocked_tag', 'message', 'That tag no fit. Choose another one.');
    end if;
    if exists (select 1 from crews c where upper(c.tag) = v_tag and c.disbanded_at is null and c.id is distinct from p_exclude) then
      return jsonb_build_object('ok', false, 'hint', 'tag_taken', 'message', 'Another crew already uses that tag.');
    end if;
  end if;
  return jsonb_build_object('ok', true, 'name', case when p_name is not null then v_name end, 'tag', case when p_tag is not null then v_tag end);
end $$;

-- Can this player found a crew? null = yes, else {hint, message}
create or replace function public.bl_crew_found_gate(p_uid uuid) returns jsonb
language plpgsql stable set search_path = public as $$
declare
  p profiles; v_cool timestamptz; v_hours numeric := bl_crew_num('crew.found_min_account_hours', 72); v_ch int := bl_crew_num('crew.found_min_charisma', 2)::int;
  v_age numeric; v_lvl int;
begin
  select * into p from profiles where id = p_uid;
  if not found then return jsonb_build_object('hint', 'no_profile', 'message', 'Create your Sim first.'); end if;
  if exists (select 1 from crew_members where user_id = p_uid) then
    return jsonb_build_object('hint', 'in_crew', 'message', 'You are already in a crew. Leave it first.');
  end if;
  v_cool := bl_crew_cool_left(p_uid);
  if v_cool is not null then
    return jsonb_build_object('hint', 'cooldown', 'message', 'You left a crew recently. You can found or join another in about ' || greatest(1, ceil(extract(epoch from v_cool - bl_now()) / 60))::int || ' minutes.', 'until', v_cool);
  end if;
  v_age := extract(epoch from bl_now() - p.created_at) / 3600;
  v_lvl := bl_skill_level(p_uid, 'charisma');
  if (v_hours > 0 or v_ch > 1) and not ((v_hours > 0 and v_age >= v_hours) or (v_ch > 1 and v_lvl >= v_ch)) then
    return jsonb_build_object('hint', 'too_new', 'message',
      'To found a crew you need ' || case when v_ch > 1 then 'Charisma level ' || v_ch || ' or ' else '' end
      || 'an account at least ' || ceil(v_hours)::int || ' hours old.');
  end if;
  return null;
end $$;

-- Can this player join a crew (invite accepted / open crew)? null = yes
create or replace function public.bl_crew_join_gate(p_uid uuid) returns jsonb
language plpgsql stable set search_path = public as $$
declare p profiles; v_cool timestamptz; v_h numeric := bl_crew_num('crew.join_min_account_hours', 24);
begin
  select * into p from profiles where id = p_uid;
  if not found or p.banned then return jsonb_build_object('hint', 'no_profile', 'message', 'That player cannot join a crew.'); end if;
  if exists (select 1 from crew_members where user_id = p_uid) then
    return jsonb_build_object('hint', 'in_crew', 'message', 'Already in a crew.');
  end if;
  v_cool := bl_crew_cool_left(p_uid);
  if v_cool is not null then
    return jsonb_build_object('hint', 'cooldown', 'message', 'Left a crew recently: wait about ' || greatest(1, ceil(extract(epoch from v_cool - bl_now()) / 60))::int || ' minutes.', 'until', v_cool);
  end if;
  if v_h > 0 and p.created_at > bl_now() - make_interval(secs => (v_h * 3600)::double precision) then
    return jsonb_build_object('hint', 'too_new', 'message', 'New accounts can join a crew after ' || ceil(v_h)::int || ' hours.');
  end if;
  return null;
end $$;

-- The caller's membership, with the crew row locked first (crew, then players: the one lock order everywhere).
-- p_min = lowest rank number allowed (0 any, 1 member, 2 lieutenant, 3 boss).
create or replace function public.bl_crew_need(p_uid uuid, p_min int default 0, p_lock boolean default true) returns public.crew_members
language plpgsql set search_path = public as $$
declare m crew_members; c crews;
begin
  select * into m from crew_members where user_id = p_uid;
  if not found then
    raise exception 'You are not in a crew.' using errcode = 'P0001', hint = 'no_crew';
  end if;
  if p_lock then
    select * into c from crews where id = m.crew_id for update;
    select * into m from crew_members where user_id = p_uid;
  end if;
  if not found then
    raise exception 'You are not in a crew.' using errcode = 'P0001', hint = 'no_crew';
  end if;
  if bl_crew_rank_n(m.rank) < p_min then
    raise exception '%', case p_min when 3 then 'Only the Boss can do that.' else 'Only the Boss or a Lieutenant can do that.' end using errcode = 'P0001', hint = 'rank';
  end if;
  return m;
end $$;

create or replace function public.bl_crew_guard(p_write boolean default true) returns void
language plpgsql stable set search_path = public as $$
begin
  if p_write and not bl_crew_on() then
    raise exception 'Crews are switched off for now. Try again later.' using errcode = 'P0001', hint = 'crews_off';
  end if;
end $$;

create or replace function public.bl_crew_online(p_last_seen timestamptz) returns boolean
language sql stable set search_path = public as $$
  select p_last_seen is not null
     and p_last_seen > bl_now() - make_interval(secs => (greatest(1, coalesce(bl_crew_num('time.presence_real_minutes', 3), 3)) * 60)::double precision);
$$;

-- Can this player take part in a job right now? null = yes, else {hint, message}. Must be free, online and standing at a meeting spot.
create or replace function public.bl_crew_gate(p_uid uuid, p_stage text default 'join') returns jsonb
language plpgsql stable set search_path = public as $$
declare
  p profiles; v_places text[] := bl_crew_list('crew.meeting_places', 'upper_sakponba,third_east,siluko_rd');
  v_hint text; v_msg text;
begin
  select * into p from profiles where id = p_uid;
  if not found or p.banned then return jsonb_build_object('hint', 'no_profile', 'message', 'Not available.'); end if;
  begin
    perform bl_assert_free(p);
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    v_msg := sqlerrm;
    return jsonb_build_object('hint', coalesce(nullif(v_hint, ''), 'busy'), 'message', v_msg);
  end;
  if not bl_crew_online(p.last_seen) then
    return jsonb_build_object('hint', 'offline', 'message', 'Not online.');
  end if;
  if p.location_id is null or not (p.location_id = any (v_places))
     or not exists (select 1 from locations l where l.id = p.location_id and coalesce(l.active, true)) then
    return jsonb_build_object('hint', 'wrong_place', 'message', 'Be at a crew meeting spot: '
      || coalesce((select string_agg(l.name, ', ' order by l.name) from locations l where l.id = any (v_places)), 'see Settings') || '.');
  end if;
  if exists (select 1 from crew_run_members x join crew_runs r on r.id = x.run_id where x.user_id = p_uid and r.status = 'running') then
    return jsonb_build_object('hint', 'on_job', 'message', 'Already on a job.');
  end if;
  return null;
end $$;

-- The crew's caught chance: the job's chance, cut by the average level of the job's skills across the crew
create or replace function public.bl_crew_job_pct(p_uids uuid[], j public.crew_jobs) returns jsonb
language plpgsql stable set search_path = public as $$
declare v_avg numeric; v_cut numeric; v_base numeric := coalesce(j.caught_pct, 0);
begin
  if not bl_skill_on() or cardinality(coalesce(p_uids, '{}')) = 0 or cardinality(coalesce(j.skills, '{}')) = 0 then
    return jsonb_build_object('base', v_base, 'cut', 0, 'avg', 1, 'pct', round(v_base, 2));
  end if;
  select avg(per_player) into v_avg from (
    select (select avg(bl_skill_level(u, s)) from unnest(j.skills) s) as per_player from unnest(p_uids) u) q;
  v_cut := greatest(0, least(100, least(bl_crew_num('crew.skill_cut_cap', 30), greatest(0, coalesce(v_avg, 1) - 1) * bl_crew_num('crew.skill_cut_per_level', 1.5))));
  return jsonb_build_object('base', v_base, 'cut', round(v_cut, 2), 'avg', round(coalesce(v_avg, 1), 2),
                            'pct', round(greatest(0, least(100, v_base * (1 - v_cut / 100.0))), 2));
end $$;

-- the rank row of a level (clamped to the highest level)
create or replace function public.bl_crew_level_row(p_level int) returns public.crew_levels
language sql stable set search_path = public as $$
  select l from crew_levels l where l.level <= greatest(1, coalesce(p_level, 1)) order by l.level desc limit 1;
$$;

create or replace function public.bl_crew_max_members(p_level int) returns int
language sql stable set search_path = public as $$
  select coalesce((select max_members from crew_levels where level <= greatest(1, coalesce(p_level, 1)) order by level desc limit 1), 6);
$$;

-- Jail one participant of a busted job through the normal jail flow (jail_cases: bail, go to jail, escape)
create or replace function public.bl_crew_bust(p_uid uuid, p_run bigint, p_job_name text) returns bigint
language plpgsql set search_path = public as $$
declare
  v_now      timestamptz := bl_now();
  v_jail     int := greatest(1, ceil(bl_crew_num('crew.jail_seconds', 120)))::int;
  v_jail_loc text := coalesce(bl_crew_text('crime.jail_location', 'police_hq'), 'police_hq');
  v_loc      text := (select location_id from profiles where id = p_uid);
  c          jail_cases;
begin
  perform bl_crime_close_stale(p_uid);
  update jail_cases set status = 'released', closed_at = v_now where user_id = p_uid and status = 'open';
  insert into jail_cases (user_id, reason, location_id, bail_amount, jail_seconds, jail_until, created_at, kind, meta)
  values (p_uid, 'Caught on a crew job: ' || p_job_name, v_loc,
          greatest(0, round(bl_crew_num('crew.bail_base', 20000000)))::bigint, v_jail,
          v_now + make_interval(secs => v_jail), v_now, 'police', jsonb_build_object('crew_run', p_run, 'job_name', p_job_name))
  returning * into c;
  update profiles set
    jailed_until = c.jail_until, jail_reason = c.reason, wanted = least(5, wanted + 1),
    location_id = coalesce((select id from locations where id = v_jail_loc), location_id),
    travel_to = null, travel_mode = null, travel_started_at = null, travel_arrives_at = null,
    busy_until = null, busy_label = null, busy_started_at = null, busy_needs_from = null
   where id = p_uid;
  perform bl_event(p_uid, 'crew_job_caught', 'Police don catch the crew!',
    'The ' || p_job_name || ' job went bad and the police caught the whole crew. Open the popup to pay bail, serve time or try to escape.',
    jsonb_build_object('case_id', c.id, 'run', p_run));
  return c.id;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 4. Weekly top crews
-- ---------------------------------------------------------------------------------------------
-- Ranking for one week: paid jobs resolved in the week, by loot (the pot), then jobs
create or replace function public.bl_crew_week_ranked(p_week date)
returns table (crew_id bigint, name text, tag text, emblem text, color text, level int, jobs bigint, loot bigint, rank bigint)
language sql stable set search_path = public as $$
  with e as (
    select r.crew_id, count(*) as jobs, coalesce(sum(r.pot), 0)::bigint as loot
      from crew_runs r
     where r.status = 'paid' and r.resolved_at >= bl_week_from(p_week) and r.resolved_at < bl_week_from(p_week + 7)
     group by r.crew_id)
  select c.id, c.name, c.tag, c.emblem, c.color, c.level, e.jobs, e.loot,
         row_number() over (order by e.loot desc, e.jobs desc, c.id)
    from e join crews c on c.id = e.crew_id
   where c.disbanded_at is null;
$$;

-- Settle every week that has closed and was never settled (the first call after the week ends does it; the unique week row makes it
-- idempotent). Prizes go into the crew BANK (crew_bank_log kind 'prize'), not into a player's money.
create or replace function public.bl_crew_week_settle() returns jsonb
language plpgsql set search_path = public as $$
declare
  v_cur  date := bl_week_start();
  v_last date;
  v_from date;
  w      date;
  n      int;
  r      record;
  v_prize bigint;
  v_min  int := greatest(0, bl_crew_num('crew.weekly_min_jobs', 2))::int;
  v_out  jsonb := '[]'::jsonb;
begin
  if coalesce((select (value #>> '{}')::boolean from game_config where key = 'crew.weekly_enabled'), true) is not true then return v_out; end if;
  select max(week_start) into v_last from crew_weeks;
  v_from := greatest(coalesce(v_last + 7, v_cur - 7), v_cur - 56);
  for w in select generate_series(v_from, v_cur - 7, interval '7 days')::date loop
    insert into crew_weeks (week_start, settled_at) values (w, bl_now()) on conflict (week_start) do nothing;
    get diagnostics n = row_count;
    if n = 0 then continue; end if;
    for r in select * from bl_crew_week_ranked(w) where rank <= 3 and jobs >= v_min order by rank loop
      v_prize := greatest(0, bl_crew_num('crew.weekly_prize_' || r.rank, 0))::bigint;
      insert into crew_week_winners (week_start, rank, crew_id, crew_name, tag, jobs, loot, prize)
      values (w, r.rank::int, r.crew_id, r.name, r.tag, r.jobs::int, r.loot, v_prize) on conflict do nothing;
      perform 1 from crews where id = r.crew_id for update;
      if v_prize > 0 then
        perform bl_crew_bank(r.crew_id, null, v_prize, 'prize', 'Top crews, week of ' || to_char(w, 'DD Mon') || ': #' || r.rank);
      end if;
      perform bl_crew_notify(r.crew_id, null, 'crew_weekly_prize',
        case r.rank when 1 then '🥇 Top crew of the week!' when 2 then '🥈 2nd top crew of the week!' else '🥉 3rd top crew of the week!' end,
        'Your crew did ' || r.jobs || ' jobs and ' || bl_naira(r.loot) || ' loot in the week of ' || to_char(w, 'DD Mon') || '.'
          || case when v_prize > 0 then ' ' || bl_naira(v_prize) || ' is in the crew bank.' else '' end, false,
        jsonb_build_object('week', w, 'rank', r.rank, 'prize', v_prize));
    end loop;
    v_out := v_out || to_jsonb(w);
  end loop;
  return v_out;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 5. JSON builders
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_crew_job_json(j public.crew_jobs, c public.crews, p_ids uuid[]) returns jsonb
language plpgsql stable set search_path = public as $$
declare v_last timestamptz; v_cd int := 0; v_est jsonb := bl_crew_job_pct(p_ids, j); v_lvl public.crew_levels := bl_crew_level_row(c.level);
begin
  select max(started_at) into v_last from crew_runs where crew_id = c.id and job_id = j.id and started_at is not null and status in ('running', 'paid', 'caught');
  if v_last is not null and j.cooldown_seconds > 0 then
    v_cd := greatest(0, ceil(extract(epoch from v_last + make_interval(secs => j.cooldown_seconds) - bl_now()))::int);
  end if;
  return jsonb_build_object(
    'id', j.id, 'name', j.name, 'icon', j.icon, 'blurb', j.blurb, 'min_members', j.min_members, 'max_members', j.max_members,
    'min_crew_level', j.min_crew_level, 'duration_seconds', j.duration_seconds, 'reward_min', j.reward_min, 'reward_max', j.reward_max,
    'bonus_pct', v_lvl.bonus_pct, 'caught_pct', j.caught_pct, 'est_pct', v_est->'pct', 'skill_cut_pct', v_est->'cut', 'cooldown_seconds', j.cooldown_seconds,
    'cooldown_left', v_cd, 'buy_in', j.buy_in, 'xp', j.xp,
    'skills', coalesce((select jsonb_agg(jsonb_build_object('id', k.id, 'name', k.name, 'icon', k.icon) order by k.sort) from skills k where k.id = any (j.skills)), '[]'::jsonb),
    'locked', c.level < j.min_crew_level,
    'locked_reason', case when c.level < j.min_crew_level then 'Needs crew level ' || j.min_crew_level end);
end $$;

create or replace function public.bl_crew_run_json(r public.crew_runs, p_viewer uuid) returns jsonb
language plpgsql stable set search_path = public as $$
declare j crew_jobs; v_ids uuid[]; v_est jsonb; v_members jsonb; v_by text;
begin
  select * into j from crew_jobs where id = r.job_id;
  select coalesce(array_agg(x.user_id), '{}') into v_ids from crew_run_members x where x.run_id = r.id;
  v_est := bl_crew_job_pct(v_ids, j);
  select coalesce(jsonb_agg(jsonb_build_object('id', x.user_id, 'username', p.username, 'rank', coalesce(x.rank, m.rank), 'payout', x.payout,
                                               'buy_in', x.buy_in, 'online', bl_crew_online(p.last_seen), 'jailed', x.jail_case is not null)
                           order by x.joined_at, x.user_id), '[]'::jsonb)
    into v_members
    from crew_run_members x join profiles p on p.id = x.user_id left join crew_members m on m.user_id = x.user_id and m.crew_id = r.crew_id
   where x.run_id = r.id;
  select username into v_by from profiles where id = r.started_by;
  return jsonb_build_object(
    'id', r.id, 'status', r.status, 'job_id', j.id, 'name', coalesce(r.job_name, j.name), 'icon', j.icon, 'blurb', j.blurb,
    'min_members', j.min_members, 'max_members', j.max_members, 'duration_seconds', j.duration_seconds, 'buy_in', j.buy_in,
    'reward_min', j.reward_min, 'reward_max', j.reward_max,
    'created_at', r.created_at, 'lobby_until', r.lobby_until, 'started_at', r.started_at, 'resolve_at', r.resolve_at, 'resolved_at', r.resolved_at,
    'started_by', v_by, 'started_by_id', r.started_by,
    'members', v_members, 'member_count', jsonb_array_length(v_members),
    'base_pct', coalesce(r.base_pct, j.caught_pct),
    'caught_pct', coalesce(r.caught_pct, (v_est->>'pct')::numeric),
    'skill_cut_pct', case when r.caught_pct is not null then r.skill_cut_pct else (v_est->>'cut')::numeric end,
    'split_bank_pct', r.split_bank_pct, 'pot', r.pot, 'bank_share', r.bank_share, 'fine', r.fine, 'note', r.note,
    'joined', exists (select 1 from crew_run_members x where x.run_id = r.id and x.user_id = p_viewer));
end $$;

create or replace function public.bl_crew_json(p_crew bigint, p_viewer uuid) returns jsonb
language plpgsql stable set search_path = public as $$
declare
  c crews; m crew_members; v_lvl crew_levels; v_next crew_levels; v_places text[] := bl_crew_list('crew.meeting_places', 'upper_sakponba,third_east,siluko_rd');
  v_members jsonb; v_jobs jsonb; v_run crew_runs; v_last crew_runs; v_ids uuid[]; v_week date := bl_week_start(); v_wk record; v_inv jsonb := '[]'::jsonb;
begin
  select * into c from crews where id = p_crew and disbanded_at is null;
  if not found then return null; end if;
  select * into m from crew_members where user_id = p_viewer and crew_id = c.id;
  v_lvl := bl_crew_level_row(c.level);
  select * into v_next from crew_levels where level = c.level + 1;
  select coalesce(array_agg(user_id), '{}') into v_ids from crew_members where crew_id = c.id;
  select coalesce(jsonb_agg(jsonb_build_object('id', x.user_id, 'username', p.username, 'avatar', p.avatar, 'rank', x.rank, 'joined_at', x.joined_at,
                                               'deposited', x.deposited, 'jobs', x.jobs, 'earned', x.earned, 'last_seen', p.last_seen,
                                               'online', bl_crew_online(p.last_seen) and not p.banned, 'at_spot', p.location_id = any (v_places) and p.travel_to is null,
                                               'me', x.user_id = p_viewer)
                           order by bl_crew_rank_n(x.rank) desc, x.joined_at, x.user_id), '[]'::jsonb)
    into v_members from crew_members x join profiles p on p.id = x.user_id where x.crew_id = c.id;
  select coalesce(jsonb_agg(bl_crew_job_json(j, c, v_ids) order by j.sort, j.id), '[]'::jsonb) into v_jobs from crew_jobs j where j.active;
  select * into v_run from crew_runs where crew_id = c.id and status in ('lobby', 'running') order by id desc limit 1;
  select * into v_last from crew_runs where crew_id = c.id and status in ('paid', 'caught') and resolved_at > bl_now() - interval '12 hours' order by id desc limit 1;
  select * into v_wk from bl_crew_week_ranked(v_week) w where w.crew_id = c.id;
  if m.user_id is not null and bl_crew_rank_n(m.rank) >= 2 then
    select coalesce(jsonb_agg(jsonb_build_object('id', i.id, 'username', p.username, 'created_at', i.created_at, 'expires_at', i.expires_at) order by i.id desc), '[]'::jsonb)
      into v_inv from crew_invites i join profiles p on p.id = i.to_user where i.crew_id = c.id and i.status = 'pending' and i.expires_at > bl_now();
  end if;
  return jsonb_build_object(
    'id', c.id, 'name', c.name, 'tag', c.tag, 'color', c.color, 'emblem', c.emblem, 'level', c.level, 'level_name', v_lvl.name, 'perks', v_lvl.perks,
    'bonus_pct', v_lvl.bonus_pct, 'xp', c.xp, 'xp_from', v_lvl.xp_needed, 'xp_to', v_next.xp_needed, 'bank', c.bank, 'split_bank_pct', c.split_bank_pct,
    'recruiting', c.recruiting, 'jobs_done', c.jobs_done, 'jobs_caught', c.jobs_caught, 'loot_total', c.loot_total, 'created_at', c.created_at,
    'members_count', cardinality(v_ids), 'max_members', v_lvl.max_members,
    'next_level', case when v_next.level is null then null else jsonb_build_object(
        'level', v_next.level, 'name', v_next.name, 'xp_needed', v_next.xp_needed, 'cost', v_next.upgrade_cost, 'max_members', v_next.max_members,
        'bonus_pct', v_next.bonus_pct, 'perks', v_next.perks, 'xp_ok', c.xp >= v_next.xp_needed, 'bank_ok', c.bank >= v_next.upgrade_cost) end,
    'members', v_members, 'pending_invites', v_inv, 'jobs', v_jobs,
    'run', case when v_run.id is null then null else bl_crew_run_json(v_run, p_viewer) end,
    'last_run', case when v_last.id is null then null else bl_crew_run_json(v_last, p_viewer) end,
    'week', jsonb_build_object('rank', v_wk.rank, 'jobs', coalesce(v_wk.jobs, 0), 'loot', coalesce(v_wk.loot, 0)),
    'meeting_places', coalesce((select jsonb_agg(jsonb_build_object('id', l.id, 'name', l.name) order by l.name) from locations l where l.id = any (v_places)), '[]'::jsonb),
    'me', case when m.user_id is null then null else jsonb_build_object(
        'rank', m.rank, 'is_boss', m.rank = 'boss', 'can_manage', bl_crew_rank_n(m.rank) >= 2, 'deposited', m.deposited, 'jobs', m.jobs, 'earned', m.earned) end);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 6. Crews: status, browse, found, invite, members
-- ---------------------------------------------------------------------------------------------
create or replace function public.crew_status() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid();
  m crew_members;
  v_due boolean;
  v_gate jsonb;
  v_cool timestamptz;
  v_invs jsonb;
begin
  perform bl_crew_expire_invites();
  perform bl_crew_week_settle();
  select * into m from crew_members where user_id = v_uid;
  if found then
    select exists (select 1 from crew_runs r where r.crew_id = m.crew_id and ((r.status = 'lobby' and r.lobby_until <= bl_now()) or (r.status = 'running' and r.resolve_at <= bl_now())))
      into v_due;
    if v_due then
      perform 1 from crews where id = m.crew_id for update;
      perform bl_crew_tick(m.crew_id);
    end if;
  end if;
  v_gate := bl_crew_found_gate(v_uid);
  v_cool := bl_crew_cool_left(v_uid);
  select coalesce(jsonb_agg(jsonb_build_object('id', i.id, 'created_at', i.created_at, 'expires_at', i.expires_at, 'from', (select username from profiles where id = i.from_user),
            'crew', jsonb_build_object('id', c.id, 'name', c.name, 'tag', c.tag, 'color', c.color, 'emblem', c.emblem, 'level', c.level,
                                       'members', (select count(*) from crew_members x where x.crew_id = c.id), 'max_members', bl_crew_max_members(c.level)))
          order by i.id desc), '[]'::jsonb)
    into v_invs from crew_invites i join crews c on c.id = i.crew_id and c.disbanded_at is null
   where i.to_user = v_uid and i.status = 'pending' and i.expires_at > bl_now();
  return jsonb_build_object(
    'enabled', bl_crew_on(), 'now', bl_now(),
    'settings', jsonb_build_object(
      'found_fee', bl_crew_num('crew.found_fee', 500000), 'found_min_charisma', bl_crew_num('crew.found_min_charisma', 2),
      'found_min_account_hours', bl_crew_num('crew.found_min_account_hours', 72), 'rejoin_cooldown_hours', bl_crew_num('crew.rejoin_cooldown_hours', 48),
      'emblems', to_jsonb(bl_crew_list('crew.emblems', '🦁')), 'default_bank_pct', bl_crew_num('crew.default_bank_pct', 30),
      'bank_pct_min', bl_crew_num('crew.bank_pct_min', 10), 'bank_pct_max', bl_crew_num('crew.bank_pct_max', 80),
      'chat_max_len', bl_crew_num('crew.chat_max_len', 300), 'min_deposit', bl_crew_num('crew.min_deposit', 1000),
      'rename_fee', bl_crew_num('crew.rename_fee', 100000), 'prospect_share_pct', bl_crew_num('crew.prospect_share_pct', 50),
      'lobby_seconds', bl_crew_num('crew.lobby_seconds', 120), 'weekly_enabled', coalesce((select (value #>> '{}')::boolean from game_config where key = 'crew.weekly_enabled'), true)),
    'can_found', jsonb_build_object('ok', v_gate is null, 'hint', v_gate->>'hint', 'message', v_gate->>'message'),
    'cooldown_until', v_cool,
    'invites', v_invs,
    'crew', case when m.user_id is null then null else bl_crew_json(m.crew_id, v_uid) end);
end $$;

-- Browse: public crews (recruiting ones first)
create or replace function public.crew_browse(p_q text default '', p_limit int default 40) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); v_q text := lower(btrim(coalesce(p_q, ''))); v_lim int := least(greatest(coalesce(p_limit, 40), 1), 100);
begin
  return jsonb_build_object('crews', coalesce((
    select jsonb_agg(jsonb_build_object('id', x.id, 'name', x.name, 'tag', x.tag, 'color', x.color, 'emblem', x.emblem, 'level', x.level,
                                        'members', x.n, 'max_members', bl_crew_max_members(x.level), 'recruiting', x.recruiting, 'jobs_done', x.jobs_done,
                                        'boss', x.boss) order by x.recruiting desc, x.level desc, x.n desc, x.id)
      from (select c.*, (select count(*) from crew_members m where m.crew_id = c.id) as n,
                   (select p.username from crew_members m join profiles p on p.id = m.user_id where m.crew_id = c.id and m.rank = 'boss') as boss
              from crews c
             where c.disbanded_at is null and (v_q = '' or lower(c.name) like '%' || replace(replace(v_q, '%', ''), '_', '') || '%' or lower(c.tag) = v_q)
             order by c.recruiting desc, c.level desc, c.id limit v_lim) x), '[]'::jsonb));
end $$;

create or replace function public.crew_create(p_name text, p_tag text, p_color text, p_emblem text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid(); v_me profiles; v_gate jsonb; v_chk jsonb; v_fee bigint := greatest(0, bl_crew_num('crew.found_fee', 500000))::bigint;
  v_color text := coalesce(nullif(btrim(p_color), ''), '#c9a227'); c crews; v_rank text;
begin
  perform bl_crew_guard();
  perform 1 from profiles where id = v_uid for update;
  v_me := bl_me();
  v_gate := bl_crew_found_gate(v_uid);
  if v_gate is not null then
    raise exception '%', v_gate->>'message' using errcode = 'P0001', hint = v_gate->>'hint';
  end if;
  v_chk := bl_crew_name_check(p_name, p_tag);
  if not (v_chk->>'ok')::boolean then
    raise exception '%', v_chk->>'message' using errcode = 'P0001', hint = v_chk->>'hint';
  end if;
  if v_color !~ '^#[0-9a-fA-F]{6}$' then
    raise exception 'Pick a colour for the crew.' using errcode = 'P0001', hint = 'bad_color';
  end if;
  if p_emblem is null or not (btrim(p_emblem) = any (bl_crew_list('crew.emblems', '🦁'))) then
    raise exception 'Pick an emblem from the list.' using errcode = 'P0001', hint = 'bad_emblem';
  end if;
  begin
    insert into crews (name, tag, color, emblem, split_bank_pct, created_by, created_at)
    values (v_chk->>'name', v_chk->>'tag', lower(v_color), btrim(p_emblem), greatest(0, least(100, bl_crew_num('crew.default_bank_pct', 30))), v_uid, bl_now())
    returning * into c;
  exception when unique_violation then
    raise exception 'That crew name or tag was just taken. Try another one.' using errcode = 'P0001', hint = 'name_taken';
  end;
  perform bl_crew_pay(v_uid, v_fee, 'crew_fee', jsonb_build_object('label', 'Crew: founding fee for ' || c.name, 'crew', c.id));
  insert into crew_members (user_id, crew_id, rank, joined_at) values (v_uid, c.id, 'boss', bl_now());
  return jsonb_build_object('message', c.name || ' [' || c.tag || '] is born. You are the Boss. Invite your people.', 'crew', bl_crew_json(c.id, v_uid));
end $$;

-- Who can I invite? Friends first (online first), then any player found by username.
create or replace function public.crew_invite_candidates(p_q text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); m crew_members; v_q text := replace(replace(lower(regexp_replace(btrim(coalesce(p_q, '')), '^@', '')), '%', ''), '_', ''); v_rows jsonb;
begin
  m := bl_crew_need(v_uid, 2, false);
  select coalesce(jsonb_agg(jsonb_build_object('id', z.id, 'username', z.username, 'avatar', z.avatar, 'online', z.online, 'friend', z.friend,
                                               'invited', z.invited, 'eligible', z.g is null, 'why', z.g->>'message')
                           order by z.friend desc, z.online desc, z.username), '[]'::jsonb)
    into v_rows from (
    select p.id, p.username, p.avatar, bl_crew_online(p.last_seen) as online, (f.user_a is not null) as friend, bl_crew_join_gate(p.id) as g,
           exists (select 1 from crew_invites i where i.crew_id = m.crew_id and i.to_user = p.id and i.status = 'pending' and i.expires_at > bl_now()) as invited
      from profiles p
      left join player_friendships f on f.status = 'accepted' and f.user_a = least(v_uid, p.id) and f.user_b = greatest(v_uid, p.id)
     where p.id <> v_uid and not p.banned and p.home_chosen and not bl_social_blocked(v_uid, p.id)
       and ((v_q = '' and f.user_a is not null)
            or (v_q <> '' and ((f.user_a is not null and lower(p.username) like '%' || v_q || '%') or lower(p.username) like v_q || '%')))
     order by (f.user_a is not null) desc, bl_crew_online(p.last_seen) desc, p.username limit 30) z;
  return jsonb_build_object('players', v_rows);
end $$;

create or replace function public.crew_invite(p_user uuid default null, p_username text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid(); m crew_members; c crews; t profiles; v_gate jsonb; i crew_invites; v_who text; v_name text := lower(regexp_replace(btrim(coalesce(p_username, '')), '^@', ''));
begin
  perform bl_crew_guard();
  m := bl_crew_need(v_uid, 2);
  select * into c from crews where id = m.crew_id;
  perform bl_crew_expire_invites();
  if p_user is not null then
    select * into t from profiles where id = p_user;
  elsif v_name <> '' then
    select * into t from profiles where lower(username) = v_name;
  end if;
  if t.id is null or t.banned or not t.home_chosen then
    raise exception 'That player no dey.' using errcode = 'P0001', hint = 'no_player';
  end if;
  if t.id = v_uid then
    raise exception 'You are already in your own crew.' using errcode = 'P0001', hint = 'self';
  end if;
  if bl_social_blocked(v_uid, t.id) then
    raise exception 'You cannot invite that player.' using errcode = 'P0001', hint = 'blocked';
  end if;
  v_gate := bl_crew_join_gate(t.id);
  if v_gate is not null then
    raise exception '@% : %', t.username, v_gate->>'message' using errcode = 'P0001', hint = coalesce(v_gate->>'hint', 'cannot_join');
  end if;
  if (select count(*) from crew_members where crew_id = c.id) >= bl_crew_max_members(c.level) then
    raise exception 'The crew is full for its level. Upgrade the crew to take more members.' using errcode = 'P0001', hint = 'full';
  end if;
  if (select count(*) from crew_invites where crew_id = c.id and created_at > bl_now() - interval '24 hours') >= bl_crew_num('crew.invite_daily_cap', 20) then
    raise exception 'You have sent plenty invites today. Try again tomorrow.' using errcode = 'P0001', hint = 'rate_limit';
  end if;
  if exists (select 1 from crew_invites where crew_id = c.id and to_user = t.id and status = 'pending' and expires_at > bl_now()) then
    raise exception '@% already has an invite from your crew.', t.username using errcode = 'P0001', hint = 'already_invited';
  end if;
  begin
    insert into crew_invites (crew_id, to_user, from_user, expires_at, created_at)
    values (c.id, t.id, v_uid, bl_now() + make_interval(secs => (bl_crew_num('crew.invite_expire_hours', 48) * 3600)::double precision), bl_now())
    returning * into i;
  exception when unique_violation then
    update crew_invites set status = 'expired' where crew_id = c.id and to_user = t.id and status = 'pending' and expires_at <= bl_now();
    insert into crew_invites (crew_id, to_user, from_user, expires_at, created_at)
    values (c.id, t.id, v_uid, bl_now() + make_interval(secs => (bl_crew_num('crew.invite_expire_hours', 48) * 3600)::double precision), bl_now())
    returning * into i;
  end;
  select username into v_who from profiles where id = v_uid;
  perform bl_event(t.id, 'crew_invite', '[' || c.tag || '] ' || c.name || ' invite you ' || c.emblem,
    '@' || v_who || ' wan make you join their crew. Open the Crew app to accept or pass.', jsonb_build_object('invite', i.id, 'crew', c.id));
  perform bl_push_enqueue(t.id, 'friends', 'crew_invite', '@' || v_who || ' invite you to a crew ' || c.emblem, c.name || ' [' || c.tag || '] · tap to answer.', '/play?go=crew', v_uid);
  return jsonb_build_object('message', 'Invite sent to @' || t.username || '.', 'invite', i.id);
end $$;

create or replace function public.crew_invite_cancel(p_invite bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); m crew_members;
begin
  m := bl_crew_need(v_uid, 2);
  update crew_invites set status = 'cancelled' where id = p_invite and crew_id = m.crew_id and status = 'pending';
  if not found then
    raise exception 'That invite is gone already.' using errcode = 'P0001', hint = 'gone';
  end if;
  return jsonb_build_object('message', 'Invite cancelled.');
end $$;

create or replace function public.bl_crew_add_member(p_crew bigint, p_uid uuid, p_rank text) returns void
language plpgsql set search_path = public as $$
declare v_name text; c crews;
begin
  select * into c from crews where id = p_crew;
  insert into crew_members (user_id, crew_id, rank, joined_at) values (p_uid, p_crew, p_rank, bl_now());
  update crew_invites set status = 'cancelled' where to_user = p_uid and status = 'pending' and crew_id <> p_crew;
  select username into v_name from profiles where id = p_uid;
  perform bl_crew_notify(p_crew, p_uid, 'crew_joined', '@' || v_name || ' joined the crew', 'Welcome @' || v_name || ' to ' || c.name || ' [' || c.tag || '].', false);
end $$;

create or replace function public.crew_invite_respond(p_invite bigint, p_accept boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid(); i crew_invites; c crews; v_gate jsonb; v_rank text := bl_crew_text('crew.new_member_rank', 'prospect'); v_who text;
begin
  perform bl_crew_guard();
  select * into i from crew_invites where id = p_invite and to_user = v_uid;
  if not found or i.status <> 'pending' then
    raise exception 'That invite is gone already.' using errcode = 'P0001', hint = 'gone';
  end if;
  select * into c from crews where id = i.crew_id for update;
  perform 1 from profiles where id = v_uid for update;
  select * into i from crew_invites where id = p_invite for update;
  if i.status <> 'pending' then
    raise exception 'That invite is gone already.' using errcode = 'P0001', hint = 'gone';
  end if;
  if not coalesce(p_accept, false) then
    update crew_invites set status = 'declined' where id = i.id;
    if i.from_user is not null then
      select username into v_who from profiles where id = v_uid;
      perform bl_event(i.from_user, 'crew_invite_reply', '@' || v_who || ' pass on the invite', 'They said no to ' || c.name || '.', jsonb_build_object('crew', c.id));
    end if;
    return jsonb_build_object('message', 'Invite declined.');
  end if;
  if c.disbanded_at is not null or i.expires_at <= bl_now() then
    update crew_invites set status = 'expired' where id = i.id;
    raise exception 'That invite has expired.' using errcode = 'P0001', hint = 'expired';
  end if;
  v_gate := bl_crew_join_gate(v_uid);
  if v_gate is not null then
    raise exception '%', v_gate->>'message' using errcode = 'P0001', hint = coalesce(v_gate->>'hint', 'cannot_join');
  end if;
  if (select count(*) from crew_members where crew_id = c.id) >= bl_crew_max_members(c.level) then
    raise exception 'That crew is full right now.' using errcode = 'P0001', hint = 'full';
  end if;
  update crew_invites set status = 'accepted' where id = i.id;
  perform bl_crew_add_member(c.id, v_uid, case when v_rank in ('member', 'prospect') then v_rank else 'prospect' end);
  return jsonb_build_object('message', 'You joined ' || c.name || ' [' || c.tag || ']!', 'crew', bl_crew_json(c.id, v_uid));
end $$;

-- Open (recruiting) crews: join directly
create or replace function public.crew_join_open(p_crew bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); c crews; v_gate jsonb; v_rank text := bl_crew_text('crew.new_member_rank', 'prospect');
begin
  perform bl_crew_guard();
  select * into c from crews where id = p_crew and disbanded_at is null for update;
  if not found then
    raise exception 'That crew no dey again.' using errcode = 'P0001', hint = 'gone';
  end if;
  perform 1 from profiles where id = v_uid for update;
  if not c.recruiting then
    raise exception 'That crew is not taking walk-ins. Ask for an invite.' using errcode = 'P0001', hint = 'not_recruiting';
  end if;
  v_gate := bl_crew_join_gate(v_uid);
  if v_gate is not null then
    raise exception '%', v_gate->>'message' using errcode = 'P0001', hint = coalesce(v_gate->>'hint', 'cannot_join');
  end if;
  if (select count(*) from crew_members where crew_id = c.id) >= bl_crew_max_members(c.level) then
    raise exception 'That crew is full right now.' using errcode = 'P0001', hint = 'full';
  end if;
  perform bl_crew_add_member(c.id, v_uid, case when v_rank in ('member', 'prospect') then v_rank else 'prospect' end);
  return jsonb_build_object('message', 'You joined ' || c.name || ' [' || c.tag || ']!', 'crew', bl_crew_json(c.id, v_uid));
end $$;

create or replace function public.crew_leave() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); m crew_members; c crews; v_who text;
begin
  m := bl_crew_need(v_uid, 0);
  select * into c from crews where id = m.crew_id;
  if m.rank = 'boss' then
    raise exception 'You are the Boss. Transfer the Boss rank first, or disband the crew.' using errcode = 'P0001', hint = 'boss_must_transfer';
  end if;
  if exists (select 1 from crew_run_members x join crew_runs r on r.id = x.run_id where x.user_id = v_uid and r.status = 'running') then
    raise exception 'You are on a job. Finish it first.' using errcode = 'P0001', hint = 'on_job';
  end if;
  delete from crew_run_members x using crew_runs r where x.user_id = v_uid and r.id = x.run_id and r.status = 'lobby';
  delete from crew_members where user_id = v_uid;
  insert into crew_cooldowns (user_id, until, reason) values (v_uid, bl_now() + make_interval(secs => (bl_crew_num('crew.rejoin_cooldown_hours', 48) * 3600)::double precision), 'left')
  on conflict (user_id) do update set until = excluded.until, reason = excluded.reason;
  select username into v_who from profiles where id = v_uid;
  perform bl_crew_notify(c.id, v_uid, 'crew_left', '@' || v_who || ' left the crew', '@' || v_who || ' is no longer in ' || c.name || '.', false);
  return jsonb_build_object('message', 'You left ' || c.name || '. You can join another crew in ' || bl_crew_num('crew.rejoin_cooldown_hours', 48)::int || ' hours.');
end $$;

create or replace function public.crew_kick(p_user uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); m crew_members; t crew_members; c crews; v_name text;
begin
  m := bl_crew_need(v_uid, 2);
  select * into c from crews where id = m.crew_id;
  select * into t from crew_members where user_id = p_user and crew_id = m.crew_id;
  if not found or p_user = v_uid then
    raise exception 'That person is not in your crew.' using errcode = 'P0001', hint = 'not_member';
  end if;
  if t.rank = 'boss' or bl_crew_rank_n(t.rank) >= bl_crew_rank_n(m.rank) then
    raise exception 'You cannot kick somebody of your rank or above.' using errcode = 'P0001', hint = 'rank';
  end if;
  if exists (select 1 from crew_run_members x join crew_runs r on r.id = x.run_id where x.user_id = p_user and r.status = 'running') then
    raise exception 'They are on a job. Wait until it ends.' using errcode = 'P0001', hint = 'on_job';
  end if;
  delete from crew_run_members x using crew_runs r where x.user_id = p_user and r.id = x.run_id and r.status = 'lobby';
  delete from crew_members where user_id = p_user;
  insert into crew_cooldowns (user_id, until, reason) values (p_user, bl_now() + make_interval(secs => (bl_crew_num('crew.rejoin_cooldown_hours', 48) * 3600)::double precision), 'kicked')
  on conflict (user_id) do update set until = excluded.until, reason = excluded.reason;
  select username into v_name from profiles where id = p_user;
  perform bl_event(p_user, 'crew_kicked', 'You were removed from ' || c.name, 'The crew leaders removed you. You can join another crew later.', jsonb_build_object('crew', c.id));
  perform bl_crew_notify(c.id, v_uid, 'crew_left', '@' || v_name || ' was removed', '@' || v_name || ' is no longer in ' || c.name || '.', false);
  return jsonb_build_object('message', '@' || v_name || ' removed from the crew.');
end $$;

create or replace function public.crew_set_rank(p_user uuid, p_rank text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); m crew_members; t crew_members; v_name text; v_to text := lower(btrim(coalesce(p_rank, '')));
begin
  m := bl_crew_need(v_uid, 2);
  if v_to not in ('lieutenant', 'member', 'prospect') then
    raise exception 'Pick Lieutenant, Member or Prospect.' using errcode = 'P0001', hint = 'bad_rank';
  end if;
  select * into t from crew_members where user_id = p_user and crew_id = m.crew_id;
  if not found or p_user = v_uid or t.rank = 'boss' then
    raise exception 'You cannot change that person''s rank.' using errcode = 'P0001', hint = 'not_member';
  end if;
  if m.rank <> 'boss' and not (t.rank = 'prospect' and v_to = 'member') then
    raise exception 'A Lieutenant can only promote a Prospect to Member.' using errcode = 'P0001', hint = 'rank';
  end if;
  if t.rank = v_to then
    return jsonb_build_object('message', 'Already ' || v_to || '.');
  end if;
  if v_to = 'lieutenant' and (select count(*) from crew_members where crew_id = m.crew_id and rank = 'lieutenant') >= bl_crew_num('crew.max_lieutenants', 3) then
    raise exception 'You already have the most Lieutenants allowed.' using errcode = 'P0001', hint = 'max_lieutenants';
  end if;
  update crew_members set rank = v_to where user_id = p_user;
  select username into v_name from profiles where id = p_user;
  perform bl_event(p_user, 'crew_rank', 'Your crew rank changed', 'You are now a ' || initcap(v_to) || '.', jsonb_build_object('crew', m.crew_id, 'rank', v_to));
  return jsonb_build_object('message', '@' || v_name || ' is now ' || initcap(v_to) || '.');
end $$;

create or replace function public.crew_transfer(p_user uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); m crew_members; t crew_members; c crews; v_name text;
begin
  m := bl_crew_need(v_uid, 3);
  select * into c from crews where id = m.crew_id;
  select * into t from crew_members where user_id = p_user and crew_id = m.crew_id;
  if not found or p_user = v_uid then
    raise exception 'Pick another member of your crew.' using errcode = 'P0001', hint = 'not_member';
  end if;
  if t.rank = 'prospect' then
    raise exception 'Promote them to Member first. A Prospect cannot be Boss.' using errcode = 'P0001', hint = 'rank';
  end if;
  update crew_members set rank = 'lieutenant' where user_id = v_uid;
  update crew_members set rank = 'boss' where user_id = p_user;
  select username into v_name from profiles where id = p_user;
  perform bl_crew_notify(c.id, null, 'crew_rank', '@' || v_name || ' is the new Boss', 'The Boss rank of ' || c.name || ' moved to @' || v_name || '.', false);
  return jsonb_build_object('message', '@' || v_name || ' is now the Boss. You are a Lieutenant.');
end $$;

-- Shared by the Boss (disband) and admins: return the bank, free the members, close the crew
create or replace function public.bl_crew_dissolve(p_crew bigint, p_admin uuid, p_reason text) returns jsonb
language plpgsql set search_path = public as $$
declare
  c crews; r record; x record; v_n int; v_share bigint; v_rest bigint; v_first uuid; v_bank bigint;
begin
  select * into c from crews where id = p_crew and disbanded_at is null for update;
  if not found then
    raise exception 'That crew is gone already.' using errcode = 'P0001', hint = 'gone';
  end if;
  -- open jobs end: buy-ins come back, busy labels clear
  for r in select * from crew_runs where crew_id = c.id and status in ('lobby', 'running') order by id loop
    for x in select * from crew_run_members where run_id = r.id and buy_in > 0 order by user_id loop
      perform bl_add_money(x.user_id, 'bank', x.buy_in, 'crew_refund', jsonb_build_object('label', 'Crew job supplies refunded', 'run', r.id));
    end loop;
    update profiles set busy_until = null, busy_label = null, busy_started_at = null, busy_needs_from = null
     where id in (select user_id from crew_run_members where run_id = r.id) and busy_label like 'Crew job:%';
    update crew_runs set status = 'cancelled', resolved_at = bl_now(), note = 'The crew was disbanded.' where id = r.id;
  end loop;
  -- the bank is shared out equally (a refund, not earned money); the rounding stays with the oldest member
  select count(*), (array_agg(user_id order by joined_at, user_id))[1] into v_n, v_first from crew_members where crew_id = c.id;
  v_bank := c.bank;
  if v_bank > 0 and v_n > 0 then
    v_share := floor(v_bank::numeric / v_n)::bigint;
    v_rest := v_bank - v_share * v_n;
    perform bl_crew_bank(c.id, null, -v_bank, 'refund', 'Crew disbanded: bank shared out');
    for r in select user_id from crew_members where crew_id = c.id order by user_id loop
      perform bl_add_money(r.user_id, 'bank', v_share + case when r.user_id = v_first then v_rest else 0 end, 'crew_refund',
                           jsonb_build_object('label', 'Crew bank returned: ' || c.name, 'crew', c.id));
    end loop;
  end if;
  update crew_invites set status = 'cancelled' where crew_id = c.id and status = 'pending';
  update crews set disbanded_at = bl_now(), disbanded_reason = left(coalesce(p_reason, ''), 200) where id = c.id;
  for r in select user_id from crew_members where crew_id = c.id order by user_id loop
    perform bl_event(r.user_id, 'crew_disbanded', c.name || ' was disbanded',
      coalesce(nullif(p_reason, ''), 'The crew is closed.') || case when v_bank > 0 then ' The bank was shared out to your bank accounts.' else '' end,
      jsonb_build_object('crew', c.id, 'by_admin', p_admin is not null));
  end loop;
  delete from crew_members where crew_id = c.id;
  return jsonb_build_object('members', v_n, 'bank', v_bank);
end $$;

create or replace function public.crew_disband() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); m crew_members; c crews; v jsonb;
begin
  m := bl_crew_need(v_uid, 3);
  select * into c from crews where id = m.crew_id;
  if exists (select 1 from crew_runs where crew_id = c.id and status = 'running') then
    raise exception 'A job is running. Wait until it ends.' using errcode = 'P0001', hint = 'on_job';
  end if;
  v := bl_crew_dissolve(c.id, null, 'Disbanded by the Boss.');
  insert into crew_cooldowns (user_id, until, reason) values (v_uid, bl_now() + make_interval(secs => (bl_crew_num('crew.rejoin_cooldown_hours', 48) * 3600)::double precision), 'disbanded')
  on conflict (user_id) do update set until = excluded.until, reason = excluded.reason;
  return jsonb_build_object('message', c.name || ' disbanded.' || case when (v->>'bank')::bigint > 0 then ' The bank was shared out.' else '' end);
end $$;

-- A Boss or Lieutenant opens the door; only the Boss sets the bank share
create or replace function public.crew_options(p_split numeric default null, p_recruiting boolean default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); m crew_members; lo numeric := bl_crew_num('crew.bank_pct_min', 10); hi numeric := bl_crew_num('crew.bank_pct_max', 80);
begin
  m := bl_crew_need(v_uid, case when p_split is not null then 3 else 2 end);
  if p_split is not null then
    if p_split < lo or p_split > hi then
      raise exception 'The bank share must be between % and % percent.', lo, hi using errcode = 'P0001', hint = 'bad_split';
    end if;
    update crews set split_bank_pct = round(p_split, 1) where id = m.crew_id;
  end if;
  if p_recruiting is not null then
    update crews set recruiting = p_recruiting where id = m.crew_id;
  end if;
  return jsonb_build_object('message', 'Crew settings saved.', 'crew', bl_crew_json(m.crew_id, v_uid));
end $$;

create or replace function public.crew_rename(p_name text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid(); m crew_members; c crews; v_chk jsonb; v_fee bigint := greatest(0, bl_crew_num('crew.rename_fee', 100000))::bigint;
  v_days numeric := bl_crew_num('crew.rename_cooldown_days', 7);
begin
  perform bl_crew_guard();
  m := bl_crew_need(v_uid, 3);
  select * into c from crews where id = m.crew_id;
  if c.renamed_at is not null and c.renamed_at > bl_now() - make_interval(secs => (v_days * 86400)::double precision) then
    raise exception 'You renamed the crew recently. Wait a few days.' using errcode = 'P0001', hint = 'rename_cooldown';
  end if;
  v_chk := bl_crew_name_check(p_name, null, c.id);
  if not (v_chk->>'ok')::boolean then
    raise exception '%', v_chk->>'message' using errcode = 'P0001', hint = v_chk->>'hint';
  end if;
  if lower(v_chk->>'name') = lower(c.name) then
    raise exception 'That is already the crew name.' using errcode = 'P0001', hint = 'same_name';
  end if;
  if v_fee > 0 then
    if c.bank < v_fee then
      raise exception 'The crew bank needs % for a rename.', bl_naira(v_fee) using errcode = 'P0001', hint = 'bank_short';
    end if;
    perform bl_crew_bank(c.id, v_uid, -v_fee, 'fee', 'Rename to ' || (v_chk->>'name'));
  end if;
  begin
    update crews set name = v_chk->>'name', renamed_at = bl_now() where id = c.id;
  exception when unique_violation then
    raise exception 'Another crew already uses that name.' using errcode = 'P0001', hint = 'name_taken';
  end;
  return jsonb_build_object('message', 'The crew is now ' || (v_chk->>'name') || '.', 'crew', bl_crew_json(c.id, v_uid));
end $$;

-- ---------------------------------------------------------------------------------------------
-- 7. Crew bank, levels, chat, reports, top crews
-- ---------------------------------------------------------------------------------------------
create or replace function public.crew_deposit(p_amount bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); m crew_members; c crews; v_who text; v_bal bigint; v_min bigint := greatest(1, bl_crew_num('crew.min_deposit', 1000))::bigint;
begin
  perform bl_crew_guard();
  m := bl_crew_need(v_uid, 0);
  select * into c from crews where id = m.crew_id;
  perform 1 from profiles where id = v_uid for update;
  if p_amount is null or p_amount < v_min then
    raise exception 'The smallest deposit is %.', bl_naira(v_min) using errcode = 'P0001', hint = 'too_small';
  end if;
  select username into v_who from profiles where id = v_uid;
  perform bl_crew_pay(v_uid, p_amount, 'crew_deposit', jsonb_build_object('label', 'Crew bank: ' || c.name, 'crew', c.id));
  v_bal := bl_crew_bank(c.id, v_uid, p_amount, 'deposit', '@' || v_who || ' deposited');
  update crew_members set deposited = deposited + p_amount where user_id = v_uid;
  return jsonb_build_object('message', bl_naira(p_amount) || ' is in the crew bank.', 'bank', v_bal);
end $$;

create or replace function public.crew_upgrade() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); m crew_members; c crews; n crew_levels; v_who text;
begin
  perform bl_crew_guard();
  m := bl_crew_need(v_uid, 2);
  select * into c from crews where id = m.crew_id;
  select * into n from crew_levels where level = c.level + 1;
  if not found then
    raise exception 'Your crew is at the top level.' using errcode = 'P0001', hint = 'max_level';
  end if;
  if c.xp < n.xp_needed then
    raise exception 'The crew needs % XP (it has %). Pull more jobs.', n.xp_needed, c.xp using errcode = 'P0001', hint = 'need_xp';
  end if;
  if c.bank < n.upgrade_cost then
    raise exception 'The crew bank needs % (it has %).', bl_naira(n.upgrade_cost), bl_naira(c.bank) using errcode = 'P0001', hint = 'bank_short';
  end if;
  select username into v_who from profiles where id = v_uid;
  if n.upgrade_cost > 0 then
    perform bl_crew_bank(c.id, v_uid, -n.upgrade_cost, 'upgrade', '@' || v_who || ' upgraded to level ' || n.level || ' (' || n.name || ')');
  end if;
  update crews set level = n.level where id = c.id;
  perform bl_crew_notify(c.id, null, 'crew_level_up', c.emblem || ' ' || c.name || ' is now level ' || n.level, n.name || '. ' || n.perks, false, jsonb_build_object('level', n.level));
  return jsonb_build_object('message', c.name || ' is now level ' || n.level || ': ' || n.name || '.', 'crew', bl_crew_json(c.id, v_uid));
end $$;

create or replace function public.crew_bank_log_list(p_limit int default 40) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); m crew_members; v_lim int := least(greatest(coalesce(p_limit, 40), 1), 200);
begin
  m := bl_crew_need(v_uid, 0, false);
  return jsonb_build_object('rows', coalesce((
    select jsonb_agg(jsonb_build_object('id', l.id, 'kind', l.kind, 'amount', l.amount, 'balance_after', l.balance_after, 'note', l.note,
                                        'username', p.username, 'created_at', l.created_at) order by l.id desc)
      from (select * from crew_bank_log where crew_id = m.crew_id order by id desc limit v_lim) l left join profiles p on p.id = l.user_id), '[]'::jsonb));
end $$;

create or replace function public.crew_chat_send(p_body text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid(); m crew_members; p profiles; v_now timestamptz := bl_now(); v_body text := bl_chat_clean(p_body);
  v_rate numeric := bl_crew_num('crew.chat_rate_seconds', 2); v_burst int := bl_crew_num('crew.chat_burst_per_minute', 20)::int;
  v_max int := bl_crew_num('crew.chat_max_len', 300)::int; v_last timestamptz; v_n int; v_masked text; x crew_messages;
begin
  m := bl_crew_need(v_uid, 0, false);
  select * into p from profiles where id = v_uid for update;
  if p.banned then
    raise exception 'This account has been banned.' using errcode = 'P0001', hint = 'banned';
  end if;
  if p.chat_muted_until is not null and p.chat_muted_until > v_now then
    raise exception 'You can''t chat for now (muted by a moderator).' using errcode = 'P0001', hint = 'muted';
  end if;
  if v_body = '' then
    raise exception 'Type a message first.' using errcode = 'P0001', hint = 'empty';
  end if;
  if char_length(v_body) > v_max then
    raise exception 'That message is too long. Keep it under % characters.', v_max using errcode = 'P0001', hint = 'too_long';
  end if;
  select max(created_at), count(*) filter (where created_at > v_now - interval '60 seconds') into v_last, v_n
    from crew_messages where user_id = v_uid and created_at > v_now - interval '1 hour';
  if v_last is not null and v_rate > 0 and v_last > v_now - make_interval(secs => v_rate::double precision) then
    raise exception 'Slow down small.' using errcode = 'P0001', hint = 'too_fast';
  end if;
  if v_n >= v_burst then
    raise exception 'You are sending too many messages. Take a short break.' using errcode = 'P0001', hint = 'too_fast';
  end if;
  v_masked := bl_chat_mask(v_body);
  delete from crew_messages where id in (select id from crew_messages where created_at < v_now - make_interval(secs => (bl_crew_num('crew.chat_retention_hours', 168) * 3600)::double precision) order by id limit 200);
  insert into crew_messages (crew_id, user_id, username, body, created_at) values (m.crew_id, v_uid, p.username, v_masked, v_now) returning * into x;
  return jsonb_build_object('id', x.id, 'username', x.username, 'body', x.body, 'created_at', x.created_at, 'mine', true, 'masked', v_masked <> v_body);
end $$;

create or replace function public.crew_chat_recent(p_after bigint default 0, p_limit int default 50) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); m crew_members; v_lim int := least(greatest(coalesce(p_limit, 50), 1), 100);
begin
  m := bl_crew_need(v_uid, 0, false);
  return jsonb_build_object('rows', coalesce((
    select jsonb_agg(jsonb_build_object('id', x.id, 'user_id', x.user_id, 'username', x.username, 'body', x.body, 'created_at', x.created_at, 'mine', x.user_id = v_uid,
                                        'rank', (select cm.rank from crew_members cm where cm.user_id = x.user_id and cm.crew_id = m.crew_id)) order by x.id)
      from (select * from crew_messages where crew_id = m.crew_id and id > coalesce(p_after, 0) order by id desc limit v_lim) x), '[]'::jsonb));
end $$;

-- Report a crew (name abuse and the like). One report per player per crew; admins see the count.
create or replace function public.crew_report(p_crew bigint, p_reason text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); c crews;
begin
  select * into c from crews where id = p_crew and disbanded_at is null;
  if not found then
    raise exception 'That crew no dey again.' using errcode = 'P0001', hint = 'gone';
  end if;
  if exists (select 1 from crew_members where user_id = v_uid and crew_id = c.id) then
    raise exception 'You cannot report your own crew. Leave it instead.' using errcode = 'P0001', hint = 'own_crew';
  end if;
  if (select count(*) from crew_reports where reporter_id = v_uid and created_at > bl_now() - interval '24 hours') >= 5 then
    raise exception 'You have reported enough for today.' using errcode = 'P0001', hint = 'rate_limit';
  end if;
  insert into crew_reports (crew_id, reporter_id, reason, created_at) values (c.id, v_uid, left(coalesce(nullif(bl_chat_clean(p_reason), ''), 'no reason'), 200), bl_now())
  on conflict do nothing;
  return jsonb_build_object('message', 'Thanks. A moderator will look at it.');
end $$;

-- Top crews this week (+ last week's winners)
create or replace function public.crew_top(p_limit int default 20) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid(); v_lim int := least(greatest(coalesce(p_limit, 20), 1), 50); v_wk date := bl_week_start(); v_mine bigint; v_last date; v_rows jsonb;
begin
  perform bl_crew_week_settle();
  select crew_id into v_mine from crew_members where user_id = v_uid;
  select coalesce(jsonb_agg(jsonb_build_object('rank', r.rank, 'crew_id', r.crew_id, 'name', r.name, 'tag', r.tag, 'emblem', r.emblem, 'color', r.color, 'level', r.level,
                                               'jobs', r.jobs, 'loot', r.loot, 'mine', r.crew_id = v_mine) order by r.rank), '[]'::jsonb)
    into v_rows from bl_crew_week_ranked(v_wk) r where r.rank <= v_lim;
  select max(week_start) into v_last from crew_week_winners;
  return jsonb_build_object(
    'enabled', coalesce((select (value #>> '{}')::boolean from game_config where key = 'crew.weekly_enabled'), true),
    'week_start', v_wk, 'ends_at', bl_week_from(v_wk + 7), 'rows', v_rows,
    'prizes', jsonb_build_array(jsonb_build_object('rank', 1, 'amount', bl_crew_num('crew.weekly_prize_1', 500000)),
                                jsonb_build_object('rank', 2, 'amount', bl_crew_num('crew.weekly_prize_2', 250000)),
                                jsonb_build_object('rank', 3, 'amount', bl_crew_num('crew.weekly_prize_3', 100000))),
    'min_jobs', bl_crew_num('crew.weekly_min_jobs', 2),
    'mine', (select jsonb_build_object('rank', r.rank, 'jobs', r.jobs, 'loot', r.loot) from bl_crew_week_ranked(v_wk) r where r.crew_id = v_mine),
    'last_week', case when v_last is null then null else jsonb_build_object('week_start', v_last,
        'winners', coalesce((select jsonb_agg(jsonb_build_object('rank', w.rank, 'name', w.crew_name, 'tag', w.tag, 'jobs', w.jobs, 'loot', w.loot, 'prize', w.prize) order by w.rank)
                               from crew_week_winners w where w.week_start = v_last), '[]'::jsonb)) end);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 8. Crew jobs: lobby, start, one roll
-- ---------------------------------------------------------------------------------------------
-- Start a lobby: drop members who no longer qualify, cancel when too few are left, charge the supplies, then the clock runs.
create or replace function public.bl_crew_run_start(p_run bigint) returns void
language plpgsql set search_path = public as $$
declare
  r crew_runs; j crew_jobs; c crews; x record; p profiles; u uuid;
  v_ok uuid[] := '{}'; v_gate jsonb; v_now timestamptz := bl_now(); v_pct jsonb; v_until timestamptz;
begin
  select * into r from crew_runs where id = p_run and status = 'lobby' for update;
  if not found then return; end if;
  select * into j from crew_jobs where id = r.job_id;
  select * into c from crews where id = r.crew_id;
  perform 1 from profiles where id in (select user_id from crew_run_members where run_id = r.id) order by id for update;
  for x in select user_id from crew_run_members where run_id = r.id order by joined_at, user_id loop
    v_gate := bl_crew_gate(x.user_id, 'start');
    select * into p from profiles where id = x.user_id;
    if v_gate is null and not exists (select 1 from crew_members where user_id = x.user_id and crew_id = r.crew_id) then
      v_gate := jsonb_build_object('message', 'You are no longer in the crew.');
    end if;
    if v_gate is null and j.buy_in > 0 and p.cash + greatest(p.bank, 0) < j.buy_in then
      v_gate := jsonb_build_object('message', 'You could not cover the ' || bl_naira(j.buy_in) || ' supplies.');
    end if;
    if v_gate is null then
      v_ok := v_ok || x.user_id;
    else
      delete from crew_run_members where run_id = r.id and user_id = x.user_id;
      perform bl_event(x.user_id, 'crew_job_drop', 'You miss the crew job', v_gate->>'message', jsonb_build_object('run', r.id));
    end if;
  end loop;
  if cardinality(v_ok) < j.min_members then
    update crew_runs set status = 'cancelled', resolved_at = v_now, note = 'Not enough hands ready (' || cardinality(v_ok) || ' of ' || j.min_members || ' needed).' where id = r.id;
    foreach u in array v_ok loop
      perform bl_event(u, 'crew_job_cancel', j.name || ' called off', 'Not enough hands were ready (' || cardinality(v_ok) || ' of ' || j.min_members || ' needed).', jsonb_build_object('run', r.id));
    end loop;
    delete from crew_run_members where run_id = r.id;
    return;
  end if;
  if j.buy_in > 0 then
    foreach u in array v_ok loop
      perform bl_crew_pay(u, j.buy_in, 'crew_job', jsonb_build_object('label', 'Crew job supplies: ' || j.name, 'run', r.id, 'crew', c.id));
    end loop;
  end if;
  v_pct := bl_crew_job_pct(v_ok, j);
  v_until := v_now + make_interval(secs => j.duration_seconds);
  update crew_runs set status = 'running', started_at = v_now, resolve_at = v_until, job_name = j.name, member_count = cardinality(v_ok),
         base_pct = (v_pct->>'base')::numeric, caught_pct = (v_pct->>'pct')::numeric, skill_cut_pct = (v_pct->>'cut')::numeric,
         split_bank_pct = c.split_bank_pct where id = r.id;
  update crew_run_members y set buy_in = j.buy_in, rank = (select m.rank from crew_members m where m.user_id = y.user_id) where y.run_id = r.id;
  update profiles set busy_until = v_until, busy_started_at = v_now, busy_label = 'Crew job: ' || j.name, busy_needs_from = null where id = any (v_ok);
  foreach u in array v_ok loop
    perform bl_event(u, 'crew_job_start', j.icon || ' ' || j.name || ' don start',
      cardinality(v_ok) || ' in the crew. Nobody move.', jsonb_build_object('run', r.id));
  end loop;
end $$;

-- Resolve a running job once its time is up: ONE roll for the crew.
-- Caught = every participant is jailed through the jail flow and the crew bank pays a fine.
-- Paid = the pot (reward range x level bonus x member bonus) splits into the crew bank (the Boss's %) and the members' cash.
create or replace function public.bl_crew_run_resolve(p_run bigint) returns void
language plpgsql set search_path = public as $$
declare
  r crew_runs; j crew_jobs; c crews; x record; v_ids uuid[]; v_now timestamptz := bl_now(); v_n int;
  v_pot bigint; v_bank bigint; v_pool bigint; v_amt bigint; v_paid bigint := 0; v_wsum numeric := 0; v_w numeric; v_rest bigint; v_fine bigint; v_case bigint;
  v_lvl crew_levels; v_psh numeric := greatest(0, least(100, bl_crew_num('crew.prospect_share_pct', 50))) / 100.0;
begin
  select * into r from crew_runs where id = p_run and status = 'running' for update;
  if not found or r.resolve_at > v_now then return; end if;
  select * into j from crew_jobs where id = r.job_id;
  select * into c from crews where id = r.crew_id for update;
  select coalesce(array_agg(user_id order by user_id), '{}') into v_ids from crew_run_members where run_id = r.id;
  v_n := cardinality(v_ids);
  if v_n = 0 then
    update crew_runs set status = 'cancelled', resolved_at = v_now, note = 'Nobody was left on the job.' where id = r.id;
    return;
  end if;
  perform 1 from profiles where id = any (v_ids) order by id for update;

  if bl_crime_roll(coalesce(r.caught_pct, j.caught_pct)) then
    for x in select user_id from crew_run_members where run_id = r.id order by user_id loop
      v_case := bl_crew_bust(x.user_id, r.id, j.name);
      update crew_run_members set jail_case = v_case where run_id = r.id and user_id = x.user_id;
    end loop;
    v_fine := least(greatest(0, bl_crew_num('crew.bust_fine_max', 2000000))::bigint, floor(c.bank * greatest(0, least(100, bl_crew_num('crew.bust_fine_pct', 15))) / 100.0)::bigint);
    if v_fine > 0 then
      perform bl_crew_bank(c.id, null, -v_fine, 'fine', 'Legal fees after the busted ' || j.name);
    end if;
    update crews set jobs_caught = jobs_caught + 1 where id = c.id;
    update crew_runs set status = 'caught', resolved_at = v_now, fine = coalesce(v_fine, 0),
           note = 'The police caught the whole crew.' where id = r.id;
    perform bl_crew_notify(c.id, null, 'crew_job_busted', j.icon || ' ' || j.name || ' got busted',
      'The police caught ' || v_n || ' of the crew.' || case when v_fine > 0 then ' The crew bank paid ' || bl_naira(v_fine) || ' in legal fees.' else '' end, false, jsonb_build_object('run', r.id));
  else
    v_lvl := bl_crew_level_row(c.level);
    v_pot := j.reward_min + floor(bl_rand() * (greatest(j.reward_max, j.reward_min) - j.reward_min + 1))::bigint;
    v_pot := round(v_pot * (1 + v_lvl.bonus_pct / 100.0) * (1 + greatest(0, bl_crew_num('crew.member_bonus_pct', 8)) * (v_n - 1) / 100.0))::bigint;
    v_bank := floor(v_pot * coalesce(r.split_bank_pct, c.split_bank_pct) / 100.0)::bigint;
    v_pool := v_pot - v_bank;
    select coalesce(sum(case when coalesce(m.rank, 'member') = 'prospect' then v_psh else 1 end), 0) into v_wsum
      from crew_run_members y left join crew_members m on m.user_id = y.user_id where y.run_id = r.id;
    for x in select y.user_id, coalesce(m.rank, 'member') as rank from crew_run_members y left join crew_members m on m.user_id = y.user_id where y.run_id = r.id order by y.user_id loop
      v_w := case when x.rank = 'prospect' then v_psh else 1 end;
      v_amt := case when v_wsum > 0 then greatest(0, floor(v_pool * v_w / v_wsum / 100) * 100)::bigint else 0 end;
      if v_amt > 0 then
        perform bl_add_money(x.user_id, 'cash', v_amt, 'crew_payout', jsonb_build_object('label', 'Crew job: ' || j.name, 'run', r.id, 'crew', c.id));
      end if;
      v_paid := v_paid + v_amt;
      update crew_run_members set payout = v_amt where run_id = r.id and user_id = x.user_id;
      update crew_members set jobs = jobs + 1, earned = earned + v_amt where user_id = x.user_id;
      update profiles set busy_until = null, busy_label = null, busy_started_at = null, busy_needs_from = null
       where id = x.user_id and busy_label like 'Crew job:%';
      perform bl_skill_award(x.user_id, 'crew', j.id);
      perform bl_event(x.user_id, 'crew_job_paid', j.icon || ' ' || j.name || ' paid: +' || bl_naira(v_amt),
        'Your share of the ' || bl_naira(v_pot) || ' loot is in your cash. Part of it went to the crew bank.',
        jsonb_build_object('run', r.id, 'amount', v_amt, 'pot', v_pot));
    end loop;
    v_rest := v_pool - v_paid;     -- rounding (and the Prospects' unclaimed part) stays in the crew bank
    perform bl_crew_bank(c.id, null, v_bank + v_rest, 'job', 'Loot from ' || j.name || ' (' || v_n || ' members)');
    update crews set xp = xp + j.xp, jobs_done = jobs_done + 1, loot_total = loot_total + v_pot where id = c.id;
    update crew_runs set status = 'paid', resolved_at = v_now, pot = v_pot, bank_share = v_bank + v_rest,
           note = 'The job paid. +' || j.xp || ' crew XP.' where id = r.id;
  end if;
end $$;

-- Move the crew's open run on: start a lobby whose countdown ended, resolve a job whose time is up (the caller holds the crew lock)
create or replace function public.bl_crew_tick(p_crew bigint) returns void
language plpgsql set search_path = public as $$
declare r crew_runs;
begin
  select * into r from crew_runs where crew_id = p_crew and status in ('lobby', 'running') order by id desc limit 1 for update;
  if not found then return; end if;
  if r.status = 'lobby' and r.lobby_until <= bl_now() then
    perform bl_crew_run_start(r.id);
  elsif r.status = 'running' and r.resolve_at <= bl_now() then
    perform bl_crew_run_resolve(r.id);
  end if;
end $$;

-- a leaving / deleted Boss: the oldest Lieutenant (then Member, then Prospect) takes over; an empty crew closes
create or replace function public.bl_crew_member_gone() returns trigger
language plpgsql set search_path = public as $$
declare c crews; v_next uuid;
begin
  select * into c from crews where id = old.crew_id;
  if not found or c.disbanded_at is not null then return old; end if;
  if not exists (select 1 from crew_members where crew_id = old.crew_id) then
    update crews set disbanded_at = bl_now(), disbanded_reason = 'No members left.' where id = old.crew_id;
    return old;
  end if;
  if old.rank = 'boss' and not exists (select 1 from crew_members where crew_id = old.crew_id and rank = 'boss') then
    select user_id into v_next from crew_members where crew_id = old.crew_id order by bl_crew_rank_n(rank) desc, joined_at, user_id limit 1;
    update crew_members set rank = 'boss' where user_id = v_next;
    perform bl_event(v_next, 'crew_rank', 'You are the new Boss', 'The old Boss is gone, so ' || c.name || ' is yours now.', jsonb_build_object('crew', c.id, 'rank', 'boss'));
  end if;
  return old;
end $$;
drop trigger if exists bl_crew_member_gone_trg on public.crew_members;
create trigger bl_crew_member_gone_trg after delete on public.crew_members for each row execute function public.bl_crew_member_gone();

create or replace function public.crew_job_open(p_job text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid(); m crew_members; c crews; j crew_jobs; r crew_runs; v_gate jsonb; v_last timestamptz; v_who text;
begin
  perform bl_crew_guard();
  m := bl_crew_need(v_uid, 2);
  select * into c from crews where id = m.crew_id;
  perform bl_crew_tick(c.id);
  select * into j from crew_jobs where id = p_job and active;
  if not found then
    raise exception 'That job is not on the board.' using errcode = 'P0001', hint = 'bad_job';
  end if;
  if c.level < j.min_crew_level then
    raise exception 'Your crew must be level % for this job.', j.min_crew_level using errcode = 'P0001', hint = 'crew_level';
  end if;
  if exists (select 1 from crew_runs where crew_id = c.id and status in ('lobby', 'running')) then
    raise exception 'The crew already has a job open or running.' using errcode = 'P0001', hint = 'run_open';
  end if;
  select max(started_at) into v_last from crew_runs where crew_id = c.id and job_id = j.id and started_at is not null and status in ('running', 'paid', 'caught');
  if v_last is not null and j.cooldown_seconds > 0 and v_last + make_interval(secs => j.cooldown_seconds) > bl_now() then
    raise exception 'The crew must lie low on this one for about % minutes.', greatest(1, ceil(extract(epoch from v_last + make_interval(secs => j.cooldown_seconds) - bl_now()) / 60))::int
      using errcode = 'P0001', hint = 'cooldown';
  end if;
  if (select count(*) from crew_runs where crew_id = c.id and started_at > bl_now() - interval '24 hours') >= bl_crew_num('crew.max_jobs_per_day', 8) then
    raise exception 'The crew has done enough jobs today. Rest.' using errcode = 'P0001', hint = 'daily_cap';
  end if;
  if (select count(*) from crew_members where crew_id = c.id) < j.min_members then
    raise exception 'This job needs % crew members. Recruit more.', j.min_members using errcode = 'P0001', hint = 'too_few';
  end if;
  perform 1 from profiles where id = v_uid for update;
  v_gate := bl_crew_gate(v_uid, 'join');
  if v_gate is not null then
    raise exception '%', v_gate->>'message' using errcode = 'P0001', hint = coalesce(v_gate->>'hint', 'cannot_join');
  end if;
  insert into crew_runs (crew_id, job_id, job_name, started_by, lobby_until, created_at)
  values (c.id, j.id, j.name, v_uid, bl_now() + make_interval(secs => bl_crew_num('crew.lobby_seconds', 120)::double precision), bl_now())
  returning * into r;
  insert into crew_run_members (run_id, user_id, rank, joined_at) values (r.id, v_uid, m.rank, bl_now());
  select username into v_who from profiles where id = v_uid;
  perform bl_crew_notify(c.id, v_uid, 'crew_job_lobby', j.icon || ' ' || j.name || ': @' || v_who || ' is gathering the crew',
    'Go to a meeting spot and join in the Crew app. Starts in about ' || (bl_crew_num('crew.lobby_seconds', 120) / 60.0)::numeric(10, 1) || ' min.', true, jsonb_build_object('run', r.id));
  return jsonb_build_object('message', 'Lobby open. Wait for your crew at the meeting spot.', 'run', bl_crew_run_json(r, v_uid));
end $$;

create or replace function public.crew_job_join(p_run bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); m crew_members; r crew_runs; j crew_jobs; v_gate jsonb;
begin
  perform bl_crew_guard();
  m := bl_crew_need(v_uid, 0);
  perform bl_crew_tick(m.crew_id);
  select * into r from crew_runs where id = p_run and crew_id = m.crew_id for update;
  if not found or r.status <> 'lobby' then
    raise exception 'That lobby is closed.' using errcode = 'P0001', hint = 'not_open';
  end if;
  select * into j from crew_jobs where id = r.job_id;
  if exists (select 1 from crew_run_members where run_id = r.id and user_id = v_uid) then
    return jsonb_build_object('message', 'You are already in.', 'run', bl_crew_run_json(r, v_uid));
  end if;
  perform 1 from profiles where id = v_uid for update;
  v_gate := bl_crew_gate(v_uid, 'join');
  if v_gate is not null then
    raise exception '%', v_gate->>'message' using errcode = 'P0001', hint = coalesce(v_gate->>'hint', 'cannot_join');
  end if;
  if (select count(*) from crew_run_members where run_id = r.id) >= j.max_members then
    raise exception 'The crew for this job is full.' using errcode = 'P0001', hint = 'full';
  end if;
  insert into crew_run_members (run_id, user_id, rank, joined_at) values (r.id, v_uid, m.rank, bl_now());
  return jsonb_build_object('message', 'You are in for ' || j.name || '.', 'run', bl_crew_run_json(r, v_uid));
end $$;

create or replace function public.crew_job_leave(p_run bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); m crew_members; r crew_runs;
begin
  m := bl_crew_need(v_uid, 0);
  select * into r from crew_runs where id = p_run and crew_id = m.crew_id and status = 'lobby' for update;
  if not found then
    raise exception 'That lobby is closed.' using errcode = 'P0001', hint = 'not_open';
  end if;
  if r.started_by = v_uid then
    update crew_runs set status = 'cancelled', resolved_at = bl_now(), note = 'The organiser called it off.' where id = r.id;
    delete from crew_run_members where run_id = r.id;
    return jsonb_build_object('message', 'Job called off.');
  end if;
  delete from crew_run_members where run_id = r.id and user_id = v_uid;
  return jsonb_build_object('message', 'You left the lobby.');
end $$;

create or replace function public.crew_job_cancel(p_run bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); m crew_members; r crew_runs; v_who text;
begin
  m := bl_crew_need(v_uid, 2);
  select * into r from crew_runs where id = p_run and crew_id = m.crew_id and status = 'lobby' for update;
  if not found then
    raise exception 'That lobby is closed.' using errcode = 'P0001', hint = 'not_open';
  end if;
  select username into v_who from profiles where id = v_uid;
  update crew_runs set status = 'cancelled', resolved_at = bl_now(), note = '@' || v_who || ' called it off.' where id = r.id;
  perform bl_crew_notify(m.crew_id, v_uid, 'crew_job_cancel', 'Job called off', '@' || v_who || ' cancelled the lobby.', false, jsonb_build_object('run', r.id));
  delete from crew_run_members where run_id = r.id;
  return jsonb_build_object('message', 'Job called off.');
end $$;

create or replace function public.crew_job_start(p_run bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); m crew_members; r crew_runs; j crew_jobs;
begin
  perform bl_crew_guard();
  m := bl_crew_need(v_uid, 2);
  select * into r from crew_runs where id = p_run and crew_id = m.crew_id and status = 'lobby' for update;
  if not found then
    raise exception 'That lobby is closed.' using errcode = 'P0001', hint = 'not_open';
  end if;
  select * into j from crew_jobs where id = r.job_id;
  if (select count(*) from crew_run_members where run_id = r.id) < j.min_members then
    raise exception 'You need at least % members in the lobby.', j.min_members using errcode = 'P0001', hint = 'too_few';
  end if;
  perform bl_crew_run_start(r.id);
  select * into r from crew_runs where id = p_run;
  return jsonb_build_object('message', case r.status when 'running' then j.name || ' don start.' else coalesce(r.note, 'The job was called off.') end,
                            'run', bl_crew_run_json(r, v_uid));
end $$;

-- ---------------------------------------------------------------------------------------------
-- 9. Admin: Crews list (the member view is audited), disband, rename, report review
-- ---------------------------------------------------------------------------------------------
create or replace function public.admin_crews_list(p_q text default '', p_limit int default 100) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_lim int := least(greatest(coalesce(p_limit, 100), 1), 300); v_q text := lower(btrim(coalesce(p_q, ''))); v_flag int := bl_crew_num('crew.report_flag_count', 3)::int;
begin
  perform bl_admin_guard();
  return jsonb_build_object(
    'stats', jsonb_build_object('crews', (select count(*) from crews where disbanded_at is null),
                                'members', (select count(*) from crew_members m join crews c on c.id = m.crew_id where c.disbanded_at is null),
                                'bank', (select coalesce(sum(bank), 0) from crews where disbanded_at is null),
                                'open_reports', (select count(*) from crew_reports r join crews c on c.id = r.crew_id where r.status = 'open' and c.disbanded_at is null),
                                'jobs_7d', (select count(*) from crew_runs where status in ('paid', 'caught') and resolved_at > bl_now() - interval '7 days')),
    'rows', coalesce((
      select jsonb_agg(jsonb_build_object('id', x.id, 'name', x.name, 'tag', x.tag, 'emblem', x.emblem, 'color', x.color, 'level', x.level, 'members', x.n,
                                          'bank', x.bank, 'boss', x.boss, 'jobs_done', x.jobs_done, 'jobs_caught', x.jobs_caught, 'loot_total', x.loot_total,
                                          'reports', x.reports, 'flagged', x.reports >= v_flag, 'recruiting', x.recruiting, 'created_at', x.created_at)
                       order by x.reports desc, x.id desc)
        from (select c.*, (select count(*) from crew_members m where m.crew_id = c.id) as n,
                     (select p.username from crew_members m join profiles p on p.id = m.user_id where m.crew_id = c.id and m.rank = 'boss') as boss,
                     (select count(*) from crew_reports r where r.crew_id = c.id and r.status = 'open') as reports
                from crews c
               where c.disbanded_at is null and (v_q = '' or lower(c.name) like '%' || replace(replace(v_q, '%', ''), '_', '') || '%' or lower(c.tag) = v_q)
               order by c.id desc limit v_lim) x), '[]'::jsonb));
end $$;

create or replace function public.admin_crew_get(p_crew bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); c crews;
begin
  select * into c from crews where id = p_crew;
  if not found then
    raise exception 'No such crew.' using errcode = 'P0001', hint = 'gone';
  end if;
  insert into admin_audit (admin_id, action, target_user, data) values (v_admin, 'crew_view', null, jsonb_build_object('crew', c.id, 'name', c.name, 'tag', c.tag));
  return jsonb_build_object(
    'crew', jsonb_build_object('id', c.id, 'name', c.name, 'tag', c.tag, 'emblem', c.emblem, 'color', c.color, 'level', c.level, 'xp', c.xp, 'bank', c.bank,
                               'split_bank_pct', c.split_bank_pct, 'recruiting', c.recruiting, 'jobs_done', c.jobs_done, 'jobs_caught', c.jobs_caught,
                               'loot_total', c.loot_total, 'created_at', c.created_at, 'disbanded_at', c.disbanded_at, 'disbanded_reason', c.disbanded_reason),
    'members', coalesce((select jsonb_agg(jsonb_build_object('id', m.user_id, 'username', p.username, 'rank', m.rank, 'joined_at', m.joined_at, 'deposited', m.deposited,
                                                              'jobs', m.jobs, 'earned', m.earned, 'last_seen', p.last_seen)
                                          order by bl_crew_rank_n(m.rank) desc, m.joined_at)
                           from crew_members m join profiles p on p.id = m.user_id where m.crew_id = c.id), '[]'::jsonb),
    'reports', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'reason', r.reason, 'status', r.status, 'by', p.username, 'created_at', r.created_at) order by r.id desc)
                           from crew_reports r left join profiles p on p.id = r.reporter_id where r.crew_id = c.id), '[]'::jsonb),
    'bank_log', coalesce((select jsonb_agg(jsonb_build_object('kind', l.kind, 'amount', l.amount, 'balance_after', l.balance_after, 'note', l.note, 'created_at', l.created_at) order by l.id desc)
                            from (select * from crew_bank_log where crew_id = c.id order by id desc limit 30) l), '[]'::jsonb),
    'runs', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'job', r.job_name, 'status', r.status, 'pot', r.pot, 'members', r.member_count, 'created_at', r.created_at) order by r.id desc)
                        from (select * from crew_runs where crew_id = c.id order by id desc limit 10) r), '[]'::jsonb));
end $$;

create or replace function public.admin_crew_disband(p_crew bigint, p_reason text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); c crews; v jsonb; v_reason text := left(btrim(coalesce(p_reason, '')), 200);
begin
  select * into c from crews where id = p_crew and disbanded_at is null for update;
  if not found then
    raise exception 'That crew is gone already.' using errcode = 'P0001', hint = 'gone';
  end if;
  v := bl_crew_dissolve(c.id, v_admin, coalesce(nullif(v_reason, ''), 'Disbanded by an admin.'));
  insert into admin_audit (admin_id, action, target_user, data)
  values (v_admin, 'crew_disband', null, jsonb_build_object('crew', c.id, 'name', c.name, 'tag', c.tag, 'reason', v_reason, 'members', v->'members', 'bank_returned', v->'bank'));
  return jsonb_build_object('message', c.name || ' disbanded.');
end $$;

create or replace function public.admin_crew_rename(p_crew bigint, p_name text, p_tag text default null, p_reason text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); c crews; v_chk jsonb; v_reason text := left(btrim(coalesce(p_reason, '')), 200); v_boss uuid;
begin
  select * into c from crews where id = p_crew and disbanded_at is null for update;
  if not found then
    raise exception 'That crew is gone already.' using errcode = 'P0001', hint = 'gone';
  end if;
  v_chk := bl_crew_name_check(coalesce(nullif(btrim(p_name), ''), c.name), nullif(btrim(coalesce(p_tag, '')), ''), c.id);
  if not (v_chk->>'ok')::boolean then
    raise exception '%', v_chk->>'message' using errcode = 'P0001', hint = v_chk->>'hint';
  end if;
  update crews set name = coalesce(v_chk->>'name', name), tag = coalesce(v_chk->>'tag', tag) where id = c.id;
  insert into admin_audit (admin_id, action, target_user, data)
  values (v_admin, 'crew_rename', null, jsonb_build_object('crew', c.id, 'old_name', c.name, 'old_tag', c.tag, 'new_name', coalesce(v_chk->>'name', c.name),
                                                           'new_tag', coalesce(v_chk->>'tag', c.tag), 'reason', v_reason));
  perform bl_crew_notify(c.id, null, 'crew_renamed', 'Your crew was renamed', 'An admin renamed the crew to ' || coalesce(v_chk->>'name', c.name) || ' [' || coalesce(v_chk->>'tag', c.tag) || ']'
    || case when v_reason <> '' then '. Reason: ' || v_reason else '.' end, false);
  return jsonb_build_object('message', 'Crew renamed.');
end $$;

create or replace function public.admin_crew_dismiss_reports(p_crew bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); n int;
begin
  update crew_reports set status = 'reviewed' where crew_id = p_crew and status = 'open';
  get diagnostics n = row_count;
  insert into admin_audit (admin_id, action, target_user, data) values (v_admin, 'crew_reports_dismiss', null, jsonb_build_object('crew', p_crew, 'reports', n));
  return jsonb_build_object('message', n || ' report(s) marked reviewed.');
end $$;

-- ---------------------------------------------------------------------------------------------
-- 10. Patches to live functions (guarded)
-- ---------------------------------------------------------------------------------------------
-- the tag next to a name: people in a place, public profiles, chat rows, friend cards
select pg_temp.bl_patch1('public.players_here(text)', 'bl_crew_badge(',
  E'''gold'', public.bl_lounge_gold(p.id, p_location))',
  E'''gold'', public.bl_lounge_gold(p.id, p_location), ''crew'', public.bl_crew_badge(p.id))');
select pg_temp.bl_patch1('public.get_public_profile(uuid)', 'bl_crew_badge(',
  E'''certificates'', bl_cert_list(id))',
  E'''certificates'', bl_cert_list(id), ''crew'', bl_crew_badge(id))');
select pg_temp.bl_patch1('public.bl_chat_row(public.chat_messages, jsonb, uuid)', 'm.crew_tag',
  E'''reply_to'', m.reply_to,',
  E'''crew_tag'', m.crew_tag, ''reply_to'', m.reply_to,');
select pg_temp.bl_patch1('public.bl_friend_card(public.profiles, public.profiles, numeric, boolean)', 'bl_crew_badge(',
  E'''yahoo_ready'', v_yahoo,',
  E'''yahoo_ready'', v_yahoo, ''crew'', bl_crew_badge(o.id),');

-- ledger text
select pg_temp.bl_patch1('public.bl_ledger_label(text, jsonb)', 'when ''crew_deposit'' then',
  E'    when ''garage'' then return',
  E'    when ''crew_deposit'' then return coalesce(nullif(p_meta->>''label'', ''''), ''Crew bank deposit'');\n    when ''crew_payout'' then return coalesce(nullif(p_meta->>''label'', ''''), ''Crew job loot'');\n    when ''crew_job'' then return coalesce(nullif(p_meta->>''label'', ''''), ''Crew job supplies'');\n    when ''crew_fee'' then return coalesce(nullif(p_meta->>''label'', ''''), ''Crew founding fee'');\n    when ''crew_refund'' then return coalesce(nullif(p_meta->>''label'', ''''), ''Crew refund'');\n    when ''garage'' then return');

-- admin Content editors
select pg_temp.bl_patch1('public.bl_admin_table_spec(text)', 'when ''crew_jobs'' then',
  E'    when ''business_types'' then',
  E'    when ''crew_jobs'' then ''{"pk":["id"],"insert":true,"order":"sort, id",\n      "cols":{"name":"text","icon":"text","blurb":"text","min_members":"int","max_members":"int","min_crew_level":"int","duration_seconds":"int","reward_min":"money","reward_max":"money","caught_pct":"num","cooldown_seconds":"int","buy_in":"money","skills":"arr","xp":"int","sort":"int","active":"bool"}}''\n    when ''crew_levels'' then ''{"pk":["level"],"insert":true,"order":"level",\n      "cols":{"name":"text","xp_needed":"money","upgrade_cost":"money","max_members":"int","bonus_pct":"num","perks":"text"}}''\n    when ''business_types'' then');

-- ---------------------------------------------------------------------------------------------
-- 11. Grants
-- ---------------------------------------------------------------------------------------------
-- every private helper (and the two triggers): not callable by clients
do $$
declare r record;
begin
  for r in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.proname like 'bl\_crew\_%' loop
    execute format('revoke all on function %s from public, anon, authenticated', r.sig);
  end loop;
end $$;

do $$
declare f text;
begin
  foreach f in array array[
    'crew_status()', 'crew_browse(text, int)', 'crew_create(text, text, text, text)', 'crew_invite_candidates(text)', 'crew_invite(uuid, text)',
    'crew_invite_cancel(bigint)', 'crew_invite_respond(bigint, boolean)', 'crew_join_open(bigint)', 'crew_leave()', 'crew_kick(uuid)',
    'crew_set_rank(uuid, text)', 'crew_transfer(uuid)', 'crew_disband()', 'crew_options(numeric, boolean)', 'crew_rename(text)',
    'crew_deposit(bigint)', 'crew_upgrade()', 'crew_bank_log_list(int)', 'crew_chat_send(text)', 'crew_chat_recent(bigint, int)',
    'crew_report(bigint, text)', 'crew_top(int)', 'crew_job_open(text)', 'crew_job_join(bigint)', 'crew_job_leave(bigint)',
    'crew_job_cancel(bigint)', 'crew_job_start(bigint)',
    'admin_crews_list(text, int)', 'admin_crew_get(bigint)', 'admin_crew_disband(bigint, text)', 'admin_crew_rename(bigint, text, text, text)',
    'admin_crew_dismiss_reports(bigint)'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated, service_role', f);
  end loop;
end $$;

notify pgrst, 'reload schema';
