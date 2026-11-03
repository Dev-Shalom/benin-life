-- Drive scene road events (20261114000100_drive.sql, docs/DRIVE.md). Rolled back. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/drive_test.sql
-- Groups: 1 settings · 2 not driving / switches · 3 limits (progress, gap, trip cap, daily cap, cooldown, pending resume) ·
-- 4 area boys · 5 police checkpoint · 6 go-slow (delays, savings, trip cap) · 7 beggar / hawker · 8 low cash · 9 turn back · 10 grants.
-- Times are pinned with bl.test_offset_seconds; every chance is forced to 0 or 100 when an outcome is tested.
create or replace function pg_temp.adv(p_secs double precision) returns void
language plpgsql as $$
begin
  perform set_config('bl.test_offset_seconds',
    (coalesce(nullif(current_setting('bl.test_offset_seconds', true), '')::double precision, 0) + p_secs)::text, true);
end $$;

create or replace function pg_temp.setc(p_key text, p_val jsonb) returns void
language sql as $$ update game_config set value = p_val where key = p_key $$;

-- a trip: mode, how far in (percent), total length in seconds; fresh drive_state unless p_keep
create or replace function pg_temp.trip(p_uid uuid, p_mode text, p_pct numeric, p_total int default 100, p_keep boolean default false) returns void
language plpgsql as $$
begin
  update profiles set travel_to = (select id from locations where id <> profiles.location_id order by id limit 1), travel_mode = p_mode,
         travel_started_at = bl_now() - make_interval(secs => p_total * p_pct / 100.0),
         travel_arrives_at = bl_now() - make_interval(secs => p_total * p_pct / 100.0) + make_interval(secs => p_total)
   where id = p_uid;
  if not p_keep then delete from drive_state where user_id = p_uid; end if;
end $$;

-- every road event on, odds 100 %, no limits in the way; the tests tighten what they need
create or replace function pg_temp.loose() returns void
language plpgsql as $$
begin
  perform pg_temp.setc('drive.enabled', 'true'); perform pg_temp.setc('drive.events_enabled', 'true');
  perform pg_temp.setc('drive.event_pct', '100'); perform pg_temp.setc('drive.max_per_day', '100'); perform pg_temp.setc('drive.max_per_trip', '5');
  perform pg_temp.setc('drive.cooldown_s', '0'); perform pg_temp.setc('drive.roll_gap_s', '0');
  perform pg_temp.setc('drive.min_progress_pct', '0'); perform pg_temp.setc('drive.max_progress_pct', '100');
  perform pg_temp.setc('drive.max_delay_s', '600'); perform pg_temp.setc('rent.enabled', 'false'); -- weekly rent is clock-dependent and would eat the low-cash player's money
  perform pg_temp.setc('drive.w_ambush', '0'); perform pg_temp.setc('drive.w_police', '0');
  perform pg_temp.setc('drive.w_goslow', '0'); perform pg_temp.setc('drive.w_beggar', '0');
end $$;

-- force one kind: only that weight stays above zero
create or replace function pg_temp.only(p_kind text) returns void
language plpgsql as $$
begin
  perform pg_temp.setc('drive.w_ambush', case when p_kind = 'ambush' then '10' else '0' end::jsonb);
  perform pg_temp.setc('drive.w_police', case when p_kind = 'police' then '10' else '0' end::jsonb);
  perform pg_temp.setc('drive.w_goslow', case when p_kind = 'goslow' then '10' else '0' end::jsonb);
  perform pg_temp.setc('drive.w_beggar', case when p_kind = 'beggar' then '10' else '0' end::jsonb);
end $$;

create or replace function pg_temp.hint_of(p_sql text) returns text
language plpgsql as $$
declare v_h text;
begin
  execute p_sql;
  return 'ok';
exception when others then
  if sqlerrm like 'TEST FAILED%' then raise; end if;
  get stacked diagnostics v_h = pg_exception_hint;
  return coalesce(nullif(v_h, ''), sqlerrm);
end $$;

