-- R12 Politics and government, "Benin Votes" (docs/POLITICS.md). A FICTIONAL, light, satirical game system: no real party (APC, PDP, LP ...),
-- no real politician, no real-world election claims. Parties are made up (seeded: Progressive Benin Movement, Oba-Town People's Party ...) or
-- founded by players, and a blocklist in Settings keeps real names out of party names, abbreviations and promise texts.
--   1. Settings `pol.*` (game_config, Settings -> Politics): windows, fees, requirements, campaign costs / points, salary, announcements, blocklists.
--   2. Admin tables (Content): offices (Councillor per ward, Chairman, Governor, six appointed Commissioners), gov_policies (the Governor's
--      whitelist), parties, wards (8 wards = the business areas, each with one polling unit).
--   3. Eight polling units (places pu_*), open ONLY while voting is on (bl_place_open is patched), with a polling desk zone.
--   4. Election cycles run lazily (no cron): registration -> campaign -> voting -> results + swearing-in, then a term. The next cycle starts
--      itself (pol.auto_cycle) so the results land when the term ends. Everybody runs together in one cycle. Admin can start / advance / cancel.
--   5. Candidates (declare with requirements and a fee), campaign (rally, poster, moderated promise, supporters / endorsements / crew
--      endorsements, a momentum indicator), vote buying is NOT a mechanic (report button, admin disqualifies, audited).
--   6. Voting: server side, one vote per account per office per election, at your ward's polling unit, only while voting is open, accounts
--      older than pol.vote_min_account_days. Tallies are secret until the close. Ties: most rally points, then a deterministic coin flip.
--   7. In office: title badge (places, chat, profiles, friends), a salary per day of term (office_salary, earned), the Governor appoints /
--      sacks Commissioners, posts one Government announcement a day (the broadcast system), sets ONE policy per term from the whitelist
--      (travel discount, council levy cut, Fitness XP bonus, slower hygiene decay; server side, small), a Councillor sponsors one ward notice.
--   8. Ledger: campaign_fee, campaign_spend (spending, never earned), office_salary (earned, added once to leaderboard.earn_reasons).
--   9. Admin: Elections page (start / advance / cancel, candidates, disqualify, remove holder, tallies after close), Content tabs, Settings.
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
('pol.enabled', 'true', 'politics', 'Benin Votes on',
 'R12 (docs/POLITICS.md): politics and elections. Off = nothing new can be declared, voted or appointed and the clock freezes (offices and policies stop applying too).', 'bool', null, null),
('pol.auto_cycle', 'true', 'politics', 'Next election starts by itself',
 'R12: after an election that an admin started has closed, the next one starts by itself so its results land when the term ends. A cancelled election never restarts by itself. Off = admin starts every election (Admin -> Elections).', 'bool', null, null),
('pol.registration_hours', '48', 'politics', 'Registration window (hours)', 'R12: real hours candidates can declare (default 2 days).', 'number', 0.01, 2160),
('pol.campaign_hours', '72', 'politics', 'Campaign window (hours)', 'R12: real hours of rallies, posters, endorsements (default 3 days).', 'number', 0.01, 2160),
('pol.voting_hours', '24', 'politics', 'Voting day (hours)', 'R12: real hours the polling units are open and players vote (default 1 day).', 'number', 0.01, 2160),
('pol.term_days', '14', 'politics', 'Term length (days)', 'R12: how long winners and their appointees stay in office. Every office has the same term.', 'number', 0.01, 365),
('pol.vote_min_account_days', '3', 'politics', 'Voting needs account age (days)', 'R12: anti-alt: accounts younger than this cannot vote, back or endorse a candidate, or report one.', 'number', 0, 3650),
('pol.clean_record_days', '7', 'politics', 'No EFCC case in the last (days)', 'R12: a candidate must have no EFCC case (a Yahoo bust) within this many days, and must not be in jail now.', 'number', 0, 3650),
('pol.max_candidates_per_slot', '8', 'politics', 'Most candidates per race', 'R12: a race is one office in one ward (or the city / state race).', 'number', 2, 100),
('pol.promise_max_len', '140', 'politics', 'Campaign promise: longest (characters)', 'R12: the promise is moderated (chat banned words + the blocklists below).', 'number', 20, 500),
('pol.party_fee', '50000', 'politics', 'Founding a party costs', 'R12: a player can found ONE fictional party. Bank first, then cash. Ledger campaign_fee.', 'naira', 0, 1000000000),
('pol.rally_cost', '20000', 'politics', 'Rally costs', 'R12: what a rally costs the candidate. Ledger campaign_spend.', 'naira', 0, 1000000000),
('pol.rally_points', '10', 'politics', 'Rally: base momentum points', 'R12: every rally earns these points (also the tie-break "rally points").', 'number', 0, 1000),
('pol.rally_attendee_points', '2', 'politics', 'Rally: points per player there', 'R12: extra points for every other player standing at the place (so a crowd beats cash).', 'number', 0, 100),
('pol.rally_attendee_cap', '10', 'politics', 'Rally: most players counted', 'R12: caps the crowd bonus.', 'number', 0, 100),
('pol.rally_cooldown_minutes', '20', 'politics', 'Rally cooldown (minutes)', 'R12: least time between two rallies of one candidate.', 'number', 0, 10080),
('pol.rally_max_per_day', '6', 'politics', 'Rallies per candidate per day', 'R12: rate limit in 24 real hours.', 'number', 1, 100),
('pol.poster_cost', '10000', 'politics', 'Poster costs', 'R12: a campaign poster slot (the simple version of a billboard). Ledger campaign_spend.', 'naira', 0, 1000000000),
('pol.poster_points', '3', 'politics', 'Poster: momentum points', 'R12: points per poster.', 'number', 0, 1000),
('pol.poster_cooldown_hours', '6', 'politics', 'Poster cooldown (hours)', 'R12: least time between two posters of one candidate.', 'number', 0, 720),
('pol.poster_max', '5', 'politics', 'Posters per candidate', 'R12: the most posters one candidate can put up in a campaign.', 'number', 1, 100),
('pol.support_points', '1', 'politics', 'Declared supporter: points', 'R12: a player declares support for one candidate per race (anonymous). Not a vote.', 'number', 0, 1000),
('pol.endorse_points', '4', 'politics', 'Public endorsement: points', 'R12: a named player endorsement (needs the Charisma level below).', 'number', 0, 1000),
('pol.crew_endorse_points', '8', 'politics', 'Crew endorsement: points', 'R12: a crew Boss / Lieutenant endorses for the crew (one per crew per race).', 'number', 0, 1000),
('pol.endorse_min_charisma', '2', 'politics', 'Endorsing needs Charisma level', 'R12: a public endorsement needs this Charisma level (skills must be on). 0 or 1 = anybody.', 'number', 0, 10),
('pol.crew_endorse_min_members', '2', 'politics', 'Crew endorsement needs members', 'R12: a crew needs at least this many members to endorse.', 'number', 1, 100),
('pol.report_flag_count', '3', 'politics', 'Reports that flag a candidate', 'R12: "report vote buying" reports. A candidate with this many open reports is highlighted in Admin -> Elections.', 'number', 1, 100),
('pol.report_daily_cap', '5', 'politics', 'Reports per player per day', 'R12: rate limit on vote-buying reports.', 'number', 1, 100),
('pol.salary_enabled', 'true', 'politics', 'Office salary on', 'R12: officeholders earn the daily salary set on each office (Content -> Offices), paid to the bank, ledger office_salary (counted as earned).', 'bool', null, null),
('pol.announce_cooldown_hours', '24', 'politics', 'Government announcement: one every (hours)', 'R12: the Governor can post one announcement to all players per this many hours (the broadcast system).', 'number', 1, 720),
('pol.announce_max_len', '200', 'politics', 'Government announcement: longest (characters)', 'R12: moderated like chat.', 'number', 20, 500),
('pol.ward_announce_max_len', '160', 'politics', 'Ward notice: longest (characters)', 'R12: a Councillor sponsors one ward event notice per term.', 'number', 20, 500),
('pol.appoint_min_account_days', '3', 'politics', 'Commissioner needs account age (days)', 'R12: the Governor can only appoint accounts at least this old.', 'number', 0, 3650),
('pol.blocked_words', '"tinubu,buhari,atiku,obasanjo,goodluck jonathan,peter obi,okpebholo,obaseki,shaibu,izeiyamu,wike,osinbajo,kwankwaso,fashola,sanwoolu,ganduje,tambuwal,amaechi,inec,rigged,rigging"', 'politics', 'Blocked words (real politicians, bodies, claims)',
 'R12: comma-separated. Real politicians, the real election body and real-world election claims must never be used, so promises, announcements and party names that contain any of these (ignoring spaces and punctuation) are refused. Words of 3 letters or fewer match whole words only. Add more as you hear them.', 'text', null, null),
('pol.blocked_party_words', '"apc,pdp,lp,nnpp,adc,apga,sdp,ypp,zlp,adp,accord,all progressives congress,peoples democratic party,labour party,new nigeria peoples party,african democratic congress"', 'politics', 'Blocked real parties',
 'R12: comma-separated. Real party names and abbreviations are refused in party names, abbreviations, promises and announcements. Words of 3 letters or fewer match whole words only.', 'text', null, null)
on conflict (key) do nothing;

-- office_salary is earned money (weekly top earners, challenge "earn"); fees and spending are not. Added once: an admin who removes it later stays removed.
do $$
begin
  if not exists (select 1 from public.game_config where key = 'pol.earn_seeded') then
    update public.game_config
       set value = to_jsonb(rtrim((value #>> '{}'), ',') || ',office_salary')
     where key = 'leaderboard.earn_reasons' and position('office_salary' in (value #>> '{}')) = 0;
    insert into public.game_config (key, value, category, label, description, kind)
    values ('pol.earn_seeded', 'true', 'politics', 'Office salary counted as earned (seeded)',
            'R12: set once by the migration so office_salary is in leaderboard.earn_reasons. Leave it.', 'bool');
  end if;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 2. Polling units (places) and wards
-- ---------------------------------------------------------------------------------------------
-- 8 units, one per ward, 46+ units from every other pin (map_geo_test needs 34). Open only on voting day (bl_place_open is patched below).
insert into public.locations (id, name, district, scene, blurb, risk, night_risk_mult, cctv, keke_ok, congestion, remote_km, x, y, actions, sort, open_hour, close_hour, active) values
('pu_ugbowo', 'Ugbowo Polling Unit', 'ugbowo', 'street', 'A school compound with plastic chairs, a ballot box and one very serious official. Open on voting day only.', .08, 1.2, false, true, 1.0, 0, 570, 140, '{chat}', 181, null, null, true),
('pu_uselu', 'Uselu Polling Unit', 'uselu', 'street', 'A market-side polling unit. Queue dey, gist dey, nobody is allowed to shout. Open on voting day only.', .08, 1.2, false, true, 1.0, 0, 400, 300, '{chat}', 182, null, null, true),
('pu_ring_road', 'Ring Road Polling Unit', 'oredo', 'street', 'Under a canopy near the roundabout, with a very long queue. Open on voting day only.', .08, 1.2, false, true, 1.0, 0, 610, 530, '{chat}', 183, null, null, true),
('pu_gra', 'GRA Polling Unit', 'gra', 'street', 'A quiet polling unit behind tall gates. Even the queue is polite. Open on voting day only.', .06, 1.2, false, true, 1.0, 0, 370, 720, '{chat}', 184, null, null, true),
('pu_sapele_rd', 'Sapele Road Polling Unit', 'sapele_rd', 'street', 'Beside the traders, so the queue sells pure water too. Open on voting day only.', .08, 1.2, false, true, 1.0, 0, 660, 740, '{chat}', 185, null, null, true),
('pu_new_benin', 'New Benin Polling Unit', 'new_benin', 'street', 'A church hall turned polling unit for the day. Open on voting day only.', .08, 1.2, false, true, 1.0, 0, 640, 320, '{chat}', 186, null, null, true),
('pu_ikpoba_hill', 'Ikpoba Hill Polling Unit', 'ikpoba_hill', 'street', 'On the hill, with a view and a breeze. Open on voting day only.', .08, 1.2, false, true, 1.0, 0, 720, 510, '{chat}', 187, null, null, true),
('pu_airport_rd', 'Airport Road Polling Unit', 'airport_rd', 'street', 'Planes overhead, ballot box below. Open on voting day only.', .08, 1.2, false, true, 1.0, 0, 330, 510, '{chat}', 188, null, null, true)
on conflict (id) do nothing;

create table if not exists public.wards (
  id        text primary key,
  name      text not null,
  districts text[] not null default '{}',               -- the map districts that belong to this ward (a player's home district decides their ward)
  poll_unit text references public.locations(id) on update cascade on delete set null,
  sort      int not null default 0,
  active    boolean not null default true
);
insert into public.wards (id, name, districts, poll_unit, sort) values
('ugbowo',      'Ugbowo',      '{ugbowo,oluku}',                                         'pu_ugbowo',      1),
('uselu',       'Uselu',       '{uselu,aduwawa}',                                        'pu_uselu',       2),
('ring_road',   'Ring Road',   '{oredo,siluko,third_east,sakponba,upper_sakponba}',       'pu_ring_road',   3),
('gra',         'GRA',         '{gra}',                                                  'pu_gra',         4),
('sapele_rd',   'Sapele Rd',   '{sapele_rd}',                                            'pu_sapele_rd',   5),
('new_benin',   'New Benin',   '{new_benin,evbuomore,iguobazuwa}',                       'pu_new_benin',   6),
('ikpoba_hill', 'Ikpoba Hill', '{ikpoba_hill}',                                          'pu_ikpoba_hill', 7),
('airport_rd',  'Airport Rd',  '{airport_rd,ekenwan}',                                   'pu_airport_rd',  8)
on conflict (id) do nothing;

-- the polling desk (a zone every unit shares, in each unit's own zone list so the shared street zones stay as they are)
insert into public.place_zones (id, scene, location_id, zone_key, label, icon, prop, x, z, w, d, rot, note, sort, active)
select l.id || '.desk', null, l.id, 'desk', 'Polling desk', '🗳️', 'desk', 9.5, 6.6, 3, 1.4, 0, 'Show face, collect your ballot, vote once, dip your finger. Na secret.', 6, true
  from public.locations l where l.id like 'pu\_%'
on conflict (id) do nothing;

-- the zone action opens the Benin Votes app on the Vote tab; the panel whitelist gets 'politics'
select pg_temp.bl_patch1('public.bl_zone_action_check()', '''politics'') then',
  $m$'inventory', 'babalawo') then$m$, $m$'inventory', 'babalawo', 'politics') then$m$);
-- ... and the place card offers it without the place listing a tab for it
select pg_temp.bl_patch1('public.place_interior(text)', '''politics'')',
  $m$(za.ref in ('chat', 'inventory', 'activities') or za.ref = any (l.actions))$m$,
  $m$(za.ref in ('chat', 'inventory', 'activities', 'politics') or za.ref = any (l.actions))$m$);
insert into public.zone_actions (id, zone_id, kind, ref, label, icon, sort)
select l.id || '.desk.vote', l.id || '.desk', 'panel', 'politics', 'Vote here', '🗳️', 1
  from public.locations l where l.id like 'pu\_%'
on conflict (id) do nothing;
insert into public.place_moods (id, scene, location_id, part, icon, line, sort)
select l.id || '.1', null, l.id, 'any', '🗳️', 'Officials dey check names, a queue dey form, somebody dey explain the rules again', 1
  from public.locations l where l.id like 'pu\_%'
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 3. Tables
-- ---------------------------------------------------------------------------------------------
create table if not exists public.offices (
  id              text primary key,
  name            text not null,
  kind            text not null check (kind in ('councillor', 'chairman', 'governor', 'commissioner')),
  title           text not null default '',               -- the badge next to a name: Hon. / Chairman / Gov. / Comm.
  icon            text not null default '🏛️',
  blurb           text not null default '',
  elected         boolean not null default true,          -- false = appointed by the Governor
  ward_scoped     boolean not null default false,         -- one seat per ward
  salary_per_day  bigint not null default 0 check (salary_per_day >= 0),
  fee             bigint not null default 0 check (fee >= 0),                    -- declaring costs this (ledger campaign_fee)
  min_charisma    int not null default 1 check (min_charisma between 0 and 10),
  min_account_days numeric not null default 3 check (min_account_days >= 0),
  cert_any        text[] not null default '{}',           -- the candidate needs ANY of these certificates (empty = no rule) ...
  alt_job_level   int not null default 0 check (alt_job_level >= 0),             -- ... or a career level at least this (0 = no alternative)
  sort            int not null default 0,
  active          boolean not null default true
);
insert into public.offices (id, name, kind, title, icon, blurb, elected, ward_scoped, salary_per_day, fee, min_charisma, min_account_days, cert_any, alt_job_level, sort) values
('councillor', 'Councillor', 'councillor', 'Hon.', '🏘️', 'One seat per ward. You speak for your street, sponsor a ward notice and collect a small daily salary.', true, true, 20000, 10000, 1, 3, '{}', 0, 1),
('chairman', 'Chairman of the City', 'chairman', 'Chairman', '🏙️', 'The LGA chairman for the whole of Benin City. Every ward votes.', true, false, 50000, 50000, 2, 5, '{}', 0, 2),
('governor', 'Governor', 'governor', 'Gov.', '🏛️', 'The big seat. Appoints the Commissioners, posts a daily government announcement and sets one small policy per term.', true, false, 100000, 250000, 4, 7, '{bsc,business_mgmt}', 5, 3),
('commissioner_works', 'Commissioner for Works', 'commissioner', 'Comm.', '🚧', 'Appointed by the Governor. Roads, gutters and the famous Ramat Park go-slow.', false, false, 40000, 0, 0, 3, '{}', 0, 11),
('commissioner_finance', 'Commissioner for Finance', 'commissioner', 'Comm.', '💰', 'Appointed by the Governor. Counts the money, mostly.', false, false, 40000, 0, 0, 3, '{}', 0, 12),
('commissioner_youth', 'Commissioner for Youth & Sports', 'commissioner', 'Comm.', '⚽', 'Appointed by the Governor. Stadium, jogging and big match talk.', false, false, 40000, 0, 0, 3, '{}', 0, 13),
('commissioner_information', 'Commissioner for Information', 'commissioner', 'Comm.', '📢', 'Appointed by the Governor. Makes sure everybody hear the good news.', false, false, 40000, 0, 0, 3, '{}', 0, 14),
('commissioner_commerce', 'Commissioner for Commerce', 'commissioner', 'Comm.', '🛍️', 'Appointed by the Governor. Markets, shops and traders.', false, false, 40000, 0, 0, 3, '{}', 0, 15),
('commissioner_security', 'Commissioner for Security', 'commissioner', 'Comm.', '🛡️', 'Appointed by the Governor. Torchlight, whistles and neighbourhood watch.', false, false, 40000, 0, 0, 3, '{}', 0, 16)
on conflict (id) do nothing;

create table if not exists public.gov_policies (
  id        text primary key,
  name      text not null,
  icon      text not null default '📜',
  blurb     text not null default '',
  kind      text not null check (kind in ('travel_discount', 'levy_cut', 'fitness_xp', 'hygiene_slow')),
  value     numeric not null default 10 check (value >= 0 and value <= 100),   -- percent
  modes     text[] not null default '{}',                                       -- travel_discount: which fares (keke, bus, drop)
  weekday   int check (weekday between 1 and 7),                                -- travel_discount: only on this ISO weekday (5 = Friday), null = every day
  sort      int not null default 0,
  active    boolean not null default true
);
insert into public.gov_policies (id, name, icon, blurb, kind, value, modes, weekday, sort) values
('keke_fridays', 'Keke Fridays', '🛺', 'Keke fares drop every Friday (Benin time) for the whole term.', 'travel_discount', 30, '{keke}', 5, 1),
('levy_holiday', 'Market levy holiday', '🧾', 'The council levy chance for business owners is cut for the term.', 'levy_cut', 25, '{}', null, 2),
('youth_sports_week', 'Youth sports week', '🏃', 'Fitness XP is boosted for the term. Everybody go jog.', 'fitness_xp', 25, '{}', null, 3),
('clean_benin', 'Clean Benin', '🧼', 'Hygiene falls slower for the term. The gutters are cleaner, they say.', 'hygiene_slow', 20, '{}', null, 4)
on conflict (id) do nothing;

create sequence if not exists public.parties_seq;
create table if not exists public.parties (
  id          text primary key default ('u' || nextval('public.parties_seq')::text),
  name        text not null,
  abbr        text not null,
  color       text not null default '#2f9e6b',
  blurb       text not null default '',
  founder_id  uuid references public.profiles(id) on delete set null,
  seeded      boolean not null default false,
  created_at  timestamptz not null default now(),
  active      boolean not null default true
);
create unique index if not exists parties_name_uq on public.parties (lower(name)) where active;
create unique index if not exists parties_abbr_uq on public.parties (upper(abbr)) where active;
create unique index if not exists parties_founder_uq on public.parties (founder_id) where active and founder_id is not null;
insert into public.parties (id, name, abbr, color, blurb, seeded) values
('pbm', 'Progressive Benin Movement', 'PBM', '#2f9e6b', 'Fictional. Promises smooth roads, steady light and jollof for all.', true),
('opp', 'Oba-Town People''s Party', 'OPP', '#d94a3d', 'Fictional. Old-school Benin pride, new-school hustle.', true),
('bua', 'Benin Unity Alliance', 'BUA', '#2f7fd1', 'Fictional. One city, one gist, one big family.', true),
('jjp', 'Jollof Justice Party', 'JJP', '#e0a030', 'Fictional and very satirical. Fair play, fair portions.', true)
on conflict (id) do nothing;

create table if not exists public.election_cycles (
  id          bigserial primary key,
  status      text not null default 'registration' check (status in ('registration', 'campaign', 'voting', 'closed', 'cancelled')),
  reg_start   timestamptz not null,
  camp_start  timestamptz not null,
  vote_start  timestamptz not null,
  vote_end    timestamptz not null,
  term_days   numeric not null,
  created_by  uuid references public.profiles(id) on delete set null,   -- null = started by itself (pol.auto_cycle)
  created_at  timestamptz not null default now(),
  closed_at   timestamptz,
  cancel_reason text
);
create unique index if not exists election_cycles_one_active on public.election_cycles ((true)) where status in ('registration', 'campaign', 'voting');
create index if not exists election_cycles_created_by_idx on public.election_cycles (created_by) where created_by is not null;

create table if not exists public.pol_candidates (
  id           bigserial primary key,
  cycle_id     bigint not null references public.election_cycles(id) on delete cascade,
  office_id    text not null references public.offices(id),
  ward_id      text references public.wards(id),
  slot_key     text not null,                      -- office:ward (ward '-' for the city and state races)
  user_id      uuid not null references public.profiles(id) on delete cascade,
  party_id     text references public.parties(id) on delete set null,
  promise      text not null default '',
  status       text not null default 'declared' check (status in ('declared', 'withdrawn', 'disqualified')),
  fee_paid     bigint not null default 0,
  rally_points int not null default 0,
  rallies      int not null default 0,
  posters      int not null default 0,
  last_rally_at  timestamptz,
  last_poster_at timestamptz,
  final_votes  int,                                 -- written at the close (ballot secrecy until then)
  won          boolean not null default false,
  dq_reason    text,
  declared_at  timestamptz not null default now()
);
create unique index if not exists pol_candidates_one_per_player on public.pol_candidates (cycle_id, user_id) where status = 'declared';
create index if not exists pol_candidates_slot_idx on public.pol_candidates (cycle_id, slot_key);
create index if not exists pol_candidates_user_idx on public.pol_candidates (user_id);
create index if not exists pol_candidates_office_idx on public.pol_candidates (office_id);
create index if not exists pol_candidates_ward_idx on public.pol_candidates (ward_id) where ward_id is not null;
create index if not exists pol_candidates_party_idx on public.pol_candidates (party_id) where party_id is not null;

-- a player's backing of a candidate: 'support' (anonymous declared supporter), 'endorse' (named), 'crew' (a crew endorses)
create table if not exists public.pol_backing (
  id           bigserial primary key,
  cycle_id     bigint not null references public.election_cycles(id) on delete cascade,
  candidate_id bigint not null references public.pol_candidates(id) on delete cascade,
  slot_key     text not null,
  user_id      uuid not null references public.profiles(id) on delete cascade,
  crew_id      bigint references public.crews(id) on delete cascade,
  kind         text not null check (kind in ('support', 'endorse', 'crew')),
  created_at   timestamptz not null default now()
);
create unique index if not exists pol_backing_one_player on public.pol_backing (cycle_id, slot_key, user_id) where kind in ('support', 'endorse');
create unique index if not exists pol_backing_one_crew on public.pol_backing (cycle_id, slot_key, crew_id) where kind = 'crew';
create index if not exists pol_backing_candidate_idx on public.pol_backing (candidate_id);
create index if not exists pol_backing_user_idx on public.pol_backing (user_id);
create index if not exists pol_backing_crew_idx on public.pol_backing (crew_id) where crew_id is not null;

create table if not exists public.pol_votes (
  id           bigserial primary key,
  cycle_id     bigint not null references public.election_cycles(id) on delete cascade,
  office_id    text not null references public.offices(id),
  ward_id      text references public.wards(id),
  voter_id     uuid not null references public.profiles(id) on delete cascade,
  candidate_id bigint not null references public.pol_candidates(id) on delete cascade,
  created_at   timestamptz not null default now(),
  unique (cycle_id, office_id, voter_id)               -- one vote per account per office per election
);
create index if not exists pol_votes_candidate_idx on public.pol_votes (candidate_id);
create index if not exists pol_votes_voter_idx on public.pol_votes (voter_id);
create index if not exists pol_votes_office_idx on public.pol_votes (office_id);
create index if not exists pol_votes_ward_idx on public.pol_votes (ward_id) where ward_id is not null;

create table if not exists public.pol_campaign_log (
  id           bigserial primary key,
  cycle_id     bigint not null references public.election_cycles(id) on delete cascade,
  candidate_id bigint not null references public.pol_candidates(id) on delete cascade,
  user_id      uuid not null references public.profiles(id) on delete cascade,
  kind         text not null check (kind in ('rally', 'poster')),
  location_id  text references public.locations(id) on delete set null,
  cost         bigint not null default 0,
  points       int not null default 0,
  attendees    int not null default 0,
  created_at   timestamptz not null default now()
);
create index if not exists pol_campaign_log_candidate_idx on public.pol_campaign_log (candidate_id, created_at desc);
create index if not exists pol_campaign_log_user_idx on public.pol_campaign_log (user_id);
create index if not exists pol_campaign_log_cycle_idx on public.pol_campaign_log (cycle_id);
create index if not exists pol_campaign_log_loc_idx on public.pol_campaign_log (location_id) where location_id is not null;

create table if not exists public.pol_reports (
  id           bigserial primary key,
  cycle_id     bigint not null references public.election_cycles(id) on delete cascade,
  candidate_id bigint not null references public.pol_candidates(id) on delete cascade,
  reporter_id  uuid references public.profiles(id) on delete set null,
  reason       text not null default '',
  status       text not null default 'open' check (status in ('open', 'reviewed')),
  created_at   timestamptz not null default now(),
  unique (candidate_id, reporter_id)
);
create index if not exists pol_reports_cycle_idx on public.pol_reports (cycle_id);
create index if not exists pol_reports_reporter_idx on public.pol_reports (reporter_id) where reporter_id is not null;

create table if not exists public.pol_results (
  id           bigserial primary key,
  cycle_id     bigint not null references public.election_cycles(id) on delete cascade,
  office_id    text not null references public.offices(id),
  ward_id      text references public.wards(id),
  slot_key     text not null,
  candidate_id bigint references public.pol_candidates(id) on delete set null,
  user_id      uuid references public.profiles(id) on delete set null,
  votes        int not null default 0,
  total_votes  int not null default 0,
  candidates_n int not null default 0,
  tie          text check (tie in ('rally', 'coin')),
  created_at   timestamptz not null default now(),
  unique (cycle_id, slot_key)
);
create index if not exists pol_results_office_idx on public.pol_results (office_id);
create index if not exists pol_results_ward_idx on public.pol_results (ward_id) where ward_id is not null;
create index if not exists pol_results_candidate_idx on public.pol_results (candidate_id) where candidate_id is not null;
create index if not exists pol_results_user_idx on public.pol_results (user_id) where user_id is not null;

create table if not exists public.office_holders (
  id            bigserial primary key,
  cycle_id      bigint references public.election_cycles(id) on delete set null,
  office_id     text not null references public.offices(id),
  ward_id       text references public.wards(id),
  user_id       uuid not null references public.profiles(id) on delete cascade,
  party_id      text references public.parties(id) on delete set null,
  appointed_by  uuid references public.profiles(id) on delete set null,
  status        text not null default 'active' check (status in ('active', 'ended', 'removed', 'resigned', 'sacked')),
  term_start    timestamptz not null,
  term_end      timestamptz not null,
  paid_through  timestamptz not null,
  salary_paid   bigint not null default 0,
  policy_id     text references public.gov_policies(id) on delete set null,
  policy_set_at timestamptz,
  last_announce_at timestamptz,
  ward_announce_used boolean not null default false,
  ended_at      timestamptz,
  ended_reason  text
);
create unique index if not exists office_holders_one_seat on public.office_holders (office_id, coalesce(ward_id, '')) where status = 'active';
create unique index if not exists office_holders_one_office on public.office_holders (user_id) where status = 'active';
create index if not exists office_holders_cycle_idx on public.office_holders (cycle_id) where cycle_id is not null;
create index if not exists office_holders_ward_idx on public.office_holders (ward_id) where ward_id is not null;
create index if not exists office_holders_party_idx on public.office_holders (party_id) where party_id is not null;
create index if not exists office_holders_policy_idx on public.office_holders (policy_id) where policy_id is not null;
create index if not exists office_holders_appointed_idx on public.office_holders (appointed_by) where appointed_by is not null;
create index if not exists office_holders_office_idx on public.office_holders (office_id, status);
create index if not exists wards_poll_unit_idx on public.wards (poll_unit) where poll_unit is not null;
create index if not exists parties_founder_idx on public.parties (founder_id) where founder_id is not null;
create index if not exists election_cycles_status_idx on public.election_cycles (status);

-- the title next to a name in chat: stamped on a chat message when it is written (realtime rows carry it too)
alter table public.chat_messages add column if not exists pol_title text;

alter table public.wards enable row level security;
alter table public.offices enable row level security;
alter table public.gov_policies enable row level security;
alter table public.parties enable row level security;
alter table public.election_cycles enable row level security;
alter table public.pol_candidates enable row level security;
alter table public.pol_backing enable row level security;
alter table public.pol_votes enable row level security;
alter table public.pol_campaign_log enable row level security;
alter table public.pol_reports enable row level security;
alter table public.pol_results enable row level security;
alter table public.office_holders enable row level security;
revoke all on table public.wards, public.offices, public.gov_policies, public.parties, public.election_cycles, public.pol_candidates, public.pol_backing,
  public.pol_votes, public.pol_campaign_log, public.pol_reports, public.pol_results, public.office_holders from public, anon, authenticated;
revoke all on sequence public.parties_seq, public.election_cycles_id_seq, public.pol_candidates_id_seq, public.pol_backing_id_seq, public.pol_votes_id_seq,
  public.pol_campaign_log_id_seq, public.pol_reports_id_seq, public.pol_results_id_seq, public.office_holders_id_seq from public, anon, authenticated;
-- the four catalogues are readable by signed-in players (admins write through admin_row_upsert); everything else is server-only,
-- so ballots stay secret: votes and tallies are only reachable through the RPCs
grant select on table public.wards, public.offices, public.gov_policies, public.parties to authenticated;
drop policy if exists wards_read on public.wards;
create policy wards_read on public.wards for select to authenticated using (true);
drop policy if exists offices_read on public.offices;
create policy offices_read on public.offices for select to authenticated using (true);
drop policy if exists gov_policies_read on public.gov_policies;
create policy gov_policies_read on public.gov_policies for select to authenticated using (true);
drop policy if exists parties_read on public.parties;
create policy parties_read on public.parties for select to authenticated using (true);

-- skill XP for politics (kind 'politics'): declaring and rallying train Charisma
do $$
declare r record;
begin
  for r in select c.conname from pg_constraint c
            where c.contype = 'c' and c.conrelid = 'public.skill_sources'::regclass
              and pg_get_constraintdef(c.oid) like '%hustle%' and pg_get_constraintdef(c.oid) not like '%politics%' loop
    execute format('alter table public.skill_sources drop constraint %I', r.conname);
    alter table public.skill_sources add constraint skill_sources_kind_check check (kind in ('hustle', 'yahoo', 'career', 'activity', 'crew', 'politics'));
  end loop;
end $$;
insert into public.skill_sources (id, kind, ref, skill_id, xp, note) values
('politics:declare:charisma', 'politics', 'declare', 'charisma', 8, 'Declared for office (Benin Votes)'),
('politics:rally:charisma', 'politics', 'rally', 'charisma', 6, 'Campaign rally (Benin Votes)'),
('politics:poster:charisma', 'politics', 'poster', 'charisma', 1, 'Campaign poster (Benin Votes)')
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 4. Private helpers
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_pol_num(p_key text, p_default numeric) returns numeric
language sql stable set search_path = public as $$
  select coalesce((select (value #>> '{}')::numeric from game_config where key = p_key), p_default);
$$;

create or replace function public.bl_pol_text(p_key text, p_default text) returns text
language sql stable set search_path = public as $$
  select coalesce((select value #>> '{}' from game_config where key = p_key), p_default);
$$;

create or replace function public.bl_pol_flag(p_key text, p_default boolean) returns boolean
language sql stable set search_path = public as $$
  select coalesce((select (value #>> '{}')::boolean from game_config where key = p_key), p_default);
$$;

create or replace function public.bl_pol_on() returns boolean
language sql stable set search_path = public as $$
  select bl_pol_flag('pol.enabled', true);
$$;

create or replace function public.bl_pol_list(p_key text, p_default text) returns text[]
language sql stable set search_path = public as $$
  select coalesce(array(select btrim(x) from unnest(string_to_array(bl_pol_text(p_key, p_default), ',')) x where btrim(x) <> ''), '{}');
$$;

-- refuse every write while Benin Votes is switched off
create or replace function public.bl_pol_guard() returns void
language plpgsql stable set search_path = public as $$
begin
  if not bl_pol_on() then
    raise exception 'Benin Votes is closed for now. Check back soon.' using errcode = 'P0001', hint = 'disabled';
  end if;
end $$;

-- is a text free of the blocked real parties / politicians / election-body words? (short words match whole words only)
create or replace function public.bl_pol_text_ok(p_text text) returns boolean
language plpgsql stable set search_path = public as $$
declare
  v_low   text := lower(coalesce(p_text, ''));
  v_norm  text := regexp_replace(v_low, '[^a-z0-9]', '', 'g');
  v_words text := ' ' || btrim(regexp_replace(v_low, '[^a-z0-9]+', ' ', 'g')) || ' ';
  k text; w text; n text;
begin
  foreach k in array array['pol.blocked_words', 'pol.blocked_party_words'] loop
    foreach w in array bl_pol_list(k, '') loop
      n := regexp_replace(lower(w), '[^a-z0-9]', '', 'g');
      if n = '' then continue; end if;
      if char_length(n) <= 3 then
        if position(' ' || btrim(regexp_replace(lower(w), '[^a-z0-9]+', ' ', 'g')) || ' ' in v_words) > 0 then return false; end if;
      elsif position(n in v_norm) > 0 then
        return false;
      end if;
    end loop;
  end loop;
  return true;
end $$;

-- clean + validate a free text (promise, announcement, party name): raises friendly errors, returns the clean text
create or replace function public.bl_pol_moderate(p_text text, p_min int, p_max int, p_what text) returns text
language plpgsql stable set search_path = public as $$
declare v text := bl_chat_clean(coalesce(p_text, ''));
begin
  if char_length(v) < p_min then
    raise exception 'Write a bit more for the % (at least % characters).', p_what, p_min using errcode = 'P0001', hint = 'too_short';
  end if;
  if char_length(v) > p_max then
    raise exception 'Keep the % under % characters.', p_what, p_max using errcode = 'P0001', hint = 'too_long';
  end if;
  if bl_chat_mask(v) <> v then
    raise exception 'Keep the % clean, abeg.', p_what using errcode = 'P0001', hint = 'blocked_text';
  end if;
  if v ~* '(https?:|www\.|\.com\b|\.ng\b|\.net\b|\.org\b)' then
    raise exception 'No links in the %.', p_what using errcode = 'P0001', hint = 'blocked_text';
  end if;
  if not bl_pol_text_ok(v) then
    raise exception 'Keep the % fictional: no real parties, politicians or election claims.', p_what using errcode = 'P0001', hint = 'blocked_text';
  end if;
  return v;
end $$;

-- a player pays the system: bank first, then cash (the same rule as every other purchase)
create or replace function public.bl_pol_pay(p_uid uuid, p_amount bigint, p_reason text, p_meta jsonb) returns void
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

-- "2 h 5 min" for an interval
create or replace function public.bl_pol_wait(p_left interval) returns text
language sql immutable set search_path = public as $$
  select case when extract(epoch from p_left) >= 86400 then floor(extract(epoch from p_left) / 86400)::int || ' d ' || floor(mod(extract(epoch from p_left)::numeric, 86400) / 3600)::int || ' h'
              when extract(epoch from p_left) >= 3600 then floor(extract(epoch from p_left) / 3600)::int || ' h ' || floor(mod(extract(epoch from p_left)::numeric, 3600) / 60)::int || ' min'
              else greatest(1, ceil(extract(epoch from p_left) / 60))::int || ' min' end;
$$;

-- ward of a player: the ward whose districts hold their home's district (first ward when nothing matches)
create or replace function public.bl_pol_ward_of(p_uid uuid) returns text
language sql stable set search_path = public as $$
  select coalesce(
    (select w.id from profiles p join locations l on l.id = p.home_location_id
       join wards w on w.active and l.district = any (w.districts) where p.id = p_uid order by w.sort limit 1),
    (select w.id from wards w where w.active order by w.sort limit 1));
$$;

-- the title next to a name (null when the player holds no office). Definer: it reads closed tables.
create or replace function public.bl_pol_title(p_uid uuid) returns text
language sql stable security definer set search_path = public as $$
  select nullif(o.title, '') from office_holders h join offices o on o.id = h.office_id
   where h.user_id = p_uid and h.status = 'active' and h.term_end > bl_now() and bl_pol_on() limit 1;
$$;

-- stamp the title on a chat message when it is written
create or replace function public.bl_pol_chat_title() returns trigger
language plpgsql set search_path = public as $$
begin
  new.pol_title := bl_pol_title(new.user_id);
  return new;
end $$;
drop trigger if exists bl_pol_chat_title_trg on public.chat_messages;
create trigger bl_pol_chat_title_trg before insert on public.chat_messages for each row execute function public.bl_pol_chat_title();

-- the Governor's policy while it applies
create or replace function public.bl_pol_policy() returns public.gov_policies
language sql stable security definer set search_path = public as $$
  select p.* from office_holders h join gov_policies p on p.id = h.policy_id
   where h.office_id = 'governor' and h.status = 'active' and h.term_end > bl_now() and p.active and bl_pol_on() limit 1;
$$;

-- Benin Votes effects, all 1 (no change) without a policy
create or replace function public.bl_pol_travel_cost(p_cost bigint, p_mode text) returns bigint
language plpgsql stable security definer set search_path = public as $$
declare p gov_policies := bl_pol_policy();
begin
  if p.id is null or p.kind <> 'travel_discount' or not (p_mode = any (p.modes)) then return p_cost; end if;
  if p.weekday is not null and extract(isodow from (bl_now() at time zone 'Africa/Lagos'))::int <> p.weekday then return p_cost; end if;
  return (ceil(p_cost * (1 - p.value / 100.0) / 10.0) * 10)::bigint;
end $$;

create or replace function public.bl_pol_levy_mult() returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce((select 1 - p.value / 100.0 from bl_pol_policy() p where p.kind = 'levy_cut'), 1);
$$;

create or replace function public.bl_pol_skill_mult(p_skill text) returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce((select 1 + p.value / 100.0 from bl_pol_policy() p where p.kind = 'fitness_xp' and p_skill = 'fitness'), 1);
$$;

create or replace function public.bl_pol_hygiene_mult() returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce((select 1 - p.value / 100.0 from bl_pol_policy() p where p.kind = 'hygiene_slow'), 1);
$$;

-- voting is open: a cycle in its voting window (by the clock, so a stale status never lies)
create or replace function public.bl_pol_poll_open() returns boolean
language sql stable security definer set search_path = public as $$
  select bl_pol_on() and exists (select 1 from election_cycles c
                                  where c.status in ('campaign', 'voting') and bl_now() >= c.vote_start and bl_now() < c.vote_end);
$$;

-- a player's push to everybody with a device (events category): registration open, voting day, results
create or replace function public.bl_pol_push_all(p_kind text, p_title text, p_body text, p_dedupe text) returns void
language plpgsql set search_path = public as $$
declare r record;
begin
  for r in select distinct s.user_id from push_subscriptions s loop
    perform bl_push_enqueue(r.user_id, 'events', p_kind, p_title, p_body, '/play?go=politics', null, null, null, p_dedupe);
  end loop;
exception when others then null;   -- a push must never break the election
end $$;

-- momentum points: rallies + posters + backing (not money alone, not votes)
create or replace function public.bl_pol_points(c public.pol_candidates) returns numeric
language sql stable set search_path = public as $$
  select c.rally_points
       + c.posters * bl_pol_num('pol.poster_points', 3)
       + coalesce((select sum(case b.kind when 'support' then bl_pol_num('pol.support_points', 1)
                                          when 'endorse' then bl_pol_num('pol.endorse_points', 4)
                                          else bl_pol_num('pol.crew_endorse_points', 8) end)
                     from pol_backing b where b.candidate_id = c.id), 0);
$$;

-- does a player hold this skill level? (skills off = everybody passes)
create or replace function public.bl_pol_charisma_ok(p_uid uuid, p_min int) returns boolean
language sql stable set search_path = public as $$
  select coalesce(p_min, 0) <= 1 or not bl_skill_on() or bl_skill_level(p_uid, 'charisma') >= p_min;
$$;

-- candidate requirements as a checklist. {ok, hint, message, checks:[{key, label, ok}]}
create or replace function public.bl_pol_requirements(p_uid uuid, o public.offices) returns jsonb
language plpgsql stable set search_path = public as $$
declare
  me profiles; v_age numeric; v_days numeric := bl_pol_num('pol.clean_record_days', 7);
  v_checks jsonb := '[]'::jsonb; v_first jsonb; v_ok boolean; v_has_cert boolean; v_alt boolean; v_certs text;
begin
  select * into me from profiles where id = p_uid;
  v_age := extract(epoch from (bl_now() - me.created_at)) / 86400.0;
  v_ok := v_age >= o.min_account_days;
  v_checks := v_checks || jsonb_build_object('key', 'account_young', 'ok', v_ok, 'label', 'Account at least ' || trim(trailing '.' from trim(trailing '0' from o.min_account_days::numeric(10, 2)::text)) || ' days old',
                                                'message', 'Your account must be at least ' || trim(trailing '.' from trim(trailing '0' from o.min_account_days::numeric(10, 2)::text)) || ' days old to run for ' || o.name || '.');
  v_ok := not (me.jailed_until is not null and me.jailed_until > bl_now()) and not exists (select 1 from jail_cases j where j.user_id = p_uid and j.status = 'open');
  v_checks := v_checks || jsonb_build_object('key', 'jailed', 'ok', v_ok, 'label', 'Not in jail', 'message', 'You dey inside. Candidates must be free people.');
  v_ok := v_days <= 0 or not exists (select 1 from jail_cases j where j.user_id = p_uid and j.kind = 'efcc' and j.created_at > bl_now() - make_interval(days => v_days::int));
  v_checks := v_checks || jsonb_build_object('key', 'efcc_record', 'ok', v_ok, 'label', 'No EFCC case in the last ' || v_days::int || ' days',
                                                'message', 'EFCC case on your record in the last ' || v_days::int || ' days. Wait small, then try again.');
  if o.min_charisma > 1 then
    v_ok := bl_pol_charisma_ok(p_uid, o.min_charisma);
    v_checks := v_checks || jsonb_build_object('key', 'charisma_low', 'ok', v_ok, 'label', 'Charisma level ' || o.min_charisma,
                                                  'message', 'You need Charisma level ' || o.min_charisma || ' to run for ' || o.name || '. Train it with rallies, clubs and gist.');
  end if;
  if cardinality(o.cert_any) > 0 then
    v_has_cert := exists (select 1 from player_certificates pc where pc.user_id = p_uid and pc.cert_id = any (o.cert_any));
    v_alt := o.alt_job_level > 0 and coalesce(me.job_level, 0) >= o.alt_job_level;
    select string_agg(c.name, ' or ' order by c.sort) into v_certs from certificates c where c.id = any (o.cert_any);
    v_checks := v_checks || jsonb_build_object('key', 'qualification', 'ok', v_has_cert or v_alt,
      'label', coalesce(v_certs, 'A certificate') || case when o.alt_job_level > 0 then ' or career level ' || o.alt_job_level else '' end,
      'message', 'To be Governor you need ' || coalesce(v_certs, 'a certificate') || case when o.alt_job_level > 0 then ' or career level ' || o.alt_job_level else '' end || '.');
  end if;
  select c into v_first from jsonb_array_elements(v_checks) c where not (c->>'ok')::boolean limit 1;
  return jsonb_build_object('ok', v_first is null, 'hint', v_first->>'key', 'message', v_first->>'message', 'checks', v_checks);
end $$;

-- the candidate row for a race slot
create or replace function public.bl_pol_slot(p_office text, p_ward text) returns text
language sql immutable set search_path = public as $$
  select p_office || ':' || coalesce(p_ward, '-');
$$;

-- who is the winner of the tie-break: a deterministic coin flip (stable for a cycle, race and player)
create or replace function public.bl_pol_coin(c public.pol_candidates) returns text
language sql immutable set search_path = public as $$
  select md5(c.cycle_id::text || ':' || c.slot_key || ':' || c.user_id::text || ':coin');
$$;

-- pay the salary days an officeholder has earned and not yet been paid (whole days, never past the end of the term)
create or replace function public.bl_pol_pay_holder(p_holder bigint) returns bigint
language plpgsql set search_path = public as $$
declare h office_holders; o offices; v_days int; v_amt bigint; v_until timestamptz;
begin
  select * into h from office_holders where id = p_holder for update;
  if not found or not bl_pol_on() or not bl_pol_flag('pol.salary_enabled', true) then return 0; end if;
  select * into o from offices where id = h.office_id;
  v_until := least(bl_now(), h.term_end);
  v_days := floor(extract(epoch from (v_until - h.paid_through)) / 86400.0)::int;
  if v_days < 1 then return 0; end if;
  v_amt := v_days::bigint * o.salary_per_day;
  update office_holders set paid_through = paid_through + make_interval(days => v_days), salary_paid = salary_paid + v_amt where id = h.id;
  if v_amt > 0 then
    perform bl_add_money(h.user_id, 'bank', v_amt, 'office_salary',
      jsonb_build_object('label', o.name || ' salary (' || v_days || ' day' || case when v_days = 1 then '' else 's' end || ')', 'office', o.id, 'days', v_days));
  end if;
  return v_amt;
end $$;

-- start a cycle (admin, or by itself). Returns the id, null when one is already running.
create or replace function public.bl_pol_start_cycle(p_admin uuid, p_reg numeric default null, p_camp numeric default null, p_vote numeric default null, p_term numeric default null) returns bigint
language plpgsql set search_path = public as $$
declare
  v_reg numeric := coalesce(p_reg, bl_pol_num('pol.registration_hours', 48));
  v_camp numeric := coalesce(p_camp, bl_pol_num('pol.campaign_hours', 72));
  v_vote numeric := coalesce(p_vote, bl_pol_num('pol.voting_hours', 24));
  v_term numeric := coalesce(p_term, bl_pol_num('pol.term_days', 14));
  v_now timestamptz := bl_now(); v_id bigint;
begin
  insert into election_cycles (status, reg_start, camp_start, vote_start, vote_end, term_days, created_by, created_at)
  values ('registration', v_now, v_now + make_interval(secs => v_reg * 3600), v_now + make_interval(secs => (v_reg + v_camp) * 3600),
          v_now + make_interval(secs => (v_reg + v_camp + v_vote) * 3600), v_term, p_admin, v_now)
  returning id into v_id;
  perform bl_pol_push_all('pol_registration', 'Benin Votes: registration open', 'Candidates can declare now. Who go lead Benin?', 'pol:' || v_id || ':reg');
  return v_id;
exception when unique_violation then
  return null;
end $$;

-- close a cycle: tally every race, break ties, write the results, end the old government, swear the winners in
create or replace function public.bl_pol_settle(p_cycle bigint) returns void
language plpgsql set search_path = public as $$
declare
  c election_cycles; r record; w record; v_now timestamptz := bl_now(); v_total int; v_n int; v_second record; v_tie text; v_seat int := 0; o offices;
begin
  select * into c from election_cycles where id = p_cycle for update;
  if not found or c.status in ('closed', 'cancelled') then return; end if;
  -- the old government is paid up to today and steps down
  for r in select id from office_holders where status = 'active' order by id loop perform bl_pol_pay_holder(r.id); end loop;
  update office_holders set status = 'ended', ended_at = v_now, ended_reason = 'A new government was sworn in' where status = 'active';
  -- the counts (ballot secrecy ends here)
  update pol_candidates k set final_votes = (select count(*) from pol_votes v where v.candidate_id = k.id) where k.cycle_id = c.id and k.status = 'declared';
  for r in select distinct k.slot_key, k.office_id, k.ward_id from pol_candidates k where k.cycle_id = c.id and k.status = 'declared' order by k.slot_key loop
    select count(*) into v_n from pol_candidates k where k.cycle_id = c.id and k.slot_key = r.slot_key and k.status = 'declared';
    select coalesce(sum(final_votes), 0) into v_total from pol_candidates k where k.cycle_id = c.id and k.slot_key = r.slot_key and k.status = 'declared';
    -- winner: most votes, then most rally points, then the deterministic coin
    select k.* into w from pol_candidates k where k.cycle_id = c.id and k.slot_key = r.slot_key and k.status = 'declared'
     order by k.final_votes desc, k.rally_points desc, bl_pol_coin(k) limit 1;
    select k.* into v_second from pol_candidates k where k.cycle_id = c.id and k.slot_key = r.slot_key and k.status = 'declared' and k.id <> w.id
     order by k.final_votes desc, k.rally_points desc, bl_pol_coin(k) limit 1;
    v_tie := null;
    if v_second.id is not null and v_second.final_votes = w.final_votes then
      v_tie := case when v_second.rally_points = w.rally_points then 'coin' else 'rally' end;
    end if;
    update pol_candidates set won = true where id = w.id;
    insert into pol_results (cycle_id, office_id, ward_id, slot_key, candidate_id, user_id, votes, total_votes, candidates_n, tie, created_at)
    values (c.id, r.office_id, r.ward_id, r.slot_key, w.id, w.user_id, w.final_votes, v_total, v_n, v_tie, v_now);
    select * into o from offices where id = r.office_id;
    insert into office_holders (cycle_id, office_id, ward_id, user_id, party_id, status, term_start, term_end, paid_through)
    values (c.id, r.office_id, r.ward_id, w.user_id, w.party_id, 'active', v_now, v_now + make_interval(secs => c.term_days * 86400), v_now);
    v_seat := v_seat + 1;
    perform bl_event(w.user_id, 'pol_won', 'You won: ' || o.name || '!',
      'Congratulations, ' || o.title || '. You were sworn in with ' || w.final_votes || ' vote' || case when w.final_votes = 1 then '' else 's' end || '. Open Benin Votes to see your powers.',
      jsonb_build_object('office', o.id, 'ward', r.ward_id, 'cycle', c.id));
    perform bl_push_enqueue(w.user_id, 'events', 'pol_won', 'You won: ' || o.name, 'Sworn in. Open Benin Votes for your powers.', '/play?go=politics', null, null, null, 'pol:' || c.id || ':won');
  end loop;
  -- the others hear how it went
  for r in select k.user_id, k.office_id, k.final_votes from pol_candidates k where k.cycle_id = c.id and k.status = 'declared' and not k.won loop
    perform bl_event(r.user_id, 'pol_lost', 'Election result', 'You no win this time, with ' || r.final_votes || ' vote' || case when r.final_votes = 1 then '' else 's' end || '. Try again next cycle.',
      jsonb_build_object('office', r.office_id, 'cycle', c.id));
  end loop;
  update election_cycles set status = 'closed', closed_at = v_now where id = c.id;
  perform bl_pol_push_all('pol_results', 'Benin Votes: results are out', v_seat || ' seat' || case when v_seat = 1 then '' else 's' end || ' filled. See who won.', 'pol:' || c.id || ':results');
end $$;

-- the lazy clock: move the cycle through its phases, settle, end terms, start the next cycle, pay salaries. Cheap when nothing is due.
create or replace function public.bl_pol_tick() returns void
language plpgsql security definer set search_path = public as $$
declare c election_cycles; v_now timestamptz := bl_now(); i int := 0; r record; v_last election_cycles; v_span numeric; v_at timestamptz;
begin
  if not bl_pol_on() then return; end if;
  loop
    i := i + 1; exit when i > 4;
    select * into c from election_cycles
     where (status = 'registration' and v_now >= camp_start) or (status = 'campaign' and v_now >= vote_start) or (status = 'voting' and v_now >= vote_end)
     order by id limit 1 for update skip locked;
    exit when not found;
    if c.status = 'registration' then
      update election_cycles set status = 'campaign' where id = c.id;
    elsif c.status = 'campaign' then
      update election_cycles set status = 'voting' where id = c.id;
      perform bl_pol_push_all('pol_voting', 'Benin Votes: voting day!', 'The polling units are open. Go to your ward polling unit and vote once.', 'pol:' || c.id || ':vote');
    else
      perform bl_pol_settle(c.id);
    end if;
  end loop;
  -- salaries for whoever is due (a few at a time), then the terms that ended
  for r in select id from office_holders where status = 'active' and (term_end <= v_now or paid_through + interval '1 day' <= v_now) order by id limit 25 for update skip locked loop
    perform bl_pol_pay_holder(r.id);
  end loop;
  update office_holders set status = 'ended', ended_at = v_now, ended_reason = 'Term ended' where status = 'active' and term_end <= v_now;
  -- the next cycle starts by itself so its results land when the term ends
  if bl_pol_flag('pol.auto_cycle', true) and not exists (select 1 from election_cycles where status in ('registration', 'campaign', 'voting')) then
    select * into v_last from election_cycles order by id desc limit 1;
    if found and v_last.status = 'closed' then
      v_span := bl_pol_num('pol.registration_hours', 48) + bl_pol_num('pol.campaign_hours', 72) + bl_pol_num('pol.voting_hours', 24);
      v_at := greatest(v_last.closed_at, v_last.vote_end + make_interval(secs => v_last.term_days * 86400 - v_span * 3600));
      if v_now >= v_at then perform bl_pol_start_cycle(null); end if;
    end if;
  end if;
end $$;

-- the open cycle (registration, campaign or voting), if any
create or replace function public.bl_pol_open_cycle() returns public.election_cycles
language sql stable set search_path = public as $$
  select * from election_cycles where status in ('registration', 'campaign', 'voting') order by id desc limit 1;
$$;

-- ---------------------------------------------------------------------------------------------
-- 5. JSON builders
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_pol_party_json(p_id text) returns jsonb
language sql stable set search_path = public as $$
  select jsonb_build_object('id', p.id, 'name', p.name, 'abbr', p.abbr, 'color', p.color) from parties p where p.id = p_id;
$$;

-- one candidate card for a viewer; p_max = the biggest points in the race (momentum is shown against the leader)
create or replace function public.bl_pol_cand_json(k public.pol_candidates, p_viewer uuid, p_max numeric) returns jsonb
language plpgsql stable set search_path = public as $$
declare
  o offices; w wards; v_pts numeric := bl_pol_points(k); v_pct int; v_label text; v_my text;
begin
  select * into o from offices where id = k.office_id;
  select * into w from wards where id = k.ward_id;
  v_pct := case when p_max <= 0 then 0 else round(100 * v_pts / p_max)::int end;
  v_label := case when p_max <= 0 then 'No momentum yet' when v_pts >= p_max then 'Leading' when v_pct >= 70 then 'Close behind' when v_pct >= 35 then 'Chasing' else 'Cold' end;
  select b.kind into v_my from pol_backing b
   where b.candidate_id = k.id and ((b.kind in ('support', 'endorse') and b.user_id = p_viewer)
      or (b.kind = 'crew' and b.crew_id = (select m.crew_id from crew_members m where m.user_id = p_viewer))) order by (b.kind = 'crew') limit 1;
  return jsonb_build_object(
    'id', k.id, 'slot_key', k.slot_key, 'office_id', k.office_id, 'office', o.name, 'ward_id', k.ward_id, 'ward', w.name,
    'user_id', k.user_id, 'username', (select username from profiles where id = k.user_id), 'title', bl_pol_title(k.user_id),
    'party', bl_pol_party_json(k.party_id), 'promise', k.promise, 'rallies', k.rallies, 'rally_points', k.rally_points, 'posters', k.posters,
    'supporters', (select count(*) from pol_backing b where b.candidate_id = k.id and b.kind = 'support'),
    'endorsers', coalesce((select jsonb_agg(p.username order by b.id) from (select * from pol_backing x where x.candidate_id = k.id and x.kind = 'endorse' order by x.id limit 5) b
                             join profiles p on p.id = b.user_id), '[]'::jsonb),
    'endorse_n', (select count(*) from pol_backing b where b.candidate_id = k.id and b.kind = 'endorse'),
    'crews', coalesce((select jsonb_agg(jsonb_build_object('name', c.name, 'tag', c.tag, 'color', c.color, 'emblem', c.emblem) order by b.id)
                         from pol_backing b join crews c on c.id = b.crew_id where b.candidate_id = k.id and b.kind = 'crew'), '[]'::jsonb),
    'points', v_pts, 'momentum_pct', v_pct, 'momentum', v_label,
    'mine', k.user_id = p_viewer, 'my_backing', v_my, 'declared_at', k.declared_at);
end $$;

-- a holder row as JSON
create or replace function public.bl_pol_holder_json(h public.office_holders) returns jsonb
language plpgsql stable set search_path = public as $$
declare o offices; w wards; pl gov_policies;
begin
  select * into o from offices where id = h.office_id;
  select * into w from wards where id = h.ward_id;
  select * into pl from gov_policies where id = h.policy_id;
  return jsonb_build_object('id', h.id, 'office_id', o.id, 'office', o.name, 'kind', o.kind, 'title', o.title, 'icon', o.icon, 'ward_id', h.ward_id, 'ward', w.name,
    'user_id', h.user_id, 'username', (select username from profiles where id = h.user_id), 'party', bl_pol_party_json(h.party_id),
    'term_start', h.term_start, 'term_end', h.term_end, 'salary_per_day', o.salary_per_day, 'salary_paid', h.salary_paid,
    'policy', case when pl.id is null then null else jsonb_build_object('id', pl.id, 'name', pl.name, 'icon', pl.icon, 'blurb', pl.blurb, 'kind', pl.kind, 'value', pl.value, 'set_at', h.policy_set_at) end);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 6. Player RPCs: status, candidates, ballot, results
-- ---------------------------------------------------------------------------------------------
create or replace function public.pol_status() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid(); me profiles; c election_cycles; h office_holders; k pol_candidates; w wards; v_now timestamptz;
  v_hid bigint; v_last election_cycles; v_next timestamptz; v_span numeric; v_gov_h office_holders; v_powers jsonb := '{}'::jsonb; o offices;
  v_age numeric; v_voted jsonb; v_unit locations;
begin
  perform bl_pol_tick();
  v_now := bl_now();
  select * into me from profiles where id = v_uid;
  select id into v_hid from office_holders where user_id = v_uid and status = 'active' and term_end > v_now;
  if v_hid is not null then perform bl_pol_pay_holder(v_hid); end if;
  select * into c from bl_pol_open_cycle();
  select * into h from office_holders where user_id = v_uid and status = 'active' and term_end > v_now;
  select * into w from wards where id = bl_pol_ward_of(v_uid);
  select * into v_unit from locations where id = w.poll_unit;
  v_age := extract(epoch from (v_now - me.created_at)) / 86400.0;
  if c.id is not null then
    select * into k from pol_candidates where cycle_id = c.id and user_id = v_uid and status = 'declared';
    select coalesce(jsonb_agg(v.office_id), '[]'::jsonb) into v_voted from pol_votes v where v.cycle_id = c.id and v.voter_id = v_uid;
  else
    v_voted := '[]'::jsonb;
  end if;
  select * into v_last from election_cycles where status = 'closed' order by id desc limit 1;
  if c.id is null and v_last.id is not null and bl_pol_flag('pol.auto_cycle', true) and bl_pol_on() then
    v_span := bl_pol_num('pol.registration_hours', 48) + bl_pol_num('pol.campaign_hours', 72) + bl_pol_num('pol.voting_hours', 24);
    v_next := greatest(v_last.closed_at, v_last.vote_end + make_interval(secs => v_last.term_days * 86400 - v_span * 3600));
  end if;
  -- powers of my office
  if h.id is not null then
    select * into o from offices where id = h.office_id;
    if o.kind = 'governor' then
      v_powers := jsonb_build_object(
        'can_announce', h.last_announce_at is null or h.last_announce_at + make_interval(hours => bl_pol_num('pol.announce_cooldown_hours', 24)::int) <= v_now,
        'announce_next_at', case when h.last_announce_at is null then null else h.last_announce_at + make_interval(hours => bl_pol_num('pol.announce_cooldown_hours', 24)::int) end,
        'can_set_policy', h.policy_id is null,
        'policies', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'name', p.name, 'icon', p.icon, 'blurb', p.blurb, 'kind', p.kind, 'value', p.value) order by p.sort)
                                from gov_policies p where p.active), '[]'::jsonb),
        'commissioners', coalesce((select jsonb_agg(jsonb_build_object('office_id', co.id, 'office', co.name, 'icon', co.icon, 'title', co.title,
                                      'user_id', ch.user_id, 'username', (select username from profiles where id = ch.user_id)) order by co.sort)
                                     from offices co left join office_holders ch on ch.office_id = co.id and ch.status = 'active' and ch.term_end > v_now
                                    where co.kind = 'commissioner' and co.active), '[]'::jsonb));
    elsif o.kind = 'councillor' then
      v_powers := jsonb_build_object('can_ward_notice', not h.ward_announce_used);
    end if;
  end if;
  return jsonb_build_object(
    'enabled', bl_pol_on(), 'now', v_now,
    'settings', jsonb_build_object('party_fee', bl_pol_num('pol.party_fee', 50000), 'rally_cost', bl_pol_num('pol.rally_cost', 20000), 'poster_cost', bl_pol_num('pol.poster_cost', 10000),
      'poster_max', bl_pol_num('pol.poster_max', 5), 'vote_min_account_days', bl_pol_num('pol.vote_min_account_days', 3), 'promise_max_len', bl_pol_num('pol.promise_max_len', 140),
      'announce_max_len', bl_pol_num('pol.announce_max_len', 200), 'ward_announce_max_len', bl_pol_num('pol.ward_announce_max_len', 160),
      'term_days', bl_pol_num('pol.term_days', 14), 'rally_cooldown_minutes', bl_pol_num('pol.rally_cooldown_minutes', 20),
      'endorse_min_charisma', bl_pol_num('pol.endorse_min_charisma', 2), 'registration_hours', bl_pol_num('pol.registration_hours', 48),
      'campaign_hours', bl_pol_num('pol.campaign_hours', 72), 'voting_hours', bl_pol_num('pol.voting_hours', 24)),
    'cycle', case when c.id is null then null else jsonb_build_object('id', c.id, 'status', c.status, 'reg_start', c.reg_start, 'camp_start', c.camp_start, 'vote_start', c.vote_start,
        'vote_end', c.vote_end, 'term_days', c.term_days, 'voting_open', c.status = 'voting' and v_now >= c.vote_start and v_now < c.vote_end,
        'next_at', case c.status when 'registration' then c.camp_start when 'campaign' then c.vote_start else c.vote_end end) end,
    'next_cycle_at', v_next,
    'last_cycle', case when v_last.id is null then null else jsonb_build_object('id', v_last.id, 'closed_at', v_last.closed_at) end,
    'me', jsonb_build_object('id', v_uid, 'account_days', round(v_age, 2),
      'ward', jsonb_build_object('id', w.id, 'name', w.name, 'poll_unit', w.poll_unit, 'poll_unit_name', v_unit.name),
      'at_polling_unit', me.location_id = w.poll_unit and me.travel_to is null and me.home_visit_host_id is null,
      'can_vote_account', v_age >= bl_pol_num('pol.vote_min_account_days', 3),
      'candidacy', case when k.id is null then null else bl_pol_cand_json(k, v_uid, (select coalesce(max(bl_pol_points(x)), 0) from pol_candidates x where x.cycle_id = c.id and x.slot_key = k.slot_key and x.status = 'declared')) end,
      'office', case when h.id is null then null else bl_pol_holder_json(h) end, 'powers', v_powers, 'voted', v_voted,
      'next_rally_at', case when k.last_rally_at is null then null else k.last_rally_at + make_interval(mins => bl_pol_num('pol.rally_cooldown_minutes', 20)::int) end),
    'government', coalesce((
      select jsonb_agg(jsonb_build_object('office_id', o2.id, 'office', o2.name, 'kind', o2.kind, 'title', o2.title, 'icon', o2.icon, 'ward_id', w2.id, 'ward', w2.name,
               'holder', case when hh.id is null then null else bl_pol_holder_json(hh) end) order by o2.sort, w2.sort)
        from offices o2 left join wards w2 on o2.ward_scoped and w2.active
        left join office_holders hh on hh.office_id = o2.id and coalesce(hh.ward_id, '') = coalesce(w2.id, '') and hh.status = 'active' and hh.term_end > v_now
       where o2.active), '[]'::jsonb),
    'policy', (select jsonb_build_object('id', p.id, 'name', p.name, 'icon', p.icon, 'blurb', p.blurb, 'kind', p.kind, 'value', p.value, 'weekday', p.weekday,
                                         'set_at', hh.policy_set_at, 'by', (select username from profiles where id = hh.user_id), 'term_end', hh.term_end)
                 from office_holders hh join gov_policies p on p.id = hh.policy_id
                where hh.office_id = 'governor' and hh.status = 'active' and hh.term_end > v_now and bl_pol_on() limit 1),
    'offices', coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'name', x.name, 'kind', x.kind, 'title', x.title, 'icon', x.icon, 'blurb', x.blurb, 'elected', x.elected,
                'ward_scoped', x.ward_scoped, 'salary_per_day', x.salary_per_day, 'fee', x.fee, 'min_charisma', x.min_charisma, 'min_account_days', x.min_account_days,
                'requirements', case when x.elected then bl_pol_requirements(v_uid, x) end) order by x.sort)
                from offices x where x.active), '[]'::jsonb),
    'parties', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'name', p.name, 'abbr', p.abbr, 'color', p.color, 'blurb', p.blurb, 'seeded', p.seeded, 'mine', p.founder_id = v_uid) order by p.seeded desc, p.name)
                           from parties p where p.active), '[]'::jsonb),
    'wards', coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'name', x.name, 'poll_unit', x.poll_unit, 'poll_unit_name', l.name) order by x.sort)
                         from wards x left join locations l on l.id = x.poll_unit where x.active), '[]'::jsonb));
