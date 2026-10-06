-- L4 events (20261006001800_events.sql). Rolled back. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/events_test.sql
-- Groups: 1 weekly recurrence in WAT (live, upcoming, ended, past midnight, WAT vs UTC date) · 2 hidden places' events
-- never show · 3 a ticket is charged once per occurrence (bank first) · 4 capacity · 5 event-only actions locked
-- without the event / a ticket, open with them (+ perks), free events need no ticket · 6 admin can edit, players can't.

-- move bl_now() to a Benin wall-clock time
create or replace function pg_temp.ev_at(p_wat text) returns void
language plpgsql as $$
begin
  perform set_config('bl.test_offset_seconds',
    extract(epoch from ((p_wat || ' Africa/Lagos')::timestamptz - now()))::text, true);
end $$;

create or replace function pg_temp.ev_ids(p_loc text default null) returns text[]
language sql as $$ select coalesce(array_agg(e->>'id' order by e->>'id'), '{}') from jsonb_array_elements(events_on_today(p_loc)) e $$;

create or replace function pg_temp.ev_get(p_id text, p_loc text default null) returns jsonb
language sql as $$ select e from jsonb_array_elements(events_on_today(p_loc)) e where e->>'id' = p_id $$;

-- the card for an activity inside a place, or null
create or replace function pg_temp.ev_card(p_loc text, p_ref text) returns jsonb
language sql as $$
  select a from jsonb_array_elements(place_interior(p_loc)->'zones') z, jsonb_array_elements(z->'actions') a
   where a->>'ref' = p_ref limit 1
$$;

create temp table t_ev (name text primary key, id uuid not null) on commit drop;
grant select on t_ev to authenticated;
create or replace function pg_temp.ev(p_name text) returns uuid
language sql as $$ select id from t_ev where name = p_name $$;

