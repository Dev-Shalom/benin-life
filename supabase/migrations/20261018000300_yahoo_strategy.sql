-- R6 Yahoo strategy (docs/YAHOO.md "R6"). In-game satire: slang and abstract buttons only. Nothing here explains how any real
-- fraud works, who it targets or which platforms it uses; fraud stays the bad-guy life path with EFCC risk.
-- * Cash-out choices: the single cash out becomes three options. FULL (everything, the cash-out job's chance x
--   yahoo.cashout_full_caught_mult %), HALF (yahoo.cashout_half_pct % of the balance, chance x yahoo.cashout_half_caught_mult %)
--   and LAUNDER through a Mallam / bureau de change contact (a fee of yahoo.launder_fee_pct % of the amount, chance x
--   yahoo.launder_caught_mult %, a longer timer yahoo.launder_seconds). The Yahoo level cut still applies at the roll.
--   yahoo_cashout_quote() shows the amount, fee, chance and time before confirming; yahoo_cashout_start(mode) starts it
--   (it reuses yahoo_job_start for every check, then sets the run's mode, fee, chance and timer).
-- * Group missions: group_missions (admin table), yahoo_groups, yahoo_group_members. A host invites 1..max-1 online friends
--   (player_friendships). Every member needs a laptop and must be at HK Quarters (yahoo.group_locations) or at home on MiFi.
--   It runs when everybody answered or the invite timer ends (lazy, any status call moves it on). One roll for the crew: the
--   chance is the mission's, cut by the AVERAGE Yahoo level of the crew. Caught = every member gets the EFCC case (same
--   fair penalties as a solo bust: yahoo.confiscate_pct, yahoo.seize_laptop_pct). Paid = a pot (reward range, + yahoo.group_member_bonus_pct
--   per extra member) split evenly into each member's yahoo balance. Cooldown per player and mission. Invites alert the
--   friend (an event and a push in the friends category).
-- * HK Quarters: a new map place (scene cyber, Uselu / Ugbowo) with laptops, couches, a generator and a Wi-Fi router. It joins
--   yahoo.cafe_locations (a desk pass works there, like the Wi-Fi Joint) and yahoo.group_locations.
-- * "Elon format": a new yahoo_jobs row (abstract celebrity crypto giveaway format, flavour only), Yahoo level 4.
-- Idempotent and safe on a non-empty DB: seeds use "on conflict do nothing"; live functions are patched from
-- pg_get_functiondef with guarded replacements that raise when a marker is missing (create or replace keeps the grants).

-- ---------------------------------------------------------------------------------------------
-- 1. Settings (category yahoo)
-- ---------------------------------------------------------------------------------------------
insert into public.game_config (key, value, category, label, description, kind, min, max) values
('yahoo.cashout_full_caught_mult', '100', 'yahoo', 'Full cash out: chance x %',
 'R6: the EFCC chance of a FULL cash out (everything at once) as a percent of the cash-out job''s chance. 100 = the job''s own chance (the highest of the three options).', 'percent', 0, 1000),
('yahoo.cashout_half_pct', '50', 'yahoo', 'Half cash out: share of balance',
 'R6: a HALF cash out moves this percent of the yahoo balance.', 'percent', 1, 99),
('yahoo.cashout_half_caught_mult', '60', 'yahoo', 'Half cash out: chance x %',
 'R6: the EFCC chance of a HALF cash out as a percent of the cash-out job''s chance (lower than a full cash out).', 'percent', 0, 1000),
('yahoo.launder_fee_pct', '15', 'yahoo', 'Launder: fee %',
 'R6: the Mallam / bureau de change keeps this percent of the amount you launder (you get the rest as cash).', 'percent', 0, 90),
('yahoo.launder_caught_mult', '25', 'yahoo', 'Launder: chance x %',
 'R6: the EFCC chance of laundering as a percent of the cash-out job''s chance (much lower than a full cash out).', 'percent', 0, 1000),
('yahoo.launder_seconds', '90', 'yahoo', 'Launder: timer (seconds)',
 'R6: how long laundering takes (a flat time; laptop speed does not shorten it). Full and half use the cash-out job''s time.', 'number', 1, 3600),
('yahoo.cashout_floor_pct', '1', 'yahoo', 'Half / launder: lowest chance',
 'R6: half and launder chances never drop below this (or below the cash-out job''s own chance when that is lower).', 'percent', 0, 100),
('yahoo.launder_contact', '"Mallam Sule at the bureau de change"', 'yahoo', 'Launder: the contact''s name',
 'R6: the "Mallam" / bureau de change contact shown on the launder option (flavour text).', 'text', null, null),
('yahoo.group_enabled', 'true', 'yahoo', 'Group missions on',
 'R6: players can start Yahoo group missions with online friends. Off = group missions are refused (running ones still finish).', 'bool', null, null),
('yahoo.group_locations', '"hk_quarters"', 'yahoo', 'Group mission places',
 'R6: comma-separated location ids where a group mission member can stand (default HK Quarters). Home with an active MiFi always works.', 'text', null, null),
('yahoo.group_member_bonus_pct', '10', 'yahoo', 'Group pot: + % per extra member',
 'R6: the group pot grows by this percent for every member after the first (4 members and 10 = pot x 1.3). It is split evenly.', 'percent', 0, 500)
on conflict (key) do nothing;

-- the default cafe list gets HK Quarters (only while it is still the Y1 default: an admin edit stays)
update public.game_config set value = '"wifi_joint,hk_quarters"'::jsonb
 where key = 'yahoo.cafe_locations' and value = '"wifi_joint"'::jsonb;

-- ---------------------------------------------------------------------------------------------
-- 2. HK Quarters: the map place, zones, cards, mood lines (scene cyber: it keeps the Computers desks and the snack corner)
-- ---------------------------------------------------------------------------------------------
-- North-west of UBTH between Ugbowo and Uselu, 50+ units from every other pin (map_geo_test needs 34).
insert into public.locations (id, name, district, scene, blurb, risk, night_risk_mult, cctv, keke_ok, congestion, remote_km, x, y, actions, sort, open_hour, close_hour, active) values
('hk_quarters', 'HK Quarters', 'uselu', 'cyber',
 'Where the Uselu boys gather to work: fast Wi-Fi, a generator wey no dey rest, couches and laptops everywhere. Na the bad-guy life, so EFCC dey watch.',
 .30, 1.6, false, true, 1.0, 0, 395, 195, '{activities,shop}', 171, null, null, true)
on conflict (id) do nothing;

-- laptops, data and noodles are sold here too (the shared Computers desk zone has those cards)
update public.items set sold_at = array_append(sold_at, 'hk_quarters')
 where id in ('laptop', 'thinkpad_t480', 'elitebook_840', 'data_bundle', 'noodles_pack') and not ('hk_quarters' = any (sold_at));

insert into public.activities (id, name, scenes, home_only, cost, game_minutes, effects, night_only, sort, max_seconds, min_seconds, scale_by_need, needs_furniture, location_ids, risky, rush, icon)
values ('hk_chill', 'Chill on the couch with the boys', '{cyber}', false, 0, 30, '{"stress": -10, "fun": 8, "energy": 3}', false, 312, 12, 6, false, false, '{hk_quarters}', false, '{}', '🛋️'),
       ('hk_fuel', 'Chip in for generator fuel', '{cyber}', false, 2000, 10, '{"fun": 4, "stress": -3}', false, 313, 8, 4, false, false, '{hk_quarters}', false, '{}', '⛽')
on conflict (id) do nothing;