end $$;

create or replace function public.pol_candidates() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); c election_cycles;
begin
  perform bl_pol_tick();
  select * into c from bl_pol_open_cycle();
  if c.id is null then return '[]'::jsonb; end if;
  return coalesce((
    select jsonb_agg(bl_pol_cand_json(k, v_uid, m.mx) order by o.sort, w.sort nulls first, bl_pol_points(k) desc, k.id)
      from pol_candidates k
      join offices o on o.id = k.office_id
      left join wards w on w.id = k.ward_id
      join lateral (select coalesce(max(bl_pol_points(x)), 0) as mx from pol_candidates x where x.cycle_id = k.cycle_id and x.slot_key = k.slot_key and x.status = 'declared') m on true
     where k.cycle_id = c.id and k.status = 'declared'), '[]'::jsonb);
end $$;

-- the ballot: the races I can vote in (my ward's Councillor, the Chairman, the Governor). Ballot secrecy: it says THAT I voted, never for whom.
create or replace function public.pol_ballot() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid(); c election_cycles; me profiles; w wards; v_unit locations; v_now timestamptz; v_open boolean; v_elig jsonb; v_at boolean; v_age numeric;
begin
  perform bl_pol_tick();
  v_now := bl_now();
  select * into me from profiles where id = v_uid;
  select * into w from wards where id = bl_pol_ward_of(v_uid);
  select * into v_unit from locations where id = w.poll_unit;
  select * into c from bl_pol_open_cycle();
  v_open := c.id is not null and c.status = 'voting' and v_now >= c.vote_start and v_now < c.vote_end;
  v_age := extract(epoch from (v_now - me.created_at)) / 86400.0;
  v_at := me.location_id = w.poll_unit and me.travel_to is null and me.home_visit_host_id is null;
  v_elig := case
    when me.banned then jsonb_build_object('ok', false, 'hint', 'banned', 'message', 'Your account cannot vote.')
    when v_age < bl_pol_num('pol.vote_min_account_days', 3) then jsonb_build_object('ok', false, 'hint', 'account_young', 'message', 'Your account must be at least ' || bl_pol_num('pol.vote_min_account_days', 3)::numeric(10, 1) || ' days old to vote.')
    when me.jailed_until is not null and me.jailed_until > v_now then jsonb_build_object('ok', false, 'hint', 'jailed', 'message', 'You dey inside. No voting from the cell.')
    else jsonb_build_object('ok', true) end;
  return jsonb_build_object(
    'voting_open', v_open, 'phase', coalesce(c.status, 'none'), 'opens_at', c.vote_start, 'closes_at', c.vote_end,
    'ward', jsonb_build_object('id', w.id, 'name', w.name), 'unit', jsonb_build_object('id', v_unit.id, 'name', v_unit.name),
    'at_unit', v_at, 'eligible', v_elig,
    'can_vote', v_open and v_at and (v_elig->>'ok')::boolean,
    'races', case when c.id is null then '[]'::jsonb else coalesce((
      select jsonb_agg(jsonb_build_object('office_id', o.id, 'office', o.name, 'icon', o.icon, 'ward_id', r.ward_id, 'ward', case when r.ward_id is null then null else w.name end, 'slot_key', r.slot_key,
               'voted', exists (select 1 from pol_votes v where v.cycle_id = c.id and v.office_id = o.id and v.voter_id = v_uid),
               'candidates', coalesce((select jsonb_agg(jsonb_build_object('id', k.id, 'username', (select username from profiles where id = k.user_id), 'party', bl_pol_party_json(k.party_id),
                                  'promise', k.promise, 'title', bl_pol_title(k.user_id)) order by md5(k.id::text || v_uid::text))
                                 from pol_candidates k where k.cycle_id = c.id and k.slot_key = r.slot_key and k.status = 'declared'), '[]'::jsonb)) order by o.sort)
        from (select o2.id as office_id, case when o2.ward_scoped then w.id end as ward_id, bl_pol_slot(o2.id, case when o2.ward_scoped then w.id end) as slot_key
                from offices o2 where o2.active and o2.elected) r join offices o on o.id = r.office_id), '[]'::jsonb) end);
end $$;

-- history: closed elections with winners and (now public) tallies
create or replace function public.pol_results(p_limit int default 5) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_lim int := least(greatest(coalesce(p_limit, 5), 1), 20);
begin
  perform bl_require_uid();
  perform bl_pol_tick();
  return coalesce((
    select jsonb_agg(jsonb_build_object('cycle_id', cy.id, 'closed_at', cy.closed_at, 'term_days', cy.term_days,
      'voters', (select count(distinct v.voter_id) from pol_votes v where v.cycle_id = cy.id),
      'votes', (select count(*) from pol_votes v where v.cycle_id = cy.id),
      'races', coalesce((
        select jsonb_agg(jsonb_build_object('office_id', o.id, 'office', o.name, 'icon', o.icon, 'ward_id', r.ward_id, 'ward', w.name, 'total_votes', r.total_votes, 'tie', r.tie,
            'winner', jsonb_build_object('username', (select username from profiles where id = r.user_id), 'party', bl_pol_party_json(k.party_id), 'votes', r.votes),
            'candidates', coalesce((select jsonb_agg(jsonb_build_object('username', (select username from profiles where id = x.user_id), 'party', bl_pol_party_json(x.party_id),
                                      'votes', x.final_votes, 'won', x.won) order by x.final_votes desc, x.rally_points desc, bl_pol_coin(x))
                                     from pol_candidates x where x.cycle_id = cy.id and x.slot_key = r.slot_key and x.status = 'declared'), '[]'::jsonb))
                 order by o.sort, w.sort nulls first)
          from pol_results r join offices o on o.id = r.office_id left join wards w on w.id = r.ward_id left join pol_candidates k on k.id = r.candidate_id
         where r.cycle_id = cy.id), '[]'::jsonb)) order by cy.id desc)
      from (select * from election_cycles where status = 'closed' order by id desc limit v_lim) cy), '[]'::jsonb);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 7. Player RPCs: declare, campaign, back, report, vote, party
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_pol_my_candidate(p_uid uuid, p_cycle bigint) returns public.pol_candidates
language sql stable set search_path = public as $$
  select * from pol_candidates where cycle_id = p_cycle and user_id = p_uid and status = 'declared';
$$;

create or replace function public.pol_party_create(p_name text, p_abbr text, p_color text default '#2f9e6b') returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); v_name text; v_abbr text := upper(btrim(coalesce(p_abbr, ''))); v_color text := coalesce(nullif(btrim(p_color), ''), '#2f9e6b'); v_id text; me profiles;
begin
  perform bl_pol_tick(); perform bl_pol_guard();
  select * into me from profiles where id = v_uid for update;
  if exists (select 1 from parties where founder_id = v_uid and active) then
    raise exception 'You already founded a party.' using errcode = 'P0001', hint = 'party_exists';
  end if;
  v_name := bl_chat_clean(coalesce(p_name, ''));
  if char_length(v_name) < 4 or char_length(v_name) > 32 or v_name !~ '^[A-Za-z0-9][A-Za-z0-9 ''\-]*[A-Za-z0-9]$' then
    raise exception 'A party name is 4 to 32 letters or numbers.' using errcode = 'P0001', hint = 'bad_name';
  end if;
  if v_abbr !~ '^[A-Z]{2,5}$' then
    raise exception 'The abbreviation is 2 to 5 letters.' using errcode = 'P0001', hint = 'bad_abbr';
  end if;
  if v_color !~ '^#[0-9a-fA-F]{6}$' then
    raise exception 'Pick a colour for the party.' using errcode = 'P0001', hint = 'bad_color';
  end if;
  if bl_chat_mask(v_name) <> v_name or bl_chat_mask(lower(v_abbr)) <> lower(v_abbr) or not bl_pol_text_ok(v_name) or not bl_pol_text_ok(v_abbr) then
    raise exception 'That party name no fit. Real parties and politicians are not allowed: make your own fictional one.' using errcode = 'P0001', hint = 'blocked_name';
  end if;
  if exists (select 1 from parties where lower(name) = lower(v_name) and active) or exists (select 1 from parties where upper(abbr) = v_abbr and active) then
    raise exception 'Another party already uses that name or abbreviation.' using errcode = 'P0001', hint = 'name_taken';
  end if;
  perform bl_pol_pay(v_uid, bl_pol_num('pol.party_fee', 50000)::bigint, 'campaign_fee', jsonb_build_object('label', 'Founded the ' || v_name, 'party', v_name));
  insert into parties (name, abbr, color, blurb, founder_id, seeded, created_at) values (v_name, v_abbr, v_color, 'A player-made party. Fictional.', v_uid, false, bl_now()) returning id into v_id;
  return jsonb_build_object('id', v_id, 'message', 'You founded the ' || v_name || ' (' || v_abbr || '). Now find a candidate.');