create or replace function pg_temp.uid(p_name text) returns uuid
language plpgsql as $$ declare v uuid; begin select id into v from pg_temp.dr_u where name = p_name; return v; end $$;

create or replace function pg_temp.cash(p_uid uuid, p_cash bigint) returns void
language sql as $$ update profiles set cash = p_cash, health = 80, stress = 20, fun = 50, hunger = 50, needs_updated_at = bl_now() where id = p_uid $$;

create temp table dr_u (name text primary key, id uuid);

do $$
declare v uuid; r record;
begin
  for r in select * from (values ('a'), ('b')) x(n) loop
    v := pg_temp.new_user('dr_' || r.n || '@drive.bl');
    update game_config set value = '"lapo"' where key = 'origin.force_next';
    perform pg_temp.login(v);
    perform create_profile_v2('DR_' || r.n, 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
    perform choose_start_home('ekenwan_face_me');
    insert into dr_u values (r.n, v);
  end loop;
  perform pg_temp.cash(pg_temp.uid('a'), 1000000);
  perform pg_temp.cash(pg_temp.uid('b'), 1000);
  perform pg_temp.loose();
  perform pg_temp.login(pg_temp.uid('a'));
end $$;

-- ---------- 1. settings ----------
do $$
declare n int;
begin
  perform pg_temp.assert((select count(*) from game_config where category = 'drive') >= 50, 'drive settings seeded');
  select count(*) into n from game_config where category = 'drive'
     and (coalesce(label, '') = '' or coalesce(description, '') = '' or (kind in ('number', 'percent', 'naira', 'minutes') and (min is null or max is null)));
  perform pg_temp.assert(n = 0, 'every drive setting has a label, a description and a min and max (' || n || ' without)');
  perform pg_temp.assert((select count(*) from game_config where category = 'drive' and key not like 'drive.%') = 0, 'keys are prefixed drive.');
  perform pg_temp.assert((select count(*) from game_config where category = 'drive' and kind = 'bool') >= 9, 'switches are bool');
  perform pg_temp.assert((select count(*) from game_config where category = 'drive' and (label ilike '%lagos%' or description ilike '%lagos%')) = 0, 'no "Lagos" in settings text');
  perform pg_temp.assert(not exists (select 1 from jsonb_array_elements(bl_drive_card('ambush', 5000)->'choices') c where false), 'cards build');
  perform pg_temp.assert(bl_drive_card('ambush', 5000)::text not ilike '%lagos%' and bl_drive_card('police', 3000)::text not ilike '%lagos%'
                         and bl_drive_card('goslow', 0)::text not ilike '%lagos%' and bl_drive_card('beggar', 0)::text not ilike '%lagos%', 'no "Lagos" on the cards');
  perform pg_temp.assert(jsonb_array_length(bl_drive_card('ambush', 5000)->'choices') = 3, 'ambush has pay, drive off, police');
  perform pg_temp.setc('drive.ambush.police_on', 'false');
  perform pg_temp.assert(jsonb_array_length(bl_drive_card('ambush', 5000)->'choices') = 2, 'police option hides with its switch');
  perform pg_temp.setc('drive.ambush.police_on', 'true');
end $$;

-- ---------- 2. not driving, walking, switches ----------
do $$
declare r jsonb; a uuid := pg_temp.uid('a');
begin
  perform pg_temp.login(a);
  perform pg_temp.only('goslow');
  r := drive_event_roll();
  perform pg_temp.assert(r->>'reason' = 'not_driving' and r->'event' = 'null'::jsonb, 'no trip: no event');
  perform pg_temp.trip(a, 'walk', 50);
  r := drive_event_roll();
  perform pg_temp.assert(r->>'reason' = 'not_driving', 'walking: no event');
  perform pg_temp.trip(a, 'car', 50);
  perform pg_temp.setc('drive.events_enabled', 'false');
  r := drive_event_roll();
  perform pg_temp.assert(r->>'reason' = 'off', 'events off: nothing');
  perform pg_temp.setc('drive.events_enabled', 'true'); perform pg_temp.setc('drive.enabled', 'false');
  r := drive_event_roll();
  perform pg_temp.assert(r->>'reason' = 'off', 'drive off: nothing');
  perform pg_temp.setc('drive.enabled', 'true');
  r := drive_event_roll();
  perform pg_temp.assert(r->'event'->>'kind' = 'goslow', 'on again: a go-slow card (got ' || r::text || ')');
  perform pg_temp.assert(pg_temp.hint_of('select drive_event_choose(''bogus'')') = 'bad_choice', 'a choice that is not on the card is refused');
  perform pg_temp.assert((select pending is not null from drive_state where user_id = a), 'a refused choice keeps the card');
end $$;

-- ---------- 3. limits ----------
do $$
declare r jsonb; a uuid := pg_temp.uid('a'); k text;
begin
  perform pg_temp.login(a);
  perform pg_temp.loose(); perform pg_temp.only('goslow');
  -- progress window
  perform pg_temp.setc('drive.min_progress_pct', '15'); perform pg_temp.setc('drive.max_progress_pct', '85');
  perform pg_temp.trip(a, 'bus', 5);
  perform pg_temp.assert(drive_event_roll()->'event' = 'null'::jsonb, 'too early in the trip: no event');
  perform pg_temp.trip(a, 'bus', 95);
  perform pg_temp.assert(drive_event_roll()->'event' = 'null'::jsonb, 'too late in the trip: no event');
  perform pg_temp.trip(a, 'bus', 50);
  perform pg_temp.assert(drive_event_roll()->'event'->>'kind' = 'goslow', 'mid trip: an event');
  -- the same card comes back after a reload (resumed), without counting twice
  r := drive_event_roll();
  perform pg_temp.assert((r->>'resumed')::boolean and r->'event'->>'kind' = 'goslow', 'the waiting card is shown again');
  perform pg_temp.assert((select events_today from drive_state where user_id = a) = 1, 'resumed card is not counted twice');
  -- an unanswered card expires after its ttl, with no effect
  perform pg_temp.setc('drive.pending_ttl_s', '30');
  perform pg_temp.adv(40);
  perform pg_temp.assert(pg_temp.hint_of('select drive_event_choose(''wait'')') = 'expired', 'an old card cannot be answered');
  perform pg_temp.setc('drive.pending_ttl_s', '240');
  perform pg_temp.loose(); perform pg_temp.only('goslow');

  -- gap between checks
  perform pg_temp.setc('drive.roll_gap_s', '30'); perform pg_temp.setc('drive.event_pct', '0');
  perform pg_temp.trip(a, 'car', 50);
  perform pg_temp.adv(50);
  perform pg_temp.assert(drive_event_roll()->>'reason' = 'none', 'first check: rolled, no event at 0 %');
  perform pg_temp.assert(drive_event_roll()->>'reason' = 'too_soon', 'second check right away: too soon');
  perform pg_temp.adv(31);
  perform pg_temp.setc('drive.event_pct', '100');
  perform pg_temp.assert(drive_event_roll()->'event'->>'kind' = 'goslow', 'after the gap: an event');
  perform pg_temp.loose(); perform pg_temp.only('goslow');

  -- one event per trip (max_per_trip = 1)
  perform pg_temp.setc('drive.max_per_trip', '1');
  perform pg_temp.trip(a, 'car', 50);
  perform drive_event_roll(); perform drive_event_choose('wait');
  perform pg_temp.assert(drive_event_roll()->>'reason' = 'none', 'second event on one trip: refused');
  -- a new trip may have one again
  perform pg_temp.adv(5);
  perform pg_temp.trip(a, 'car', 51, 100, true);
  perform pg_temp.assert(drive_event_roll()->'event'->>'kind' = 'goslow', 'a new trip: allowed');
  perform drive_event_choose('wait');
  perform pg_temp.loose(); perform pg_temp.only('goslow');

  -- cooldown
  perform pg_temp.setc('drive.cooldown_s', '600');
  perform pg_temp.adv(5);
  perform pg_temp.trip(a, 'car', 52, 100, true);
  perform pg_temp.assert(drive_event_roll()->>'reason' = 'none', 'inside the cooldown: no event');
  perform pg_temp.adv(601);
  perform pg_temp.trip(a, 'car', 53, 100, true);
  perform pg_temp.assert(drive_event_roll()->'event'->>'kind' = 'goslow', 'after the cooldown: an event');
  perform drive_event_choose('wait');
  perform pg_temp.setc('drive.cooldown_s', '0');

  -- daily cap, and the next Benin day resets it
  perform pg_temp.trip(a, 'car', 50);
  update drive_state set events_today = 0 where user_id = a;
  delete from drive_state where user_id = a;
  perform pg_temp.setc('drive.max_per_day', '2');
  perform pg_temp.adv(86400 * 3);
  perform pg_temp.trip(a, 'car', 50); perform drive_event_roll(); perform drive_event_choose('wait');
  perform pg_temp.adv(2); perform pg_temp.trip(a, 'car', 50, 100, true); perform drive_event_roll(); perform drive_event_choose('wait');
  perform pg_temp.adv(2); perform pg_temp.trip(a, 'car', 50, 100, true);
  perform pg_temp.assert(drive_event_roll()->>'reason' = 'none', 'third event the same day: refused (cap 2)');
  perform pg_temp.assert((select events_today from drive_state where user_id = a) = 2, 'two events counted today');
  perform pg_temp.adv(86400);
  perform pg_temp.trip(a, 'car', 50, 100, true);
  perform pg_temp.assert(drive_event_roll()->'event'->>'kind' = 'goslow', 'next Benin day: the cap resets');
  perform drive_event_choose('wait');
  perform pg_temp.assert(pg_temp.hint_of('select drive_event_choose(''wait'')') = 'no_event', 'answering twice is refused');
  perform pg_temp.loose();
end $$;

-- ---------- 4. area boys ----------
do $$
declare r jsonb; a uuid := pg_temp.uid('a'); c0 bigint; c1 bigint; h0 numeric; h1 numeric; amt bigint;
begin
  perform pg_temp.login(a);
  perform pg_temp.loose(); perform pg_temp.only('ambush');
  perform pg_temp.setc('drive.ambush.pay_pct', '10'); perform pg_temp.setc('drive.ambush.pay_min', '1000'); perform pg_temp.setc('drive.ambush.pay_max', '30000');
  perform pg_temp.cash(a, 100000);
  perform pg_temp.trip(a, 'car', 50);
  r := drive_event_roll();
  perform pg_temp.assert(r->'event'->>'kind' = 'ambush', 'an ambush card');
  perform pg_temp.assert(r->'event'->'choices'->0->>'label' = 'Pay them ' || bl_naira(10000), 'demand 10 % of 100,000 = 10,000 on the card (' || (r->'event'->'choices'->0->>'label') || ')');
  r := drive_event_choose('pay');
  perform pg_temp.assert((r->>'cash_delta')::bigint = -10000 and (select cash from profiles where id = a) = 90000, 'paying takes exactly the demand');
  perform pg_temp.assert(exists (select 1 from ledger where user_id = a and reason = 'drive_ambush' and delta = -10000), 'the loss is in the ledger');
  perform pg_temp.assert(r->>'tone' = 'warn', 'tone warn');
  -- demand rails
  perform pg_temp.cash(a, 100000000); perform pg_temp.trip(a, 'car', 50);
  r := drive_event_roll();
  perform pg_temp.assert(r->'event'->'choices'->0->>'label' = 'Pay them ' || bl_naira(30000), 'demand capped at pay_max');
  perform drive_event_choose('pay');
  perform pg_temp.cash(a, 3000); perform pg_temp.trip(a, 'car', 50);
  r := drive_event_roll();
  perform pg_temp.assert(r->'event'->'choices'->0->>'label' = 'Pay them ' || bl_naira(1000), 'demand floored at pay_min');
  perform drive_event_choose('pay');

  -- drive off: escape
  perform pg_temp.cash(a, 100000); perform pg_temp.trip(a, 'car', 50);
  perform pg_temp.setc('drive.ambush.escape_pct', '100');
  perform drive_event_roll(); r := drive_event_choose('drive');
  perform pg_temp.assert((r->>'cash_delta')::bigint = 0 and r->>'tone' = 'good' and (select cash from profiles where id = a) = 100000, 'clean escape: nothing lost');
  -- drive off: fail = mult x demand + repair, health down
  perform pg_temp.cash(a, 100000); perform pg_temp.trip(a, 'car', 50);
  perform pg_temp.setc('drive.ambush.escape_pct', '0'); perform pg_temp.setc('drive.ambush.fail_mult', '2'); perform pg_temp.setc('drive.ambush.damage_cost', '8000');
  perform pg_temp.setc('drive.ambush.fail_health', '4');
  perform drive_event_roll(); r := drive_event_choose('drive');
  perform pg_temp.assert((r->>'cash_delta')::bigint = -28000 and (select cash from profiles where id = a) = 72000, 'failed escape: 2 x 10,000 + 8,000 repair (' || (r->>'cash_delta') || ')');
  perform pg_temp.assert((select health from profiles where id = a) < 80, 'failed escape: health down');
  perform pg_temp.assert(exists (select 1 from ledger where user_id = a and reason = 'drive_repair'), 'repair is in the ledger');
  -- losses never take more than the cash on hand
  perform pg_temp.cash(a, 2500); perform pg_temp.trip(a, 'car', 50);
  perform drive_event_roll(); r := drive_event_choose('drive');
  perform pg_temp.assert((select cash from profiles where id = a) = 0, 'cash never goes below zero (' || (select cash from profiles where id = a) || ')');
  -- police: in time / too late with a delay
  perform pg_temp.cash(a, 100000); perform pg_temp.trip(a, 'car', 50);
  perform pg_temp.setc('drive.ambush.police_pct', '100');
  perform drive_event_roll(); r := drive_event_choose('police');
  perform pg_temp.assert((r->>'cash_delta')::bigint = 0 and r->>'tone' = 'good', 'police in time: nothing lost');
  perform pg_temp.cash(a, 100000); perform pg_temp.trip(a, 'car', 50);
  perform pg_temp.setc('drive.ambush.police_pct', '0'); perform pg_temp.setc('drive.ambush.police_fail_pct', '50'); perform pg_temp.setc('drive.ambush.police_delay_s', '12');
  perform drive_event_roll();
  c0 := (select extract(epoch from travel_arrives_at) from profiles where id = a)::bigint;
  r := drive_event_choose('police');
  perform pg_temp.assert((r->>'cash_delta')::bigint = -5000, 'police too late: half the demand (' || (r->>'cash_delta') || ')');
  perform pg_temp.assert((r->>'delay_s')::int = 12 and (select extract(epoch from travel_arrives_at) from profiles where id = a)::bigint = c0 + 12, 'police too late: arrival 12 s later');
  -- police option switched off: refused
  perform pg_temp.setc('drive.ambush.police_on', 'false'); perform pg_temp.cash(a, 100000); perform pg_temp.trip(a, 'car', 50);
  perform drive_event_roll();
  perform pg_temp.assert(pg_temp.hint_of('select drive_event_choose(''police'')') = 'bad_choice', 'police choice refused when switched off');
  perform drive_event_choose('pay');
  perform pg_temp.setc('drive.ambush.police_on', 'true');
  -- the switch for the whole kind
  perform pg_temp.setc('drive.ambush_on', 'false'); perform pg_temp.cash(a, 100000); perform pg_temp.trip(a, 'car', 50);
  perform pg_temp.assert(drive_event_roll()->>'reason' = 'none', 'ambush switched off: no event when nothing else is on');
  perform pg_temp.setc('drive.ambush_on', 'true');
end $$;

-- ---------- 5. police checkpoint ----------
do $$
declare r jsonb; a uuid := pg_temp.uid('a');
begin
  perform pg_temp.login(a);
  perform pg_temp.loose(); perform pg_temp.only('police');
  perform pg_temp.setc('drive.police.fine', '5000'); perform pg_temp.setc('drive.police.settle', '3000');
  perform pg_temp.cash(a, 100000); perform pg_temp.trip(a, 'drop', 50);
  r := drive_event_roll();
  perform pg_temp.assert(r->'event'->>'kind' = 'police' and r->'event'->'choices'->1->>'label' = 'Settle ' || bl_naira(3000), 'police card with the settle price');
  perform pg_temp.setc('drive.police.papers_ok_pct', '100');
  r := drive_event_choose('papers');
  perform pg_temp.assert((r->>'cash_delta')::bigint = 0 and r->>'tone' = 'good', 'papers in order: waved on');
  perform pg_temp.setc('drive.police.papers_ok_pct', '0');
  perform pg_temp.cash(a, 100000); perform pg_temp.trip(a, 'drop', 50); perform drive_event_roll();
  r := drive_event_choose('papers');
  perform pg_temp.assert((r->>'cash_delta')::bigint = -5000, 'papers fail: the fine');
  perform pg_temp.cash(a, 100000); perform pg_temp.trip(a, 'drop', 50); perform drive_event_roll();
  r := drive_event_choose('settle');
  perform pg_temp.assert((r->>'cash_delta')::bigint = -3000 and (r->>'delay_s')::int = 0, 'settle: flat amount, no delay');
  perform pg_temp.setc('drive.police.argue_pct', '100');
  perform pg_temp.cash(a, 100000); perform pg_temp.trip(a, 'drop', 50); perform drive_event_roll();
  r := drive_event_choose('argue');
  perform pg_temp.assert((r->>'cash_delta')::bigint = 0 and r->>'tone' = 'good', 'argue won: free');
  perform pg_temp.setc('drive.police.argue_pct', '0'); perform pg_temp.setc('drive.police.argue_fine_mult', '2'); perform pg_temp.setc('drive.police.argue_delay_s', '15');
  perform pg_temp.cash(a, 100000); perform pg_temp.trip(a, 'drop', 50); perform drive_event_roll();
  r := drive_event_choose('argue');
  perform pg_temp.assert((r->>'cash_delta')::bigint = -10000 and (r->>'delay_s')::int = 15, 'argue lost: double fine and 15 s');
  perform pg_temp.assert((select stress from profiles where id = a) > 20, 'argue lost: stress up');
end $$;

-- ---------- 6. go-slow ----------
do $$
declare r jsonb; a uuid := pg_temp.uid('a'); t0 timestamptz; t1 timestamptz;
begin
  perform pg_temp.login(a);
  perform pg_temp.loose(); perform pg_temp.only('goslow');
  perform pg_temp.setc('drive.goslow.wait_s', '12'); perform pg_temp.setc('drive.goslow.wait_fun', '-2');
  perform pg_temp.cash(a, 100000); perform pg_temp.trip(a, 'keke', 40);
  t0 := (select travel_arrives_at from profiles where id = a);
  perform drive_event_roll(); r := drive_event_choose('wait');
  t1 := (select travel_arrives_at from profiles where id = a);
  perform pg_temp.assert(t1 = t0 + interval '12 seconds' and (r->>'delay_s')::int = 12, 'wait: 12 s later');
  perform pg_temp.assert((select fun from profiles where id = a) < 50, 'wait: fun down');
  perform pg_temp.assert((r->>'cash_delta')::bigint = 0, 'wait: free');
  -- shortcut works: sooner, but never closer than 3 s from now
  perform pg_temp.setc('drive.goslow.shortcut_pct', '100'); perform pg_temp.setc('drive.goslow.shortcut_save_s', '10');
  perform pg_temp.trip(a, 'keke', 40);
  t0 := (select travel_arrives_at from profiles where id = a);
  perform drive_event_roll(); r := drive_event_choose('shortcut');
  t1 := (select travel_arrives_at from profiles where id = a);
  perform pg_temp.assert(t1 = t0 - interval '10 seconds' and (r->>'delay_s')::int = -10 and r->>'tone' = 'good', 'shortcut: 10 s sooner');
  perform pg_temp.setc('drive.goslow.shortcut_save_s', '500');
  perform pg_temp.trip(a, 'keke', 90, 100);
  perform drive_event_roll(); perform drive_event_choose('shortcut');
  perform pg_temp.assert((select travel_arrives_at from profiles where id = a) >= bl_now() + interval '3 seconds', 'a shortcut never lands in the past');
  -- shortcut fails: later, a repair cost, stress
  perform pg_temp.setc('drive.goslow.shortcut_pct', '0'); perform pg_temp.setc('drive.goslow.shortcut_fail_s', '20'); perform pg_temp.setc('drive.goslow.shortcut_fail_cost', '4000');
  perform pg_temp.cash(a, 100000); perform pg_temp.trip(a, 'keke', 40);
  t0 := (select travel_arrives_at from profiles where id = a);
  perform drive_event_roll(); r := drive_event_choose('shortcut');
  perform pg_temp.assert((select travel_arrives_at from profiles where id = a) = t0 + interval '20 seconds' and (r->>'cash_delta')::bigint = -4000, 'failed shortcut: 20 s and the repair');
  -- delays are capped for the trip
  perform pg_temp.setc('drive.max_delay_s', '25'); perform pg_temp.setc('drive.max_per_trip', '5');
  perform pg_temp.trip(a, 'keke', 40);
  t0 := (select travel_arrives_at from profiles where id = a);
  perform drive_event_roll(); perform drive_event_choose('wait');           -- +12
  perform drive_event_roll(); r := drive_event_choose('shortcut');         -- would be +20, room is 13
  perform pg_temp.assert((r->>'delay_s')::int = 13, 'delay capped by room left on the trip (' || (r->>'delay_s') || ')');
  perform drive_event_roll(); r := drive_event_choose('wait');             -- no room
  perform pg_temp.assert((r->>'delay_s')::int = 0 and (select travel_arrives_at from profiles where id = a) = t0 + interval '25 seconds', 'no more delay once the cap is used');
  -- a card answered after the trip clock ran out: still allowed, the delay counts from now
  perform pg_temp.setc('drive.max_delay_s', '600'); perform pg_temp.setc('rent.enabled', 'false'); -- weekly rent is clock-dependent and would eat the low-cash player's money
  perform pg_temp.trip(a, 'keke', 50); perform drive_event_roll();
  perform pg_temp.adv(200);
  r := drive_event_choose('wait');
  perform pg_temp.assert((select travel_arrives_at from profiles where id = a) = bl_now() + interval '12 seconds', 'late answer: arrival is now + 12 s');
  -- a go-slow still happens to a player with no cash
  perform pg_temp.cash(a, 0); perform pg_temp.trip(a, 'keke', 40);
  perform pg_temp.assert(drive_event_roll()->'event'->>'kind' = 'goslow', 'a broke player still gets a go-slow');
  perform drive_event_choose('wait');
end $$;

-- ---------- 7. beggar / hawker ----------
do $$
declare r jsonb; a uuid := pg_temp.uid('a');
begin
  perform pg_temp.login(a);
  perform pg_temp.loose(); perform pg_temp.only('beggar');
  perform pg_temp.setc('drive.beggar.give', '500'); perform pg_temp.setc('drive.beggar.water_cost', '200');
  perform pg_temp.cash(a, 100000); perform pg_temp.trip(a, 'bus', 50);
  r := drive_event_roll();
  perform pg_temp.assert(r->'event'->>'kind' = 'beggar' and r->'event'->'choices'->0->>'label' = 'Give ' || bl_naira(500), 'beggar card');
  r := drive_event_choose('give');
  perform pg_temp.assert((r->>'cash_delta')::bigint = -500 and (select fun from profiles where id = a) > 50 and (select stress from profiles where id = a) < 20, 'give: pay, fun up, stress down');
  perform pg_temp.cash(a, 100000); perform pg_temp.trip(a, 'bus', 50); perform drive_event_roll();
  r := drive_event_choose('water');
  perform pg_temp.assert((r->>'cash_delta')::bigint = -200 and (select hunger from profiles where id = a) > 50, 'water: pay 200, hunger up');
  perform pg_temp.cash(a, 100000); perform pg_temp.trip(a, 'bus', 50); perform drive_event_roll();
  r := drive_event_choose('ignore');
  perform pg_temp.assert((r->>'cash_delta')::bigint = 0 and (select stress from profiles where id = a) >= 20, 'ignore: free, a pang of stress');
end $$;

-- ---------- 8. low cash ----------
do $$
declare r jsonb; b uuid := pg_temp.uid('b');
begin
  perform pg_temp.login(b);
  perform pg_temp.loose(); perform pg_temp.only('ambush');
  perform pg_temp.setc('drive.min_cash', '2000');
  perform pg_temp.cash(b, 1000); perform pg_temp.trip(b, 'car', 50);
  perform pg_temp.assert(drive_event_roll()->>'reason' = 'none', 'under the cash floor: no money event');
  perform pg_temp.setc('drive.min_cash', '500');
  perform pg_temp.assert(drive_event_roll()->'event'->>'kind' = 'ambush', 'above the floor: boys appear');
  perform drive_event_choose('pay');
  perform pg_temp.assert((select cash from profiles where id = b) >= 0, 'cash stays non-negative');
  perform pg_temp.setc('drive.min_cash', '2000');
end $$;

-- ---------- 9. turn back ----------
do $$
declare r jsonb; a uuid := pg_temp.uid('a'); loc text; cash0 bigint;
begin
  perform pg_temp.login(a);
  perform pg_temp.loose(); perform pg_temp.only('goslow');
  perform pg_temp.trip(a, 'car', 50);
  loc := (select location_id from profiles where id = a);
  perform drive_event_roll();
  r := drive_turn_back();
  perform pg_temp.assert((select travel_to is null and travel_arrives_at is null and location_id = loc from profiles where id = a), 'turned back: not travelling, same place');
  perform pg_temp.assert((select pending is null from drive_state where user_id = a), 'turn back clears the card');
  perform pg_temp.assert(pg_temp.hint_of('select drive_turn_back()') <> 'ok', 'not travelling: refused');
  perform pg_temp.trip(a, 'car', 100);
  perform pg_temp.adv(5);
  perform pg_temp.assert(pg_temp.hint_of('select drive_turn_back()') = 'arrived', 'already arrived: cannot turn back');
  perform pg_temp.setc('drive.turn_back_on', 'false');
  perform pg_temp.trip(a, 'car', 50);
  perform pg_temp.assert(pg_temp.hint_of('select drive_turn_back()') = 'off', 'switched off: refused');
  perform pg_temp.setc('drive.turn_back_on', 'true');
end $$;

-- ---------- 10. grants ----------
do $$
begin
  perform pg_temp.assert(not has_function_privilege('anon', 'public.drive_event_roll()', 'execute'), 'anon cannot roll');
  perform pg_temp.assert(not has_function_privilege('anon', 'public.drive_event_choose(text)', 'execute'), 'anon cannot choose');
  perform pg_temp.assert(has_function_privilege('authenticated', 'public.drive_event_choose(text)', 'execute'), 'players can choose');
  perform pg_temp.assert(not has_function_privilege('authenticated', 'public.bl_drive_card(text, bigint)', 'execute'), 'card builder is internal');
  perform pg_temp.assert(not has_table_privilege('authenticated', 'public.drive_state', 'select'), 'drive_state is not readable by players');
  perform pg_temp.assert((select relrowsecurity from pg_class where oid = 'public.drive_state'::regclass), 'drive_state has RLS');
  perform pg_temp.assert(not exists (select 1 from pg_trigger where tgrelid = 'public.profiles'::regclass and tgname ilike '%drive%'), 'no drive trigger on profiles');
  raise notice 'drive_test: all passed';
end $$;
