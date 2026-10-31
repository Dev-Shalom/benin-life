-- Daily return pack, part 3: THE WEEKLY CALENDAR "This week in Benin" (docs/DAILY_RETURN.md).
-- Five recurring events, all computed from the Benin (WAT) calendar the moment somebody asks: there is nothing to create, nothing for cron to
-- schedule (the cron's bl_push_tick only sends the morning push and the Monday announcement, and weekly_calendar() does the announcement
-- lazily too if cron is down).
--   Friday Club Night   check in at any club: a little cash and fun
--   Saturday Owambe     check in at the party place (Golden Tulip Essential): a little cash and fun
--   Sunday Rest Day     check in at home: less stress, more energy
--   Monday Winners      last week's top earners announced as a broadcast (the weekly prize winners that already exist)
--   Wednesday Market Day  Oba Market prices are lower all day (bl_dealer_net, so the list, the buy button and tax all agree)
-- Every reward is a setting (Admin -> Settings -> Weekly events); every event has its own switch; one opt-in morning push (Game events).
-- Idempotent. Nothing touches profiles. No loops over all players: the morning push is a bounded batch.

create or replace function pg_temp.dr3_patch(p_sig text, p_old text, p_new text, p_done text) returns void
language plpgsql as $$
declare v_def text; v_n int;
begin
  select pg_get_functiondef(p_sig::regprocedure) into v_def;
  if position(p_done in v_def) > 0 then return; end if;
  v_n := (length(v_def) - length(replace(v_def, p_old, ''))) / length(p_old);
  if v_n <> 1 then raise exception 'weekly_events: % : marker found % times: %', p_sig, v_n, left(p_old, 80); end if;
  execute replace(v_def, p_old, p_new);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 1. Settings (Admin -> Settings -> Weekly events)
-- ---------------------------------------------------------------------------------------------
insert into public.game_config (key, value, category, label, description, kind, min, max) values
('weekly.enabled', 'true', 'weekly', 'Weekly events on', 'Master switch for "This week in Benin": the calendar, the banners, the check-in rewards, the market discount and the morning push. Each event also has its own switch.', 'bool', null, null),
('weekly.fri_club_enabled', 'true', 'weekly', 'Friday Club Night on', 'Fridays: clubs are the place to be. Check in at any club for a small bonus.', 'bool', null, null),
('weekly.fri_club_cash', '1000', 'weekly', 'Friday Club Night: cash', 'Naira for checking in at a club on Friday.', 'naira', 0, 100000),
('weekly.fri_club_fun', '15', 'weekly', 'Friday Club Night: fun', 'Fun points (0-100 scale) for checking in.', 'number', 0, 100),
('weekly.sat_owambe_enabled', 'true', 'weekly', 'Saturday Owambe on', 'Saturdays: a city party. Check in at the party place for a small reward.', 'bool', null, null),
('weekly.sat_owambe_cash', '1500', 'weekly', 'Saturday Owambe: cash', 'Naira for checking in at the owambe.', 'naira', 0, 100000),
('weekly.sat_owambe_fun', '20', 'weekly', 'Saturday Owambe: fun', 'Fun points for checking in.', 'number', 0, 100),
('weekly.sat_owambe_place', '"golden_tulip"', 'weekly', 'Saturday Owambe: place (id)', 'Location id of the party (default Golden Tulip Essential). Must be an active place.', 'text', null, null),
('weekly.sun_rest_enabled', 'true', 'weekly', 'Sunday Rest Day on', 'Sundays: take it easy. Check in at home for a relaxation bonus. (A Church event can replace this later.)', 'bool', null, null),
('weekly.sun_rest_stress', '20', 'weekly', 'Sunday Rest Day: less stress', 'Stress points taken off (0-100 scale) for resting at home.', 'number', 0, 100),
('weekly.sun_rest_energy', '10', 'weekly', 'Sunday Rest Day: more energy', 'Energy points added for resting at home.', 'number', 0, 100),
('weekly.mon_winners_enabled', 'true', 'weekly', 'Monday Winners on', 'Mondays: last week''s top earners are announced to everyone as a broadcast.', 'bool', null, null),
('weekly.wed_market_enabled', 'true', 'weekly', 'Wednesday Market Day on', 'Wednesdays: prices at the market below are lower all day.', 'bool', null, null),
('weekly.wed_market_discount_pct', '15', 'weekly', 'Wednesday Market Day: discount (%)', 'How much cheaper everything is at the market on Wednesday.', 'percent', 0, 50),
('weekly.wed_market_place', '"oba_market"', 'weekly', 'Wednesday Market Day: market (id)', 'Location id of the market that has the discount (default Oba Market).', 'text', null, null),
('weekly.push_enabled', 'true', 'weekly', 'Morning push on', 'One push on the morning of an event (Game events category, opt-in), at most one a day per player.', 'bool', null, null),
('weekly.push_hour', '9', 'weekly', 'Morning push hour', 'Benin hour (0-23) from which the morning push goes out. It stops at the "Quiet hours: stop sending at" hour of Settings -> Welcome back.', 'number', 0, 23),
('weekly.push_batch', '200', 'weekly', 'Morning push: players per tick', 'At most this many players per push tick, so the morning push is spread over a few minutes.', 'number', 10, 2000)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 2. Tables (RLS on, closed to players)
-- ---------------------------------------------------------------------------------------------
create table if not exists public.weekly_event_checkins (
  user_id uuid not null,
  event_key text not null,
  day date not null,
  created_at timestamptz not null default now(),
  primary key (user_id, event_key, day)
);
create index if not exists weekly_event_checkins_day_idx on public.weekly_event_checkins (day);