end $$;

create or replace function public.pol_declare(p_office text, p_ward text default null, p_promise text default '', p_party text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid(); c election_cycles; o offices; w wards; me profiles; v_req jsonb; v_slot text; v_promise text; v_n int; v_id bigint; v_home text;
begin
  perform bl_pol_tick(); perform bl_pol_guard();
  select * into c from bl_pol_open_cycle();
  if c.id is null or c.status <> 'registration' then
    raise exception 'Candidate registration is not open right now.' using errcode = 'P0001', hint = 'registration_closed';
  end if;
  select * into me from profiles where id = v_uid for update;
  select * into o from offices where id = p_office and active and elected;
  if not found then
    raise exception 'You cannot run for that office.' using errcode = 'P0001', hint = 'bad_office';
  end if;
  if o.ward_scoped then
    v_home := bl_pol_ward_of(v_uid);
    select * into w from wards where id = coalesce(nullif(p_ward, ''), v_home) and active;
    if not found or w.id <> v_home then
      raise exception 'A Councillor runs in the ward where they live (%). Move house to run somewhere else.', (select name from wards where id = v_home) using errcode = 'P0001', hint = 'wrong_ward';
    end if;
  end if;
  v_slot := bl_pol_slot(o.id, w.id);
  if exists (select 1 from pol_candidates where cycle_id = c.id and user_id = v_uid and status = 'declared') then
    raise exception 'You are already a candidate in this election. Withdraw first to change your race.' using errcode = 'P0001', hint = 'already_candidate';
  end if;
  v_req := bl_pol_requirements(v_uid, o);
  if not (v_req->>'ok')::boolean then
    raise exception '%', v_req->>'message' using errcode = 'P0001', hint = v_req->>'hint';
  end if;
  v_promise := bl_pol_moderate(p_promise, 10, bl_pol_num('pol.promise_max_len', 140)::int, 'promise');
  if p_party is not null and btrim(p_party) <> '' and not exists (select 1 from parties where id = btrim(p_party) and active) then
    raise exception 'Pick a party from the list, or run as an independent.' using errcode = 'P0001', hint = 'bad_party';
  end if;
  select count(*) into v_n from pol_candidates where cycle_id = c.id and slot_key = v_slot and status = 'declared';
  if v_n >= bl_pol_num('pol.max_candidates_per_slot', 8) then
    raise exception 'That race is full (% candidates).', v_n using errcode = 'P0001', hint = 'race_full';
  end if;
  perform bl_pol_pay(v_uid, o.fee, 'campaign_fee', jsonb_build_object('label', 'Candidacy fee: ' || o.name, 'office', o.id));
  insert into pol_candidates (cycle_id, office_id, ward_id, slot_key, user_id, party_id, promise, fee_paid, declared_at)
  values (c.id, o.id, w.id, v_slot, v_uid, nullif(btrim(coalesce(p_party, '')), ''), v_promise, o.fee, bl_now()) returning id into v_id;
  perform bl_skill_award(v_uid, 'politics', 'declare');
  return jsonb_build_object('id', v_id, 'message', 'You are a candidate for ' || o.name || coalesce(' in ' || w.name, '') || '. Campaign season starts when registration closes.');
end $$;

create or replace function public.pol_set_promise(p_promise text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); c election_cycles; k pol_candidates; v_promise text;
begin
  perform bl_pol_tick(); perform bl_pol_guard();
  select * into c from bl_pol_open_cycle();
  if c.id is null or c.status not in ('registration', 'campaign') then
    raise exception 'The promise is locked now.' using errcode = 'P0001', hint = 'locked';
  end if;
  select * into k from bl_pol_my_candidate(v_uid, c.id);
  if k.id is null then raise exception 'You are not a candidate.' using errcode = 'P0001', hint = 'not_candidate'; end if;
  v_promise := bl_pol_moderate(p_promise, 10, bl_pol_num('pol.promise_max_len', 140)::int, 'promise');
  update pol_candidates set promise = v_promise where id = k.id;
  return jsonb_build_object('message', 'Promise updated.');
end $$;

create or replace function public.pol_withdraw() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); c election_cycles; k pol_candidates;
begin
  perform bl_pol_tick(); perform bl_pol_guard();
  select * into c from bl_pol_open_cycle();
  if c.id is null or c.status not in ('registration', 'campaign') then
    raise exception 'You can only withdraw before voting day.' using errcode = 'P0001', hint = 'locked';
  end if;
  select * into k from bl_pol_my_candidate(v_uid, c.id);
  if k.id is null then raise exception 'You are not a candidate.' using errcode = 'P0001', hint = 'not_candidate'; end if;
  update pol_candidates set status = 'withdrawn' where id = k.id;
  delete from pol_backing where candidate_id = k.id;
  return jsonb_build_object('message', 'You withdrew. The fee is not refunded.');