-- the interior is built from existing place parts: desks with laptops (the cyber scene's Computers zone + a second row),
-- couches, a generator and a Wi-Fi router. Positions keep clear of the scene zones (desks 1.5-6.5 x 1.5-4.5, snacks at 9.5, 6.5).
insert into public.place_zones (id, scene, location_id, zone_key, label, icon, prop, x, z, w, d, rot, note, sort, active) values
('hk_quarters.laptops', null, 'hk_quarters', 'laptops', 'Laptop row', '💻', 'desks', 4, 6.4, 5, 2.2, 0, 'Face caps, hot laptops and Wi-Fi. Make you sabi say EFCC dey watch', 5, true),
('hk_quarters.couches', null, 'hk_quarters', 'couches', 'Couches', '🛋️', 'couches', 10.6, 2.3, 3.2, 1.6, 0, 'The boys relax here between "work"', 6, true),
('hk_quarters.gen',     null, 'hk_quarters', 'gen',     'Generator', '⛽', 'generator', 13.1, 3.8, 1.4, 1.0, 0, 'NEPA took light. This one no dey rest', 7, true),
('hk_quarters.wifi',    null, 'hk_quarters', 'wifi',    'Wi-Fi router', '📶', 'router', 7.7, 1.6, 1.2, 0.8, 0, 'Fastest Wi-Fi for Uselu. Gist with the boys', 8, true)
on conflict (id) do nothing;

insert into public.zone_actions (id, zone_id, kind, ref, label, icon, sort) values
  ('hk_quarters.laptops.side_project',   'hk_quarters.laptops', 'activity', 'side_project',  null, null, 1),
  ('hk_quarters.laptops.thinkpad_t480',  'hk_quarters.laptops', 'shop',     'thinkpad_t480', null, null, 2),
  ('hk_quarters.couches.hk_chill',       'hk_quarters.couches', 'activity', 'hk_chill',      null, null, 1),
  ('hk_quarters.gen.hk_fuel',            'hk_quarters.gen',     'activity', 'hk_fuel',       null, null, 1),
  ('hk_quarters.wifi.chat',              'hk_quarters.wifi',    'panel',    'chat',          'Gist with the boys', '💬', 1),
  ('hk_quarters.wifi.data_bundle',       'hk_quarters.wifi',    'shop',     'data_bundle',   null, null, 2)
on conflict (id) do nothing;

insert into public.place_moods (id, scene, location_id, part, icon, line, sort) values
  ('hk_quarters.1', null, 'hk_quarters', 'any',     '🧢', 'Face caps everywhere. Somebody dey laugh for one corner', 1),
  ('hk_quarters.2', null, 'hk_quarters', 'night',   '⛽', 'The generator dey hum, laptops glowing, nobody sabi sleep', 2),
  ('hk_quarters.3', null, 'hk_quarters', 'morning', '📶', 'Wi-Fi light dey blink green. Boys dey drag the couch near the router', 3)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 3. The "Elon format" job: an abstract "celebrity crypto giveaway format" (flavour text only, no instructions)
-- ---------------------------------------------------------------------------------------------
-- room in the ordering: Chat, Romance, Elon, Big job, Cash out (first run only: the old sorts are still the Y1 ones)
update public.yahoo_jobs set sort = 5 where id = 'cash_out' and sort = 4 and not exists (select 1 from public.yahoo_jobs where id = 'elon_format');
update public.yahoo_jobs set sort = 4 where id = 'big_job' and sort = 3 and not exists (select 1 from public.yahoo_jobs where id = 'elon_format');
-- between Romance (50k-400k, 16 %) and Big job (500k-3M, 24 %); needs Yahoo level 4 (Content -> Yahoo jobs) and a ThinkPad or better
insert into public.yahoo_jobs (id, name, icon, blurb, kind, seconds, pay_min, pay_max, caught_pct, cooldown_seconds, min_tier, min_skill_level, sort, active) values
('elon_format', 'Elon format', '🚀', 'Pose as a billionaire for crypto lovers — the format wey everybody dey run.', 'job', 50, 200000, 1200000, 20, 180, 1, 4, 3, true)
on conflict (id) do nothing;
insert into public.skill_sources (id, kind, ref, skill_id, xp, note) values
('yahoo:elon_format:yahoo', 'yahoo', 'elon_format', 'yahoo', 22, 'Elon format')
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 4. Tables
-- ---------------------------------------------------------------------------------------------
-- cash-out runs remember the option and the fee
alter table public.yahoo_runs add column if not exists mode text check (mode in ('full', 'half', 'launder'));
alter table public.yahoo_runs add column if not exists fee bigint not null default 0 check (fee >= 0);

-- admin catalogue (Admin -> Content -> Group missions)
create table if not exists public.group_missions (
  id               text primary key,
  name             text not null,
  icon             text not null default '👥',
  blurb            text not null default '',
  min_members      int not null default 2 check (min_members between 2 and 8),
  max_members      int not null default 4 check (max_members between 2 and 8),
  duration_seconds int not null default 90 check (duration_seconds between 1 and 3600),
  reward_min       bigint not null default 0 check (reward_min >= 0),     -- the whole pot, before the member bonus; split evenly
  reward_max       bigint not null default 0 check (reward_max >= 0),
  caught_pct       numeric not null default 25 check (caught_pct between 0 and 100),
  min_yahoo_level  int not null default 1 check (min_yahoo_level between 1 and 50),
  invite_seconds   int not null default 120 check (invite_seconds between 5 and 3600),   -- the start timer
  cooldown_seconds int not null default 600 check (cooldown_seconds between 0 and 604800),
  sort             int not null default 0,
  active           boolean not null default true
);
insert into public.group_missions (id, name, icon, blurb, min_members, max_members, duration_seconds, reward_min, reward_max, caught_pct, min_yahoo_level, invite_seconds, cooldown_seconds, sort) values
('crew_hustle', 'Crew hustle', '👥', 'Two or three of una work one format together. Bigger pot, bigger risk.', 2, 4, 90, 400000, 1600000, 20, 2, 120, 600, 1),
('hk_big_table', 'HK big table', '🪑', 'The whole HK crew on one big table. Plenty money, plenty EFCC.', 3, 4, 150, 3000000, 12000000, 32, 4, 180, 1200, 2)
on conflict (id) do nothing;
insert into public.skill_sources (id, kind, ref, skill_id, xp, note) values
('yahoo:group_crew_hustle:yahoo', 'yahoo', 'group:crew_hustle', 'yahoo', 18, 'Crew hustle (group mission)'),
('yahoo:group_hk_big_table:yahoo', 'yahoo', 'group:hk_big_table', 'yahoo', 32, 'HK big table (group mission)')
on conflict (id) do nothing;

create table if not exists public.yahoo_groups (
  id           bigserial primary key,
  mission_id   text not null references public.group_missions(id) on update cascade,
  name         text,                                   -- the mission's name when it was made
  host_id      uuid not null references public.profiles(id) on delete cascade,
  status       text not null default 'inviting' check (status in ('inviting', 'running', 'paid', 'caught', 'cancelled')),
  location_id  text,
  created_at   timestamptz not null default now(),
  start_at     timestamptz not null,                   -- the start timer
  started_at   timestamptz,
  resolve_at   timestamptz,
  resolved_at  timestamptz,
  caught_pct   numeric,                                -- fixed when it starts (the crew's average Yahoo level already applied)
  member_count int not null default 0,
  pot          bigint not null default 0,
  per_member   bigint not null default 0
);
create index if not exists yahoo_groups_open_idx on public.yahoo_groups (status) where status in ('inviting', 'running');
create index if not exists yahoo_groups_host_idx on public.yahoo_groups (host_id, id desc);

create table if not exists public.yahoo_group_members (
  group_id      bigint not null references public.yahoo_groups(id) on delete cascade,
  user_id       uuid not null references public.profiles(id) on delete cascade,
  status        text not null default 'invited' check (status in ('invited', 'accepted', 'declined', 'dropped', 'expired')),
  laptop_item   text,
  invited_at    timestamptz not null default now(),
  responded_at  timestamptz,
  payout        bigint not null default 0,
  seized        bigint not null default 0,
  laptop_seized text,
  primary key (group_id, user_id)
);
create index if not exists yahoo_group_members_user_idx on public.yahoo_group_members (user_id, group_id desc);

alter table public.group_missions enable row level security;
alter table public.yahoo_groups enable row level security;
alter table public.yahoo_group_members enable row level security;
revoke all on table public.group_missions, public.yahoo_groups, public.yahoo_group_members from public, anon, authenticated;
revoke all on sequence public.yahoo_groups_id_seq from public, anon, authenticated;
-- the catalogue is read by signed-in players (admins write through admin_row_upsert); groups are server-only (the RPCs return them)
grant select on table public.group_missions to authenticated;
drop policy if exists group_missions_read on public.group_missions;
create policy group_missions_read on public.group_missions for select to authenticated using (true);

-- ---------------------------------------------------------------------------------------------
-- 5. Private helpers
-- ---------------------------------------------------------------------------------------------
-- Cash-out options. The chance: the cash-out job's chance (laptop points, blindfold, bad luck) x the option's multiplier.
-- Half and launder never drop under yahoo.cashout_floor_pct (or the job's own chance when lower). The Yahoo level cut is applied
-- at the roll (and shown as caught_pct); base_caught_pct is what the run stores.
create or replace function public.bl_yahoo_cash_quote(p_uid uuid, p_mode text) returns jsonb
language plpgsql stable set search_path = public as $$
declare
  y        yahoo_players;
  j        yahoo_jobs;
  v_lap    jsonb;
  v_base   numeric;
  v_mult   numeric;
  v_pct    numeric;
  v_amt    bigint;
  v_fee    bigint := 0;
  v_secs   int;
  v_min    bigint := greatest(0, bl_yahoo_num('yahoo.cashout_min', 1000))::bigint;
  v_floor  numeric := greatest(0, least(100, bl_yahoo_num('yahoo.cashout_floor_pct', 1)));
  v_ok     boolean := true;
  v_why    text;
begin
  if p_mode not in ('full', 'half', 'launder') then
    raise exception 'Choose how to cash out.' using errcode = 'P0001', hint = 'bad_mode';
  end if;
  select * into y from yahoo_players where user_id = p_uid;
  select * into j from yahoo_jobs where kind = 'cashout' and active order by sort, id limit 1;
  if not found then
    return jsonb_build_object('mode', p_mode, 'ok', false, 'why', 'Cash out is closed for now.', 'amount', 0, 'fee', 0, 'net', 0);
  end if;
  v_lap := bl_yahoo_laptop(p_uid);
  v_base := bl_yahoo_caught_pct(p_uid, j, v_lap);
  v_mult := greatest(0, case p_mode when 'half' then bl_yahoo_num('yahoo.cashout_half_caught_mult', 60)
                                    when 'launder' then bl_yahoo_num('yahoo.launder_caught_mult', 25)
                                    else bl_yahoo_num('yahoo.cashout_full_caught_mult', 100) end);
  v_pct := least(100, case when p_mode = 'full' then v_base * v_mult / 100.0
                           else greatest(least(v_base, v_floor), v_base * v_mult / 100.0) end);
  v_amt := case p_mode when 'half' then floor(coalesce(y.dirty, 0) * least(99, greatest(1, bl_yahoo_num('yahoo.cashout_half_pct', 50))) / 100.0)::bigint
                       else coalesce(y.dirty, 0) end;
  if p_mode = 'launder' then
    v_fee := round(v_amt * least(90, greatest(0, bl_yahoo_num('yahoo.launder_fee_pct', 15))) / 100.0)::bigint;
  end if;
  v_secs := case when p_mode = 'launder' then greatest(1, ceil(bl_yahoo_num('yahoo.launder_seconds', 90)))::int else bl_yahoo_seconds(j, v_lap) end;
  if coalesce(y.dirty, 0) <= 0 then
    v_ok := false; v_why := 'Your yahoo balance is empty. Nothing to cash out.';
  elsif v_amt < least(v_min, y.dirty) then
    v_ok := false; v_why := 'Too small for this option. Cash out at least ' || bl_naira(least(v_min, y.dirty)) || '.';
  end if;
  return jsonb_build_object(
    'mode', p_mode,
    'label', case p_mode when 'half' then 'Half cash out' when 'launder' then 'Launder' else 'Full cash out' end,
    'amount', v_amt, 'fee', v_fee, 'net', v_amt - v_fee,
    'base_caught_pct', round(v_pct, 2), 'caught_pct', round(bl_skill_caught_pct(p_uid, v_pct), 2),
    'seconds', v_secs, 'ok', v_ok, 'why', v_why);
end $$;

-- friends who are online right now (the same window the admin and the friends list use)
create or replace function public.bl_yahoo_online(p_last_seen timestamptz) returns boolean
language sql stable set search_path = public as $$
  select p_last_seen is not null
     and p_last_seen > bl_now() - make_interval(secs => (greatest(1, coalesce(bl_cfg('time.presence_real_minutes'), 3)) * 60)::double precision);
$$;

create or replace function public.bl_yahoo_is_friend(p_a uuid, p_b uuid) returns boolean
language sql stable set search_path = public as $$
  select exists (select 1 from player_friendships f
                  where f.user_a = least(p_a, p_b) and f.user_b = greatest(p_a, p_b) and f.status = 'accepted')
     and not bl_social_blocked(p_a, p_b);
$$;

-- the skill whose level cuts the EFCC chance (Settings -> skills.caught_skill, default yahoo)
create or replace function public.bl_yahoo_caught_skill() returns text
language sql stable set search_path = public as $$
  select coalesce(nullif((select value #>> '{}' from game_config where key = 'skills.caught_skill'), ''), 'yahoo');
$$;

-- A crew's chance: the mission's chance, cut by the AVERAGE Yahoo level of the crew with the skill's own cut per level and cap.
create or replace function public.bl_yahoo_group_pct(p_uids uuid[], p_base numeric) returns numeric
language plpgsql stable set search_path = public as $$
declare k skills; v_avg numeric; v_cut numeric;
begin
  if not bl_skill_on() or cardinality(coalesce(p_uids, '{}')) = 0 then return round(coalesce(p_base, 0), 2); end if;
  select * into k from skills where id = bl_yahoo_caught_skill();
  if not found then return round(coalesce(p_base, 0), 2); end if;
  select avg(bl_skill_level(u, k.id)) into v_avg from unnest(p_uids) u;
  v_cut := greatest(0, least(100, least(k.caught_cap_pct, greatest(0, coalesce(v_avg, 1) - 1) * k.caught_pct_per_level)));
  return round(greatest(0, least(100, coalesce(p_base, 0) * (1 - v_cut / 100.0))), 2);
end $$;

-- Where can I stand for a group mission? {ok, place ('hk' | 'home'), hint, message}
create or replace function public.bl_yahoo_group_spot(p_me public.profiles) returns jsonb
language plpgsql stable set search_path = public as $$
declare
  y yahoo_players;
  v_locs text[] := bl_yahoo_list('yahoo.group_locations', 'hk_quarters');
  v_names text;
begin
  select * into y from yahoo_players where user_id = p_me.id;
  select string_agg(name, ' or ' order by sort) into v_names from locations where id = any (v_locs) and coalesce(active, true);
  v_names := coalesce(v_names, 'HK Quarters');
  if p_me.travel_to is null and p_me.home_visit_host_id is null and p_me.location_id = any (v_locs) then
    return jsonb_build_object('ok', true, 'place', 'hk', 'message', 'At ' || v_names || '.');
  end if;
  if p_me.travel_to is null and p_me.home_visit_host_id is null and p_me.location_id = p_me.home_location_id then
    if y.mifi_until is not null and y.mifi_until > bl_now() then
      return jsonb_build_object('ok', true, 'place', 'home', 'message', 'Home, on MiFi.');
    end if;
    return jsonb_build_object('ok', false, 'place', 'home', 'hint', 'no_mifi',
      'message', 'No data for house. Buy a MiFi + data bundle, or go to ' || v_names || '.');
  end if;
  return jsonb_build_object('ok', false, 'place', null, 'hint', 'wrong_place',
    'message', 'Group missions run from ' || v_names || ' or from home with MiFi.');
end $$;

-- Can this player take part in this mission now? null = yes, else {hint, message}. 'join' = at create / accept, 'start' = the
-- recheck when the mission begins (no cooldown / one-group checks).
create or replace function public.bl_yahoo_group_gate(p_uid uuid, m public.group_missions, p_stage text) returns jsonb
language plpgsql stable set search_path = public as $$
declare
  p      profiles;
  v_h    text;
  v_spot jsonb;
  v_last timestamptz;
  v_lvl  int;
begin
  select * into p from profiles where id = p_uid;
  if not found then return jsonb_build_object('hint', 'no_profile', 'message', 'No Sim yet.'); end if;
  if exists (select 1 from yahoo_runs where user_id = p_uid and status = 'running') then
    return jsonb_build_object('hint', 'busy', 'message', 'Finish the Yahoo job you dey do first.');
  end if;
  begin
    perform bl_assert_free(p);
  exception when others then
    get stacked diagnostics v_h = pg_exception_hint;
    return jsonb_build_object('hint', coalesce(nullif(v_h, ''), 'busy'), 'message', sqlerrm);
  end;
  if bl_yahoo_laptop(p_uid) is null then
    return jsonb_build_object('hint', 'no_laptop', 'message', 'Everybody in the crew needs a laptop. Check Bronze Tech Hub or the Wi-Fi Joint.');
  end if;
  v_spot := bl_yahoo_group_spot(p);
  if not (v_spot->>'ok')::boolean then return v_spot; end if;
  if m.min_yahoo_level > 1 and bl_skill_on() then
    v_lvl := bl_skill_level(p_uid, 'yahoo');
    if v_lvl < m.min_yahoo_level then
      return jsonb_build_object('hint', 'skill_level',
        'message', m.name || ' needs Yahoo level ' || m.min_yahoo_level || ' (you are level ' || v_lvl || ').');
    end if;
  end if;
  if p_stage = 'join' then
    if exists (select 1 from yahoo_group_members x join yahoo_groups g on g.id = x.group_id
                where x.user_id = p_uid and x.status = 'accepted' and g.status in ('inviting', 'running')) then
      return jsonb_build_object('hint', 'in_group', 'message', 'You are already in a group mission. Finish or leave it first.');
    end if;
    select max(g.started_at) into v_last from yahoo_group_members x join yahoo_groups g on g.id = x.group_id
     where x.user_id = p_uid and x.status = 'accepted' and g.mission_id = m.id and g.started_at is not null;
    if v_last is not null and v_last + make_interval(secs => m.cooldown_seconds) > bl_now() then
      return jsonb_build_object('hint', 'cooldown',
        'message', 'Cool down small. ' || m.name || ' again in about '
                   || ceil(extract(epoch from v_last + make_interval(secs => m.cooldown_seconds) - bl_now()))::int || ' sec.');
    end if;
  end if;
  return null;
end $$;

-- Everything the app shows about one group for one viewer.
create or replace function public.bl_yahoo_group_json(p_group bigint, p_viewer uuid) returns jsonb
language plpgsql stable set search_path = public as $$
declare
  g       yahoo_groups;
  m       group_missions;
  v_acc   uuid[];
  v_n     int;
  v_en    int;
  v_bonus numeric := greatest(0, bl_yahoo_num('yahoo.group_member_bonus_pct', 10));
  v_skill text := bl_yahoo_caught_skill();
begin
  select * into g from yahoo_groups where id = p_group;
  if not found then return null; end if;
  select * into m from group_missions where id = g.mission_id;
  select coalesce(array_agg(user_id order by user_id), '{}') into v_acc from yahoo_group_members where group_id = g.id and status = 'accepted';
  v_n := cardinality(v_acc);
  v_en := greatest(v_n, m.min_members, 1);
  return jsonb_build_object(
    'id', g.id, 'mission_id', m.id, 'name', coalesce(g.name, m.name), 'icon', m.icon, 'blurb', m.blurb, 'status', g.status,
    'host_id', g.host_id, 'host', (select username from profiles where id = g.host_id), 'i_am_host', g.host_id = p_viewer,
    'my_status', (select status from yahoo_group_members where group_id = g.id and user_id = p_viewer),
    'min_members', m.min_members, 'max_members', m.max_members, 'duration_seconds', m.duration_seconds,
    'created_at', g.created_at, 'start_at', g.start_at, 'started_at', g.started_at, 'resolve_at', g.resolve_at, 'resolved_at', g.resolved_at,
    'base_caught_pct', m.caught_pct,
    'caught_pct', coalesce(g.caught_pct, bl_yahoo_group_pct(v_acc, m.caught_pct)),
    'ready', v_n,
    'per_min', floor(m.reward_min * (1 + v_bonus * (v_en - 1) / 100.0) / v_en / 100.0) * 100,
    'per_max', floor(greatest(m.reward_max, m.reward_min) * (1 + v_bonus * (v_en - 1) / 100.0) / v_en / 100.0) * 100,
    'pot', g.pot, 'per_member', g.per_member,
    'members', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', x.user_id, 'username', p.username, 'status', x.status, 'host', x.user_id = g.host_id, 'me', x.user_id = p_viewer,
               'level', case when bl_skill_on() then bl_skill_level(x.user_id, v_skill) end,
               'payout', x.payout, 'seized', x.seized,
               'laptop_seized', (select name from items where id = x.laptop_seized))
             order by (x.user_id = g.host_id) desc, lower(p.username))
        from yahoo_group_members x join profiles p on p.id = x.user_id where x.group_id = g.id), '[]'::jsonb));
end $$;

-- The EFCC bust for one member (the solo flow, shared with groups): confiscate yahoo.confiscate_pct of the yahoo balance,
-- maybe seize the laptop (yahoo.seize_laptop_pct), open the efcc jail case, jail and tell the player.
create or replace function public.bl_yahoo_bust(p_uid uuid, p_group_id bigint, p_job_name text, p_location text, p_laptop text) returns jsonb
language plpgsql set search_path = public as $$
declare
  y          yahoo_players;
  v_now      timestamptz := bl_now();
  v_seized   bigint := 0;
  v_lap_name text;
  v_had_lap  boolean := false;
  v_jail     int := greatest(1, ceil(bl_yahoo_num('yahoo.jail_seconds', 90)))::int;
  v_jail_loc text := bl_yahoo_text('crime.jail_location', 'police_hq');
  v_place    text;
  c          jail_cases;
begin
  y := bl_yahoo_row(p_uid, true);
  select name into v_place from locations where id = p_location;
  v_seized := floor(y.dirty * greatest(0, least(100, bl_yahoo_num('yahoo.confiscate_pct', 50))) / 100.0)::bigint;
  if v_seized > 0 then
    perform bl_yahoo_dirty(p_uid, -v_seized, 'seized', jsonb_build_object('group_id', p_group_id, 'job', p_job_name));
  end if;
  select name into v_lap_name from items where id = p_laptop;
  if p_laptop is not null and bl_crime_roll(bl_yahoo_num('yahoo.seize_laptop_pct', 35))
     and exists (select 1 from inventory where user_id = p_uid and item_id = p_laptop and qty > 0) then
    perform bl_give_item(p_uid, p_laptop, -1);
    v_had_lap := true;
  end if;
  update yahoo_players set busts = busts + 1, updated_at = v_now where user_id = p_uid;
  perform bl_crime_close_stale(p_uid);
  update jail_cases set status = 'released', closed_at = v_now where user_id = p_uid and status = 'open';
  insert into jail_cases (user_id, reason, location_id, bail_amount, jail_seconds, jail_until, created_at, kind, meta)
  values (p_uid, 'EFCC caught you doing Yahoo work' || coalesce(' at ' || v_place, ''), p_location,
          greatest(0, round(bl_yahoo_num('yahoo.bail_base', 50000000)))::bigint, v_jail,
          v_now + make_interval(secs => v_jail), v_now, 'efcc',
          jsonb_build_object('group_id', p_group_id, 'job_name', p_job_name, 'laptop', case when v_had_lap then p_laptop end,
                             'laptop_name', case when v_had_lap then v_lap_name end, 'seized', v_seized))
  returning * into c;
  update profiles set
    jailed_until = c.jail_until, jail_reason = c.reason, wanted = least(5, wanted + 1),
    location_id = coalesce((select id from locations where id = v_jail_loc), location_id),
    travel_to = null, travel_mode = null, travel_started_at = null, travel_arrives_at = null,
    busy_until = null, busy_label = null, busy_started_at = null, busy_needs_from = null
   where id = p_uid;
  perform bl_event(p_uid, 'efcc_caught', 'EFCC don catch you!',
    'EFCC caught you and the crew doing Yahoo work.' || case when v_had_lap then ' Your ' || v_lap_name || ' was seized.' else '' end
    || case when v_seized > 0 then ' ' || bl_naira(v_seized) || ' yahoo balance confiscated.' else '' end,
    jsonb_build_object('case_id', c.id, 'seized', v_seized, 'laptop', case when v_had_lap then p_laptop end, 'group_id', p_group_id));
  return jsonb_build_object('seized', v_seized, 'laptop_seized', case when v_had_lap then p_laptop end, 'case_id', c.id);
end $$;

-- A friend gets an alert and a push (friends category) when invited
create or replace function public.bl_yahoo_group_notify(p_to uuid, p_host profiles, m public.group_missions, p_group bigint) returns void
language plpgsql set search_path = public as $$
begin
  perform bl_event(p_to, 'yahoo_group_invite', '@' || p_host.username || ' invite you to a group mission 💻',
    m.name || '. Be at HK Quarters or home on MiFi with a laptop, then accept in the Yahoo app.',
    jsonb_build_object('group_id', p_group, 'mission', m.id, 'host', p_host.id));
  perform bl_push_enqueue(p_to, 'friends', 'yahoo_group_invite', '@' || p_host.username || ' wan run a group mission 💻',
    m.name || ' · tap to join the crew.', '/play?go=yahoo', p_host.id);
end $$;

-- Cancel an inviting group (everybody who answered is told)
create or replace function public.bl_yahoo_group_cancel(p_group bigint, p_reason text) returns void
language plpgsql set search_path = public as $$
declare g yahoo_groups; r record;
begin
  select * into g from yahoo_groups where id = p_group and status = 'inviting' for update;
  if not found then return; end if;
  update yahoo_groups set status = 'cancelled', resolved_at = bl_now() where id = g.id;
  update yahoo_group_members set status = 'expired', responded_at = coalesce(responded_at, bl_now()) where group_id = g.id and status = 'invited';
  for r in select user_id from yahoo_group_members where group_id = g.id and status = 'accepted' loop
    perform bl_event(r.user_id, 'yahoo_group_cancel', 'Group mission cancelled', coalesce(p_reason, 'The mission no happen.'),
      jsonb_build_object('group_id', g.id));
  end loop;
end $$;

-- Start an inviting group: drop members who no longer qualify, cancel when too few are left, else the clock runs.
create or replace function public.bl_yahoo_group_start(p_group bigint) returns void
language plpgsql set search_path = public as $$
declare
  g       yahoo_groups;
  m       group_missions;
  r       record;
  v_ok    uuid[] := '{}';
  v_gate  jsonb;
  v_now   timestamptz := bl_now();
  v_until timestamptz;
  u       uuid;
begin
  select * into g from yahoo_groups where id = p_group and status = 'inviting' for update;
  if not found then return; end if;
  select * into m from group_missions where id = g.mission_id;
  perform 1 from profiles where id in (select user_id from yahoo_group_members where group_id = g.id and status = 'accepted') order by id for update;
  for r in select user_id from yahoo_group_members where group_id = g.id and status = 'accepted' order by user_id loop
    v_gate := bl_yahoo_group_gate(r.user_id, m, 'start');
    if v_gate is null then
      v_ok := v_ok || r.user_id;
    else
      update yahoo_group_members set status = 'dropped', responded_at = v_now where group_id = g.id and user_id = r.user_id;
      perform bl_event(r.user_id, 'yahoo_group_drop', 'You miss the group mission', v_gate->>'message', jsonb_build_object('group_id', g.id));
    end if;
  end loop;
  update yahoo_group_members set status = 'expired', responded_at = v_now where group_id = g.id and status = 'invited';
  if cardinality(v_ok) < m.min_members then
    perform bl_yahoo_group_cancel(g.id, 'Not enough hands ready (' || cardinality(v_ok) || ' of ' || m.min_members || ' needed).');
    return;
  end if;
  v_until := v_now + make_interval(secs => m.duration_seconds);
  update yahoo_groups set status = 'running', started_at = v_now, resolve_at = v_until, member_count = cardinality(v_ok), name = m.name,
         caught_pct = bl_yahoo_group_pct(v_ok, m.caught_pct) where id = g.id;
  update yahoo_group_members x set laptop_item = bl_yahoo_laptop(x.user_id)->>'item_id' where x.group_id = g.id and x.user_id = any (v_ok);
  -- the crew is busy until the mission ends (it can't be stopped halfway, like a solo job)
  update profiles set busy_until = v_until, busy_started_at = v_now, busy_label = 'Yahoo: ' || m.name, busy_needs_from = null
   where id = any (v_ok);
  foreach u in array v_ok loop
    perform bl_event(u, 'yahoo_group_start', m.icon || ' ' || m.name || ' don start',
      cardinality(v_ok) || ' in the crew. Laptops open, nobody move.', jsonb_build_object('group_id', g.id));
  end loop;
end $$;

-- Resolve a running group once its time is up: ONE roll for the crew. Caught = every member gets the EFCC case.
-- Paid = the pot (reward range x member bonus) split evenly into each member's yahoo balance.
create or replace function public.bl_yahoo_group_resolve(p_group bigint) returns void
language plpgsql set search_path = public as $$
declare
  g       yahoo_groups;
  m       group_missions;
  v_ids   uuid[];
  r       record;
  v_now   timestamptz := bl_now();
  v_n     int;
  v_pot   bigint;
  v_per   bigint;
  v_rank0 text;
  v_rank1 yahoo_ranks;
  v_res   jsonb;
  v_bonus numeric := greatest(0, bl_yahoo_num('yahoo.group_member_bonus_pct', 10));
begin
  select * into g from yahoo_groups where id = p_group and status = 'running' for update;
  if not found or g.resolve_at > v_now then return; end if;
  select * into m from group_missions where id = g.mission_id;
  select coalesce(array_agg(user_id order by user_id), '{}') into v_ids from yahoo_group_members where group_id = g.id and status = 'accepted';
  v_n := cardinality(v_ids);
  if v_n = 0 then
    update yahoo_groups set status = 'cancelled', resolved_at = v_now where id = g.id;
    return;
  end if;
  perform 1 from profiles where id = any (v_ids) order by id for update;

  if bl_crime_roll(coalesce(g.caught_pct, m.caught_pct)) then
    for r in select user_id, laptop_item from yahoo_group_members where group_id = g.id and status = 'accepted' order by user_id loop
      v_res := bl_yahoo_bust(r.user_id, g.id, 'Group: ' || coalesce(g.name, m.name),
                             (select location_id from profiles where id = r.user_id), r.laptop_item);
      update yahoo_group_members set seized = (v_res->>'seized')::bigint, laptop_seized = v_res->>'laptop_seized'
       where group_id = g.id and user_id = r.user_id;
    end loop;
    update yahoo_groups set status = 'caught', resolved_at = v_now where id = g.id;
  else
    v_pot := m.reward_min + floor(bl_rand() * (greatest(m.reward_max, m.reward_min) - m.reward_min + 1))::bigint;
    v_pot := round(v_pot * (1 + v_bonus * (v_n - 1) / 100.0))::bigint;
    v_per := greatest(0, floor(v_pot::numeric / v_n / 100) * 100)::bigint;
    for r in select user_id from yahoo_group_members where group_id = g.id and status = 'accepted' order by user_id loop
      v_rank0 := bl_yahoo_rank(r.user_id);
      perform bl_yahoo_row(r.user_id, true);
      if v_per > 0 then
        perform bl_yahoo_dirty(r.user_id, v_per, 'job',
          jsonb_build_object('group_id', g.id, 'job_name', 'Group: ' || coalesce(g.name, m.name)));
      end if;
      update yahoo_players set total_earned = total_earned + v_per, jobs_done = jobs_done + 1, updated_at = v_now where user_id = r.user_id;
      update yahoo_group_members set payout = v_per where group_id = g.id and user_id = r.user_id;
      update profiles set busy_until = null, busy_label = null, busy_started_at = null, busy_needs_from = null
       where id = r.user_id and busy_label like 'Yahoo:%';
      perform bl_skill_award(r.user_id, 'yahoo', 'group:' || m.id);
      perform bl_event(r.user_id, 'yahoo_group_paid', m.icon || ' ' || coalesce(g.name, m.name) || ' paid: +' || bl_naira(v_per),
        'Your share of the ' || bl_naira(v_per * v_n) || ' pot is in your yahoo balance. Cash out before you spend am.',
        jsonb_build_object('group_id', g.id, 'amount', v_per));
      v_rank1 := bl_yahoo_rank_row(r.user_id);
      if v_rank1.id is distinct from v_rank0 then
        perform bl_event(r.user_id, 'yahoo_rank_up', 'You don rise: ' || v_rank1.name || ' ' || v_rank1.icon,
                         coalesce(nullif(v_rank1.perks, ''), 'New Yahoo rank.'), jsonb_build_object('rank', v_rank1.id));
      end if;
      begin
        perform bl_challenge_bump(r.user_id, 'yahoo_clean', 1, 'group:' || m.id);
      exception when others then
        raise warning 'group challenge bump: %', sqlerrm;
      end;
    end loop;
    update yahoo_groups set status = 'paid', resolved_at = v_now, pot = v_per * v_n, per_member = v_per where id = g.id;
  end if;
end $$;

-- Move one group on: start it when everybody answered or the timer ended, resolve it when its time is up.
create or replace function public.bl_yahoo_group_tick(p_group bigint) returns void
language plpgsql set search_path = public as $$
declare g yahoo_groups;
begin
  select * into g from yahoo_groups where id = p_group for update;
  if not found then return; end if;
  if g.status = 'inviting' then
    if g.start_at <= bl_now() or not exists (select 1 from yahoo_group_members where group_id = g.id and status = 'invited') then
      perform bl_yahoo_group_start(g.id);
    end if;
  elsif g.status = 'running' and g.resolve_at <= bl_now() then
    perform bl_yahoo_group_resolve(g.id);
  end if;
end $$;

-- Tick every open group I am part of (called by the player RPCs)
create or replace function public.bl_yahoo_group_tick_user(p_uid uuid) returns void
language plpgsql set search_path = public as $$
declare r record;
begin
  for r in select g.id from yahoo_groups g join yahoo_group_members x on x.group_id = g.id
            where x.user_id = p_uid and x.status in ('invited', 'accepted') and g.status in ('inviting', 'running') order by g.id loop
    perform bl_yahoo_group_tick(r.id);
  end loop;
end $$;

revoke all on function public.bl_yahoo_cash_quote(uuid, text) from public, anon, authenticated;
revoke all on function public.bl_yahoo_online(timestamptz) from public, anon, authenticated;
revoke all on function public.bl_yahoo_is_friend(uuid, uuid) from public, anon, authenticated;
revoke all on function public.bl_yahoo_caught_skill() from public, anon, authenticated;
revoke all on function public.bl_yahoo_group_pct(uuid[], numeric) from public, anon, authenticated;
revoke all on function public.bl_yahoo_group_spot(public.profiles) from public, anon, authenticated;
revoke all on function public.bl_yahoo_group_gate(uuid, public.group_missions, text) from public, anon, authenticated;
revoke all on function public.bl_yahoo_group_json(bigint, uuid) from public, anon, authenticated;
revoke all on function public.bl_yahoo_bust(uuid, bigint, text, text, text) from public, anon, authenticated;
revoke all on function public.bl_yahoo_group_notify(uuid, public.profiles, public.group_missions, bigint) from public, anon, authenticated;
revoke all on function public.bl_yahoo_group_cancel(bigint, text) from public, anon, authenticated;
revoke all on function public.bl_yahoo_group_start(bigint) from public, anon, authenticated;
revoke all on function public.bl_yahoo_group_resolve(bigint) from public, anon, authenticated;
revoke all on function public.bl_yahoo_group_tick(bigint) from public, anon, authenticated;
revoke all on function public.bl_yahoo_group_tick_user(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- 6. Player RPCs
-- ---------------------------------------------------------------------------------------------
-- The three cash-out options with their real numbers (shown before confirming).
create or replace function public.yahoo_cashout_quote() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid   uuid := bl_require_uid();
  v_me    profiles;
  y       yahoo_players;
  j       yahoo_jobs;
  v_lap   jsonb;
  v_where jsonb;
  v_cd    timestamptz;
  v_block text;
begin
  select * into v_me from profiles where id = v_uid;
  if not found then return jsonb_build_object('enabled', false); end if;
  y := bl_yahoo_row(v_uid);
  select * into j from yahoo_jobs where kind = 'cashout' and active order by sort, id limit 1;
  v_lap := bl_yahoo_laptop(v_uid);
  v_where := bl_yahoo_where(v_me);
  if j.id is not null then
    select max(x.started_at) + make_interval(secs => j.cooldown_seconds) into v_cd from yahoo_runs x
     where x.user_id = v_uid and x.job_id = j.id and x.status <> 'cancelled';
    if v_cd is not null and v_cd <= bl_now() then v_cd := null; end if;
  end if;
  v_block := case when not coalesce(bl_cfg_bool('yahoo.enabled'), true) then 'Switched off'
                  when j.id is null then 'Cash out is closed for now'
                  when v_lap is null then 'Need a laptop'
                  when not (v_where->>'ok')::boolean then v_where->>'message'
                  when exists (select 1 from yahoo_runs where user_id = v_uid and status = 'running') then 'Finish your running job first'
                  when v_cd is not null then 'Cool down small'
                  else null end;
  return jsonb_build_object(
    'enabled', coalesce(bl_cfg_bool('yahoo.enabled'), true),
    'dirty', y.dirty, 'job_id', j.id, 'min', greatest(0, bl_yahoo_num('yahoo.cashout_min', 1000)),
    'contact', bl_yahoo_text('yahoo.launder_contact', 'Mallam Sule at the bureau de change'),
    'fee_pct', bl_yahoo_num('yahoo.launder_fee_pct', 15),
    'blocked', v_block, 'cooldown_until', v_cd,
    'options', jsonb_build_array(bl_yahoo_cash_quote(v_uid, 'full'), bl_yahoo_cash_quote(v_uid, 'half'), bl_yahoo_cash_quote(v_uid, 'launder')));
end $$;
revoke all on function public.yahoo_cashout_quote() from public, anon;
grant execute on function public.yahoo_cashout_quote() to authenticated, service_role;

-- Start a cash out in one of the three modes. yahoo_job_start does every check (laptop, place, gates, cooldown, minimum);
-- then the run takes the option's chance, fee and timer.
create or replace function public.yahoo_cashout_start(p_mode text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me    profiles := bl_me();
  j       yahoo_jobs;
  q       jsonb;
  v       jsonb;
  v_until timestamptz;
  v_secs  int;
  v_fee   bigint;
  v_amt   bigint;
  v_msg   text;
begin
  if p_mode not in ('full', 'half', 'launder') then
    raise exception 'Choose how to cash out.' using errcode = 'P0001', hint = 'bad_mode';
  end if;
  select * into j from yahoo_jobs where kind = 'cashout' and active order by sort, id limit 1;
  if not found then
    raise exception 'Cash out is closed for now.' using errcode = 'P0001', hint = 'bad_job';
  end if;
  perform 1 from profiles where id = v_me.id for update;
  q := bl_yahoo_cash_quote(v_me.id, p_mode);
  v_amt := (q->>'amount')::bigint;
  v := yahoo_job_start(j.id, case when v_amt > 0 then v_amt else null end);
  v_secs := (q->>'seconds')::int;
  v_fee := (q->>'fee')::bigint;
  v_until := bl_now() + make_interval(secs => v_secs);
  update yahoo_runs set mode = p_mode, fee = v_fee, caught_pct = (q->>'base_caught_pct')::numeric, resolve_at = v_until
   where id = (v->>'run_id')::bigint;
  update profiles set busy_until = v_until where id = v_me.id;
  v_msg := case p_mode
    when 'launder' then 'You reach ' || bl_yahoo_text('yahoo.launder_contact', 'the Mallam') || '… ' || bl_naira(v_amt - v_fee) || ' coming after the ' || bl_naira(v_fee) || ' fee.'
    when 'half' then 'Half go first… ' || bl_naira(v_amt) || ' on the way.'
    else 'You call the "Western Union guy"… ' || bl_naira(v_amt) || ' on the way.' end;
  return v || jsonb_build_object('mode', p_mode, 'fee', v_fee, 'net', v_amt - v_fee, 'amount', v_amt, 'seconds', v_secs,
    'caught_pct', (q->>'base_caught_pct')::numeric, 'skill_caught_pct', (q->>'caught_pct')::numeric,
    'resolve_at', v_until, 'busy_until', v_until, 'message', v_msg);
end $$;
revoke all on function public.yahoo_cashout_start(text) from public, anon;
grant execute on function public.yahoo_cashout_start(text) to authenticated, service_role;

-- Group missions: what the app shows (missions, my place, friends, my open group, invites, my last result).
create or replace function public.yahoo_group_status() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid   uuid := bl_require_uid();
  v_me    profiles;
  v_spot  jsonb;
  v_lap   jsonb;
  v_my    bigint;
  v_last  bigint;
  v_lvl   int;
  v_locs  text[] := bl_yahoo_list('yahoo.group_locations', 'hk_quarters');
begin
  select * into v_me from profiles where id = v_uid;
  if not found then return jsonb_build_object('enabled', false); end if;
  perform bl_yahoo_group_tick_user(v_uid);
  select * into v_me from profiles where id = v_uid;
  v_spot := bl_yahoo_group_spot(v_me);
  v_lap := bl_yahoo_laptop(v_uid);
  v_lvl := case when bl_skill_on() then bl_skill_level(v_uid, 'yahoo') else 1 end;
  select g.id into v_my from yahoo_groups g join yahoo_group_members x on x.group_id = g.id
   where x.user_id = v_uid and x.status = 'accepted' and g.status in ('inviting', 'running') order by g.id desc limit 1;
  select g.id into v_last from yahoo_groups g join yahoo_group_members x on x.group_id = g.id
   where x.user_id = v_uid and x.status = 'accepted' and g.status in ('paid', 'caught') order by g.resolved_at desc, g.id desc limit 1;
  return jsonb_build_object(
    'enabled', coalesce(bl_cfg_bool('yahoo.enabled'), true) and coalesce(bl_cfg_bool('yahoo.group_enabled'), true),
    'spot', v_spot, 'has_laptop', v_lap is not null, 'level', v_lvl,
    'bonus_pct', greatest(0, bl_yahoo_num('yahoo.group_member_bonus_pct', 10)),
    'places', coalesce((select jsonb_agg(jsonb_build_object('id', l.id, 'name', l.name) order by l.sort)
                          from locations l where l.id = any (v_locs) and coalesce(l.active, true)), '[]'::jsonb),
    'missions', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', m.id, 'name', m.name, 'icon', m.icon, 'blurb', m.blurb, 'min_members', m.min_members, 'max_members', m.max_members,
               'duration_seconds', m.duration_seconds, 'reward_min', m.reward_min, 'reward_max', m.reward_max, 'caught_pct', m.caught_pct,
               'min_yahoo_level', m.min_yahoo_level, 'invite_seconds', m.invite_seconds, 'cooldown_seconds', m.cooldown_seconds,
               'level_ok', m.min_yahoo_level <= 1 or not bl_skill_on() or v_lvl >= m.min_yahoo_level,
               'cooldown_until', (select max(g.started_at) + make_interval(secs => m.cooldown_seconds)
                                    from yahoo_group_members x join yahoo_groups g on g.id = x.group_id
                                   where x.user_id = v_uid and x.status = 'accepted' and g.mission_id = m.id and g.started_at is not null
                                  having max(g.started_at) + make_interval(secs => m.cooldown_seconds) > bl_now()))
             order by m.sort, m.id)
        from group_missions m where m.active), '[]'::jsonb),
    'friends', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', o.id, 'username', o.username, 'avatar', o.avatar, 'online', bl_yahoo_online(o.last_seen),
               'ready', bl_yahoo_online(o.last_seen) and bl_yahoo_laptop(o.id) is not null and (bl_yahoo_group_spot(o)->>'ok')::boolean
                        and not exists (select 1 from yahoo_group_members x join yahoo_groups g on g.id = x.group_id
                                         where x.user_id = o.id and x.status = 'accepted' and g.status in ('inviting', 'running')))
             order by bl_yahoo_online(o.last_seen) desc, lower(o.username))
        from player_friendships f
        join profiles o on o.id = case when f.user_a = v_uid then f.user_b else f.user_a end
       where f.status = 'accepted' and v_uid in (f.user_a, f.user_b) and not o.banned and not bl_social_blocked(v_uid, o.id)), '[]'::jsonb),
    'group', case when v_my is not null then bl_yahoo_group_json(v_my, v_uid) end,
    'invites', coalesce((
      select jsonb_agg(bl_yahoo_group_json(g.id, v_uid) order by g.id desc)
        from yahoo_groups g join yahoo_group_members x on x.group_id = g.id
       where x.user_id = v_uid and x.status = 'invited' and g.status = 'inviting'), '[]'::jsonb),
    'last', case when v_last is not null then bl_yahoo_group_json(v_last, v_uid) end);
