-- D1: Daily reward (7-day ladder) + daily gem hunt. docs/DAILY.md
-- Idempotent: tables `if not exists`, seeds `on conflict do nothing`, functions `create or replace`.
-- Everything is server-authoritative and keyed to the WAT calendar day (bl_clock_tz(), bl_now()).
-- Money moves only through bl_add_money (ledger).

-- ---------------------------------------------------------------------
-- 1. Config
-- ---------------------------------------------------------------------
insert into public.game_config (key, value, category, label, description, kind, min, max) values
('daily.reward_enabled', 'true', 'daily', 'Daily reward on',
 'The 7-day daily reward ladder (claim once per Benin calendar day; a missed day starts again at day 1). Amounts: Content → Daily reward. Off = the HUD chip is hidden and claims are refused.', 'bool', null, null),
('daily.gems_enabled', 'true', 'daily', 'Daily gem hunt on',
 'Gems hidden at real public places each Benin day, the same for every player. Off = the HUD chip and the gems are hidden and finds are refused.', 'bool', null, null),
('daily.gems_per_day', '3', 'daily', 'Gems per day',
 'How many places get a gem each Benin day (always-open, active, public places only; never homes, police or hospitals).', 'number', 1, 10),
('daily.gem_prize', '3000', 'daily', 'Prize per gem',
 'Cash each gem pays the player who finds it.', 'naira', 0, 10000000),
('daily.gem_all_bonus', '5000', 'daily', 'Bonus for finding all',
 'Extra cash for finding every gem of the day (paid once, with the last gem).', 'naira', 0, 10000000)
on conflict (key) do nothing;

-- WAT calendar date "now" (clock.timezone, default Africa/Lagos). Tests time-travel via bl_now().
create or replace function public.bl_wat_date(p_at timestamptz default null) returns date
language sql stable set search_path = public as $$
  select (coalesce(p_at, bl_now()) at time zone bl_clock_tz())::date;
$$;

-- ---------------------------------------------------------------------
-- 2. Tables
-- ---------------------------------------------------------------------
create table if not exists public.daily_reward_steps (
  day     int primary key check (day between 1 and 7),
  cash    bigint not null default 0 check (cash >= 0),
  item_id text references public.items(id) on update cascade on delete set null,
  label   text not null default ''
);

insert into public.daily_reward_steps (day, cash, item_id, label) values
  (1,  1000, null, 'Small chop money'),
  (2,  1500, null, 'Transport fare'),
  (3,  2000, null, 'Lunch at the buka'),
  (4,  3000, null, 'Data and airtime'),
  (5,  4000, null, 'Weekend fund'),
  (6,  5000, null, 'Something nice'),
  (7, 10000, (select id from public.items where id in ('energy_drink', 'power_horse', 'monster_energy', 'red_bull')
               or name ilike '%energy drink%' order by id limit 1), 'Big day 7 prize')
on conflict (day) do nothing;

create table if not exists public.daily_reward_state (
  user_id         uuid primary key references public.profiles(id) on delete cascade,
  last_claim_date date,
  streak_day      int not null default 0 check (streak_day between 0 and 7),
  total_claims    int not null default 0,
  updated_at      timestamptz not null default now()
);

create table if not exists public.gem_finds (
  user_id     uuid not null references public.profiles(id) on delete cascade,
  hunt_date   date not null,
  location_id text not null references public.locations(id) on update cascade on delete cascade,
  prize       bigint not null default 0,
  bonus       bigint not null default 0,
  found_at    timestamptz not null default now(),
  primary key (user_id, hunt_date, location_id)
);
create index if not exists gem_finds_date_idx on public.gem_finds (hunt_date);

alter table public.daily_reward_steps enable row level security;
alter table public.daily_reward_state enable row level security;
alter table public.gem_finds          enable row level security;

drop policy if exists daily_reward_steps_read on public.daily_reward_steps;
create policy daily_reward_steps_read on public.daily_reward_steps for select to authenticated using (true);
drop policy if exists daily_reward_state_own on public.daily_reward_state;
create policy daily_reward_state_own on public.daily_reward_state for select to authenticated using (user_id = auth.uid());
drop policy if exists gem_finds_own on public.gem_finds;
create policy gem_finds_own on public.gem_finds for select to authenticated using (user_id = auth.uid());