end $$;

-- a rally where I stand: costs money, earns Charisma XP and momentum, and is announced in the place
create or replace function public.pol_rally() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid(); c election_cycles; k pol_candidates; me profiles; l locations; w wards; o offices; v_att int; v_pts int; v_cost bigint;
  v_text text; v_place text; r record; v_name text;
begin
  perform bl_pol_tick(); perform bl_pol_guard();
  select * into c from bl_pol_open_cycle();
  if c.id is null or c.status <> 'campaign' then
    raise exception 'Rallies happen during the campaign window.' using errcode = 'P0001', hint = 'not_campaign';
  end if;
  select * into me from profiles where id = v_uid for update;
  select * into k from bl_pol_my_candidate(v_uid, c.id);
  if k.id is null then raise exception 'You are not a candidate in this election.' using errcode = 'P0001', hint = 'not_candidate'; end if;
  if me.travel_to is not null or me.home_visit_host_id is not null or (me.busy_until is not null and me.busy_until > bl_now()) or (me.jailed_until is not null and me.jailed_until > bl_now())
     or (me.hospitalized_until is not null and me.hospitalized_until > bl_now()) then
    raise exception 'You must be free and standing at a public place to hold a rally.' using errcode = 'P0001', hint = 'not_free';
  end if;
  select * into l from locations where id = me.location_id;
  if l.private_home_owner_id is not null or l.id like 'pu\_%' then
    raise exception 'No rally at home or at a polling unit. Go to a public place.' using errcode = 'P0001', hint = 'bad_place';
  end if;
  if not bl_place_open(l) then
    raise exception '% is closed right now.', l.name using errcode = 'P0001', hint = 'closed';
  end if;
  select * into o from offices where id = k.office_id;
  if o.ward_scoped then
    select * into w from wards where id = k.ward_id;
    if not (l.district = any (w.districts)) then
      raise exception 'A Councillor rally must be inside your ward (%).', w.name using errcode = 'P0001', hint = 'wrong_ward';
    end if;
  end if;
  if k.last_rally_at is not null and k.last_rally_at + make_interval(mins => bl_pol_num('pol.rally_cooldown_minutes', 20)::int) > bl_now() then
    raise exception 'Your crowd is still catching breath. Next rally in %.', bl_pol_wait(k.last_rally_at + make_interval(mins => bl_pol_num('pol.rally_cooldown_minutes', 20)::int) - bl_now())
      using errcode = 'P0001', hint = 'cooldown';
  end if;
  if (select count(*) from pol_campaign_log g where g.candidate_id = k.id and g.kind = 'rally' and g.created_at > bl_now() - interval '24 hours') >= bl_pol_num('pol.rally_max_per_day', 6) then
    raise exception 'That is enough rallies for one day.' using errcode = 'P0001', hint = 'daily_cap';
  end if;
  select count(*) into v_att from profiles p
   where p.location_id = l.id and p.id <> v_uid and p.travel_to is null and not p.banned
     and p.last_seen > bl_now() - make_interval(secs => (bl_cfg('time.presence_real_minutes') * 60)::double precision);
  v_att := least(v_att, bl_pol_num('pol.rally_attendee_cap', 10)::int);
  v_pts := bl_pol_num('pol.rally_points', 10)::int + v_att * bl_pol_num('pol.rally_attendee_points', 2)::int;
  v_cost := bl_pol_num('pol.rally_cost', 20000)::bigint;
  perform bl_pol_pay(v_uid, v_cost, 'campaign_spend', jsonb_build_object('label', 'Campaign rally at ' || l.name, 'office', o.id));
  update pol_candidates set rally_points = rally_points + v_pts, rallies = rallies + 1, last_rally_at = bl_now() where id = k.id;
  insert into pol_campaign_log (cycle_id, candidate_id, user_id, kind, location_id, cost, points, attendees, created_at) values (c.id, k.id, v_uid, 'rally', l.id, v_cost, v_pts, v_att, bl_now());
  perform bl_skill_award(v_uid, 'politics', 'rally');
  v_place := regexp_replace(l.name, '\s*\(.*\)\s*$', '');
  v_name := me.username;
  v_text := format('%s @%s is holding a rally for %s%s at %s! "%s"', o.icon, v_name, o.name, coalesce(' (' || (select name from wards where id = k.ward_id) || ')', ''), v_place, k.promise);
  insert into place_announcements (location_id, user_id, username, kind, amount, qty, text, ticker, global, place)
  values (l.id, v_uid, v_name, 'rally', v_cost, 1, left(v_text, 400), null, false, v_place);
  for r in select p.id from profiles p where p.location_id = l.id and p.id <> v_uid and p.travel_to is null and not p.banned
              and p.last_seen > bl_now() - make_interval(secs => (bl_cfg('time.presence_real_minutes') * 60)::double precision) order by p.id limit 30 loop
    perform bl_event(r.id, 'pol_rally', 'Rally at ' || v_place, '@' || v_name || ' for ' || o.name || ': "' || k.promise || '"', jsonb_build_object('candidate', k.id, 'location', l.id));
  end loop;
  return jsonb_build_object('points', v_pts, 'attendees', v_att, 'cost', v_cost,
    'message', 'Rally done at ' || v_place || '! +' || v_pts || ' momentum' || case when v_att > 0 then ' (' || v_att || ' player' || case when v_att = 1 then '' else 's' end || ' showed face)' else '' end || '.');