create table if not exists public.weekly_event_runs (    -- "this happened today": the Monday announcement, "morning push finished"
  event_key text not null,
  day date not null,
  created_at timestamptz not null default now(),
  primary key (event_key, day)
);

create table if not exists public.weekly_push_log (
  user_id uuid not null,
  day date not null,
  primary key (user_id, day)
);

do $$
declare t text;
begin
  foreach t in array array['weekly_event_checkins', 'weekly_event_runs', 'weekly_push_log'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 3. The programme and today
-- ---------------------------------------------------------------------------------------------
-- weekday 0 = Monday ... 6 = Sunday (the same numbering as place_events)
create or replace function public.bl_weekly_catalog() returns table (key text, weekday int, icon text, title text, blurb text)
language sql immutable set search_path = public as $$
  select * from (values
    ('fri_club',   4, '🪩', 'Friday Club Night',   'Clubs are the place to be tonight. Check in at any club for a little cash and a fun boost.'),
    ('sat_owambe', 5, '🎉', 'Saturday Owambe',     'A big city party. Show face at the owambe and collect a small reward.'),
    ('sun_rest',   6, '🛋️', 'Sunday Rest Day',      'Take it easy. Rest at home for less stress and more energy.'),
    ('mon_winners',0, '🏆', 'Monday Winners',      'Last week''s top earners are announced to everybody. Could you be next?'),
    ('wed_market', 2, '🛒', 'Wednesday Market Day', 'Prices at the market are lower all day. Go and buy your food.')
  ) v(key, weekday, icon, title, blurb)
$$;

-- is this event on (master + its own switch)?
create or replace function public.bl_weekly_on(p_key text) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(bl_cfg_bool('weekly.enabled'), false) and coalesce(bl_cfg_bool('weekly.' || p_key || '_enabled'), false)
$$;

create or replace function public.bl_weekly_dow(p_at timestamptz default null) returns int      -- 0 = Monday in Benin time
language sql stable set search_path = public as $$
  select (extract(isodow from (coalesce(p_at, bl_now()) at time zone bl_clock_tz()))::int - 1)
$$;

-- the event of a weekday (null when none or switched off)
create or replace function public.bl_weekly_key(p_weekday int) returns text
language sql stable security definer set search_path = public as $$
  select c.key from bl_weekly_catalog() c where c.weekday = p_weekday and bl_weekly_on(c.key)
$$;

-- Wednesday Market Day: the price at the market. Cheap when it does not apply (weekday check first, no query).
create or replace function public.bl_weekly_discount(p_price bigint, p_location text) returns bigint
language plpgsql stable security definer set search_path = public as $$
declare v_pct numeric; v_p numeric;
begin
  if p_price is null or bl_weekly_dow() <> 2 then return p_price; end if;
  if not bl_weekly_on('wed_market') or p_location is distinct from bl_cfg_text('weekly.wed_market_place') then return p_price; end if;
  v_pct := least(50, greatest(0, coalesce(bl_cfg('weekly.wed_market_discount_pct'), 0)));
  if v_pct <= 0 then return p_price; end if;
  v_p := p_price * (1 - v_pct / 100.0);
  if v_p < 1000 then return greatest(10, (round(v_p / 10.0) * 10)::bigint); end if;
  return (round(v_p / 50.0) * 50)::bigint;
end $$;

select pg_temp.dr3_patch('public.bl_dealer_net(public.items, text)',
  $o$when p_item.category <> 'vehicle' then coalesce(bl_shop_price(p_item, p_location), p_item.price)$o$,
  $o$when p_item.category <> 'vehicle' then bl_weekly_discount(coalesce(bl_shop_price(p_item, p_location), p_item.price), p_location)$o$,
  'bl_weekly_discount(');

-- ---------------------------------------------------------------------------------------------
-- 4. The calendar and the check-in
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_weekly_place_name(p_id text) returns text
language sql stable set search_path = public as $$
  select regexp_replace(name, '\s*\(.*\)\s*$', '') from locations where id = p_id
$$;

-- Monday: announce last week's winners once (lazy; the cron tick calls it too)
create or replace function public.bl_weekly_monday_run() returns boolean
language plpgsql volatile security definer set search_path = public as $$
declare v_today date := bl_wat_date(); v_body text := ''; r record; v_n int := 0; v_id bigint; v_week date := bl_week_start() - 7;
begin
  if bl_weekly_dow() <> 0 or not bl_weekly_on('mon_winners') then return false; end if;
  if exists (select 1 from weekly_event_runs where event_key = 'mon_winners' and day = v_today) then return false; end if;
  if not pg_try_advisory_xact_lock(hashtext('weekly_monday')) then return false; end if;
  begin perform bl_weekly_settle(); exception when others then null; end;      -- make sure last week is settled
  for r in select username, total, rank from weekly_earn_winners where week_start = v_week order by rank limit 3 loop
    v_body := v_body || case r.rank when 1 then '🥇 ' when 2 then '🥈 ' else '🥉 ' end || '@' || r.username || ' earned ' || bl_naira(r.total) || E'\n';
    v_n := v_n + 1;
  end loop;
  insert into weekly_event_runs (event_key, day) values ('mon_winners', v_today) on conflict do nothing;
  if v_n = 0 then return false; end if;
  insert into broadcasts (kind, title, body, style, audience, popup, expires_at, targeted, target_count, created_by)
  values ('message', '🏆 Monday Winners', left('Last week''s top earners in Benin:' || E'\n' || btrim(v_body, E'\n') || E'\nKeep hustling, your name can be here next Monday.', 500),
          'celebration', 'everyone', true, bl_now() + interval '24 hours', false, 0, null)
  returning id into v_id;
  return true;
end $$;
revoke all on function public.bl_weekly_monday_run() from public, anon, authenticated;

create or replace function public.bl_weekly_json(p_key text, p_uid uuid, p_day date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare c record; v_place text; v_reward text; v_where text; v_rule text; v_cash bigint; v_pct numeric; v_win jsonb;
begin
  select * into c from bl_weekly_catalog() x where x.key = p_key;
  if not found then return null; end if;
  if p_key = 'fri_club' then
    v_rule := 'club'; v_where := 'Any club';
    v_cash := bl_cfg('weekly.fri_club_cash')::bigint;
    v_reward := concat_ws(' + ', case when v_cash > 0 then bl_naira(v_cash) end, case when bl_cfg('weekly.fri_club_fun') > 0 then 'fun +' || bl_cfg('weekly.fri_club_fun')::int end);
  elsif p_key = 'sat_owambe' then
    v_rule := 'place'; v_place := bl_cfg_text('weekly.sat_owambe_place'); v_where := bl_weekly_place_name(v_place);
    v_cash := bl_cfg('weekly.sat_owambe_cash')::bigint;
    v_reward := concat_ws(' + ', case when v_cash > 0 then bl_naira(v_cash) end, case when bl_cfg('weekly.sat_owambe_fun') > 0 then 'fun +' || bl_cfg('weekly.sat_owambe_fun')::int end);
  elsif p_key = 'sun_rest' then
    v_rule := 'home'; v_where := 'At home';
    v_reward := concat_ws(' + ', case when bl_cfg('weekly.sun_rest_stress') > 0 then 'stress -' || bl_cfg('weekly.sun_rest_stress')::int end,
                                 case when bl_cfg('weekly.sun_rest_energy') > 0 then 'energy +' || bl_cfg('weekly.sun_rest_energy')::int end);
  elsif p_key = 'wed_market' then
    v_place := bl_cfg_text('weekly.wed_market_place'); v_where := bl_weekly_place_name(v_place); v_pct := bl_cfg('weekly.wed_market_discount_pct');
    v_reward := v_pct::int || '% off at ' || coalesce(v_where, 'the market');
  elsif p_key = 'mon_winners' then
    select coalesce(jsonb_agg(jsonb_build_object('rank', w.rank, 'username', w.username, 'total', w.total) order by w.rank), '[]'::jsonb) into v_win
      from weekly_earn_winners w where w.week_start = bl_week_start(bl_now()) - 7;
    v_where := 'Everywhere';
    v_reward := 'Last week''s top earners';
  end if;
  return jsonb_build_object('key', c.key, 'weekday', c.weekday, 'icon', c.icon, 'title', c.title, 'blurb', c.blurb, 'reward', nullif(v_reward, ''),
    'where', v_where, 'place_id', v_place, 'checkin', v_rule is not null, 'rule', v_rule,
    'checked_in', p_uid is not null and exists (select 1 from weekly_event_checkins k where k.user_id = p_uid and k.event_key = p_key and k.day = p_day),
    'winners', v_win, 'discount_pct', v_pct);
end $$;
revoke all on function public.bl_weekly_json(text, uuid, date) from public, anon, authenticated;

-- "This week in Benin": Monday to Sunday of the current Benin week, today marked
create or replace function public.weekly_calendar() returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); v_today date := bl_wat_date(); v_dow int := bl_weekly_dow(); v_days jsonb := '[]'::jsonb; i int; k text; d date; v_today_ev jsonb;
begin
  if not coalesce(bl_cfg_bool('weekly.enabled'), false) then return jsonb_build_object('enabled', false, 'days', '[]'::jsonb); end if;
  perform bl_weekly_monday_run();
  for i in 0..6 loop
    d := v_today - v_dow + i;
    k := bl_weekly_key(i);
    v_days := v_days || jsonb_build_array(jsonb_build_object('date', d, 'weekday', i, 'today', d = v_today, 'past', d < v_today,
      'event', case when k is null then null else bl_weekly_json(k, v_uid, d) end));
  end loop;
  v_today_ev := v_days -> v_dow -> 'event';
  return jsonb_build_object('enabled', true, 'today', v_today, 'weekday', v_dow, 'days', v_days, 'today_event', v_today_ev);
end $$;

-- Check in: right place, once per event per day, small reward
create or replace function public.weekly_event_checkin() returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_me profiles := bl_me(); v_day date := bl_wat_date(); k text := bl_weekly_key(bl_weekly_dow()); l locations; v_cash bigint := 0; v_needs jsonb := '{}'::jsonb;
  v_title text; v_msg text; v_place text; v_n int;
begin
  if k is null or k not in ('fri_club', 'sat_owambe', 'sun_rest') then
    raise exception 'There is nothing to check in to today.' using errcode = 'P0001', hint = 'no_event';
  end if;
  perform bl_assert_free(v_me);
  select c.title into v_title from bl_weekly_catalog() c where c.key = k;
  if v_me.travel_to is not null then
    raise exception 'Finish your trip first, then check in.' using errcode = 'P0001', hint = 'not_here';
  end if;
  select * into l from locations where id = v_me.location_id;
  if k = 'fri_club' then
    if l.scene is distinct from 'club' then raise exception 'Go to any club to join %.', v_title using errcode = 'P0001', hint = 'not_here'; end if;
    v_cash := greatest(0, bl_cfg('weekly.fri_club_cash'))::bigint;
    v_needs := jsonb_build_object('fun', greatest(0, bl_cfg('weekly.fri_club_fun')));
  elsif k = 'sat_owambe' then
    v_place := bl_cfg_text('weekly.sat_owambe_place');
    if v_me.location_id is distinct from v_place then
      raise exception 'Go to % to join the owambe.', coalesce(bl_weekly_place_name(v_place), 'the party place') using errcode = 'P0001', hint = 'not_here';
    end if;
    v_cash := greatest(0, bl_cfg('weekly.sat_owambe_cash'))::bigint;
    v_needs := jsonb_build_object('fun', greatest(0, bl_cfg('weekly.sat_owambe_fun')));
  else
    if v_me.location_id is distinct from v_me.home_location_id then
      raise exception 'Go home to rest properly.' using errcode = 'P0001', hint = 'not_here';
    end if;
    v_needs := jsonb_build_object('stress', -greatest(0, bl_cfg('weekly.sun_rest_stress')), 'energy', greatest(0, bl_cfg('weekly.sun_rest_energy')));
  end if;
  perform 1 from profiles where id = v_me.id for update;
  insert into weekly_event_checkins (user_id, event_key, day) values (v_me.id, k, v_day) on conflict do nothing;
  get diagnostics v_n = row_count;
  if v_n = 0 then raise exception 'You already checked in today.' using errcode = 'P0001', hint = 'already'; end if;
  if v_cash > 0 then perform bl_add_money(v_me.id, 'cash', v_cash, 'Weekly event: ' || v_title, jsonb_build_object('event', k, 'day', v_day)); end if;
  perform bl_adjust_needs(v_me.id, v_needs);
  v_msg := v_title || ': checked in.' || case when v_cash > 0 then ' ' || bl_naira(v_cash) || ' added.' else '' end;
  return jsonb_build_object('ok', true, 'event', k, 'cash', v_cash, 'needs', v_needs, 'message', v_msg);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 5. The cron side: Monday announcement + one morning push (bounded)
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_weekly_tick() returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_now timestamptz := bl_now(); v_today date := bl_wat_date(v_now); v_hour numeric := extract(hour from (v_now at time zone bl_clock_tz()));
  k text := bl_weekly_key(bl_weekly_dow(v_now)); v_batch int := greatest(10, coalesce(bl_cfg('weekly.push_batch'), 200))::int;
  r record; c record; v_n int := 0; v_seen int := 0; v_mon boolean := false;
begin
  if not coalesce(bl_cfg_bool('weekly.enabled'), false) then return jsonb_build_object('skipped', 'off'); end if;
  v_mon := bl_weekly_monday_run();
  if k is null or k = 'mon_winners' or not coalesce(bl_cfg_bool('weekly.push_enabled'), false)
     or not (coalesce(bl_cfg_bool('push.enabled'), false) and coalesce(bl_cfg_bool('push.cat_events'), false)) then
    return jsonb_build_object('monday', v_mon, 'pushed', 0);
  end if;
  if v_hour < bl_cfg('weekly.push_hour') or v_hour >= bl_cfg('return.push_to_hour') then return jsonb_build_object('monday', v_mon, 'pushed', 0, 'skipped', 'hours'); end if;
  if exists (select 1 from weekly_event_runs where event_key = 'push:' || k and day = v_today) then return jsonb_build_object('monday', v_mon, 'pushed', 0, 'skipped', 'done'); end if;
  select * into c from bl_weekly_catalog() x where x.key = k;
  for r in
    select p.id from profiles p
     where p.home_chosen and not p.banned and p.seen_bucket >= floor(extract(epoch from v_now - interval '14 days') / 300)::bigint
       and exists (select 1 from push_prefs pp where pp.user_id = p.id and pp.master and pp.events)
       and exists (select 1 from push_subscriptions ps where ps.user_id = p.id)
       and not exists (select 1 from weekly_push_log w where w.user_id = p.id and w.day = v_today)
     limit v_batch
  loop
    v_seen := v_seen + 1;
    insert into weekly_push_log (user_id, day) values (r.id, v_today) on conflict do nothing;
    if bl_push_enqueue(r.id, 'events', 'weekly_event', c.icon || ' ' || c.title || ' is on today', left(c.blurb, 110), '/play?go=week', null, null, null, 'wk:' || k || ':' || v_today) is not null then
      v_n := v_n + 1;
    end if;
  end loop;
  if v_seen < v_batch then insert into weekly_event_runs (event_key, day) values ('push:' || k, v_today) on conflict do nothing; end if;
  delete from weekly_push_log where ctid in (select ctid from weekly_push_log where day < v_today - 14 limit 2000);
  return jsonb_build_object('monday', v_mon, 'pushed', v_n, 'looked_at', v_seen);
exception when others then
  return jsonb_build_object('error', sqlerrm);
end $$;
revoke all on function public.bl_weekly_tick() from public, anon, authenticated;

select pg_temp.dr3_patch('public.bl_push_tick()',
  E'jsonb_build_object(''return_pushed'', bl_return_push_tick());',
  E'jsonb_build_object(''return_pushed'', bl_return_push_tick())\n         || jsonb_build_object(''weekly'', bl_weekly_tick());',
  'bl_weekly_tick(');

-- ---------------------------------------------------------------------------------------------
-- 6. Grants
-- ---------------------------------------------------------------------------------------------
revoke all on function public.bl_weekly_on(text), public.bl_weekly_dow(timestamptz), public.bl_weekly_key(int), public.bl_weekly_discount(bigint, text),
  public.bl_weekly_place_name(text), public.bl_weekly_catalog() from public, anon, authenticated;
revoke all on function public.weekly_calendar() from public, anon;
grant execute on function public.weekly_calendar() to authenticated;
revoke all on function public.weekly_event_checkin() from public, anon;
grant execute on function public.weekly_event_checkin() to authenticated;

notify pgrst, 'reload schema';