revoke insert, update, delete, truncate on public.daily_reward_steps from anon, authenticated;
revoke insert, update, delete, truncate on public.daily_reward_state from anon, authenticated;
revoke insert, update, delete, truncate on public.gem_finds          from anon, authenticated;
revoke all on public.daily_reward_state, public.gem_finds from anon;

-- ---------------------------------------------------------------------
-- 3. Daily reward
-- ---------------------------------------------------------------------
-- Status for the caller: ready/claimed, the day to claim (or claimed today), the next reward, the 7-day list.
create or replace function public.daily_reward_status() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_uid   uuid := bl_require_uid();
  v_today date := bl_wat_date();
  s       daily_reward_state;
  v_claimed boolean;
  v_day   int;
  v_next  jsonb;
  v_steps jsonb;
begin
  select * into s from daily_reward_state where user_id = v_uid;
  v_claimed := s.last_claim_date is not distinct from v_today;
  if v_claimed then
    v_day := s.streak_day;
  elsif s.last_claim_date = v_today - 1 then
    v_day := (s.streak_day % 7) + 1;
  else
    v_day := 1;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'day', d.day, 'cash', coalesce(r.cash, 0), 'item_id', r.item_id, 'item_name', i.name, 'item_icon', i.icon,
           'label', coalesce(r.label, ''),
           'state', case when d.day < v_day or (d.day = v_day and v_claimed) then 'claimed'
                         when d.day = v_day then 'today' else 'upcoming' end)
           order by d.day), '[]'::jsonb)
    into v_steps
    from generate_series(1, 7) d(day)
    left join daily_reward_steps r on r.day = d.day
    left join items i on i.id = r.item_id;

  -- what you get next: today's step when ready, tomorrow's when already claimed
  v_next := v_steps -> (case when v_claimed then v_day % 7 else v_day - 1 end);

  return jsonb_build_object(
    'enabled', bl_cfg_bool('daily.reward_enabled'),
    'date', v_today,
    'ready', not v_claimed,
    'claimed', v_claimed,
    'day', v_day,
    'next', v_next,
    'steps', v_steps,
    'total_claims', coalesce(s.total_claims, 0)
  );
end $$;

-- Claim today's step. Once per WAT day (row lock + date check), credits cash through the ledger.
create or replace function public.daily_reward_claim() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid   uuid := bl_require_uid();
  v_today date := bl_wat_date();
  s       daily_reward_state;
  v_day   int;
  r       daily_reward_steps;
  v_item  items;
  v_msg   text;
begin
  if not bl_cfg_bool('daily.reward_enabled') then
    raise exception 'The daily reward is switched off right now.' using errcode = 'P0001', hint = 'disabled';
  end if;
  if not exists (select 1 from profiles where id = v_uid) then
    raise exception 'Create your Sim first.' using errcode = 'P0001', hint = 'no_profile';
  end if;

  insert into daily_reward_state (user_id) values (v_uid) on conflict (user_id) do nothing;
  select * into s from daily_reward_state where user_id = v_uid for update;

  if s.last_claim_date is not distinct from v_today then
    raise exception 'You already claimed today''s reward. Come back tomorrow for day %.', (s.streak_day % 7) + 1
      using errcode = 'P0001', hint = 'already_claimed';
  end if;
  v_day := case when s.last_claim_date = v_today - 1 then (s.streak_day % 7) + 1 else 1 end;

  select * into r from daily_reward_steps where day = v_day;
  if coalesce(r.cash, 0) > 0 then
    perform bl_add_money(v_uid, 'cash', r.cash, format('Daily reward (day %s)', v_day),
                         jsonb_build_object('daily_day', v_day, 'date', v_today));
  end if;
  if r.item_id is not null then
    select * into v_item from items where id = r.item_id;
    if found then perform bl_give_item(v_uid, r.item_id, 1); end if;
  end if;

  update daily_reward_state
     set last_claim_date = v_today, streak_day = v_day, total_claims = total_claims + 1, updated_at = bl_now()
   where user_id = v_uid;

  v_msg := format('Day %s reward: %s%s', v_day, bl_naira(coalesce(r.cash, 0)),
                  case when v_item.id is not null then ' + ' || v_item.name else '' end);
  return jsonb_build_object('message', v_msg, 'day', v_day, 'cash', coalesce(r.cash, 0),
                            'item_id', v_item.id, 'item_name', v_item.name);
end $$;