create or replace function pg_temp.ev_make(p_name text) returns uuid
language plpgsql as $$
declare v uuid := pg_temp.new_user(lower(p_name) || '@events.bl');
begin
  insert into t_ev values (p_name, v);
  perform pg_temp.login(v);
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform create_profile_v2(p_name, 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  update profiles set rent_owed = 0, location_id = 'ogbemudia_stadium', cash = 100000, bank = 500, busy_until = null where id = v;
  return v;
end $$;

do $$
begin
  perform pg_temp.ev_make('Ev_Osaro');
  perform pg_temp.ev_make('Ev_Eki');
  perform pg_temp.ev_make('Ev_Admin');
  update profiles set is_admin = true where id = pg_temp.ev('Ev_Admin');
  update game_config set value = '3' where key = 'events.banner_lead_hours';
  update game_config set value = 'false' where key = 'rent.enabled'; -- time travel would charge rent (rolled back)
  update game_config set value = 'true' where key = 'places.hours_enabled';
  update game_config set value = '"real"' where key = 'clock.mode';
  update game_config set value = '"Africa/Lagos"' where key = 'clock.timezone';
  -- known seed state
  update place_events set active = true, weekday = 6, start_time = 16, end_time = 18, ticket_price = 1000, capacity = 5000,
         recurrence = 'weekly', starts_at = null, ends_at = null where id = 'bendel_home_match';
  update place_events set active = true, weekday = 5, start_time = 22, end_time = 4, recurrence = 'weekly', starts_at = null, ends_at = null
   where id in ('amapiano_sat');
  update place_events set active = true, weekday = 4, start_time = 18, end_time = 23, ticket_price = 5000, capacity = 120,
         recurrence = 'weekly', starts_at = null, ends_at = null where id = 'kada_premiere';
  update place_events set active = true, weekday = 5, start_time = 7, end_time = 18, ticket_price = 0, recurrence = 'weekly',
         starts_at = null, ends_at = null where id = 'oba_market_day';
  update locations set active = true where id in ('ogbemudia_stadium', 'club_360', 'kada_plaza', 'oba_market');
  update locations set active = false where id = 'club_de_medici';
  perform set_config('bl.test_rand', '0.999', true);
end $$;

-- ---------- 1. recurrence in WAT ----------
do $$
declare e jsonb;
begin
  perform pg_temp.login(pg_temp.ev('Ev_Osaro'));
  -- Sunday 11 Oct 2026, 4:30 PM: the match is LIVE
  perform pg_temp.ev_at('2026-10-11 16:30');
  e := pg_temp.ev_get('bendel_home_match', 'ogbemudia_stadium');
  perform pg_temp.assert(e is not null and (e->>'live')::boolean, 'match LIVE at 4:30 PM Sunday: ' || coalesce(e::text, 'null'));
  perform pg_temp.assert(e->>'occurs_on' = '2026-10-11', 'occurrence date is the WAT date');
  perform pg_temp.assert((e->>'starts_at')::timestamptz = '2026-10-11 16:00 Africa/Lagos'::timestamptz, 'starts 4 PM WAT (15:00 UTC)');
  perform pg_temp.assert(e->>'title' like 'Bendel Insurance vs %' and e->>'title' not like '%{variant}%', 'title gets this week''s opponent: ' || (e->>'title'));
  perform pg_temp.assert(e->>'starts_label' = '4 PM', 'starts label: ' || (e->>'starts_label'));
  -- 10 AM the same day: on today, not live yet
  perform pg_temp.ev_at('2026-10-11 10:00');
  e := pg_temp.ev_get('bendel_home_match');
  perform pg_temp.assert(e is not null and not (e->>'live')::boolean, 'match on today, upcoming at 10 AM');
  -- 7 PM: over, gone
  perform pg_temp.ev_at('2026-10-11 19:00');
  perform pg_temp.assert(pg_temp.ev_get('bendel_home_match') is null, 'match gone after it ends');
  -- Tuesday: nothing at the stadium
  perform pg_temp.ev_at('2026-10-13 16:30');
  perform pg_temp.assert(pg_temp.ev_ids('ogbemudia_stadium') = '{}', 'no match on Tuesday');
  -- Saturday 11:30 PM and Sunday 2 AM: Saturday's Amapiano Night is LIVE (past midnight), occurrence = Saturday
  perform pg_temp.ev_at('2026-10-10 23:30');
  e := pg_temp.ev_get('amapiano_sat', 'club_360');
  perform pg_temp.assert(e is not null and (e->>'live')::boolean and e->>'occurs_on' = '2026-10-10', 'Amapiano Sat LIVE at 11:30 PM');
  perform pg_temp.ev_at('2026-10-11 02:00');
  e := pg_temp.ev_get('amapiano_sat', 'club_360');
  perform pg_temp.assert(e is not null and (e->>'live')::boolean and e->>'occurs_on' = '2026-10-10', 'still LIVE at 2 AM Sunday, Saturday''s night');
  -- 00:30 WAT Sunday is still Saturday in UTC: Sunday's match already counts as today (WAT)
  perform pg_temp.ev_at('2026-10-11 00:30');
  e := pg_temp.ev_get('bendel_home_match');
  perform pg_temp.assert(e is not null and e->>'occurs_on' = '2026-10-11', 'WAT date decides "today", not UTC');
  -- banner lead: Saturday 7 PM, Amapiano at 10 PM is today and within 3 h
  perform pg_temp.ev_at('2026-10-10 19:00');
  e := pg_temp.ev_get('amapiano_sat');
  perform pg_temp.assert(e is not null and not (e->>'live')::boolean, 'Amapiano upcoming at 7 PM');
  raise notice 'ok 1: weekly recurrence in WAT (live, upcoming, ended, past midnight, WAT date)';
end $$;

-- ---------- 2. hidden places' events never show ----------
do $$
declare r jsonb;
begin
  perform pg_temp.login(pg_temp.ev('Ev_Osaro'));
  perform pg_temp.ev_at('2026-10-08 23:00'); -- Thursday: Ladies' Night at the hidden Club De Medici
  perform pg_temp.assert(not ('medici_ladies' = any (pg_temp.ev_ids())), 'hidden club''s event not listed');
  perform pg_temp.assert(pg_temp.ev_ids('club_de_medici') = '{}', 'not listed for the place either');
  begin
    r := event_buy_ticket('medici_ladies');
    raise exception 'TEST FAILED: bought a ticket at a hidden place';
  exception when others then
    perform pg_temp.assert(sqlerrm not like 'TEST FAILED%', sqlerrm);
  end;
  -- players can't read hidden places' events through the table either
  set local role authenticated;
  perform pg_temp.assert(not exists (select 1 from place_events where id = 'medici_ladies'), 'RLS hides the row');
  reset role;
  update locations set active = true where id = 'club_de_medici';
  perform pg_temp.assert('medici_ladies' = any (pg_temp.ev_ids()), 'shows once the place is switched on');
  update locations set active = false where id = 'club_de_medici';
  update place_events set active = false where id = 'bendel_home_match';
  perform pg_temp.ev_at('2026-10-11 16:30');
  perform pg_temp.assert(pg_temp.ev_get('bendel_home_match') is null, 'inactive event not listed');
  update place_events set active = true where id = 'bendel_home_match';
  raise notice 'ok 2: hidden places'' (and inactive) events never show';
end $$;

-- ---------- 3. a ticket is charged once per occurrence ----------
do $$
declare a uuid := pg_temp.ev('Ev_Osaro'); r jsonb; p profiles; n int;
begin
  perform pg_temp.login(a);
  update profiles set cash = 100000, bank = 500 where id = a;
  perform pg_temp.ev_at('2026-10-11 15:00');
  r := event_buy_ticket('bendel_home_match');
  select * into p from profiles where id = a;
  perform pg_temp.assert(p.bank = 0 and p.cash = 99500, 'bank first (500), then cash (500): bank ' || p.bank || ' cash ' || p.cash);
  perform pg_temp.assert((r->'ticket'->>'occurs_on') = '2026-10-11' and (r->'ticket'->>'price')::int = 1000, 'returns the ticket: ' || r::text);
  perform pg_temp.assert((r->'event'->>'has_ticket')::boolean, 'event says you have a ticket');
  begin
    r := event_buy_ticket('bendel_home_match');
    raise exception 'TEST FAILED: second ticket';
  exception when others then
    perform pg_temp.assert(sqlerrm like 'You already have a ticket%', 'second buy refused: ' || sqlerrm);
  end;
  select * into p from profiles where id = a;
  perform pg_temp.assert(p.cash = 99500, 'charged once');
  select count(*) into n from ledger where user_id = a and reason = 'event_ticket';
  perform pg_temp.assert(n = 2, 'two ledger rows (bank + cash) for one ticket: ' || n);
  -- next Sunday is a new occurrence
  perform pg_temp.ev_at('2026-10-18 15:00');
  r := event_buy_ticket('bendel_home_match');
  perform pg_temp.assert((r->'ticket'->>'occurs_on') = '2026-10-18', 'next week''s ticket');
  -- free events need no ticket and charge nothing
  perform pg_temp.ev_at('2026-10-10 10:00');
  r := event_buy_ticket('oba_market_day');
  perform pg_temp.assert((r->>'free')::boolean and not exists (select 1 from event_tickets where event_id = 'oba_market_day'), 'free event: no ticket');
  -- not enough money
  update profiles set cash = 0, bank = 0 where id = a;
  perform pg_temp.ev_at('2026-10-09 17:00');
  begin
    r := event_buy_ticket('kada_premiere');
    raise exception 'TEST FAILED: bought with no money';
  exception when others then
    perform pg_temp.assert(sqlerrm like 'Not enough money%', sqlerrm);
  end;
  raise notice 'ok 3: one ticket per occurrence, bank first';
end $$;

-- ---------- 4. capacity ----------
do $$
declare r jsonb;
begin
  update place_events set capacity = 1 where id = 'kada_premiere';
  perform pg_temp.ev_at('2026-10-09 17:00');
  perform pg_temp.login(pg_temp.ev('Ev_Eki'));
  update profiles set cash = 100000 where id = pg_temp.ev('Ev_Eki');
  r := event_buy_ticket('kada_premiere');
  perform pg_temp.login(pg_temp.ev('Ev_Admin'));
  update profiles set cash = 100000 where id = pg_temp.ev('Ev_Admin');
  begin
    r := event_buy_ticket('kada_premiere');
    raise exception 'TEST FAILED: over capacity';
  exception when others then
    perform pg_temp.assert(sqlerrm like '%sold out%', 'sold out: ' || sqlerrm);
  end;
  perform pg_temp.assert((pg_temp.ev_get('kada_premiere')->>'sold')::int = 1, 'sold count');
  raise notice 'ok 4: capacity respected';
end $$;

-- ---------- 5. event-only actions ----------
do $$
declare a uuid := pg_temp.ev('Ev_Eki'); c jsonb; r jsonb; v_cred int; v_cred2 int;
begin
  perform pg_temp.login(a);
  update profiles set location_id = 'ogbemudia_stadium', busy_until = null, travel_to = null, cash = 100000 where id = a;
  -- Tuesday: no match, no card, refused
  perform pg_temp.ev_at('2026-10-13 16:30');
  perform pg_temp.assert(pg_temp.ev_card('ogbemudia_stadium', 'watch_match_live') is null, 'no card without an event');
  begin
    r := do_activity('watch_match_live');
    raise exception 'TEST FAILED: event action without an event';
  exception when others then
    perform pg_temp.assert(sqlerrm like '%only on during an event%', sqlerrm);
  end;
  -- Sunday 3 PM: the card shows, locked until kick-off
  perform pg_temp.ev_at('2026-10-11 15:00');
  c := pg_temp.ev_card('ogbemudia_stadium', 'watch_match_live');
  perform pg_temp.assert(c->>'locked' = 'Starts 4 PM', 'locked before kick-off: ' || coalesce(c::text, 'null'));
  begin
    r := do_activity('watch_match_live');
    raise exception 'TEST FAILED: before kick-off';
  exception when others then
    perform pg_temp.assert(sqlerrm like '%opens when%', sqlerrm);
  end;
  -- 4:30 PM, no ticket
  perform pg_temp.ev_at('2026-10-11 16:30');
  c := pg_temp.ev_card('ogbemudia_stadium', 'watch_match_live');
  perform pg_temp.assert(c->>'locked' = 'Needs a ticket', 'locked without a ticket: ' || coalesce(c::text, 'null'));
  begin
    r := do_activity('watch_match_live');
    raise exception 'TEST FAILED: without a ticket';
  exception when others then
    perform pg_temp.assert(sqlerrm like 'You need a ticket%', sqlerrm);
  end;
  -- with a ticket: open, perks added
  r := event_buy_ticket('bendel_home_match');
  c := pg_temp.ev_card('ogbemudia_stadium', 'watch_match_live');
  perform pg_temp.assert(c->>'locked' is null and c->'event'->>'state' = 'ok', 'open with a ticket: ' || c::text);
  perform pg_temp.assert((c->'effects'->>'fun')::numeric = 70, 'card shows the perk on top (55 + 15): ' || (c->'effects')::text);
  select street_cred into v_cred from profiles where id = a;
  r := do_activity('watch_match_live');
  perform pg_temp.assert((r->'effects'->>'fun')::numeric = 70 and (r->'effects'->>'street_cred')::int = 1, 'perks applied: ' || (r->'effects')::text);
  perform pg_temp.assert(r->'event'->>'event_id' = 'bendel_home_match', 'returns the event');
  select street_cred into v_cred2 from profiles where id = a;
  perform pg_temp.assert(v_cred2 = v_cred + 1, 'street cred from perks');
  -- free event (market day): open without a ticket
  update profiles set location_id = 'oba_market', busy_until = null where id = a;
  perform pg_temp.ev_at('2026-10-10 10:00');
  c := pg_temp.ev_card('oba_market', 'market_day_bargains');
  perform pg_temp.assert(c is not null and c->>'locked' is null, 'free event card open: ' || coalesce(c::text, 'null'));
  r := do_activity('market_day_bargains');
  -- the same card on a Monday: gone
  update profiles set busy_until = null where id = a;
  perform pg_temp.ev_at('2026-10-12 10:00');
  perform pg_temp.assert(pg_temp.ev_card('oba_market', 'market_day_bargains') is null, 'market day card gone on Monday');
  -- other market without the event: no card
  perform pg_temp.ev_at('2026-10-10 10:00');
  perform pg_temp.assert(pg_temp.ev_card('uselu_market', 'market_day_bargains') is null, 'no card at a market without the event');
  raise notice 'ok 5: event-only actions locked without event / ticket, open with them';
end $$;

-- ---------- 6. admin can edit, players can't ----------
do $$
declare r jsonb;
begin
  perform pg_temp.login(pg_temp.ev('Ev_Admin'));
  r := admin_row_upsert('place_events', '{"id": "bendel_home_match", "ticket_price": 1500}');
  perform pg_temp.assert((select ticket_price from place_events where id = 'bendel_home_match') = 1500, 'admin edits the price');
  r := admin_row_upsert('place_events', '{"id": "test_fest", "location_id": "oba_market", "title": "Test fest", "kind": "concert",
    "recurrence": "none", "starts_at": "2026-10-20 18:00+01", "ends_at": "2026-10-20 23:00+01", "ticket_price": 0, "perks": {}}');
  perform pg_temp.assert(exists (select 1 from place_events where id = 'test_fest' and recurrence = 'none'), 'admin adds a one-off event');
  perform pg_temp.assert(exists (select 1 from admin_audit where data->>'table' = 'place_events'), 'audited');
  perform pg_temp.ev_at('2026-10-20 19:00');
  perform pg_temp.assert('test_fest' = any (pg_temp.ev_ids('oba_market')), 'one-off event LIVE');
  r := admin_row_upsert('activities', '{"id": "match_day", "requires_event": null}');
  begin
    r := admin_row_upsert('place_events', '{"id": "test_fest", "weekday": 9}');
    raise exception 'TEST FAILED: weekday 9';
  exception when others then
    perform pg_temp.assert(sqlerrm like 'weekday must be%', sqlerrm);
  end;
  begin
    r := admin_row_upsert('place_events', '{"id": "test_fest", "starts_at": "soon"}');
    raise exception 'TEST FAILED: bad time';
  exception when others then
    perform pg_temp.assert(sqlerrm like '%date and time%', sqlerrm);
  end;
  perform pg_temp.login(pg_temp.ev('Ev_Osaro'));
  begin
    r := admin_row_upsert('place_events', '{"id": "bendel_home_match", "ticket_price": 0}');
    raise exception 'TEST FAILED: player edited an event';
  exception when others then
    perform pg_temp.assert(sqlerrm not like 'TEST FAILED%', sqlerrm);
  end;
  set local role authenticated;
  begin
    update place_events set ticket_price = 0 where id = 'bendel_home_match';
    raise exception 'TEST FAILED: direct update';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into event_tickets (event_id, user_id, occurs_on) values ('bendel_home_match', pg_temp.ev('Ev_Osaro'), '2026-10-25');
    raise exception 'TEST FAILED: direct ticket insert';
  exception when insufficient_privilege then null;
  end;
  reset role;
  perform pg_temp.assert((select ticket_price from place_events where id = 'bendel_home_match') = 1500, 'price unchanged by the player');
  perform pg_temp.assert(not has_function_privilege('authenticated', 'public.bl_event_access(uuid, text, text)', 'execute'), 'helpers revoked');
  perform pg_temp.assert(not has_function_privilege('anon', 'public.events_on_today(text)', 'execute'), 'anon can''t list events');
  perform pg_temp.assert(has_function_privilege('authenticated', 'public.event_buy_ticket(text)', 'execute'), 'players can buy');
  raise notice 'ok 6: admin edits (audited), players can''t';
end $$;

do $$ begin
  perform set_config('bl.test_offset_seconds', '', true);
  perform set_config('bl.test_rand', '', true);
end $$;
