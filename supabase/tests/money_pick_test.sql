-- SP2 Pick the money (20261012001660_money_pick.sql). Rolled back. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/money_pick_test.sql
-- Time moves with bl.test_offset_seconds (clubs open 22:00 - 05:00; a drop lives 5 s, grace 1.5 s).
-- Groups: 1 grants / anon / helpers private / config / pools · 2 the drop: 20 % of the spray, out of the sprayed money,
-- 5 s, tiny spray no drop, single-note drop, VIP drop · 3 picking: ₦10k per tap to cash, ledger, rate cap by time, per
-- player cap, announcement once per player per drop with @username · 4 refusals: sprayer, wrong place, on the road,
-- jailed, bad taps, no drop; self pick switch · 5 expiry + grace, settle + top picker line once · 6 racing: the pool
-- never goes negative · 7 bigint (₦2T spray) · 8 RLS + live drops RPC · 9 picking off: no drop.

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

create or replace function pg_temp.advance(p_seconds numeric) returns void
language plpgsql as $$
declare v numeric := coalesce(nullif(current_setting('bl.test_offset_seconds', true), '')::numeric, 0) + p_seconds;
begin
  perform set_config('bl.test_offset_seconds', v::text, true);
end $$;

create or replace function pg_temp.sp_at(p_wd int, p_hour int) returns void
language plpgsql as $$
declare c jsonb; cur numeric; tgt numeric; delta numeric;
begin
  perform set_config('bl.test_offset_seconds', '', true);
  c := bl_game_clock();
  cur := (c->>'weekday')::numeric * 86400 + (c->>'hour')::numeric * 3600 + (c->>'minute')::numeric * 60;
  tgt := p_wd * 86400 + p_hour * 3600 + 1800;
  delta := ((tgt - cur) % 604800 + 604800) % 604800;
  perform set_config('bl.test_offset_seconds', delta::text, true);
end $$;

-- 1. grants / anon / config
do $$
declare f text;
begin
  foreach f in array array['money_pick(bigint,integer)', 'money_drops_live(text)'] loop
    perform pg_temp.assert(not has_function_privilege('anon', 'public.' || f, 'execute'), 'anon blocked ' || f);
    perform pg_temp.assert(has_function_privilege('authenticated', 'public.' || f, 'execute'), 'authenticated may ' || f);
  end loop;
  foreach f in array array['bl_money_drop_create(uuid,text,bigint,boolean)', 'bl_money_pick_line(text,text,text,bigint,text,text)',
                           'bl_money_drop_settle(bigint)'] loop
    perform pg_temp.assert(not has_function_privilege('anon', 'public.' || f, 'execute')
                           and not has_function_privilege('authenticated', 'public.' || f, 'execute'), 'helper private ' || f);
  end loop;
  perform pg_temp.assert(not has_table_privilege('authenticated', 'public.money_drop_picks', 'select')
                         and not has_table_privilege('anon', 'public.money_drop_picks', 'select'), 'money_drop_picks private');
  perform pg_temp.assert(has_table_privilege('authenticated', 'public.money_drops', 'select')
                         and not has_table_privilege('authenticated', 'public.money_drops', 'insert')
                         and not has_table_privilege('authenticated', 'public.money_drops', 'update')
                         and not has_table_privilege('anon', 'public.money_drops', 'select'), 'money_drops read-only for players');
  perform pg_temp.assert((select count(*) from game_config where category = 'club' and key in ('club.pick_enabled', 'club.pick_pct',
     'club.pick_seconds', 'club.pick_note', 'club.pick_grace_s', 'club.pick_max_taps_per_sec', 'club.pick_max_per_player',
     'club.pick_self', 'club.pick_summary', 'club.pick_poll_s')) = 10, 'all pick settings in Clubs');
  perform pg_temp.assert(bl_spray_num('club.pick_pct', 0) = 20 and bl_spray_num('club.pick_note', 0) = 10000
     and bl_spray_num('club.pick_seconds', 0) = 5 and bl_spray_num('club.pick_grace_s', 0) = 1.5
     and bl_spray_num('club.pick_max_taps_per_sec', 0) = 12 and bl_spray_num('club.pick_max_per_player', 0) = 50
     and not bl_cfg_bool('club.pick_self'), 'default numbers');
  perform pg_temp.assert((select count(*) from hype_templates where kind = 'pick' and active) >= 10, 'pick pool >= 10 lines');
  perform pg_temp.assert(not exists (select 1 from hype_templates where kind in ('pick', 'pick_top') and line not like '%@{user}%'), 'every line names @{user}');
  perform pg_temp.assert(exists (select 1 from hype_templates where kind = 'pick_top' and line like '%{amount}%'), 'top picker pool');
  raise notice 'ok 1: grants, helpers private, config, pools';
