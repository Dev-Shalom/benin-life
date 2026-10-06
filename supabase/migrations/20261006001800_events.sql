-- L4 events (docs/EVENTS.md, docs/REAL_LIFE_PLAN.md "L4").
-- * place_events: data-driven events at places (match days, club nights, market days, owambe, premieres, pool
--   parties, promos). One-off (recurrence 'none': starts_at .. ends_at) or weekly (weekday 0 = Monday .. 6 = Sunday,
--   start_time .. end_time in Benin hours, end <= start = past midnight; starts_at / ends_at optionally bound the
--   season). Always computed in real Benin time (clock.timezone, WAT), through bl_now() so tests can move time.
--   ticket_price 0 = free, capacity optional, perks {"effects": {...}, "street_cred": n} added to event-only actions.
--   Events at hidden (inactive) places never show. Admin-editable (Content -> Events), audited.
-- * event_tickets: one ticket per player per occurrence (event_id + occurs_on = the local date it starts).
-- * events_on_today(p_location): today's and LIVE events (plus those starting within events.banner_lead_hours).
-- * event_buy_ticket(p_event): bank first, then cash; one per occurrence; capacity respected.
-- * activities.requires_event (an event kind or event id): the card shows only on a day that event is on at the
--   place, locked "Starts 4 PM" / "Needs a ticket", open while it's LIVE and you have a ticket (or it's free).
-- * Config events.banner_enabled (true), events.banner_lead_hours (3).
-- Re-created from their live definitions (grants kept): place_interior, do_activity, bl_admin_table_spec,
-- bl_admin_check_value. Idempotent and safe on a non-empty DB.

-- ---------------------------------------------------------------------
-- 1. Config
-- ---------------------------------------------------------------------
insert into public.game_config (key, value, category, label, description, kind, min, max) values
('events.banner_enabled', 'true', 'events', 'Event banner',
 'A slim banner at the top of the game for LIVE events and ones starting soon. Tap opens the place.', 'bool', null, null),
('events.banner_lead_hours', '3', 'events', 'Banner: starts within (hours)',
 'Upcoming events show in the banner (and "On today") this many hours before they start.', 'number', 0, 24)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------
-- 2. Tables
-- ---------------------------------------------------------------------
create table if not exists public.place_events (
  id           text primary key,
  location_id  text not null references public.locations(id) on delete cascade,
  title        text not null,
  description  text not null default '',
  kind         text not null default 'promo',
  icon         text not null default '🎉',
  recurrence   text not null default 'weekly',
  weekday      int,
  start_time   numeric,
  end_time     numeric,
  starts_at    timestamptz,
  ends_at      timestamptz,
  ticket_price bigint not null default 0,
  capacity     int,
  perks        jsonb not null default '{}'::jsonb,
  variants     text not null default '',
  sort         int not null default 0,
  active       boolean not null default true,
  constraint place_events_kind_chk check (kind in ('match', 'concert', 'club_night', 'market_day', 'church', 'owambe', 'premiere', 'party', 'promo')),
  constraint place_events_rec_chk check (recurrence in ('none', 'weekly')),
  constraint place_events_weekly_chk check (recurrence <> 'weekly' or (weekday between 0 and 6
    and start_time between 0 and 24 and end_time between 0 and 24 and start_time <> end_time)),
  constraint place_events_once_chk check (recurrence <> 'none' or (starts_at is not null and ends_at is not null and ends_at > starts_at)),
  constraint place_events_price_chk check (ticket_price >= 0 and (capacity is null or capacity >= 0)),
  constraint place_events_perks_chk check (jsonb_typeof(perks) = 'object'),
  constraint place_events_len_chk check (char_length(title) between 1 and 120 and char_length(description) <= 600)
);
create index if not exists place_events_loc_idx on public.place_events (location_id) where active;
alter table public.place_events enable row level security;
revoke all on table public.place_events from public, anon, authenticated;
grant select on table public.place_events to authenticated;
drop policy if exists place_events_read on public.place_events;
create policy place_events_read on public.place_events for select to authenticated
  using (active and exists (select 1 from public.locations l where l.id = location_id and coalesce(l.active, true)));