end $$;

create or replace function public.pol_poster() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); c election_cycles; k pol_candidates; v_cost bigint := bl_pol_num('pol.poster_cost', 10000)::bigint; v_pts int := bl_pol_num('pol.poster_points', 3)::int; o offices;
begin
  perform bl_pol_tick(); perform bl_pol_guard();
  select * into c from bl_pol_open_cycle();
  if c.id is null or c.status <> 'campaign' then
    raise exception 'Posters go up during the campaign window.' using errcode = 'P0001', hint = 'not_campaign';
  end if;
  select * into k from pol_candidates where cycle_id = c.id and user_id = v_uid and status = 'declared' for update;
  if not found then raise exception 'You are not a candidate in this election.' using errcode = 'P0001', hint = 'not_candidate'; end if;
  if k.posters >= bl_pol_num('pol.poster_max', 5) then
    raise exception 'All % posters are up already.', k.posters using errcode = 'P0001', hint = 'poster_max';
  end if;
  if k.last_poster_at is not null and k.last_poster_at + make_interval(hours => bl_pol_num('pol.poster_cooldown_hours', 6)::int) > bl_now() then
    raise exception 'The poster glue is still wet. Next poster in %.', bl_pol_wait(k.last_poster_at + make_interval(hours => bl_pol_num('pol.poster_cooldown_hours', 6)::int) - bl_now())
      using errcode = 'P0001', hint = 'cooldown';
  end if;
  select * into o from offices where id = k.office_id;
  perform bl_pol_pay(v_uid, v_cost, 'campaign_spend', jsonb_build_object('label', 'Campaign poster', 'office', o.id));
  update pol_candidates set posters = posters + 1, last_poster_at = bl_now() where id = k.id;
  insert into pol_campaign_log (cycle_id, candidate_id, user_id, kind, cost, points, created_at) values (c.id, k.id, v_uid, 'poster', v_cost, v_pts, bl_now());
  perform bl_skill_award(v_uid, 'politics', 'poster');
  return jsonb_build_object('message', 'Poster up! +' || v_pts || ' momentum.');