end $$;

set local role anon;
do $$
begin
  perform pg_temp.assert(pg_temp.hint_of($q$ select money_pick(1, 1) $q$) <> 'ok', 'anon refused money_pick');
  perform pg_temp.assert(pg_temp.hint_of($q$ select money_drops_live('club_raptor') $q$) <> 'ok', 'anon refused money_drops_live');
  perform pg_temp.assert(pg_temp.hint_of($q$ select 1 from money_drops limit 1 $q$) <> 'ok', 'anon cannot read money_drops');
end $$;
reset role;

do $$
declare
  v uuid := pg_temp.new_user('mp_ada@pick.bl');
  w uuid := pg_temp.new_user('mp_bob@pick.bl');
  x uuid := pg_temp.new_user('mp_cy@pick.bl');
  r jsonb; d money_drops; a place_announcements; c0 bigint; c1 bigint; n int; did bigint; d2 bigint;
begin
  perform set_config('bl.test_rand', '0.99', true);
  perform pg_temp.login(w);
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform create_profile_v2('Mp_Bob', 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  perform pg_temp.login(x);
  update game_config set value = '"nepo"' where key = 'origin.force_next';
  perform create_profile_v2('Mp_Cy', 'female', '{"gender":"female"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  perform pg_temp.login(v);
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform create_profile_v2('Mp_Ada', 'female', '{"gender":"female"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  update game_config set value = 'true' where key = 'places.hours_enabled';
  update game_config set value = '"real"' where key = 'clock.mode';
  update game_config set value = 'true' where key = 'hype.enabled';
  update game_config set value = '1000' where key = 'club.spray_min';
  update game_config set value = '10' where key = 'club.spray_cooldown_s';
  update game_config set value = 'false' where key = 'club.vip_spray_needs_booking';
  update game_config set value = 'true' where key = 'club.pick_enabled';
  update game_config set value = '20' where key = 'club.pick_pct';
  update game_config set value = '5' where key = 'club.pick_seconds';
  update game_config set value = '10000' where key = 'club.pick_note';
  update game_config set value = '1.5' where key = 'club.pick_grace_s';
  update game_config set value = '12' where key = 'club.pick_max_taps_per_sec';
  update game_config set value = '50' where key = 'club.pick_max_per_player';
  update game_config set value = 'false' where key = 'club.pick_self';
  update game_config set value = 'true' where key = 'club.pick_summary';
  perform pg_temp.sp_at(2, 23);  -- Wednesday 11:30 PM: the club is open
  update profiles set location_id = 'club_raptor', travel_to = null, cash = 5000000, jailed_until = null, hospitalized_until = null
   where id in (v, w, x);

  -- 2. the drop
  r := spray_custom('club_raptor', 1000000, false);
  did := (r->'drop'->>'id')::bigint;
  select * into d from money_drops where id = did;
  perform pg_temp.assert(d.total = 200000 and d.remaining = 200000 and d.note = 10000 and d.location_id = 'club_raptor'
     and d.sprayer = v and d.username = 'Mp_Ada' and not d.vip and not d.settled, 'drop = 20%: ' || to_jsonb(d)::text);
  perform pg_temp.assert(d.expires_at = d.created_at + interval '5 seconds' and d.created_at = bl_now(), 'lives 5 s');
  perform pg_temp.assert((r->'drop'->>'notes')::int = 20 and (r->'drop'->>'ms_left')::int = 5000, 'notes + ms_left in the result');
  perform pg_temp.assert((select cash from profiles where id = v) = 4000000, 'the sprayer pays the spray only, nothing extra');
  perform pg_temp.assert((select count(*) from ledger where user_id = v and reason = 'spray') = 1, 'one spray ledger row');
  -- tiny spray: 20% of ₦40k = ₦8k < one note -> no drop
  perform pg_temp.advance(11);
  r := spray_custom('club_raptor', 40000, false);
  perform pg_temp.assert(r->'drop' = 'null'::jsonb, 'tiny spray drops nothing: ' || r::text);
  -- ₦50k -> exactly one note
  perform pg_temp.advance(11);
  r := spray_custom('club_raptor', 50000, false);
  perform pg_temp.assert((r->'drop'->>'total')::bigint = 10000 and (r->'drop'->>'notes')::int = 1, 'single-note drop');
  -- VIP spray drops too (gold notes on the client)
  perform pg_temp.advance(11);
  r := spray_custom('club_raptor', 100000, true);
  perform pg_temp.assert((r->'drop'->>'vip')::boolean and (r->'drop'->>'total')::bigint = 20000, 'VIP drop: ' || r::text);
  raise notice 'ok 2: drop = 20%% out of the spray, 5 s, tiny none, single note, VIP';

  -- 3. picking (a fresh drop of 40 notes; time 0 of the drop)
  perform pg_temp.advance(11);
  r := spray_custom('club_raptor', 2000000, false);
  did := (r->'drop'->>'id')::bigint;
  perform pg_temp.login(w);
  c0 := (select cash from profiles where id = w);
  r := money_pick(did, 3);
  perform pg_temp.assert((r->>'picked')::bigint = 30000 and (r->>'taps')::int = 3 and (r->>'remaining')::bigint = 370000
     and (r->>'my_total')::bigint = 30000 and (r->>'first')::boolean, '3 taps = ₦30k: ' || r::text);
  perform pg_temp.assert((select cash from profiles where id = w) = c0 + 30000 and (r->>'cash_after')::bigint = c0 + 30000, 'to cash');
  perform pg_temp.assert((select bl_ledger_label(reason, meta) from ledger where user_id = w and reason = 'money_pick' order by id desc limit 1)
     = 'Picked money at Club Raptor', 'ledger label');
  select * into a from place_announcements where user_id = w and kind = 'pick' order by id desc limit 1;
  perform pg_temp.assert(a.id = (r->'hype'->>'id')::bigint and a.location_id = 'club_raptor' and a.text like '%@Mp_Bob%'
     and position('{' in a.text) = 0 and not a.global, 'announcement names @Mp_Bob: ' || coalesce(a.text, 'none'));
  perform pg_temp.assert(exists (select 1 from hype_template_recent where location_id = 'club_raptor' and kind = 'pick'), 'MC pick pool used');
  -- rate cap: at 0 s only floor(0.5 x 12) = 6 taps in total
  r := money_pick(did, 10);
  perform pg_temp.assert((r->>'taps')::int = 3 and (r->>'capped')::boolean and (r->>'my_taps')::int = 6 and r->'hype' = 'null'::jsonb,
    'rate cap at 0 s: ' || r::text);
  perform pg_temp.advance(1);  -- 1 s: floor(1.5 x 12) = 18 in total
  r := money_pick(did, 20);
  perform pg_temp.assert((r->>'taps')::int = 12 and (r->>'my_taps')::int = 18, 'rate cap at 1 s: ' || r::text);
  perform pg_temp.assert((select count(*) from place_announcements where user_id = w and kind = 'pick') = 1, 'one announcement per player per drop');
  -- per player cap
  update game_config set value = '20' where key = 'club.pick_max_per_player';
  perform pg_temp.advance(2);  -- 3 s: rate allows 42, the player cap 20
  r := money_pick(did, 30);
  perform pg_temp.assert((r->>'taps')::int = 2 and (r->>'my_total')::bigint = 200000, 'per player cap: ' || r::text);
  r := money_pick(did, 5);
  perform pg_temp.assert((r->>'taps')::int = 0 and (r->>'picked')::bigint = 0, 'nothing past the cap');
  update game_config set value = '50' where key = 'club.pick_max_per_player';
  -- a second picker gets their own announcement
  perform pg_temp.login(x);
  r := money_pick(did, 4);
  perform pg_temp.assert((r->>'picked')::bigint = 40000 and (r->>'remaining')::bigint = 160000 and (r->>'first')::boolean, 'second picker: ' || r::text);
  perform pg_temp.assert((select remaining from money_drops where id = did) = 160000, 'pool 400k - 200k - 40k');
  perform pg_temp.assert((select count(*) from place_announcements where user_id = x and kind = 'pick' and text like '%@Mp_Cy%') = 1, 'Cy announced once');
  raise notice 'ok 3: ₦10k per tap to cash, ledger, rate + per-player caps, one announcement per player per drop';
end $$;

-- the remaining-pool arithmetic in plain numbers (a fresh drop of 20 notes)
do $$
declare
  v uuid := (select id from profiles where username = 'Mp_Ada');
  w uuid := (select id from profiles where username = 'Mp_Bob');
  x uuid := (select id from profiles where username = 'Mp_Cy');
  r jsonb; did bigint; c0 bigint; a place_announcements; n int;
begin
  perform pg_temp.login(v);
  perform pg_temp.advance(11);
  r := spray_custom('club_raptor', 1000000, false);
  did := (r->'drop'->>'id')::bigint;
  perform pg_temp.advance(2);  -- allowance 30
  perform pg_temp.login(w);
  r := money_pick(did, 12);
  perform pg_temp.assert((r->>'remaining')::bigint = 80000 and (r->>'notes_left')::int = 8, '20 - 12 = 8 notes left: ' || r::text);
  perform pg_temp.login(x);
  r := money_pick(did, 5);
  perform pg_temp.assert((r->>'remaining')::bigint = 30000, 'then 3 left');

  -- 4. refusals
  perform pg_temp.login(v);
  perform pg_temp.assert(pg_temp.hint_of(format('select money_pick(%s, 1)', did)) = 'own_drop', 'sprayer cannot pick own drop');
  perform pg_temp.login(x);
  update profiles set location_id = 'national_museum' where id = x;
  perform pg_temp.assert(pg_temp.hint_of(format('select money_pick(%s, 1)', did)) = 'wrong_place', 'must be in the club');
  update profiles set location_id = 'club_raptor', travel_to = 'club_360' where id = x;
  perform pg_temp.assert(pg_temp.hint_of(format('select money_pick(%s, 1)', did)) = 'traveling', 'not on the road');
  update profiles set travel_to = null, jailed_until = bl_now() + interval '1 hour' where id = x;
  perform pg_temp.assert(pg_temp.hint_of(format('select money_pick(%s, 1)', did)) = 'jailed', 'not in a cell');
  update profiles set jailed_until = null where id = x;
  perform pg_temp.assert(pg_temp.hint_of(format('select money_pick(%s, -1)', did)) = 'bad_taps', 'negative taps');
  perform pg_temp.assert(pg_temp.hint_of(format('select money_pick(%s, 1001)', did)) = 'bad_taps', 'absurd taps');
  perform pg_temp.assert(pg_temp.hint_of(format('select money_pick(%s, null)', did)) = 'bad_taps', 'null taps');
  perform pg_temp.assert(pg_temp.hint_of('select money_pick(-42, 1)') = 'no_drop', 'unknown drop');
  perform pg_temp.assert((select remaining from money_drops where id = did) = 30000, 'refusals took nothing');
  raise notice 'ok 4: sprayer / wrong place / road / jail / bad taps / no drop refused';

  -- 5. expiry + grace, settle, top picker once
  perform pg_temp.advance(3.9);  -- 5.9 s after the drop: ended, but inside the 1.5 s grace
  r := money_pick(did, 1);
  perform pg_temp.assert((r->>'picked')::bigint = 10000 and not (r->>'expired')::boolean, 'late batch inside the grace counts: ' || r::text);
  perform pg_temp.advance(0.7);  -- 6.6 s: past 5 + 1.5
  r := money_pick(did, 1);
  perform pg_temp.assert((r->>'expired')::boolean and (r->>'picked')::bigint = 0 and (r->>'remaining')::bigint = 20000, 'expired: ' || r::text);
  perform pg_temp.assert((select settled from money_drops where id = did), 'settled on the first late call');
  select * into a from place_announcements where kind = 'pick_top' order by id desc limit 1;
  perform pg_temp.assert(a.user_id = w and a.amount = 120000 and a.text like '%@Mp_Bob%' and a.text like '%₦120,000%', 'top picker line: ' || coalesce(a.text, 'none'));
  select count(*) into n from place_announcements where kind = 'pick_top';
  perform pg_temp.login(w);
  r := money_pick(did, 0);
  perform pg_temp.assert((r->>'expired')::boolean and (select count(*) from place_announcements where kind = 'pick_top') = n, 'summary only once');
  -- live drops: none now
  perform pg_temp.assert(jsonb_array_length(money_drops_live('club_raptor')->'drops') = 0, 'nothing live after expiry');
  raise notice 'ok 5: expiry + grace, settled once with the top picker';

  -- 6. racing: 3 notes, two pickers asking for 3 each; the pool never goes negative and empties -> settled
  perform pg_temp.login(v);
  perform pg_temp.advance(11);
  r := spray_custom('club_raptor', 150000, false);
  did := (r->'drop'->>'id')::bigint;
  perform pg_temp.assert((r->'drop'->>'notes')::int = 3, '3 notes');
  perform pg_temp.login(w);
  r := money_pick(did, 3);
  perform pg_temp.assert((r->>'picked')::bigint = 30000 and (r->>'remaining')::bigint = 0 and (r->>'empty')::boolean, 'Bob takes all 3');
  perform pg_temp.login(x);
  c0 := (select cash from profiles where id = x);
  r := money_pick(did, 3);
  perform pg_temp.assert((r->>'picked')::bigint = 0 and (r->>'remaining')::bigint = 0 and (select cash from profiles where id = x) = c0,
    'Cy gets nothing, pool stays 0: ' || r::text);
  perform pg_temp.assert((select settled from money_drops where id = did), 'empty floor settles at once');
  perform pg_temp.assert(pg_temp.hint_of(format('update money_drops set remaining = -1 where id = %s', did)) <> 'ok', 'remaining can never be negative');
  perform pg_temp.assert(position('for update' in lower(pg_get_functiondef('public.money_pick(bigint,integer)'::regprocedure))) > 0, 'drop row locked');
  raise notice 'ok 6: racing pickers, pool never negative';

  -- self pick switch (captured on the drop)
  update game_config set value = 'true' where key = 'club.pick_self';
  perform pg_temp.login(v);
  perform pg_temp.advance(11);
  r := spray_custom('club_raptor', 100000, false);
  did := (r->'drop'->>'id')::bigint;
  r := money_pick(did, 2);
  perform pg_temp.assert((r->>'picked')::bigint = 20000, 'pick_self on: the sprayer may pick');
  update game_config set value = 'false' where key = 'club.pick_self';

  -- 7. bigint: a ₦2T spray drops ₦400B; the taps cap keeps payouts small
  update profiles set cash = 3000000000000 where id = v;
  perform pg_temp.advance(11);
  r := spray_custom('club_raptor', 2000000000000, false);
  did := (r->'drop'->>'id')::bigint;
  perform pg_temp.assert((r->'drop'->>'total')::bigint = 400000000000 and (r->'drop'->>'notes')::bigint = 40000000, '₦400B drop');
  perform pg_temp.assert((select cash from profiles where id = v) = 1000000000000, 'sprayer paid exactly ₦2T');
  perform pg_temp.login(w);
  perform pg_temp.advance(4.9);
  c0 := (select cash from profiles where id = w);
  r := money_pick(did, 1000);
  perform pg_temp.assert((r->>'taps')::int = 50 and (r->>'picked')::bigint = 500000 and (r->>'remaining')::bigint = 400000000000 - 500000,
    'capped at 50 taps: ' || r::text);
  perform pg_temp.assert((select cash from profiles where id = w) = c0 + 500000, 'bigint-safe credit');

  -- 8. RLS + live RPC
  r := money_drops_live('club_raptor');
  perform pg_temp.assert(jsonb_array_length(r->'drops') = 1 and (r->'drops'->0->>'id')::bigint = did
     and (r->'drops'->0->>'ms_left')::int between 1 and 5000 and (r->'drops'->0->>'my_total')::bigint = 500000
     and (r->>'poll_s')::numeric = 3, 'live drops: ' || r::text);
  set local role authenticated;
  perform pg_temp.assert(exists (select 1 from money_drops where id = did), 'players read money_drops (realtime)');
  perform pg_temp.assert(pg_temp.hint_of('select 1 from money_drop_picks limit 1') <> 'ok', 'players cannot read picks');
  perform pg_temp.assert(pg_temp.hint_of(format('update money_drops set remaining = 0 where id = %s', did)) <> 'ok', 'players cannot write drops');
  reset role;
  raise notice 'ok 7-8: ₦2T drop bigint-safe, RLS, live drops RPC';

  -- 9. picking off: the spray works, no drop
  update game_config set value = 'false' where key = 'club.pick_enabled';
  perform pg_temp.login(v);
  perform pg_temp.advance(11);
  r := spray_custom('club_raptor', 1000000, false);
  perform pg_temp.assert(r->'drop' = 'null'::jsonb and (r->>'amount')::bigint = 1000000, 'off: no drop');
  perform pg_temp.assert(pg_temp.hint_of(format('select money_pick(%s, 1)', did)) = 'disabled', 'off: picking refused');
  update game_config set value = 'true' where key = 'club.pick_enabled';
  raise notice 'ok 9: picking off';
end $$;