create table if not exists public.event_tickets (
  id         bigserial primary key,
  event_id   text not null references public.place_events(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  occurs_on  date not null,
  price      bigint not null default 0,
  created_at timestamptz not null default now(),
  constraint event_tickets_once unique (event_id, user_id, occurs_on)
);
create index if not exists event_tickets_occ_idx on public.event_tickets (event_id, occurs_on);
alter table public.event_tickets enable row level security;
revoke all on table public.event_tickets from public, anon, authenticated;
grant select on table public.event_tickets to authenticated;
revoke all on sequence public.event_tickets_id_seq from public, anon, authenticated;
drop policy if exists event_tickets_own on public.event_tickets;
create policy event_tickets_own on public.event_tickets for select to authenticated using (user_id = auth.uid());

alter table public.activities add column if not exists requires_event text;

-- ---------------------------------------------------------------------
-- 3. Occurrences (real Benin time)
-- ---------------------------------------------------------------------
-- Every occurrence of every event whose local start date is yesterday, today or tomorrow (enough for "today",
-- "LIVE now" past midnight and the banner lead). Inactive events / places are filtered by the callers.
create or replace function public.bl_event_occurrences(p_now timestamptz default null)
returns table (event_id text, occurs_on date, starts_at timestamptz, ends_at timestamptz)
language sql stable set search_path = public as $$
  with c as (select coalesce(p_now, bl_now()) as now, bl_clock_tz() as tz),
  d as (select ((c.now at time zone c.tz)::date + g) as day, c.tz from c, generate_series(-1, 1) g),
  o as (
    select e.id, d.day,
           (d.day + make_interval(secs => (e.start_time * 3600)::double precision)) at time zone d.tz as s,
           (d.day + make_interval(secs => ((case when e.end_time <= e.start_time then e.end_time + 24 else e.end_time end) * 3600)::double precision)) at time zone d.tz as f,
           e.starts_at as lo, e.ends_at as hi
      from place_events e join d on extract(isodow from d.day)::int - 1 = e.weekday
     where e.recurrence = 'weekly'
  )
  select o.id, o.day, o.s, o.f from o
   where (o.lo is null or o.s >= o.lo) and (o.hi is null or o.s < o.hi)
  union all
  select e.id, (e.starts_at at time zone c.tz)::date, e.starts_at, e.ends_at
    from place_events e, c
   where e.recurrence = 'none'
     and e.ends_at > c.now - interval '2 days' and e.starts_at < c.now + interval '2 days';
$$;
revoke execute on function public.bl_event_occurrences(timestamptz) from public, anon, authenticated;

-- "Bendel Insurance vs {variant}": a different line each week (one per row in variants)
create or replace function public.bl_event_title(p_title text, p_variants text, p_on date)
returns text language sql immutable as $$
  select case when position('{variant}' in p_title) = 0 then p_title
    else replace(p_title, '{variant}', coalesce((
      select v from (select v, row_number() over () - 1 as i, count(*) over () as n
                       from unnest(string_to_array(p_variants, E'\n')) v where btrim(v) <> '') q
       where q.i = ((((p_on - date '2026-01-05') / 7) % q.n) + q.n) % q.n), 'a mystery side')) end;
$$;
revoke execute on function public.bl_event_title(text, text, date) from public, anon, authenticated;

-- 12-hour clock label of a timestamptz in Benin time ("4 PM", "9:30 PM")
create or replace function public.bl_time_label(p_at timestamptz)
returns text language sql stable set search_path = public as $$
  select bl_hour_label(extract(hour from p_at at time zone bl_clock_tz())::numeric
                       + extract(minute from p_at at time zone bl_clock_tz())::numeric / 60.0);
$$;
revoke execute on function public.bl_time_label(timestamptz) from public, anon, authenticated;

-- The occurrences that count as "on today" now: LIVE, starting today (and not over), or starting within the
-- banner lead. One per event (the earliest). Active events at active places only.
create or replace function public.bl_events_now(p_location text default null)
returns table (event_id text, occurs_on date, starts_at timestamptz, ends_at timestamptz, live boolean)
language sql stable set search_path = public as $$
  with c as (select bl_now() as now, bl_clock_tz() as tz,
                    greatest(0, coalesce(bl_cfg('events.banner_lead_hours'), 3)) as lead)
  select distinct on (o.event_id) o.event_id, o.occurs_on, o.starts_at, o.ends_at,
         (o.starts_at <= c.now and o.ends_at > c.now) as live
    from c, bl_event_occurrences(c.now) o
    join place_events e on e.id = o.event_id and e.active
    join locations l on l.id = e.location_id and coalesce(l.active, true)
   where (p_location is null or e.location_id = p_location)
     and o.ends_at > c.now
     and (o.starts_at <= c.now
          or (o.starts_at at time zone c.tz)::date = (c.now at time zone c.tz)::date
          or o.starts_at <= c.now + make_interval(secs => (c.lead * 3600)::double precision))
   order by o.event_id, o.starts_at;
$$;
revoke execute on function public.bl_events_now(text) from public, anon, authenticated;

-- One event occurrence as JSON for a player
create or replace function public.bl_event_json(p_uid uuid, e place_events, p_on date, p_s timestamptz, p_f timestamptz, p_live boolean)
returns jsonb language sql stable set search_path = public as $$
  select jsonb_build_object(
    'id', e.id, 'location_id', e.location_id, 'location_name', l.name, 'scene', l.scene, 'district', l.district,
    'title', bl_event_title(e.title, e.variants, p_on), 'description', e.description, 'kind', e.kind, 'icon', e.icon,
    'occurs_on', p_on, 'starts_at', p_s, 'ends_at', p_f, 'live', p_live,
    'time_label', bl_time_label(p_s) || ' – ' || bl_time_label(p_f),
    'starts_label', bl_time_label(p_s),
    'ticket_price', e.ticket_price, 'free', e.ticket_price = 0, 'capacity', e.capacity,
    'sold', (select count(*) from event_tickets t where t.event_id = e.id and t.occurs_on = p_on),
    'has_ticket', exists (select 1 from event_tickets t where t.event_id = e.id and t.occurs_on = p_on and t.user_id = p_uid),
    'perks', e.perks,
    'actions', coalesce((select jsonb_agg(coalesce(a.icon, '✨') || ' ' || a.name order by a.sort)
                           from activities a where a.requires_event in (e.kind, e.id) and l.scene = any (a.scenes)
                            and (cardinality(a.location_ids) = 0 or l.id = any (a.location_ids))), '[]'::jsonb))
  from locations l where l.id = e.location_id;
$$;
revoke execute on function public.bl_event_json(uuid, place_events, date, timestamptz, timestamptz, boolean) from public, anon, authenticated;

-- Can this player use an event-only card (requires_event = an event kind or id) at this place now?
-- {state: none | later | ticket | ok, event_id, occurs_on, title, starts_label, price, perks}
create or replace function public.bl_event_access(p_uid uuid, p_loc text, p_req text)
returns jsonb language plpgsql stable set search_path = public as $$
declare r record; v_best jsonb; v_rank int := 0; v_this int; v_has boolean;
begin
  if p_req is null or p_req = '' then return null; end if;
  for r in select n.*, e from bl_events_now(p_loc) n join place_events e on e.id = n.event_id
            where e.kind = p_req or e.id = p_req loop
    v_has := (r.e).ticket_price = 0 or exists (select 1 from event_tickets t where t.event_id = r.event_id
                                                 and t.occurs_on = r.occurs_on and t.user_id = p_uid);
    v_this := case when r.live and v_has then 3 when r.live then 2 else 1 end;
    if v_this > v_rank then
      v_rank := v_this;
      v_best := jsonb_build_object('state', case v_this when 3 then 'ok' when 2 then 'ticket' else 'later' end,
        'event_id', r.event_id, 'occurs_on', r.occurs_on, 'title', bl_event_title((r.e).title, (r.e).variants, r.occurs_on),
        'starts_label', bl_time_label(r.starts_at), 'price', (r.e).ticket_price, 'perks', (r.e).perks,
        'has_ticket', v_has);
    end if;
  end loop;
  return coalesce(v_best, '{"state": "none"}'::jsonb);
end $$;
revoke execute on function public.bl_event_access(uuid, text, text) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 4. RPCs
-- ---------------------------------------------------------------------
create or replace function public.events_on_today(p_location text default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid();
begin
  return coalesce((
    select jsonb_agg(bl_event_json(v_uid, e, n.occurs_on, n.starts_at, n.ends_at, n.live)
                     order by n.live desc, n.starts_at, e.sort, e.id)
      from bl_events_now(p_location) n join place_events e on e.id = n.event_id), '[]'::jsonb);
end $$;
revoke execute on function public.events_on_today(text) from public, anon;
grant execute on function public.events_on_today(text) to authenticated, service_role;

create or replace function public.event_buy_ticket(p_event text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_me   profiles := bl_me();
  e      place_events;
  l      locations;
  n      record;
  v_sold int;
  v_bank bigint := 0;
  v_cash bigint := 0;
  t      event_tickets;
  v_title text;
begin
  select * into e from place_events where id = p_event and active for update;
  if not found then
    raise exception 'That event doesn''t exist.' using errcode = 'P0001', hint = 'no_event';
  end if;
  select * into l from locations where id = e.location_id;
  if not coalesce(l.active, true) then
    raise exception '% is closed for now. Check back soon.', l.name using errcode = 'P0001', hint = 'inactive';
  end if;
  select * into n from bl_events_now(e.location_id) x where x.event_id = e.id;
  if not found then
    raise exception 'There''s no % on today.', e.title using errcode = 'P0001', hint = 'no_occurrence';
  end if;
  v_title := bl_event_title(e.title, e.variants, n.occurs_on);
  if e.ticket_price = 0 then
    return jsonb_build_object('free', true, 'message', v_title || ' is free. Just show up!',
                              'event', bl_event_json(v_me.id, e, n.occurs_on, n.starts_at, n.ends_at, n.live));
  end if;
  if exists (select 1 from event_tickets where event_id = e.id and user_id = v_me.id and occurs_on = n.occurs_on) then
    raise exception 'You already have a ticket for %.', v_title using errcode = 'P0001', hint = 'already_have';
  end if;
  select count(*) into v_sold from event_tickets where event_id = e.id and occurs_on = n.occurs_on;
  if e.capacity is not null and v_sold >= e.capacity then
    raise exception '% is sold out.', v_title using errcode = 'P0001', hint = 'sold_out';
  end if;
  -- bank first, then cash (like the car dealer)
  v_bank := least(greatest(v_me.bank, 0), e.ticket_price);
  v_cash := e.ticket_price - v_bank;
  if v_cash > v_me.cash then
    raise exception 'Not enough money. A ticket costs % and you have % (bank % + cash %).', bl_naira(e.ticket_price),
      bl_naira(v_me.bank + v_me.cash), bl_naira(v_me.bank), bl_naira(v_me.cash) using errcode = 'P0001', hint = 'insufficient';
  end if;
  if v_bank > 0 then
    perform bl_add_money(v_me.id, 'bank', -v_bank, 'event_ticket', jsonb_build_object('event', e.id, 'on', n.occurs_on));
  end if;
  if v_cash > 0 then
    perform bl_add_money(v_me.id, 'cash', -v_cash, 'event_ticket', jsonb_build_object('event', e.id, 'on', n.occurs_on));
  end if;
  insert into event_tickets (event_id, user_id, occurs_on, price) values (e.id, v_me.id, n.occurs_on, e.ticket_price)
  returning * into t;
  return jsonb_build_object(
    'message', 'Ticket bought for ' || v_title || ' (' || bl_naira(e.ticket_price) || '). '
               || case when n.live then 'It''s on now, go!' else 'Starts ' || bl_time_label(n.starts_at) || '.' end,
    'ticket', to_jsonb(t), 'from_bank', v_bank, 'from_cash', v_cash,
    'event', bl_event_json(v_me.id, e, n.occurs_on, n.starts_at, n.ends_at, n.live));
end $$;
revoke execute on function public.event_buy_ticket(text) from public, anon;
grant execute on function public.event_buy_ticket(text) to authenticated, service_role;

-- ---------------------------------------------------------------------
-- 5. Seed events (once per id; the admin edits them in Content -> Events)
-- ---------------------------------------------------------------------
insert into public.place_events (id, location_id, title, description, kind, icon, recurrence, weekday, start_time, end_time,
                                 ticket_price, capacity, perks, variants, sort)
select v.id, v.loc, v.title, v.descr, v.kind, v.icon, 'weekly', v.wd, v.st, v.et, v.price, v.cap, v.perks::jsonb, v.variants, v.sort
  from (values
  ('bendel_home_match', 'ogbemudia_stadium', 'Bendel Insurance vs {variant}',
   'NPFL home match at Ogbemudia. The Benin Arsenal, drums from the popular stand, suya at the gate.', 'match', '⚽', 6, 16, 18, 1000, 5000,
   '{"effects": {"fun": 15, "social": 10}, "street_cred": 1}',
   E'Enyimba\nRangers International\nRivers United\nKano Pillars\nShooting Stars\nRemo Stars\nLobi Stars\nPlateau United', 10),
  ('amapiano_fri', 'club_360', 'Amapiano Night',
   'Friday at 360 Signature: DJ Ekpen on the decks, MC Lightning on the mic, log drums till 4.', 'club_night', '🎶', 4, 22, 4, 10000, 300,
   '{"effects": {"fun": 15, "social": 15}, "street_cred": 2}', '', 20),
  ('amapiano_sat', 'club_360', 'Amapiano Night',
   'Saturday at 360 Signature: the big one. Sparklers, bottles, the whole of GRA in one room.', 'club_night', '🎶', 5, 22, 4, 10000, 300,
   '{"effects": {"fun": 15, "social": 15}, "street_cred": 2}', '', 21),
  ('oba_market_day', 'oba_market', 'Big market day',
   'Saturday is the big day at Oba Market: traders from every village, best prices, plenty noise.', 'market_day', '🧺', 5, 7, 18, 0, null,
   '{"effects": {"social": 10, "fun": 5}}', '', 30),
  ('tulip_owambe', 'golden_tulip', 'Sunday owambe',
   'A big Bini wedding reception in the hall: aso-ebi, jollof, live highlife band and plenty spraying.', 'owambe', '💃🏾', 6, 13, 19, 0, null,
   '{"effects": {"fun": 15, "social": 20, "hunger": 20}, "street_cred": 1}', '', 40),
  ('kada_premiere', 'kada_plaza', 'New Nollywood premiere',
   'Friday night premiere at Kada Cinemas: red carpet, the cast in the lobby, the new one everybody is talking about.', 'premiere', '🎬', 4, 18, 23, 5000, 120,
   '{"effects": {"fun": 15, "social": 10}, "street_cred": 1}', '', 50),
  ('protea_pool_party', 'protea_hotel', 'Pool party',
   'Saturday afternoon by the pool at Protea: DJ, cocktails, small chops, everybody looking fresh.', 'party', '🏊🏾', 5, 13, 19, 15000, 150,
   '{"effects": {"fun": 15, "social": 15, "stress": -10}, "street_cred": 1}', '', 60),
  -- hidden clubs get their nights too (they never show while the place is hidden)
  ('medici_ladies', 'club_de_medici', 'Ladies'' Night', 'Thursday at Club De Medici: ladies free before midnight.', 'club_night', '🥂', 3, 22, 4, 5000, 250,
   '{"effects": {"fun": 10, "social": 15}, "street_cred": 1}', '', 70),
  ('rome_saturday', 'rome_club', 'Rome Saturday', 'The biggest club in Benin on a Saturday night.', 'club_night', '🎶', 5, 22, 4, 10000, 500,
   '{"effects": {"fun": 15, "social": 15}, "street_cred": 2}', '', 71),
  ('owambe_republic_fri', 'owambe_republic', 'Owambe Friday', 'Highlife and Afrobeats till dawn.', 'club_night', '💃🏾', 4, 22, 4, 5000, 250,
   '{"effects": {"fun": 15, "social": 15}, "street_cred": 1}', '', 72)
  ) as v(id, loc, title, descr, kind, icon, wd, st, et, price, cap, perks, variants, sort)
 where exists (select 1 from public.locations where id = v.loc)
on conflict (id) do nothing;

-- Event-only action cards (bigger effects; open only while the event is LIVE and you have a ticket / it's free)
insert into public.activities (id, name, scenes, home_only, cost, game_minutes, effects, night_only, sort, max_seconds, min_seconds,
                               scale_by_need, location_ids, risky, rush, icon, requires_event) values
('watch_match_live', 'Watch the match live', '{stadium}', false, 0, 120,
 '{"fun": 55, "social": 40, "stress": -20, "energy": -8, "bladder": -10}', false, 400, 15, 10, false, '{}', false, '{}', '⚽', 'match'),
('lead_the_chant', 'Lead the chant', '{stadium}', false, 0, 30,
 '{"fun": 35, "social": 35, "energy": -10, "street_cred": 2}', false, 401, 8, 5, false, '{}', false, '{}', '📣', 'match'),
('amapiano_vip', 'VIP at Amapiano Night', '{club}', false, 80000, 120,
 '{"fun": 60, "social": 50, "stress": -25, "energy": -10, "bladder": -15, "street_cred": 3}', false, 402, 15, 10, false, '{}', false, '{}', '🎶', 'club_night'),
('amapiano_dance', 'Dance at Amapiano Night', '{club}', false, 0, 60,
 '{"fun": 45, "social": 35, "energy": -15, "hygiene": -8}', false, 403, 12, 6, false, '{}', false, '{}', '🕺🏾', 'club_night'),
('market_day_bargains', 'Market day bargains', '{market}', false, 0, 45,
 '{"fun": 25, "social": 30, "energy": -8}', false, 404, 10, 5, false, '{}', false, '{}', '🧺', 'market_day'),
('owambe_dance_spray', 'Dance and spray at the owambe', '{hotel}', false, 20000, 90,
 '{"fun": 50, "social": 50, "stress": -15, "energy": -12, "street_cred": 2}', false, 405, 14, 8, false, '{}', false, '{}', '💃🏾', 'owambe'),
('owambe_jollof', 'Party jollof and small chops', '{hotel}', false, 0, 30,
 '{"hunger": 60, "fun": 15, "social": 15}', false, 406, 8, 4, false, '{}', false, '{}', '🍛', 'owambe'),
('premiere_red_carpet', 'Red carpet premiere', '{cinema}', false, 0, 150,
 '{"fun": 60, "social": 30, "stress": -18}', false, 407, 15, 10, false, '{}', false, '{}', '🎬', 'premiere'),
('pool_party', 'Pool party vibes', '{hotel}', false, 0, 90,
 '{"fun": 55, "social": 45, "stress": -20, "hygiene": 10, "energy": -10}', false, 408, 14, 8, false, '{}', false, '{}', '🏊🏾', 'party')
on conflict (id) do nothing;

insert into public.zone_actions (id, zone_id, kind, ref, label, sort)
select v.id, v.zone, 'activity', v.ref, null, v.sort
  from (values
  ('stadium.popular.watch_match_live', 'stadium.popular', 'watch_match_live', -2),
  ('stadium.popular.lead_the_chant', 'stadium.popular', 'lead_the_chant', -1),
  ('club.vip.amapiano_vip', 'club.vip', 'amapiano_vip', -1),
  ('club.dance.amapiano_dance', 'club.dance', 'amapiano_dance', -1),
  ('market.traders.market_day_bargains', 'market.traders', 'market_day_bargains', -1),
  ('hotel.restaurant.owambe_dance_spray', 'hotel.restaurant', 'owambe_dance_spray', -2),
  ('hotel.restaurant.owambe_jollof', 'hotel.restaurant', 'owambe_jollof', -1),
  ('cinema.screen.premiere_red_carpet', 'cinema.screen', 'premiere_red_carpet', -1),
  ('hotel.pool.pool_party', 'hotel.pool', 'pool_party', -1)
  ) as v(id, zone, ref, sort)
 where exists (select 1 from public.place_zones where id = v.zone)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------
-- 6. place_interior (live definition + event-only cards)
-- ---------------------------------------------------------------------
create or replace function public.place_interior(p_location text default null::text)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
declare
  v_uid   uuid := bl_require_uid();
  v_me    profiles;
  l       locations;
  v_open  boolean;
  v_closed_for text;
  v_night boolean := (bl_game_clock()->>'is_night')::boolean;
  v_part  text := bl_day_part();
  v_here  boolean;
  v_home  boolean;
  v_zones jsonb;
begin
  select * into v_me from profiles where id = v_uid;
  if not found then
    raise exception 'You haven''t created your Sim yet. Create one first.' using errcode = 'P0001', hint = 'no_profile';
  end if;
  l := bl_location(coalesce(p_location, v_me.location_id));
  v_open := bl_place_open(l);
  v_closed_for := case when not coalesce(l.active, true) then 'Closed for now' else 'Opens ' || bl_hour_label(l.open_hour) end;
  v_here := v_me.location_id = l.id and v_me.travel_to is null;
  v_home := v_me.home_location_id = l.id;

  with z as (
    select distinct on (pz.zone_key) pz.*
      from place_zones pz
     where pz.scene = l.scene or pz.location_id = l.id
     order by pz.zone_key, (pz.location_id is not null) desc
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', z.id, 'key', z.zone_key, 'label', z.label, 'icon', z.icon, 'prop', z.prop,
           'x', z.x, 'z', z.z, 'w', z.w, 'd', z.d, 'rot', z.rot, 'note', z.note,
           'actions', coalesce((
             select jsonb_agg(act order by s1, s2) from (
               -- activities (L4: event-only cards show only on a day their event is on here)
               select za.sort as s1, a.sort as s2, jsonb_build_object(
                        'id', za.id, 'kind', 'activity', 'ref', a.id,
                        'name', coalesce(za.label, a.name), 'icon', coalesce(za.icon, a.icon, '✨'),
                        'cost', a.cost, 'effects', case when ev.acc is null then a.effects
                                                    else bl_effects_add(a.effects, coalesce(ev.acc->'perks'->'effects', '{}'::jsonb))
                                                         || jsonb_build_object('street_cred', coalesce((a.effects->>'street_cred')::int, 0)
                                                                                + coalesce((ev.acc->'perks'->>'street_cred')::int, 0)) end,
                        'game_minutes', a.game_minutes,
                        'max_seconds', a.max_seconds, 'min_seconds', a.min_seconds, 'scale_by_need', a.scale_by_need,
                        'night_only', a.night_only, 'risky', a.risky, 'home_only', a.home_only,
                        'rush', case when a.rush = '{}'::jsonb then null else a.rush - 'line' end,
                        'event', case when ev.acc is null then null
                                      else jsonb_build_object('id', ev.acc->>'event_id', 'title', ev.acc->>'title',
                                                              'state', ev.acc->>'state', 'price', ev.acc->'price') end,
                        'locked', case
                          when a.home_only and not v_home then 'Only in your own home'
                          when not a.home_only and not v_open then v_closed_for
                          when a.night_only and not v_night then 'Night only'
                          when ev.acc->>'state' = 'later' then 'Starts ' || (ev.acc->>'starts_label')
                          when ev.acc->>'state' = 'ticket' then 'Needs a ticket'
                          else null end) as act
                 from zone_actions za join activities a on a.id = za.ref
                 left join lateral (select bl_event_access(v_uid, l.id, a.requires_event) as acc) ev on true
                where za.zone_id = z.id and za.kind = 'activity' and za.active
                  and l.scene = any (a.scenes)
                  and (cardinality(a.location_ids) = 0 or l.id = any (a.location_ids))
                  and (a.requires_event is null or coalesce(ev.acc->>'state', 'none') <> 'none')
               union all
               -- shop items sold at this place
               select za.sort, it.sort, jsonb_build_object(
                        'id', za.id, 'kind', 'shop', 'ref', it.id,
                        'name', coalesce(za.label, it.name), 'icon', coalesce(za.icon, it.icon, '🛍️'),
                        'cost', it.price, 'effects', it.effects, 'category', it.category,
                        'owned', coalesce((select qty from inventory where user_id = v_uid and item_id = it.id), 0),
                        'locked', case when not v_open then v_closed_for else null end)
                 from zone_actions za join items it on it.id = za.ref
                where za.zone_id = z.id and za.kind = 'shop' and za.active and l.id = any (it.sold_at)
               union all
               -- job tracks that work here
               select za.sort, 0, jsonb_build_object(
                        'id', za.id, 'kind', 'job', 'ref', t.id,
                        'name', coalesce(za.label, case when v_me.job_id = t.id then 'Work a shift' else t.name || ' jobs' end),
                        'icon', coalesce(za.icon, t.emoji),
                        'mine', v_me.job_id = t.id,
                        'title', (select title from career_levels where track_id = t.id
                                   and level = case when v_me.job_id = t.id then v_me.job_level else 1 end),
                        'pay', (select round(pay_per_shift * bl_cfg('career.pay_mult')) from career_levels where track_id = t.id
                                 and level = case when v_me.job_id = t.id then v_me.job_level else 1 end),
                        'locked', null)
                 from zone_actions za join career_tracks t on t.id = za.ref
                where za.zone_id = z.id and za.kind = 'job' and za.active and t.active and l.id = any (t.location_ids)
               union all
               -- open a tab of the place sheet (bank counter, PoS, the whole shop...)
               select za.sort, 0, jsonb_build_object(
                        'id', za.id, 'kind', 'panel', 'ref', za.ref,
                        'name', coalesce(za.label, initcap(za.ref)), 'icon', coalesce(za.icon,
                          case za.ref when 'bank' then '🏦' when 'pos' then '💳' when 'shop' then '🛍️' when 'jobs' then '💼' else '›' end),
                        'locked', null)
                 from zone_actions za
                where za.zone_id = z.id and za.kind = 'panel' and za.active
                  and (za.ref in ('chat', 'inventory', 'activities') or za.ref = any (l.actions))
             ) q), '[]'::jsonb))
         order by z.sort, z.zone_key), '[]'::jsonb)
    into v_zones
    from z where z.active;

  return jsonb_build_object(
    'location', jsonb_build_object('id', l.id, 'name', l.name, 'district', l.district, 'scene', l.scene, 'blurb', l.blurb,
                                   'open_hour', l.open_hour, 'close_hour', l.close_hour),
    'here', v_here, 'home', v_home, 'open', v_open, 'active', coalesce(l.active, true),
    'opens', case when v_open then null else v_closed_for end,
    'hours', case when l.open_hour is null then null
                  else bl_hour_label(l.open_hour) || ' – ' || bl_hour_label(l.close_hour) end,
    'night', v_night, 'part', v_part,
    'moods', coalesce((select jsonb_agg(jsonb_build_object('icon', m.icon, 'line', m.line) order by (m.location_id is null), m.sort)
                         from place_moods m
                        where m.active and (m.scene = l.scene or m.location_id = l.id)
                          and (m.part = 'any' or m.part = v_part)), '[]'::jsonb),
    'events', coalesce((select jsonb_agg(bl_event_json(v_uid, e, n.occurs_on, n.starts_at, n.ends_at, n.live) order by n.live desc, n.starts_at)
                          from bl_events_now(l.id) n join place_events e on e.id = n.event_id), '[]'::jsonb),
    'zones', v_zones);
end $function$;
revoke execute on function public.place_interior(text) from public, anon;
grant execute on function public.place_interior(text) to authenticated, service_role;

-- ---------------------------------------------------------------------
-- 7. do_activity (live definition + event-only gate and perks)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.do_activity(p_activity text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_me     profiles := bl_me();
  a        activities;
  v_scene  text;
  v_until  timestamptz;
  v_eff    jsonb;
  v_used   text[] := '{}';
  r        record;
  v_pct    numeric;
  v_rent   boolean := false;
  v_msg    text;
  v_from   jsonb;
  v_secs   numeric;
  v_furn   jsonb;
  v_loc    locations;
  v_hour   numeric;
  v_robbed jsonb;
  v_hype   jsonb;
  v_round  int;
  v_ev     jsonb;
begin
  perform bl_assert_free(v_me);
  select * into a from activities where id = p_activity;
  if not found then
    raise exception 'That activity doesn''t exist.' using errcode = 'P0001';
  end if;
  -- P2: Shut down the club follows its admin settings
  if a.id = 'shut_down_club' then
    a.cost := greatest(0, round(bl_cfg('hype.shutdown_cost')))::bigint;
    a.effects := a.effects || jsonb_build_object('street_cred', greatest(0, round(bl_cfg('hype.shutdown_cred')))::int);
  end if;
  select * into v_loc from locations where id = v_me.location_id;
  v_scene := v_loc.scene;
  if not (v_scene = any(a.scenes)) then
    raise exception 'You can''t do "%" here. Go where it is offered.', a.name using errcode = 'P0001';
  end if;
  if cardinality(a.location_ids) > 0 and not (v_loc.id = any (a.location_ids)) then
    raise exception '"%" is only at %.', a.name,
      (select string_agg(name, ', ' order by sort) from locations where id = any (a.location_ids))
      using errcode = 'P0001', hint = 'wrong_place';
  end if;
  if a.home_only and v_me.location_id <> v_me.home_location_id then
    raise exception 'You can only do "%" in your own home.', a.name using errcode = 'P0001';
  end if;
  v_furn := bl_furniture_for(v_me.id, a.id);
  if a.home_only and a.needs_furniture and not (v_furn->>'owned')::boolean then
    raise exception 'You don''t have the furniture for "%" at home yet.', a.name
      using errcode = 'P0001', hint = 'no_furniture';
  end if;
  if a.night_only and not (bl_game_clock()->>'is_night')::boolean then
    raise exception '"%" is a night-time thing. Come back after dark.', a.name using errcode = 'P0001';
  end if;
  -- opening hours (after the night-only rule, so its message stays the same)
  if not a.home_only then
    perform bl_assert_place_open(v_loc);
  end if;
  -- L4: event-only cards (requires_event = an event kind or id): LIVE here, with a ticket or free
  if a.requires_event is not null then
    v_ev := bl_event_access(v_me.id, v_loc.id, a.requires_event);
    if v_ev->>'state' = 'none' then
      raise exception '"%" is only on during an event here.', a.name using errcode = 'P0001', hint = 'no_event';
    elsif v_ev->>'state' = 'later' then
      raise exception '"%" opens when % starts (%).', a.name, v_ev->>'title', v_ev->>'starts_label'
        using errcode = 'P0001', hint = 'event_later';
    elsif v_ev->>'state' = 'ticket' then
      raise exception 'You need a ticket for % first (%).', v_ev->>'title', bl_naira((v_ev->>'price')::bigint)
        using errcode = 'P0001', hint = 'no_ticket';
    end if;
  end if;
  -- rush hour: it can sell out (nothing is charged)
  if coalesce(a.rush->>'pct', '') <> '' and (a.rush->>'pct')::numeric > 0 then
    v_hour := (bl_game_clock()->>'hour')::numeric;
    if v_hour >= coalesce((a.rush->>'from')::numeric, 0) and v_hour < coalesce((a.rush->>'to')::numeric, 24)
       and bl_rand() < (a.rush->>'pct')::numeric / 100.0 then
      raise exception '%', coalesce(nullif(a.rush->>'line', ''), a.name || ' is sold out right now. Try again soon.')
        using errcode = 'P0001', hint = 'sold_out';
    end if;
  end if;
  if a.cost > 0 then
    perform bl_add_money(v_me.id, 'cash', -a.cost, 'activity', jsonb_build_object('activity', a.id));
  end if;

  v_eff := a.effects;
  for r in select it.id, it.name, it.effects->'boost'->a.id as bonus
             from inventory i join items it on it.id = i.item_id
            where i.user_id = v_me.id and i.qty > 0 and jsonb_typeof(it.effects->'boost'->a.id) = 'object'
            order by it.sort, it.id loop
    v_eff := v_eff || bl_effects_add(bl_need_effects(v_eff), bl_need_effects(r.bonus));
    perform bl_give_item(v_me.id, r.id, -1);
    v_used := v_used || r.name;
  end loop;
  -- L4: the event's perks on top
  if v_ev is not null and v_ev->>'state' = 'ok' then
    v_eff := v_eff || bl_effects_add(bl_need_effects(v_eff), bl_need_effects(v_ev->'perks'->'effects'));
    if coalesce((v_ev->'perks'->>'street_cred')::int, 0) <> 0 then
      v_eff := v_eff || jsonb_build_object('street_cred', coalesce((v_eff->>'street_cred')::int, 0) + (v_ev->'perks'->>'street_cred')::int);
    end if;
  end if;
  -- how well this piece rests you (foam mat < bed)
  if a.home_only and (v_furn->>'owned')::boolean and (v_furn->>'rest_pct')::numeric <> 100
     and coalesce((v_eff->>'energy')::numeric, 0) > 0 then
    v_eff := v_eff || jsonb_build_object('energy',
               round((v_eff->>'energy')::numeric * greatest(0, least(200, (v_furn->>'rest_pct')::numeric)) / 100, 1));
  end if;
  if v_me.rent_owed > 0 and bl_csv_has(bl_cfg_text('rent.owed_sleep_activities'), a.id)
     and coalesce((v_eff->>'energy')::numeric, 0) > 0 then
    v_pct := greatest(0, least(100, bl_cfg('rent.owed_sleep_energy_pct')));
    if v_pct < 100 then
      v_eff := v_eff || jsonb_build_object('energy', round((v_eff->>'energy')::numeric * v_pct / 100, 1));
      v_rent := true;
    end if;
  end if;

  v_from := bl_needs_snapshot(v_me);
  v_secs := bl_activity_seconds(v_me, a, a.effects);
  perform bl_adjust_needs(v_me.id, v_eff);
  if coalesce((v_eff->>'street_cred')::int, 0) <> 0 then
    update profiles set street_cred = greatest(0, street_cred + (v_eff->>'street_cred')::int) where id = v_me.id;
  end if;
  v_until := bl_set_busy_seconds(v_me.id, v_secs, a.name);
  update profiles set busy_needs_from = v_from where id = v_me.id;
  v_msg := 'You started "' || a.name || '"'
           || case when a.cost > 0 then ' (' || bl_naira(a.cost) || ').' else '. Enjoy!' end;
  if cardinality(v_used) > 0 then
    v_msg := v_msg || ' Used: ' || array_to_string(v_used, ', ') || '.';
  end if;
  if v_rent then
    v_msg := v_msg || ' The landlord keeps knocking: "Where my rent? You owe ' || bl_naira(v_me.rent_owed)
             || '!" You won''t rest well until you pay.';
  end if;
  -- Risky: flashing money here can attract the wrong boys (the usual street robbery roll at this place)
  if a.risky then
    v_robbed := bl_roll_street_robbery(v_me.id, v_loc.id, 'walk', 1.0);
    if v_robbed is not null then
      v_msg := v_msg || ' Omo! Somebody dipped hand for your pocket: ' || bl_naira((v_robbed->>'amount')::bigint) || ' gone.';
    end if;
  end if;
  -- P2: club spends get the hype man's announcement (server-side only); Shut down the club buys a round
  if v_scene = 'club' and bl_hype_kind(a.id) is not null then
    if a.id = 'shut_down_club' then
      v_round := bl_hype_round(v_me.id, v_loc.id);
      v_msg := v_msg || ' The DJ cuts the music, the MC calls your name: drinks on you for '
               || coalesce(v_round, 0) || case when v_round = 1 then ' other player' else ' other players' end || ' here!';
    end if;
    v_hype := bl_hype_announce(v_me.id, v_loc.id, bl_hype_kind(a.id), a.cost, 1, a.id = 'shut_down_club');
  end if;
  return jsonb_build_object('message', v_msg, 'busy_until', v_until, 'effects', v_eff,
                            'used', to_jsonb(v_used), 'rent_penalty', v_rent, 'real_seconds', v_secs,
                            'robbed', v_robbed, 'hype', v_hype,
                            'event', case when v_ev is null then null else v_ev - 'perks' end);
end $function$;
revoke execute on function public.do_activity(text) from public, anon;
grant execute on function public.do_activity(text) to authenticated, service_role;

-- ---------------------------------------------------------------------
-- 8. Admin: Content -> Events (live definitions + place_events, activities.requires_event, type ts_null)
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
  end::jsonb;
$function$;
revoke execute on function public.bl_admin_table_spec(text) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.bl_admin_check_value(p_col text, p_type text, p_val jsonb)
 RETURNS void
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
declare t text := jsonb_typeof(p_val); n numeric;
begin
  if t is null or t = 'null' then
    if p_type in ('text_null', 'int_null', 'num_null', 'ts_null') then return; end if;
    raise exception '% can''t be empty.', p_col using errcode = 'P0001', hint = 'bad_value';
  end if;
  case p_type
    when 'text', 'text_null' then
      if t <> 'string' then raise exception '% must be text.', p_col using errcode = 'P0001', hint = 'bad_value'; end if;
      if length(p_val #>> '{}') > 4000 then raise exception '% is too long.', p_col using errcode = 'P0001', hint = 'bad_value'; end if;
    when 'ts_null' then
      if t <> 'string' then raise exception '% must be a date and time.', p_col using errcode = 'P0001', hint = 'bad_value'; end if;
      begin
        perform (p_val #>> '{}')::timestamptz;
      exception when others then
        raise exception '% must be a date and time like 2026-10-10 16:00+01.', p_col using errcode = 'P0001', hint = 'bad_value';
      end;
    when 'bool' then
      if t <> 'boolean' then raise exception '% must be true or false.', p_col using errcode = 'P0001', hint = 'bad_value'; end if;
    when 'obj' then
      if t <> 'object' then raise exception '% must be a JSON object ({...}).', p_col using errcode = 'P0001', hint = 'bad_value'; end if;
    when 'arr' then
      if t <> 'array' or exists (select 1 from jsonb_array_elements(p_val) e where jsonb_typeof(e) <> 'string') then
        raise exception '% must be a list of text values.', p_col using errcode = 'P0001', hint = 'bad_value';
      end if;
    when 'int', 'int_null', 'money', 'num', 'num_null' then
      if t <> 'number' then raise exception '% must be a number.', p_col using errcode = 'P0001', hint = 'bad_value'; end if;
      n := p_val::text::numeric;
      if p_type not in ('num', 'num_null') and n <> trunc(n) then
        raise exception '% must be a whole number.', p_col using errcode = 'P0001', hint = 'bad_value';
      end if;
      if p_col <> 'sort' and n < 0 then
        raise exception '% can''t be negative.', p_col using errcode = 'P0001', hint = 'bad_value';
      end if;
      if abs(n) > 1e13 then raise exception '% is too big.', p_col using errcode = 'P0001', hint = 'bad_value'; end if;
      if p_col in ('resale_pct') and n > 100 then
        raise exception '% must be 0–100.', p_col using errcode = 'P0001', hint = 'bad_value';
      end if;
      if p_col = 'risk' and n > 1 then
        raise exception 'risk must be between 0 and 1.' using errcode = 'P0001', hint = 'bad_value';
      end if;
      if p_col = 'weekday' and n > 6 then
        raise exception 'weekday must be 0 (Monday) to 6 (Sunday).' using errcode = 'P0001', hint = 'bad_value';
      end if;
      if p_col in ('open_hour', 'close_hour', 'start_time', 'end_time') and n > 24 then
        raise exception '% must be an hour from 0 to 24.', p_col using errcode = 'P0001', hint = 'bad_value';
      end if;
    else
      raise exception 'Unknown column type %', p_type using errcode = 'P0001';
  end case;
end $function$;
revoke execute on function public.bl_admin_check_value(text, text, jsonb) from public, anon, authenticated;