end $$;
revoke all on function public.yahoo_group_status() from public, anon;
grant execute on function public.yahoo_group_status() to authenticated, service_role;

-- Start a group mission and invite 1..max-1 online friends.
create or replace function public.yahoo_group_create(p_mission text, p_friends uuid[]) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me   profiles := bl_me();
  m      group_missions;
  v_ids  uuid[];
  v_gate jsonb;
  f      uuid;
  fp     profiles;
  g      yahoo_groups;
begin
  if not coalesce(bl_cfg_bool('yahoo.enabled'), true) or not coalesce(bl_cfg_bool('yahoo.group_enabled'), true) then
    raise exception 'Group missions are switched off for now.' using errcode = 'P0001', hint = 'disabled';
  end if;
  select * into m from group_missions where id = p_mission and active;
  if not found then
    raise exception 'No such group mission.' using errcode = 'P0001', hint = 'bad_mission';
  end if;
  v_ids := coalesce(array(select distinct x from unnest(coalesce(p_friends, '{}')) x where x is not null and x <> v_me.id), '{}');
  if cardinality(v_ids) < 1 then
    raise exception 'Invite at least one friend.' using errcode = 'P0001', hint = 'no_friends';
  end if;
  if cardinality(v_ids) > m.max_members - 1 then
    raise exception '% takes at most % people, so invite up to % friends.', m.name, m.max_members, m.max_members - 1
      using errcode = 'P0001', hint = 'too_many';
  end if;
  perform 1 from profiles where id = v_me.id for update;
  v_me := bl_me();
  perform bl_yahoo_group_tick_user(v_me.id);
  v_gate := bl_yahoo_group_gate(v_me.id, m, 'join');
  if v_gate is not null then
    raise exception '%', v_gate->>'message' using errcode = 'P0001', hint = v_gate->>'hint';
  end if;
  foreach f in array v_ids loop
    select * into fp from profiles where id = f and not banned;
    if not found or not bl_yahoo_is_friend(v_me.id, f) then
      raise exception 'You fit only invite your friends.' using errcode = 'P0001', hint = 'not_friend';
    end if;
    if not bl_yahoo_online(fp.last_seen) then
      raise exception '@% is not online right now.', fp.username using errcode = 'P0001', hint = 'friend_offline';
    end if;
  end loop;
  insert into yahoo_groups (mission_id, name, host_id, location_id, start_at)
  values (m.id, m.name, v_me.id, v_me.location_id, bl_now() + make_interval(secs => m.invite_seconds))
  returning * into g;
  insert into yahoo_group_members (group_id, user_id, status, laptop_item, responded_at)
  values (g.id, v_me.id, 'accepted', bl_yahoo_laptop(v_me.id)->>'item_id', bl_now());
  foreach f in array v_ids loop
    insert into yahoo_group_members (group_id, user_id) values (g.id, f);
    perform bl_yahoo_group_notify(f, v_me, m, g.id);
  end loop;
  return jsonb_build_object('group', bl_yahoo_group_json(g.id, v_me.id), 'message', 'Group mission open. Waiting for the crew…');