end $$;

-- declare support / endorse a candidate (a player), or endorse as a crew. One backing per player per race; switching moves it.
create or replace function public.pol_back(p_candidate bigint, p_kind text default 'support') returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid(); c election_cycles; k pol_candidates; me profiles; v_kind text := lower(btrim(coalesce(p_kind, 'support'))); m crew_members; cr crews; v_n int;
begin
  perform bl_pol_tick(); perform bl_pol_guard();
  select * into c from bl_pol_open_cycle();
  if c.id is null or c.status not in ('registration', 'campaign') then
    raise exception 'Backing a candidate is open during registration and the campaign, not on voting day.' using errcode = 'P0001', hint = 'locked';
  end if;
  if v_kind not in ('support', 'endorse', 'crew') then
    raise exception 'Pick support, endorse or crew.' using errcode = 'P0001', hint = 'bad_kind';
  end if;
  select * into k from pol_candidates where id = p_candidate and cycle_id = c.id and status = 'declared';
  if not found then raise exception 'That candidate is not running.' using errcode = 'P0001', hint = 'not_candidate'; end if;
  select * into me from profiles where id = v_uid;
  if extract(epoch from (bl_now() - me.created_at)) / 86400.0 < bl_pol_num('pol.vote_min_account_days', 3) then
    raise exception 'Your account must be at least % days old to back a candidate.', bl_pol_num('pol.vote_min_account_days', 3)::numeric(10, 1) using errcode = 'P0001', hint = 'account_young';
  end if;
  if k.user_id = v_uid then
    raise exception 'You cannot back yourself, my guy.' using errcode = 'P0001', hint = 'self';
  end if;
  if v_kind = 'crew' then
    select * into m from crew_members where user_id = v_uid;
    if not found or m.rank not in ('boss', 'lieutenant') then
      raise exception 'Only a crew Boss or Lieutenant can endorse for the crew.' using errcode = 'P0001', hint = 'not_crew_leader';
    end if;
    select * into cr from crews where id = m.crew_id and disbanded_at is null;
    select count(*) into v_n from crew_members where crew_id = m.crew_id;
    if v_n < bl_pol_num('pol.crew_endorse_min_members', 2) then
      raise exception 'Your crew needs at least % members to endorse.', bl_pol_num('pol.crew_endorse_min_members', 2)::int using errcode = 'P0001', hint = 'crew_small';
    end if;
    delete from pol_backing where cycle_id = c.id and slot_key = k.slot_key and crew_id = m.crew_id and kind = 'crew';
    insert into pol_backing (cycle_id, candidate_id, slot_key, user_id, crew_id, kind, created_at) values (c.id, k.id, k.slot_key, v_uid, m.crew_id, 'crew', bl_now());
    return jsonb_build_object('message', cr.name || ' endorsed @' || (select username from profiles where id = k.user_id) || '.');
  end if;
  if v_kind = 'endorse' and not bl_pol_charisma_ok(v_uid, bl_pol_num('pol.endorse_min_charisma', 2)::int) then
    raise exception 'A public endorsement needs Charisma level %. You can still declare support.', bl_pol_num('pol.endorse_min_charisma', 2)::int using errcode = 'P0001', hint = 'charisma_low';
  end if;
  delete from pol_backing where cycle_id = c.id and slot_key = k.slot_key and user_id = v_uid and kind in ('support', 'endorse');
  insert into pol_backing (cycle_id, candidate_id, slot_key, user_id, kind, created_at) values (c.id, k.id, k.slot_key, v_uid, v_kind, bl_now());
  return jsonb_build_object('message', case v_kind when 'endorse' then 'You endorsed @' else 'You are a declared supporter of @' end || (select username from profiles where id = k.user_id) || '. This is not a vote.');
end $$;

create or replace function public.pol_unback(p_candidate bigint, p_kind text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); c election_cycles; k pol_candidates; m crew_members; n int;
begin
  perform bl_pol_tick(); perform bl_pol_guard();
  select * into c from bl_pol_open_cycle();
  if c.id is null or c.status not in ('registration', 'campaign') then
    raise exception 'Backing is locked on voting day.' using errcode = 'P0001', hint = 'locked';
  end if;
  select * into k from pol_candidates where id = p_candidate and cycle_id = c.id;
  if not found then raise exception 'That candidate is not running.' using errcode = 'P0001', hint = 'not_candidate'; end if;
  if lower(coalesce(p_kind, '')) = 'crew' then
    select * into m from crew_members where user_id = v_uid and rank in ('boss', 'lieutenant');
    delete from pol_backing where candidate_id = k.id and kind = 'crew' and crew_id = m.crew_id;
  else
    delete from pol_backing where candidate_id = k.id and kind in ('support', 'endorse') and user_id = v_uid;
  end if;
  get diagnostics n = row_count;
  return jsonb_build_object('message', case when n > 0 then 'Backing removed.' else 'Nothing to remove.' end);
end $$;

-- vote buying is not a mechanic: report it, an admin reviews and can disqualify (audited)
create or replace function public.pol_report_vote_buying(p_candidate bigint, p_reason text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); c election_cycles; k pol_candidates; me profiles; v_reason text := left(btrim(coalesce(p_reason, '')), 200);
begin
  perform bl_pol_tick(); perform bl_pol_guard();
  select * into c from bl_pol_open_cycle();
  if c.id is null then raise exception 'There is no election running.' using errcode = 'P0001', hint = 'no_election'; end if;
  select * into k from pol_candidates where id = p_candidate and cycle_id = c.id and status = 'declared';
  if not found then raise exception 'That candidate is not running.' using errcode = 'P0001', hint = 'not_candidate'; end if;
  select * into me from profiles where id = v_uid;
  if extract(epoch from (bl_now() - me.created_at)) / 86400.0 < bl_pol_num('pol.vote_min_account_days', 3) then
    raise exception 'Your account must be at least % days old to report.', bl_pol_num('pol.vote_min_account_days', 3)::numeric(10, 1) using errcode = 'P0001', hint = 'account_young';
  end if;
  if k.user_id = v_uid then raise exception 'You cannot report yourself.' using errcode = 'P0001', hint = 'self'; end if;
  if exists (select 1 from pol_reports where candidate_id = k.id and reporter_id = v_uid) then
    raise exception 'You already reported this candidate.' using errcode = 'P0001', hint = 'already_reported';
  end if;
  if (select count(*) from pol_reports where reporter_id = v_uid and created_at > bl_now() - interval '24 hours') >= bl_pol_num('pol.report_daily_cap', 5) then
    raise exception 'Too many reports today. Wait small.' using errcode = 'P0001', hint = 'daily_cap';
  end if;
  if v_reason <> '' and (bl_chat_mask(v_reason) <> v_reason) then v_reason := '(removed)'; end if;
  insert into pol_reports (cycle_id, candidate_id, reporter_id, reason, created_at) values (c.id, k.id, v_uid, v_reason, bl_now());
  return jsonb_build_object('message', 'Report sent. An admin will review it. Vote buying is not allowed in Benin Votes.');
end $$;