-- ---------------------------------------------------------------------
-- 4. Daily gem hunt
-- ---------------------------------------------------------------------
-- Today's gem places for p_date: deterministic (md5 of date + place id), the same for every player.
-- Eligible: active, public (no private home), not a home scene, not police/hospital, open all day.
create or replace function public.bl_gem_places(p_date date) returns table (idx int, location_id text, district text)
language sql stable set search_path = public as $$
  select (row_number() over (order by md5(p_date::text || ':' || l.id), l.id))::int as idx, l.id, l.district
    from (select l.* from locations l
           where coalesce(l.active, true)
             and l.private_home_owner_id is null
             and l.scene not like 'home%'
             and l.scene not in ('police', 'hospital')
             and (l.open_hour is null or l.open_hour = l.close_hour)
             and not exists (select 1 from start_homes h where h.location_id = l.id)
           order by md5(p_date::text || ':' || l.id), l.id
           limit greatest(0, least(10, coalesce(bl_cfg('daily.gems_per_day'), 3)::int))) l
   order by 1;
$$;

create or replace function public.gem_hunt_status() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_uid    uuid := bl_require_uid();
  v_today  date := bl_wat_date();
  v_prize  bigint := bl_cfg('daily.gem_prize')::bigint;
  v_bonus  bigint := bl_cfg('daily.gem_all_bonus')::bigint;
  v_here   text;
  v_total  int;
  v_found  int;
  v_all    bigint;
  v_gems   jsonb;
begin
  select case when travel_to is null then location_id end into v_here from profiles where id = v_uid;

  select count(*)::int, count(f.location_id)::int,
         coalesce(jsonb_agg(jsonb_build_object(
           'idx', g.idx, 'district', g.district, 'found', f.location_id is not null,
           -- the exact place only once found, or when you are standing in it
           'location_id', case when f.location_id is not null or g.location_id = v_here then g.location_id end,
           'place_name', case when f.location_id is not null then l.name end,
           'here', g.location_id = v_here and f.location_id is null) order by g.idx), '[]'::jsonb)
    into v_total, v_found, v_gems
    from bl_gem_places(v_today) g
    join locations l on l.id = g.location_id
    left join gem_finds f on f.user_id = v_uid and f.hunt_date = v_today and f.location_id = g.location_id;

  select count(*) into v_all from gem_finds where hunt_date = v_today;

  return jsonb_build_object(
    'enabled', bl_cfg_bool('daily.gems_enabled'),
    'date', v_today,
    'total', v_total,
    'found', v_found,
    'found_all_players', v_all,
    'prize', v_prize,
    'all_bonus', v_bonus,
    'next_prize', case when v_found >= v_total then 0
                       when v_total - v_found = 1 then v_prize + v_bonus else v_prize end,
    'here', (select g->>'location_id' from jsonb_array_elements(v_gems) g where (g->>'here')::boolean limit 1),
    'gems', v_gems
  );
end $$;