end $$;
revoke all on function public.yahoo_group_create(text, uuid[]) from public, anon;
grant execute on function public.yahoo_group_create(text, uuid[]) to authenticated, service_role;

-- Accept or decline an invite (or leave while it is still inviting).
create or replace function public.yahoo_group_respond(p_group bigint, p_accept boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid  uuid := bl_require_uid();
  v_me   profiles;
  g      yahoo_groups;
  m      group_missions;
  mem    yahoo_group_members;
  v_gate jsonb;
  v_name text;
begin
  perform bl_yahoo_group_tick(p_group);
  select * into g from yahoo_groups where id = p_group for update;
  if not found then
    raise exception 'That mission no dey again.' using errcode = 'P0001', hint = 'no_group';
  end if;
  select * into mem from yahoo_group_members where group_id = g.id and user_id = v_uid for update;
  if not found then
    raise exception 'You no dey that crew.' using errcode = 'P0001', hint = 'not_invited';
  end if;
  if g.status <> 'inviting' then
    raise exception 'That mission don close.' using errcode = 'P0001', hint = 'closed';
  end if;
  select * into m from group_missions where id = g.mission_id;
  select username into v_name from profiles where id = v_uid;
  if p_accept then
    if mem.status <> 'accepted' then
      perform 1 from profiles where id = v_uid for update;
      v_me := bl_me();
      v_gate := bl_yahoo_group_gate(v_uid, m, 'join');
      if v_gate is not null then
        raise exception '%', v_gate->>'message' using errcode = 'P0001', hint = v_gate->>'hint';
      end if;
      update yahoo_group_members set status = 'accepted', laptop_item = bl_yahoo_laptop(v_uid)->>'item_id', responded_at = bl_now()
       where group_id = g.id and user_id = v_uid;
      perform bl_event(g.host_id, 'yahoo_group_reply', '@' || v_name || ' join your mission',
        m.name || ': ' || (select count(*) from yahoo_group_members where group_id = g.id and status = 'accepted') || ' ready.',
        jsonb_build_object('group_id', g.id));
    end if;
  else
    if g.host_id = v_uid then
      raise exception 'You na the host. Cancel the mission instead.' using errcode = 'P0001', hint = 'host';
    end if;
    update yahoo_group_members set status = 'declined', responded_at = bl_now() where group_id = g.id and user_id = v_uid;
    perform bl_event(g.host_id, 'yahoo_group_reply', '@' || v_name || ' no dey follow', m.name || ': they pass.', jsonb_build_object('group_id', g.id));
  end if;
  perform bl_yahoo_group_tick(g.id);
  return jsonb_build_object('group', bl_yahoo_group_json(g.id, v_uid),
    'message', case when p_accept then 'You don join the crew.' else 'You pass this one.' end);
end $$;
revoke all on function public.yahoo_group_respond(bigint, boolean) from public, anon;
grant execute on function public.yahoo_group_respond(bigint, boolean) to authenticated, service_role;

-- Host: start now with whoever already accepted.
create or replace function public.yahoo_group_start(p_group bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid();
  g     yahoo_groups;
  m     group_missions;
  v_n   int;
begin
  perform bl_yahoo_group_tick(p_group);
  select * into g from yahoo_groups where id = p_group for update;
  if not found or g.host_id <> v_uid then
    raise exception 'Only the host fit start the mission.' using errcode = 'P0001', hint = 'not_host';
  end if;
  if g.status <> 'inviting' then
    raise exception 'That mission don close.' using errcode = 'P0001', hint = 'closed';
  end if;
  select * into m from group_missions where id = g.mission_id;
  select count(*) into v_n from yahoo_group_members where group_id = g.id and status = 'accepted';
  if v_n < m.min_members then
    raise exception 'You need at least % in the crew to start (% ready).', m.min_members, v_n using errcode = 'P0001', hint = 'not_enough';
  end if;
  perform bl_yahoo_group_start(g.id);
  return jsonb_build_object('group', bl_yahoo_group_json(g.id, v_uid), 'message', 'Mission on. Laptops open.');
end $$;
revoke all on function public.yahoo_group_start(bigint) from public, anon;
grant execute on function public.yahoo_group_start(bigint) to authenticated, service_role;

-- Host: cancel while still inviting.
create or replace function public.yahoo_group_cancel(p_group bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid();
  g     yahoo_groups;
begin
  perform bl_yahoo_group_tick(p_group);
  select * into g from yahoo_groups where id = p_group for update;
  if not found or g.host_id <> v_uid then
    raise exception 'Only the host fit cancel the mission.' using errcode = 'P0001', hint = 'not_host';
  end if;
  if g.status <> 'inviting' then
    raise exception 'That mission don close.' using errcode = 'P0001', hint = 'closed';
  end if;
  perform bl_yahoo_group_cancel(g.id, 'The host cancelled the mission.');
  return jsonb_build_object('group', bl_yahoo_group_json(g.id, v_uid), 'message', 'Mission cancelled.');
end $$;
revoke all on function public.yahoo_group_cancel(bigint) from public, anon;
grant execute on function public.yahoo_group_cancel(bigint) to authenticated, service_role;

-- Roll my running group mission once its timer is over (any member's call settles it for everyone).
create or replace function public.yahoo_group_finish() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid();
  g     yahoo_groups;
  mem   yahoo_group_members;
  c     jail_cases;
begin
  perform bl_me_any();
  select g2.* into g from yahoo_groups g2 join yahoo_group_members x on x.group_id = g2.id
   where x.user_id = v_uid and x.status = 'accepted' and g2.status = 'running' order by g2.id desc limit 1;
  if not found then
    raise exception 'You are not in a running group mission.' using errcode = 'P0001', hint = 'no_group';
  end if;
  if g.resolve_at > bl_now() then
    raise exception 'Hold on, about % sec more.', ceil(extract(epoch from g.resolve_at - bl_now()))::int using errcode = 'P0001', hint = 'not_yet';
  end if;
  perform bl_yahoo_group_resolve(g.id);
  select * into g from yahoo_groups where id = g.id;
  select * into mem from yahoo_group_members where group_id = g.id and user_id = v_uid;
  if g.status = 'caught' then
    select * into c from jail_cases where user_id = v_uid and status = 'open' order by id desc limit 1;
  end if;
  return jsonb_build_object('status', g.status, 'group', bl_yahoo_group_json(g.id, v_uid), 'amount', coalesce(mem.payout, 0),
    'seized', coalesce(mem.seized, 0), 'laptop_seized', (select name from items where id = mem.laptop_seized),
    'case', case when c.id is not null then bl_crime_case_json(c) end);
end $$;
revoke all on function public.yahoo_group_finish() from public, anon;
grant execute on function public.yahoo_group_finish() to authenticated, service_role;

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

-- A finished cash out pays the net (amount minus the launder fee) in cash; the yahoo balance loses the whole amount.
select pg_temp.bl_patch('public.bl_yahoo_resolve(bigint)', $j$[
 {"done": "'mode', r.mode, 'fee', least(v_amt, coalesce(r.fee, 0)))",
  "marker": "perform bl_yahoo_dirty(r.user_id, -v_amt, 'cashout', jsonb_build_object('run_id', r.id));",
  "new": "perform bl_yahoo_dirty(r.user_id, -v_amt, 'cashout', jsonb_build_object('run_id', r.id, 'mode', r.mode, 'fee', least(v_amt, coalesce(r.fee, 0))));"},
 {"done": "v_amt - least(v_amt, coalesce(r.fee, 0)), 'yahoo_cashout'",
  "marker": "perform bl_add_money(r.user_id, 'cash', v_amt, 'yahoo_cashout', jsonb_build_object('run_id', r.id));",
  "new": "if v_amt - least(v_amt, coalesce(r.fee, 0)) > 0 then\n        perform bl_add_money(r.user_id, 'cash', v_amt - least(v_amt, coalesce(r.fee, 0)), 'yahoo_cashout', jsonb_build_object('run_id', r.id, 'mode', r.mode, 'fee', least(v_amt, coalesce(r.fee, 0))));\n      end if;"},
 {"done": "fee to the Mallam",
  "marker": "'Cash out don land: +' || bl_naira(v_amt) || ' cash.'",
  "new": "'Cash out don land: +' || bl_naira(v_amt - least(v_amt, coalesce(r.fee, 0))) || ' cash.' || case when coalesce(r.fee, 0) > 0 then ' (' || bl_naira(least(v_amt, r.fee)) || ' fee to the Mallam.)' else '' end"},
 {"done": "'fee', case when v_status = 'cashed'",
  "marker": "'amount', v_amt, 'seized', v_seized,",
  "new": "'amount', v_amt, 'fee', case when v_status = 'cashed' then least(v_amt, coalesce(r.fee, 0)) else 0 end, 'mode', r.mode, 'seized', v_seized,"}
]$j$::jsonb);

select pg_temp.bl_patch('public.bl_yahoo_run_json(public.yahoo_runs)', $j$[
 {"done": "'mode', r.mode",
  "marker": "'status', r.status,",
  "new": "'status', r.status, 'mode', r.mode, 'fee', r.fee,"}
]$j$::jsonb);

-- Admin -> Content -> Group missions
select pg_temp.bl_patch('public.bl_admin_table_spec(text)', jsonb_build_array(jsonb_build_object(
  'done', 'group_missions',
  'marker', 'when ''yahoo_ranks'' then',
  'new', $q$when 'group_missions' then '{"pk":["id"],"insert":true,"order":"sort, id",
      "cols":{"name":"text","icon":"text","blurb":"text","min_members":"int","max_members":"int","duration_seconds":"int",
              "reward_min":"money","reward_max":"money","caught_pct":"num","min_yahoo_level":"int","invite_seconds":"int",
              "cooldown_seconds":"int","sort":"int","active":"bool"}}'
    when 'yahoo_ranks' then$q$)));

notify pgrst, 'reload schema';