-- cast a vote: one per account per office per election, at your ward's polling unit, while voting is open. The ballot is secret.
create or replace function public.pol_vote(p_candidate bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid(); c election_cycles; k pol_candidates; me profiles; w wards; o offices; v_now timestamptz; v_unit locations;
begin
  perform bl_pol_tick(); perform bl_pol_guard();
  v_now := bl_now();
  select * into c from bl_pol_open_cycle();
  if c.id is null or c.status <> 'voting' or v_now < c.vote_start or v_now >= c.vote_end then
    raise exception 'Voting is not open right now.' using errcode = 'P0001', hint = 'not_voting';
  end if;
  select * into me from profiles where id = v_uid for update;
  if me.banned then raise exception 'Your account cannot vote.' using errcode = 'P0001', hint = 'banned'; end if;
  if extract(epoch from (v_now - me.created_at)) / 86400.0 < bl_pol_num('pol.vote_min_account_days', 3) then
    raise exception 'Your account must be at least % days old to vote.', bl_pol_num('pol.vote_min_account_days', 3)::numeric(10, 1) using errcode = 'P0001', hint = 'account_young';
  end if;
  if me.jailed_until is not null and me.jailed_until > v_now then
    raise exception 'You dey inside. No voting from the cell.' using errcode = 'P0001', hint = 'jailed';
  end if;
  select * into w from wards where id = bl_pol_ward_of(v_uid);
  select * into v_unit from locations where id = w.poll_unit;
  if me.location_id is distinct from w.poll_unit or me.travel_to is not null or me.home_visit_host_id is not null then
    raise exception 'You must vote at your polling unit: %. Go there first.', v_unit.name using errcode = 'P0001', hint = 'wrong_place';
  end if;
  select * into k from pol_candidates where id = p_candidate and cycle_id = c.id and status = 'declared';
  if not found then raise exception 'That candidate is not on the ballot.' using errcode = 'P0001', hint = 'not_candidate'; end if;
  select * into o from offices where id = k.office_id;
  if o.ward_scoped and k.ward_id is distinct from w.id then
    raise exception 'That Councillor race is for another ward. Your ward is %.', w.name using errcode = 'P0001', hint = 'wrong_ward';
  end if;
  begin
    insert into pol_votes (cycle_id, office_id, ward_id, voter_id, candidate_id, created_at) values (c.id, k.office_id, k.ward_id, v_uid, k.id, v_now);
  exception when unique_violation then
    raise exception 'You already voted for % in this election.', o.name using errcode = 'P0001', hint = 'already_voted';
  end;
  return jsonb_build_object('office_id', o.id, 'message', 'Vote cast for ' || o.name || '. Your ballot is secret. Tallies open after voting closes.');
end $$;

-- ---------------------------------------------------------------------------------------------
-- 8. Powers in office
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_pol_my_office(p_uid uuid, p_kind text) returns public.office_holders
language plpgsql stable set search_path = public as $$
declare h office_holders;
begin
  select h2.* into h from office_holders h2 join offices o on o.id = h2.office_id
   where h2.user_id = p_uid and h2.status = 'active' and h2.term_end > bl_now() and o.kind = p_kind;
  return h;
end $$;

create or replace function public.pol_appoint(p_office text, p_username text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); g office_holders; o offices; t profiles; v_id bigint; v_name text := btrim(coalesce(p_username, ''));
begin
  perform bl_pol_tick(); perform bl_pol_guard();
  g := bl_pol_my_office(v_uid, 'governor');
  if g.id is null then raise exception 'Only the Governor appoints Commissioners.' using errcode = 'P0001', hint = 'not_governor'; end if;
  select * into o from offices where id = p_office and kind = 'commissioner' and active;
  if not found then raise exception 'Pick a Commissioner post.' using errcode = 'P0001', hint = 'bad_office'; end if;
  select * into t from profiles where lower(username) = lower(regexp_replace(v_name, '^@', '')) and home_chosen and not banned;
  if not found then raise exception 'No player with that username.' using errcode = 'P0001', hint = 'no_player'; end if;
  if t.id = v_uid then raise exception 'You are already the Governor.' using errcode = 'P0001', hint = 'self'; end if;
  if extract(epoch from (bl_now() - t.created_at)) / 86400.0 < bl_pol_num('pol.appoint_min_account_days', 3) then
    raise exception '@% is too new for a Commissioner post (accounts must be % days old).', t.username, bl_pol_num('pol.appoint_min_account_days', 3)::numeric(10, 1) using errcode = 'P0001', hint = 'account_young';
  end if;
  if exists (select 1 from office_holders where user_id = t.id and status = 'active' and term_end > bl_now()) then
    raise exception '@% already holds an office.', t.username using errcode = 'P0001', hint = 'holds_office';
  end if;
  if exists (select 1 from office_holders where office_id = o.id and status = 'active' and term_end > bl_now()) then
    raise exception '% is filled. Sack the current Commissioner first.', o.name using errcode = 'P0001', hint = 'filled';
  end if;
  insert into office_holders (cycle_id, office_id, user_id, appointed_by, status, term_start, term_end, paid_through)
  values (g.cycle_id, o.id, t.id, v_uid, 'active', bl_now(), g.term_end, bl_now()) returning id into v_id;
  perform bl_event(t.id, 'pol_appointed', 'You are now ' || o.name, 'Governor @' || (select username from profiles where id = v_uid) || ' appointed you. You earn a daily salary until the term ends.',
    jsonb_build_object('office', o.id));
  return jsonb_build_object('id', v_id, 'message', '@' || t.username || ' is now ' || o.name || '.');
end $$;

create or replace function public.pol_sack(p_office text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); g office_holders; h office_holders; o offices;
begin
  perform bl_pol_tick(); perform bl_pol_guard();
  g := bl_pol_my_office(v_uid, 'governor');
  if g.id is null then raise exception 'Only the Governor sacks Commissioners.' using errcode = 'P0001', hint = 'not_governor'; end if;
  select * into o from offices where id = p_office and kind = 'commissioner';
  if not found then raise exception 'Pick a Commissioner post.' using errcode = 'P0001', hint = 'bad_office'; end if;
  select * into h from office_holders where office_id = o.id and status = 'active' and term_end > bl_now() for update;
  if not found then raise exception 'Nobody holds that post.' using errcode = 'P0001', hint = 'vacant'; end if;
  perform bl_pol_pay_holder(h.id);
  update office_holders set status = 'sacked', ended_at = bl_now(), ended_reason = 'Sacked by the Governor' where id = h.id;
  perform bl_event(h.user_id, 'pol_sacked', 'You were sacked', 'The Governor removed you as ' || o.name || '.', jsonb_build_object('office', o.id));
  return jsonb_build_object('message', (select username from profiles where id = h.user_id) || ' was sacked as ' || o.name || '.');
end $$;

-- one Government announcement a day: the existing broadcast system (alerts + the Announcements push), moderated and rate limited
create or replace function public.pol_announce(p_body text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); g office_holders; v_body text; v_next timestamptz; v_id bigint; v_name text; n int;
begin
  perform bl_pol_tick(); perform bl_pol_guard();
  g := bl_pol_my_office(v_uid, 'governor');
  if g.id is null then raise exception 'Only the Governor posts government announcements.' using errcode = 'P0001', hint = 'not_governor'; end if;
  select * into g from office_holders where id = g.id for update;
  v_next := g.last_announce_at + make_interval(hours => bl_pol_num('pol.announce_cooldown_hours', 24)::int);
  if g.last_announce_at is not null and v_next > bl_now() then
    raise exception 'One government announcement per day. Next one in %.', bl_pol_wait(v_next - bl_now()) using errcode = 'P0001', hint = 'cooldown';
  end if;
  v_body := bl_pol_moderate(p_body, 10, bl_pol_num('pol.announce_max_len', 200)::int, 'announcement');
  select username into v_name from profiles where id = v_uid;
  insert into broadcasts (kind, title, body, style, audience, popup, expires_at, created_by)
  values ('message', left('Government announcement: Gov. @' || v_name, 80), v_body, 'info', 'everyone', true, now() + interval '24 hours', v_uid)
  returning id into v_id;
  select count(*) into n from bl_broadcast_targets('everyone', null);
  update broadcasts set target_count = n where id = v_id;
  perform bl_broadcast_bump(v_id);
  update office_holders set last_announce_at = bl_now() where id = g.id;
  return jsonb_build_object('id', v_id, 'reach', n, 'message', 'Announcement sent to ' || n || ' player' || case when n = 1 then '' else 's' end || '.');
end $$;

create or replace function public.pol_set_policy(p_policy text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); g office_holders; p gov_policies;
begin
  perform bl_pol_tick(); perform bl_pol_guard();
  g := bl_pol_my_office(v_uid, 'governor');
  if g.id is null then raise exception 'Only the Governor sets a policy.' using errcode = 'P0001', hint = 'not_governor'; end if;
  select * into g from office_holders where id = g.id for update;
  if g.policy_id is not null then raise exception 'You already set your one policy for this term.' using errcode = 'P0001', hint = 'policy_set'; end if;
  select * into p from gov_policies where id = p_policy and active;
  if not found then raise exception 'Pick a policy from the list.' using errcode = 'P0001', hint = 'bad_policy'; end if;
  update office_holders set policy_id = p.id, policy_set_at = bl_now() where id = g.id;
  return jsonb_build_object('message', p.name || ' is now government policy until the term ends.');
end $$;

-- a Councillor sponsors ONE ward event notice per term: an alert to the ward's recently active residents
create or replace function public.pol_ward_notice(p_body text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); h office_holders; w wards; v_body text; r record; n int := 0; v_name text;
begin
  perform bl_pol_tick(); perform bl_pol_guard();
  h := bl_pol_my_office(v_uid, 'councillor');
  if h.id is null then raise exception 'Only a Councillor sponsors a ward notice.' using errcode = 'P0001', hint = 'not_councillor'; end if;
  select * into h from office_holders where id = h.id for update;
  if h.ward_announce_used then raise exception 'You already used your ward notice for this term.' using errcode = 'P0001', hint = 'used'; end if;
  select * into w from wards where id = h.ward_id;
  v_body := bl_pol_moderate(p_body, 10, bl_pol_num('pol.ward_announce_max_len', 160)::int, 'ward notice');
  select username into v_name from profiles where id = v_uid;
  for r in select p.id from profiles p join locations l on l.id = p.home_location_id
            where l.district = any (w.districts) and p.id <> v_uid and p.home_chosen and not p.banned and p.last_seen > bl_now() - interval '3 days' order by p.id limit 300 loop
    perform bl_event(r.id, 'pol_ward_notice', 'Hon. @' || v_name || ' (' || w.name || ' ward)', v_body, jsonb_build_object('ward', w.id, 'holder', h.id));
    n := n + 1;
  end loop;
  update office_holders set ward_announce_used = true where id = h.id;
  return jsonb_build_object('reach', n, 'message', 'Ward notice sent to ' || n || ' neighbour' || case when n = 1 then '' else 's' end || '.');
end $$;

create or replace function public.pol_resign() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); h office_holders; o offices;
begin
  perform bl_pol_tick(); perform bl_pol_guard();
  select * into h from office_holders where user_id = v_uid and status = 'active' and term_end > bl_now() for update;
  if not found then raise exception 'You hold no office.' using errcode = 'P0001', hint = 'no_office'; end if;
  select * into o from offices where id = h.office_id;
  perform bl_pol_pay_holder(h.id);
  update office_holders set status = 'resigned', ended_at = bl_now(), ended_reason = 'Resigned' where id = h.id;
  if o.kind = 'governor' then
    update office_holders set status = 'ended', ended_at = bl_now(), ended_reason = 'The Governor resigned'
     where status = 'active' and office_id in (select id from offices where kind = 'commissioner');
  end if;
  return jsonb_build_object('message', 'You resigned as ' || o.name || '. The seat is vacant until the next election.');
end $$;

-- ---------------------------------------------------------------------------------------------
-- 9. Admin: Elections (start / advance / cancel, candidates, disqualify, remove a holder, tallies after the close). Every action is audited.
-- ---------------------------------------------------------------------------------------------
create or replace function public.admin_pol_overview() returns jsonb
language plpgsql security definer set search_path = public as $$
declare c election_cycles; v_show bigint; v_flag int := bl_pol_num('pol.report_flag_count', 3)::int; v_now timestamptz;
begin
  perform bl_admin_guard();
  perform bl_pol_tick();
  v_now := bl_now();
  select * into c from bl_pol_open_cycle();
  v_show := coalesce(c.id, (select max(id) from election_cycles where status = 'closed'));
  return jsonb_build_object(
    'now', v_now, 'enabled', bl_pol_on(), 'auto_cycle', bl_pol_flag('pol.auto_cycle', true),
    'cycle', case when c.id is null then null else jsonb_build_object('id', c.id, 'status', c.status, 'reg_start', c.reg_start, 'camp_start', c.camp_start, 'vote_start', c.vote_start,
               'vote_end', c.vote_end, 'term_days', c.term_days, 'created_by', (select username from profiles where id = c.created_by),
               'next_at', case c.status when 'registration' then c.camp_start when 'campaign' then c.vote_start else c.vote_end end,
               'votes_cast', (select count(*) from pol_votes where cycle_id = c.id), 'voters', (select count(distinct voter_id) from pol_votes where cycle_id = c.id)) end,
    'shown_cycle', v_show,
    'candidates', coalesce((
      select jsonb_agg(jsonb_build_object('id', k.id, 'cycle_id', k.cycle_id, 'user_id', k.user_id, 'username', p.username, 'office_id', k.office_id, 'office', o.name, 'ward', w.name,
               'party', bl_pol_party_json(k.party_id), 'promise', k.promise, 'status', k.status, 'dq_reason', k.dq_reason, 'fee_paid', k.fee_paid, 'rally_points', k.rally_points,
               'rallies', k.rallies, 'posters', k.posters, 'won', k.won, 'final_votes', k.final_votes,
               'supporters', (select count(*) from pol_backing b where b.candidate_id = k.id and b.kind = 'support'),
               'endorsements', (select count(*) from pol_backing b where b.candidate_id = k.id and b.kind in ('endorse', 'crew')),
               'reports', (select count(*) from pol_reports r where r.candidate_id = k.id and r.status = 'open'),
               'flagged', (select count(*) from pol_reports r where r.candidate_id = k.id and r.status = 'open') >= v_flag,
               'report_texts', coalesce((select jsonb_agg(r.reason order by r.id desc) from (select * from pol_reports x where x.candidate_id = k.id order by x.id desc limit 5) r where r.reason <> ''), '[]'::jsonb),
               'declared_at', k.declared_at) order by (select count(*) from pol_reports r where r.candidate_id = k.id and r.status = 'open') desc, o.sort, w.sort nulls first, k.id)
        from pol_candidates k join profiles p on p.id = k.user_id join offices o on o.id = k.office_id left join wards w on w.id = k.ward_id where k.cycle_id = v_show), '[]'::jsonb),
    'holders', coalesce((select jsonb_agg(bl_pol_holder_json(h) order by o.sort, h.ward_id nulls first) from office_holders h join offices o on o.id = h.office_id
                          where h.status = 'active' and h.term_end > v_now), '[]'::jsonb),
    'history', coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'status', x.status, 'reg_start', x.reg_start, 'vote_end', x.vote_end, 'closed_at', x.closed_at, 'cancel_reason', x.cancel_reason,
                 'candidates', (select count(*) from pol_candidates k where k.cycle_id = x.id and k.status = 'declared'),
                 'votes', case when x.status = 'closed' then (select count(*) from pol_votes v where v.cycle_id = x.id) end) order by x.id desc)
                 from (select * from election_cycles order by id desc limit 12) x), '[]'::jsonb));
end $$;

create or replace function public.admin_pol_start(p_reg_hours numeric default null, p_camp_hours numeric default null, p_vote_hours numeric default null, p_term_days numeric default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); v_id bigint;
begin
  perform bl_pol_tick();
  perform bl_pol_guard();
  if coalesce(p_reg_hours, 1) <= 0 or coalesce(p_camp_hours, 1) <= 0 or coalesce(p_vote_hours, 1) <= 0 or coalesce(p_term_days, 1) <= 0 then
    raise exception 'Every window and the term must be above zero.' using errcode = 'P0001', hint = 'bad_value';
  end if;
  v_id := bl_pol_start_cycle(v_admin, p_reg_hours, p_camp_hours, p_vote_hours, p_term_days);
  if v_id is null then
    raise exception 'An election is already running. Cancel it or let it finish.' using errcode = 'P0001', hint = 'running';
  end if;
  insert into admin_audit (admin_id, action, target_user, data)
  values (v_admin, 'pol_start', null, jsonb_build_object('cycle', v_id, 'reg_hours', p_reg_hours, 'camp_hours', p_camp_hours, 'vote_hours', p_vote_hours, 'term_days', p_term_days));
  return jsonb_build_object('id', v_id, 'message', 'Election started: registration is open.');