-- Find today's gem at p_location: you must be standing there (not travelling), once per gem per day.
create or replace function public.gem_find(p_location text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid    uuid := bl_require_uid();
  v_today  date := bl_wat_date();
  v_prize  bigint := bl_cfg('daily.gem_prize')::bigint;
  v_bonus  bigint := 0;
  p        profiles;
  v_total  int;
  v_found  int;
  v_name   text;
  v_ins    int;
begin
  if not bl_cfg_bool('daily.gems_enabled') then
    raise exception 'The gem hunt is switched off right now.' using errcode = 'P0001', hint = 'disabled';
  end if;
  select * into p from profiles where id = v_uid for update;
  if not found then
    raise exception 'Create your Sim first.' using errcode = 'P0001', hint = 'no_profile';
  end if;
  if p.travel_to is not null or p.location_id is distinct from p_location then
    raise exception 'Go there first: you have to be inside the place to pick up its gem.' using errcode = 'P0001', hint = 'not_here';
  end if;
  if not exists (select 1 from bl_gem_places(v_today) g where g.location_id = p_location) then
    raise exception 'No gem here today. Check the hints for today''s districts.' using errcode = 'P0001', hint = 'no_gem';
  end if;

  insert into gem_finds (user_id, hunt_date, location_id, prize, found_at)
  values (v_uid, v_today, p_location, v_prize, bl_now())
  on conflict do nothing;
  get diagnostics v_ins = row_count;
  if v_ins = 0 then
    raise exception 'You already found this gem today.' using errcode = 'P0001', hint = 'already_found';
  end if;

  if v_prize > 0 then
    perform bl_add_money(v_uid, 'cash', v_prize, 'Daily gem hunt', jsonb_build_object('location_id', p_location, 'date', v_today));
  end if;

  select count(*)::int, count(f.location_id)::int into v_total, v_found
    from bl_gem_places(v_today) g
    left join gem_finds f on f.user_id = v_uid and f.hunt_date = v_today and f.location_id = g.location_id;

  if v_total > 0 and v_found >= v_total
     and not exists (select 1 from gem_finds where user_id = v_uid and hunt_date = v_today and bonus > 0) then
    v_bonus := bl_cfg('daily.gem_all_bonus')::bigint;
    if v_bonus > 0 then
      perform bl_add_money(v_uid, 'cash', v_bonus, 'Daily gem hunt bonus (all found)', jsonb_build_object('date', v_today));
      update gem_finds set bonus = v_bonus where user_id = v_uid and hunt_date = v_today and location_id = p_location;
    end if;
  end if;

  select name into v_name from locations where id = p_location;
  return jsonb_build_object(
    'message', case when v_bonus > 0 then format('All %s gems found! %s + %s bonus', v_total, bl_naira(v_prize), bl_naira(v_bonus))
                    else format('Gem found at %s! %s (%s of %s)', v_name, bl_naira(v_prize), v_found, v_total) end,
    'prize', v_prize, 'bonus', v_bonus, 'found', v_found, 'total', v_total);
end $$;

-- ---------------------------------------------------------------------
-- 5. Grants
-- ---------------------------------------------------------------------
revoke execute on function public.bl_wat_date(timestamptz) from public, anon, authenticated;
revoke execute on function public.bl_gem_places(date)      from public, anon, authenticated;
revoke execute on function public.daily_reward_status()    from public, anon;
revoke execute on function public.daily_reward_claim()     from public, anon;
revoke execute on function public.gem_hunt_status()        from public, anon;
revoke execute on function public.gem_find(text)           from public, anon;
grant execute on function public.daily_reward_status() to authenticated;
grant execute on function public.daily_reward_claim()  to authenticated;
grant execute on function public.gem_hunt_status()     to authenticated;
grant execute on function public.gem_find(text)        to authenticated;

-- ---------------------------------------------------------------------
-- 6. Admin: Content -> Daily reward (edit cash / item / label of days 1..7) and Gem finds (read-only log)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.bl_admin_table_spec(p_table text)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select case p_table
    when 'origin_tiers' then '{"pk":["id"],"insert":false,"order":"sort, id",
      "cols":{"name":"text","tagline":"text","welcome":"text","sort":"int","perks":"obj"}}'
    when 'traits' then '{"pk":["id"],"insert":true,"order":"sort, id",
      "cols":{"name":"text","emoji":"text","description":"text","effects":"obj","sort":"int","active":"bool"}}'
    when 'dreams' then '{"pk":["id"],"insert":true,"order":"sort, id",
      "cols":{"name":"text","emoji":"text","description":"text","goal":"obj","sort":"int","active":"bool"}}'
    when 'start_homes' then '{"pk":["id"],"insert":true,"order":"sort, id",
      "cols":{"name":"text","emoji":"text","location_id":"text","district":"text","tag":"text","description":"text",
              "weekly_rent":"money","start_cash":"obj","allowed_origins":"arr","locked_quip":"text","housing_id":"text",
              "sort":"int","active":"bool"}}'
    when 'career_tracks' then '{"pk":["id"],"insert":false,"order":"sort, id",
      "cols":{"name":"text","emoji":"text","description":"text","location_ids":"arr","skill":"text_null","sort":"int","active":"bool"}}'
    when 'career_levels' then '{"pk":["track_id","level"],"insert":true,"order":"track_id, level",
      "cols":{"title":"text","pay_per_shift":"money","shift_game_minutes":"int","energy_cost":"int","effects":"obj",
              "xp_per_shift":"int","xp_to_next":"int_null","requirements":"obj","perks":"obj"}}'
    when 'items' then '{"pk":["id"],"insert":true,"order":"sort, id",
      "cols":{"name":"text","category":"text","price":"money","description":"text","effects":"obj","sold_at":"arr",
              "sellable":"bool","resale_pct":"num","icon":"text_null","sort":"int"}}'
    when 'activities' then '{"pk":["id"],"insert":false,"order":"sort, id",
      "cols":{"name":"text","scenes":"arr","home_only":"bool","night_only":"bool","cost":"money","game_minutes":"int",
              "max_seconds":"num","min_seconds":"num","scale_by_need":"bool","needs_furniture":"bool","effects":"obj","sort":"int",
              "location_ids":"arr","risky":"bool","rush":"obj","icon":"text_null","requires_event":"text_null"}}'
    when 'locations' then '{"pk":["id"],"insert":false,"order":"sort, id",
      "cols":{"name":"text","blurb":"text","risk":"num","night_risk_mult":"num","cctv":"bool","keke_ok":"bool",
              "congestion":"num","remote_km":"num","actions":"arr","sort":"int","open_hour":"num_null","close_hour":"num_null","active":"bool"}}'
    when 'chat_banned_words' then '{"pk":["word"],"insert":true,"order":"word","cols":{"active":"bool"}}'
    when 'furniture' then '{"pk":["id"],"insert":true,"order":"sort, id",
      "cols":{"name":"text","emoji":"text","kind":"text","slot":"text","activities":"arr","rest_pct":"int",
              "color":"text_null","description":"text","sort":"int","active":"bool"}}'
    when 'starter_furniture' then '{"pk":["id"],"insert":true,"order":"origin, sort, id",
      "cols":{"origin":"text","start_home":"text_null","furniture_id":"text","slot":"text_null","sort":"int","active":"bool"}}'
    when 'place_zones' then '{"pk":["id"],"insert":true,"order":"coalesce(scene, location_id), sort, id",
      "cols":{"scene":"text_null","location_id":"text_null","zone_key":"text","label":"text","icon":"text","prop":"text",
              "x":"num","z":"num","w":"num","d":"num","rot":"int","note":"text_null","sort":"int","active":"bool"}}'
    when 'zone_actions' then '{"pk":["id"],"insert":true,"order":"zone_id, sort, id",
      "cols":{"zone_id":"text","kind":"text","ref":"text","label":"text_null","icon":"text_null","sort":"int","active":"bool"}}'
    when 'place_moods' then '{"pk":["id"],"insert":true,"order":"coalesce(scene, location_id), part, sort, id",
      "cols":{"scene":"text_null","location_id":"text_null","part":"text","icon":"text","line":"text","sort":"int","active":"bool"}}'
    when 'npc_roster' then '{"pk":["id"],"insert":true,"order":"sort, id",
      "cols":{"name":"text","role":"text","motion":"text","avatar":"obj","lines":"text","pidgin":"text","scenes":"arr",
              "location_ids":"arr","zone_key":"text_null","headliner":"bool","sort":"int","active":"bool"}}'
    when 'crowd_profiles' then '{"pk":["id"],"insert":true,"order":"scene, from_hour, days, id",
      "cols":{"scene":"text","days":"text","from_hour":"int","to_hour":"int","npcs":"int","sort":"int","active":"bool"}}'
    when 'hype_templates' then '{"pk":["id"],"insert":true,"order":"kind, sort, id",
      "cols":{"kind":"text","line":"text","ticker":"text","sort":"int","active":"bool"}}'
    when 'place_events' then '{"pk":["id"],"insert":true,"order":"sort, id",
      "cols":{"location_id":"text","title":"text","description":"text","kind":"text","icon":"text","recurrence":"text",
              "weekday":"int_null","start_time":"num_null","end_time":"num_null","starts_at":"ts_null","ends_at":"ts_null",
              "ticket_price":"money","capacity":"int_null","perks":"obj","variants":"text","sort":"int","active":"bool"}}'
    when 'topup_packs' then '{"pk":["id"],"insert":true,"order":"sort, id",
      "cols":{"label":"text","game_naira":"money","price_kobo":"money","bonus_tag":"text_null","sort":"int","active":"bool"}}'
    when 'daily_reward_steps' then '{"pk":["day"],"insert":false,"order":"day",
      "cols":{"cash":"money","item_id":"text_null","label":"text"}}'
    when 'gem_finds' then '{"pk":["user_id","hunt_date","location_id"],"insert":false,"order":"hunt_date desc, found_at desc",
      "cols":{}}'
  end::jsonb;
$function$;
revoke execute on function public.bl_admin_table_spec(text) from public, anon, authenticated;