end $$;

create or replace function public.admin_pol_advance() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); c election_cycles; v_now timestamptz; v_camp interval; v_vote interval; v_old text; v_new text;
begin
  perform bl_pol_tick();
  v_now := bl_now();
  select * into c from election_cycles where status in ('registration', 'campaign', 'voting') order by id desc limit 1 for update;
  if not found then raise exception 'No election is running.' using errcode = 'P0001', hint = 'none'; end if;
  v_old := c.status;
  v_camp := c.vote_start - c.camp_start;
  v_vote := c.vote_end - c.vote_start;
  if c.status = 'registration' then
    update election_cycles set camp_start = v_now, vote_start = v_now + v_camp, vote_end = v_now + v_camp + v_vote where id = c.id;
  elsif c.status = 'campaign' then
    update election_cycles set vote_start = v_now, vote_end = v_now + v_vote where id = c.id;
  else
    update election_cycles set vote_end = v_now where id = c.id;
  end if;
  perform bl_pol_tick();
  select status into v_new from election_cycles where id = c.id;
  insert into admin_audit (admin_id, action, target_user, data) values (v_admin, 'pol_advance', null, jsonb_build_object('cycle', c.id, 'from', v_old, 'to', v_new));
  return jsonb_build_object('message', 'Moved from ' || v_old || ' to ' || v_new || '.', 'status', v_new);
end $$;

create or replace function public.admin_pol_cancel(p_reason text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); c election_cycles; r record; v_reason text := left(btrim(coalesce(p_reason, '')), 200); n int := 0;
begin
  perform bl_pol_tick();
  select * into c from election_cycles where status in ('registration', 'campaign', 'voting') order by id desc limit 1 for update;
  if not found then raise exception 'No election is running.' using errcode = 'P0001', hint = 'none'; end if;
  update election_cycles set status = 'cancelled', closed_at = bl_now(), cancel_reason = v_reason where id = c.id;
  -- the fees come back (the current government stays as it was)
  for r in select k.id, k.user_id, k.fee_paid from pol_candidates k where k.cycle_id = c.id and k.status = 'declared' order by k.id loop
    if r.fee_paid > 0 then
      perform bl_add_money(r.user_id, 'bank', r.fee_paid, 'campaign_fee', jsonb_build_object('label', 'Candidacy fee refunded (election cancelled)', 'refund', true));
    end if;
    perform bl_event(r.user_id, 'pol_cancelled', 'Election cancelled', 'The election was cancelled' || case when v_reason <> '' then ': ' || v_reason else '' end || '. Your fee was refunded.', jsonb_build_object('cycle', c.id));
    n := n + 1;
  end loop;
  insert into admin_audit (admin_id, action, target_user, data) values (v_admin, 'pol_cancel', null, jsonb_build_object('cycle', c.id, 'reason', v_reason, 'refunded', n));
  return jsonb_build_object('message', 'Election cancelled. ' || n || ' candidate' || case when n = 1 then '' else 's' end || ' refunded.');
end $$;

create or replace function public.admin_pol_disqualify(p_candidate bigint, p_reason text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); k pol_candidates; c election_cycles; v_reason text := left(btrim(coalesce(p_reason, '')), 200); v_votes int;
begin
  perform bl_pol_tick();
  select * into k from pol_candidates where id = p_candidate for update;
  if not found then raise exception 'No such candidate.' using errcode = 'P0001', hint = 'gone'; end if;
  select * into c from election_cycles where id = k.cycle_id;
  if c.status in ('closed', 'cancelled') then
    raise exception 'That election is over. Use Remove from office instead.' using errcode = 'P0001', hint = 'closed';
  end if;
  if k.status <> 'declared' then raise exception 'That candidate is not running.' using errcode = 'P0001', hint = 'gone'; end if;
  if v_reason = '' then raise exception 'Give a reason (it is kept in the audit log).' using errcode = 'P0001', hint = 'reason'; end if;
  -- votes already cast for them are voided (those voters can vote again); backing goes
  select count(*) into v_votes from pol_votes where candidate_id = k.id;
  delete from pol_votes where candidate_id = k.id;
  delete from pol_backing where candidate_id = k.id;
  update pol_candidates set status = 'disqualified', dq_reason = v_reason where id = k.id;
  update pol_reports set status = 'reviewed' where candidate_id = k.id and status = 'open';
  perform bl_event(k.user_id, 'pol_disqualified', 'You were disqualified', 'An admin disqualified your candidacy. Reason: ' || v_reason || '. Vote buying is not allowed in Benin Votes.', jsonb_build_object('cycle', k.cycle_id));
  insert into admin_audit (admin_id, action, target_user, data)
  values (v_admin, 'pol_disqualify', k.user_id, jsonb_build_object('candidate', k.id, 'cycle', k.cycle_id, 'office', k.office_id, 'ward', k.ward_id, 'reason', v_reason, 'votes_voided', v_votes));
  return jsonb_build_object('message', 'Disqualified. ' || v_votes || ' vote' || case when v_votes = 1 then '' else 's' end || ' voided.');
end $$;

create or replace function public.admin_pol_dismiss_reports(p_candidate bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); n int;
begin
  update pol_reports set status = 'reviewed' where candidate_id = p_candidate and status = 'open';
  get diagnostics n = row_count;
  insert into admin_audit (admin_id, action, target_user, data) values (v_admin, 'pol_reports_dismiss', null, jsonb_build_object('candidate', p_candidate, 'reports', n));
  return jsonb_build_object('message', n || ' report(s) marked reviewed.');
end $$;

create or replace function public.admin_pol_remove_holder(p_holder bigint, p_reason text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); h office_holders; o offices; v_reason text := left(btrim(coalesce(p_reason, '')), 200);
begin
  select * into h from office_holders where id = p_holder and status = 'active' for update;
  if not found then raise exception 'That seat is already empty.' using errcode = 'P0001', hint = 'gone'; end if;
  if v_reason = '' then raise exception 'Give a reason (it is kept in the audit log).' using errcode = 'P0001', hint = 'reason'; end if;
  select * into o from offices where id = h.office_id;
  perform bl_pol_pay_holder(h.id);
  update office_holders set status = 'removed', ended_at = bl_now(), ended_reason = v_reason where id = h.id;
  if o.kind = 'governor' then
    update office_holders set status = 'ended', ended_at = bl_now(), ended_reason = 'The Governor was removed'
     where status = 'active' and office_id in (select id from offices where kind = 'commissioner');
  end if;
  perform bl_event(h.user_id, 'pol_removed', 'You were removed from office', 'An admin removed you as ' || o.name || '. Reason: ' || v_reason, jsonb_build_object('office', o.id));
  insert into admin_audit (admin_id, action, target_user, data) values (v_admin, 'pol_remove_holder', h.user_id, jsonb_build_object('holder', h.id, 'office', o.id, 'ward', h.ward_id, 'reason', v_reason));
  return jsonb_build_object('message', 'Removed from office.');
end $$;

-- tallies: closed elections only (ballot secrecy)
create or replace function public.admin_pol_tallies(p_cycle bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c election_cycles;
begin
  perform bl_admin_guard();
  select * into c from election_cycles where id = p_cycle;
  if not found then raise exception 'No such election.' using errcode = 'P0001', hint = 'gone'; end if;
  if c.status <> 'closed' then
    raise exception 'Ballot secrecy: tallies open after voting closes.' using errcode = 'P0001', hint = 'secret';
  end if;
  return jsonb_build_object('cycle', c.id, 'closed_at', c.closed_at,
    'races', coalesce((select jsonb_agg(jsonb_build_object('office', o.name, 'ward', w.name, 'tie', r.tie, 'total_votes', r.total_votes,
        'candidates', coalesce((select jsonb_agg(jsonb_build_object('username', p.username, 'party', bl_pol_party_json(x.party_id), 'votes', x.final_votes, 'rally_points', x.rally_points, 'won', x.won)
                                 order by x.final_votes desc, x.rally_points desc, bl_pol_coin(x))
                                 from pol_candidates x join profiles p on p.id = x.user_id where x.cycle_id = c.id and x.slot_key = r.slot_key and x.status = 'declared'), '[]'::jsonb))
        order by o.sort, w.sort nulls first)
        from pol_results r join offices o on o.id = r.office_id left join wards w on w.id = r.ward_id where r.cycle_id = c.id), '[]'::jsonb));
end $$;

-- ---------------------------------------------------------------------------------------------
-- 10. Patches to live functions (guarded)
-- ---------------------------------------------------------------------------------------------
-- the title next to a name: people in a place, public profiles, chat rows, friend cards
select pg_temp.bl_patch1('public.players_here(text)', 'bl_pol_title(',
  E'''crew'', public.bl_crew_badge(p.id))',
  E'''crew'', public.bl_crew_badge(p.id), ''title'', public.bl_pol_title(p.id))');
select pg_temp.bl_patch1('public.get_public_profile(uuid)', 'bl_pol_title(',
  E'''crew'', bl_crew_badge(id))',
  E'''crew'', bl_crew_badge(id), ''title'', bl_pol_title(id))');
select pg_temp.bl_patch1('public.bl_chat_row(public.chat_messages, jsonb, uuid)', 'm.pol_title',
  E'''crew_tag'', m.crew_tag,',
  E'''crew_tag'', m.crew_tag, ''pol_title'', m.pol_title,');
select pg_temp.bl_patch1('public.bl_friend_card(public.profiles, public.profiles, numeric, boolean)', 'bl_pol_title(',
  E'''crew'', bl_crew_badge(o.id),',
  E'''crew'', bl_crew_badge(o.id), ''title'', bl_pol_title(o.id),');

-- ledger text
select pg_temp.bl_patch1('public.bl_ledger_label(text, jsonb)', 'when ''campaign_fee'' then',
  E'    when ''garage'' then return',
  E'    when ''campaign_fee'' then return coalesce(nullif(p_meta->>''label'', ''''), ''Election fee'');\n    when ''campaign_spend'' then return coalesce(nullif(p_meta->>''label'', ''''), ''Campaign spending'');\n    when ''office_salary'' then return coalesce(nullif(p_meta->>''label'', ''''), ''Office salary'');\n    when ''garage'' then return');

-- admin Content editors
select pg_temp.bl_patch1('public.bl_admin_table_spec(text)', 'when ''offices'' then',
  E'    when ''business_types'' then',
  E'    when ''offices'' then ''{"pk":["id"],"insert":true,"order":"sort, id",\n      "cols":{"name":"text","kind":"text","title":"text","icon":"text","blurb":"text","elected":"bool","ward_scoped":"bool","salary_per_day":"money","fee":"money","min_charisma":"int","min_account_days":"num","cert_any":"arr","alt_job_level":"int","sort":"int","active":"bool"}}''\n    when ''gov_policies'' then ''{"pk":["id"],"insert":true,"order":"sort, id",\n      "cols":{"name":"text","icon":"text","blurb":"text","kind":"text","value":"num","modes":"arr","weekday":"int_null","sort":"int","active":"bool"}}''\n    when ''parties'' then ''{"pk":["id"],"insert":true,"order":"seeded desc, name",\n      "cols":{"name":"text","abbr":"text","color":"text","blurb":"text","active":"bool"}}''\n    when ''wards'' then ''{"pk":["id"],"insert":true,"order":"sort, id",\n      "cols":{"name":"text","districts":"arr","poll_unit":"text_null","sort":"int","active":"bool"}}''\n    when ''business_types'' then');

-- polling units are open only while voting is on (a place with an id pu_*), and say so when you try to travel there
select pg_temp.bl_patch1('public.bl_place_open(public.locations)', 'bl_pol_poll_open()',
  $m$  if p_loc.id is not null and not coalesce(p_loc.active, true) then return false; end if;$m$,
  $m$  if p_loc.id is not null and not coalesce(p_loc.active, true) then return false; end if;
  if p_loc.id is not null and left(p_loc.id, 3) = 'pu_' then return bl_pol_poll_open(); end if;$m$);
select pg_temp.bl_patch1('public.bl_travel_quote(public.profiles, text)', 'Polling units open on voting day only',
  $m$raise exception '% is closed right now. It opens at %.', dst.name, bl_hour_label(dst.open_hour)$m$,
  $m$raise exception '% is closed right now. %', dst.name, case when left(dst.id, 3) = 'pu_' then 'Polling units open on voting day only.' else 'It opens at ' || bl_hour_label(dst.open_hour) || '.' end$m$);
-- the Governor's travel policy
select pg_temp.bl_patch1('public.bl_travel_quote(public.profiles, text)', 'bl_pol_travel_cost(',
  $m$v_cost  := (ceil((bl_cfg('travel.' || v_key || '.base_cost') + bl_cfg('travel.' || v_key || '.per_km') * v_km) / 10.0) * 10)::bigint;$m$,
  $m$v_cost  := (ceil((bl_cfg('travel.' || v_key || '.base_cost') + bl_cfg('travel.' || v_key || '.per_km') * v_km) / 10.0) * 10)::bigint;
    v_cost  := bl_pol_travel_cost(v_cost, m);$m$);
-- Fitness XP policy
select pg_temp.bl_patch1('public.bl_skill_award(uuid, text, text)', 'bl_pol_skill_mult(',
  $m$round(r.base * v_mult * bl_skill_num('skills.xp_mult', 1))$m$,
  $m$round(r.base * v_mult * bl_skill_num('skills.xp_mult', 1) * bl_pol_skill_mult(r.skill_id))$m$);
-- slower hygiene decay policy
select pg_temp.bl_patch1('public.bl_decay_row(public.profiles, timestamptz)', 'bl_pol_hygiene_mult()',
  $m$r_hy  := bl_cfg('needs.hygiene_per_hour') * bl_trait_mult(v.traits, 'hygiene');$m$,
  $m$r_hy  := bl_cfg('needs.hygiene_per_hour') * bl_trait_mult(v.traits, 'hygiene') * bl_pol_hygiene_mult();$m$);
-- council levy policy (R10 business events)
select pg_temp.bl_patch1('public.bl_biz_settle(bigint, boolean)', 'bl_pol_levy_mult()',
  $m$v_pct := bl_biz_evn(t, 'levy', 'chance_pct', 'business.levy_pct', 8) * (1 - v_staffcut / 100.0);$m$,
  $m$v_pct := bl_biz_evn(t, 'levy', 'chance_pct', 'business.levy_pct', 8) * (1 - v_staffcut / 100.0) * bl_pol_levy_mult();$m$);

-- ---------------------------------------------------------------------------------------------
-- 11. Grants
-- ---------------------------------------------------------------------------------------------
-- every private helper (and the chat trigger): not callable by clients
do $$
declare r record;
begin
  for r in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.proname like 'bl\_pol\_%' loop
    execute format('revoke all on function %s from public, anon, authenticated', r.sig);
  end loop;
end $$;

do $$
declare f text;
begin
  foreach f in array array[
    'pol_status()', 'pol_candidates()', 'pol_ballot()', 'pol_results(int)', 'pol_party_create(text, text, text)', 'pol_declare(text, text, text, text)',
    'pol_set_promise(text)', 'pol_withdraw()', 'pol_rally()', 'pol_poster()', 'pol_back(bigint, text)', 'pol_unback(bigint, text)',
    'pol_report_vote_buying(bigint, text)', 'pol_vote(bigint)', 'pol_appoint(text, text)', 'pol_sack(text)', 'pol_announce(text)', 'pol_set_policy(text)',
    'pol_ward_notice(text)', 'pol_resign()',
    'admin_pol_overview()', 'admin_pol_start(numeric, numeric, numeric, numeric)', 'admin_pol_advance()', 'admin_pol_cancel(text)',
    'admin_pol_disqualify(bigint, text)', 'admin_pol_dismiss_reports(bigint)', 'admin_pol_remove_holder(bigint, text)', 'admin_pol_tallies(bigint)'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated, service_role', f);
  end loop;
end $$;

notify pgrst, 'reload schema';
