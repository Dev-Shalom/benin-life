-- SP1 custom spray (20261012001650_custom_spray.sql). Rolled back. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/custom_spray_test.sql
-- Time moves with bl.test_offset_seconds (clubs open 22:00 - 05:00).
-- Groups: 1 grants / anon / helpers private / config · 2 refusals: not a club, wrong club, closed club, on the road ·
-- 3 amount checks: min, whole naira, max, giant number (bigint safe), cash only (PoS hint) · 4 a spray: cash, ledger
-- "Sprayed at <club>", hype record with amount / tier / points, needs · 5 cooldown · 6 tiers incl. ₦1B and ₦2T (short form,
-- full amount, app-wide), points log-scale · 7 VIP: needs a booking, VIP min, +hype bonus, VIP pool, tag · 8 bonuses (iPhone),
-- tier thresholds from config, no repeated lines, works while dancing, hype off still sprays · 9 status RPC.

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

create or replace function pg_temp.msg_of(p_sql text) returns text
language plpgsql as $$
begin
  execute p_sql;
  return 'ok';
exception when others then
  if sqlerrm like 'TEST FAILED%' then raise; end if;
  return sqlerrm;
end $$;

create or replace function pg_temp.advance(p_seconds numeric) returns void
language plpgsql as $$
declare v numeric := coalesce(nullif(current_setting('bl.test_offset_seconds', true), '')::numeric, 0) + p_seconds;
begin
  perform set_config('bl.test_offset_seconds', v::text, true);
end $$;

-- the Benin clock to weekday p_wd (0 = Monday) at p_hour:30
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

-- 1. grants / anon
do $$
declare f text;
begin
  foreach f in array array['spray_custom(text,numeric,boolean)', 'get_spray_status(text)'] loop
    perform pg_temp.assert(not has_function_privilege('anon', 'public.' || f, 'execute'), 'anon blocked ' || f);
    perform pg_temp.assert(has_function_privilege('authenticated', 'public.' || f, 'execute'), 'authenticated may ' || f);
  end loop;
  foreach f in array array['bl_spray_num(text,numeric)', 'bl_spray_tier(numeric)', 'bl_spray_tier_rank(text)', 'bl_spray_short(numeric)',
                           'bl_spray_points(numeric)', 'bl_spray_chips(text,text)', 'bl_spray_vip_ok(uuid)'] loop
    perform pg_temp.assert(not has_function_privilege('anon', 'public.' || f, 'execute')
                           and not has_function_privilege('authenticated', 'public.' || f, 'execute'), 'helper private ' || f);
  end loop;
  perform pg_temp.assert(not has_table_privilege('authenticated', 'public.player_spray', 'select')
                         and not has_table_privilege('anon', 'public.player_spray', 'select'), 'player_spray private');
  perform pg_temp.assert((select count(*) from game_config where key in ('club.spray_min', 'club.spray_max', 'club.spray_cooldown_s',
     'club.vip_spray_min', 'club.vip_hype_bonus_pct', 'club.spray_tier_nice', 'club.spray_tier_big', 'club.spray_tier_huge',
     'club.spray_tier_oga', 'club.spray_tier_billionaire', 'club.spray_tier_trillionaire', 'club.spray_chips', 'club.vip_spray_chips')
     and category = 'club') = 13, 'all spray settings in the club category');
  perform pg_temp.assert((select value::text from game_config where key = 'club.spray_max') = '10000000000000', 'max ₦10T');
  perform pg_temp.assert((select count(*) from hype_templates where kind = k and active) >= 8, 'pool ' || k)
    from unnest(array['spray_small', 'spray_nice', 'spray_big', 'spray_huge', 'spray_oga', 'spray_billionaire', 'spray_trillionaire', 'spray_vip']) k;
  perform pg_temp.assert(not exists (select 1 from hype_templates where kind like 'spray\_%' and line not like '%@{name}%'), 'every line names @{name}');
  perform pg_temp.assert(exists (select 1 from zone_actions where id = 'club.dj.spray_money') and exists (select 1 from zone_actions where id = 'club.vip.spray_money'),
    'spray cards on the DJ booth + VIP');
  raise notice 'ok 1: grants, helpers private, config, pools';
end $$;

set local role anon;
do $$
begin
  perform pg_temp.assert(pg_temp.hint_of($q$ select spray_custom('club_raptor', 5000, false) $q$) <> 'ok', 'anon refused spray_custom');
end $$;
reset role;

do $$
declare
  v uuid := pg_temp.new_user('sp_ada@spray.bl');
  w uuid := pg_temp.new_user('sp_bob@spray.bl');
  r jsonb; m text; a place_announcements; c0 bigint; n int; p1 int; p2 int; pv int; t1 text;
begin
  perform set_config('bl.test_rand', '0.99', true);
  perform pg_temp.login(w);
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform create_profile_v2('Sp_Bob', 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  perform pg_temp.login(v);
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform create_profile_v2('Sp_Ada', 'female', '{"gender":"female"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  update game_config set value = 'true' where key = 'places.hours_enabled';
  update game_config set value = '"real"' where key = 'clock.mode';
  update game_config set value = 'true' where key = 'hype.enabled';
  update game_config set value = '500000' where key = 'hype.global_min';
  update game_config set value = '1000' where key = 'club.spray_min';
  update game_config set value = '10000000000000' where key = 'club.spray_max';
  update game_config set value = '10' where key = 'club.spray_cooldown_s';
  update game_config set value = '100000' where key = 'club.vip_spray_min';
  update game_config set value = '25' where key = 'club.vip_hype_bonus_pct';
  update game_config set value = 'true' where key = 'club.vip_spray_needs_booking';
  update game_config set value = '"vip_table,big_boy_booth,amapiano_vip"' where key = 'club.vip_spray_activities';
  delete from player_charms where user_id = v;
  delete from inventory where user_id = v and item_id = 'iphone_18';

  -- 2. refusals: not a club, wrong club, closed club, on the road
  perform pg_temp.sp_at(2, 23);  -- Wednesday 11:30 PM
  update profiles set location_id = 'national_museum', cash = 80000 where id = v;
  perform pg_temp.assert(pg_temp.hint_of($q$ select spray_custom('national_museum', 5000, false) $q$) = 'not_club', 'non-club refused');
  perform pg_temp.assert(pg_temp.hint_of($q$ select spray_custom('club_raptor', 5000, false) $q$) = 'wrong_place', 'must stand in that club');
  update profiles set location_id = 'club_raptor' where id = v;
  perform pg_temp.assert(pg_temp.hint_of($q$ select spray_custom('club_360', 5000, false) $q$) = 'wrong_place', 'another club refused');
  perform pg_temp.sp_at(2, 21);  -- 9:30 PM: closed
  perform pg_temp.assert(pg_temp.hint_of($q$ select spray_custom('club_raptor', 5000, false) $q$) = 'closed', 'closed club refused');
  perform pg_temp.sp_at(3, 6);   -- 6:30 AM: closed
  perform pg_temp.assert(pg_temp.hint_of($q$ select spray_custom('club_raptor', 5000, false) $q$) = 'closed', 'closed after 5 AM');
  perform pg_temp.sp_at(2, 23);
  update profiles set travel_to = 'club_360' where id = v;
  perform pg_temp.assert(pg_temp.hint_of($q$ select spray_custom('club_raptor', 5000, false) $q$) = 'traveling', 'on the road refused');
  update profiles set travel_to = null where id = v;
  perform pg_temp.assert((select cash from profiles where id = v) = 80000 and not exists (select 1 from ledger where user_id = v and reason = 'spray'),
    'refusals charge nothing');
  raise notice 'ok 2: non-club / wrong club / closed / on the road refused';

  -- 3. amount checks
  perform pg_temp.assert(pg_temp.hint_of($q$ select spray_custom('club_raptor', 999, false) $q$) = 'too_small', 'below ₦1,000');
  perform pg_temp.assert(pg_temp.hint_of($q$ select spray_custom('club_raptor', 1500.5, false) $q$) = 'bad_amount', 'kobo refused');
  perform pg_temp.assert(pg_temp.hint_of($q$ select spray_custom('club_raptor', 0, false) $q$) = 'bad_amount', 'zero refused');
  perform pg_temp.assert(pg_temp.hint_of($q$ select spray_custom('club_raptor', -5000, false) $q$) = 'bad_amount', 'negative refused');
  perform pg_temp.assert(pg_temp.hint_of($q$ select spray_custom('club_raptor', null, false) $q$) = 'bad_amount', 'null refused');
  perform pg_temp.assert(pg_temp.hint_of($q$ select spray_custom('club_raptor', 10000000000001, false) $q$) = 'too_much', 'above ₦10T');
  perform pg_temp.assert(pg_temp.hint_of($q$ select spray_custom('club_raptor', 100000000000000000000000, false) $q$) = 'too_much',
    'a giant number is refused, not an overflow');
  perform pg_temp.assert(pg_temp.hint_of($q$ select spray_custom('club_raptor', 9223372036854775808, false) $q$) = 'too_much', 'past bigint refused');
  update profiles set cash = 5000, bank = 100000000 where id = v;
  perform pg_temp.assert(pg_temp.hint_of($q$ select spray_custom('club_raptor', 6000, false) $q$) = 'no_cash', 'cash only, bank does not count');
  m := pg_temp.msg_of($q$ select spray_custom('club_raptor', 6000, false) $q$);
  perform pg_temp.assert(m like '%Withdraw at the PoS first%', 'PoS hint: ' || m);
  perform pg_temp.assert((select bank from profiles where id = v) = 100000000, 'bank untouched');
  raise notice 'ok 3: min / whole naira / max / bigint safe / cash only';

  -- 4. a spray
  update profiles set cash = 80000 where id = v;
  r := spray_custom('club_raptor', 5000, false);
  perform pg_temp.assert((r->>'amount')::bigint = 5000 and (r->>'cash_after')::bigint = 75000, 'charged: ' || r::text);
  perform pg_temp.assert((select cash from profiles where id = v) = 75000, 'cash down by 5000');
  perform pg_temp.assert((select count(*) from ledger where user_id = v and reason = 'spray' and delta = -5000 and account = 'cash') = 1, 'one ledger row');
  perform pg_temp.assert((select bl_ledger_label(reason, meta) from ledger where user_id = v and reason = 'spray') = 'Sprayed at Club Raptor',
    'ledger label: ' || (select bl_ledger_label(reason, meta) from ledger where user_id = v and reason = 'spray'));
  select * into a from place_announcements where user_id = v order by id desc limit 1;
  perform pg_temp.assert(a.id = (r->'hype'->>'id')::bigint and a.kind = 'spray' and a.amount = 5000 and a.tier = 'small'
                         and not a.vip and a.location_id = 'club_raptor' and a.place = 'Club Raptor', 'hype record: ' || to_jsonb(a)::text);
  perform pg_temp.assert(a.points = bl_spray_points(5000) and a.points > 0, 'points recorded');
  perform pg_temp.assert(a.text like '%@Sp_Ada%' or a.text like '%Sp_Ada%', 'line names the player: ' || a.text);
  perform pg_temp.assert(a.text like '%₦5,000%' or a.text not like '%{amount}%', 'amount filled');
  perform pg_temp.assert(position('{' in a.text) = 0, 'no placeholders left: ' || a.text);
  perform pg_temp.assert((select hype_points from player_spray where user_id = v) = a.points and (select sprays from player_spray where user_id = v) = 1, 'totals');
  raise notice 'ok 4: spray charges cash, ledger "Sprayed at Club Raptor", hype record';

  -- 5. cooldown
  perform pg_temp.assert(pg_temp.hint_of($q$ select spray_custom('club_raptor', 5000, false) $q$) = 'cooldown', 'second spray at once refused');
  perform pg_temp.advance(5);
  perform pg_temp.assert(pg_temp.hint_of($q$ select spray_custom('club_raptor', 5000, false) $q$) = 'cooldown', 'still cooling at +5 s');
  perform pg_temp.advance(6);
  perform pg_temp.assert(pg_temp.hint_of($q$ select spray_custom('club_raptor', 5000, false) $q$) = 'ok', 'ok after 10 s');
  perform pg_temp.assert((select cash from profiles where id = v) = 70000, 'cooldown refusal charged nothing');
  raise notice 'ok 5: cooldown';

  -- 6. tiers by amount, incl. ₦1B and ₦2T
  update profiles set cash = 20000000000000 where id = v;
  perform pg_temp.assert(bl_spray_tier(49999) = 'small' and bl_spray_tier(50000) = 'nice' and bl_spray_tier(500000) = 'big'
     and bl_spray_tier(5000000) = 'huge' and bl_spray_tier(50000000) = 'oga' and bl_spray_tier(999999999) = 'oga'
     and bl_spray_tier(1000000000) = 'billionaire' and bl_spray_tier(999999999999) = 'billionaire'
     and bl_spray_tier(1000000000000) = 'trillionaire' and bl_spray_tier(10000000000000) = 'trillionaire', 'tier thresholds');
  perform pg_temp.advance(11);
  r := spray_custom('club_raptor', 1000000, false);
  perform pg_temp.assert(r->>'tier' = 'big' and (r->'hype'->>'tier') = 'big' and (r->'hype'->>'amount')::bigint = 1000000, '₦1M is Big: ' || r::text);
  perform pg_temp.assert(exists (select 1 from hype_templates where kind = 'spray_big' and id = (select template_id from hype_template_recent
     where location_id = 'club_raptor' and kind = 'spray_big' order by used_at desc limit 1)), 'line from the Big pool');
  perform pg_temp.advance(11);
  r := spray_custom('club_raptor', 1000000000, false);
  p1 := (r->>'points')::int;
  perform pg_temp.assert(r->>'tier' = 'billionaire' and (r->'hype'->>'global')::boolean, '₦1B is Billionaire and app-wide: ' || r::text);
  perform pg_temp.advance(11);
  r := spray_custom('club_raptor', 2000000000000, false);
  p2 := (r->>'points')::int;
  select * into a from place_announcements where id = (r->'hype'->>'id')::bigint;
  perform pg_temp.assert(a.tier = 'trillionaire' and a.amount = 2000000000000 and a.global, '₦2T is Trillionaire: ' || to_jsonb(a)::text);
  perform pg_temp.assert(a.ticker like '%₦2 TRILLION%' and a.ticker like '%@Sp_Ada%', 'ticker short form: ' || coalesce(a.ticker, 'null'));
  perform pg_temp.assert(a.text like '%₦2,000,000,000,000%' or a.text like '%₦2 TRILLION%', 'line says the amount: ' || a.text);
  perform pg_temp.assert(bl_spray_short(2000000000000) = '₦2 TRILLION' and bl_spray_short(1500000000) = '₦1.5 BILLION'
     and bl_spray_short(1000000) = '₦1 MILLION' and bl_spray_short(10000000000000) = '₦10 TRILLION', 'short forms');
  perform pg_temp.assert(p2 > p1 and p1 > bl_spray_points(1000000) and p2 <= 1000 and bl_spray_points(10000000000000) <= 1000,
    'points log-scale: 1B=' || p1 || ' 2T=' || p2);
  perform pg_temp.assert((select cash from profiles where id = v) = 20000000000000 - 1000000 - 1000000000 - 2000000000000, 'bigint cash exact');
  raise notice 'ok 6: tiers (₦1M Big, ₦1B Billionaire, ₦2T Trillionaire), short forms, log points';

  -- 7. VIP
  perform pg_temp.advance(11);
  perform pg_temp.assert(pg_temp.hint_of($q$ select spray_custom('club_raptor', 200000, true) $q$) = 'not_vip', 'VIP needs a booking');
  insert into ledger (user_id, account, delta, balance_after, reason, meta, created_at)
  values (v, 'cash', -150000, 0, 'activity', '{"activity": "vip_table"}', bl_now());
  perform pg_temp.assert(pg_temp.hint_of($q$ select spray_custom('club_raptor', 50000, true) $q$) = 'too_small', 'VIP min ₦100k');
  r := spray_custom('club_raptor', 100000, true);
  pv := (r->>'points')::int;
  select * into a from place_announcements where id = (r->'hype'->>'id')::bigint;
  perform pg_temp.assert(a.vip and (r->>'vip')::boolean, 'VIP tag on the shout-out');
  perform pg_temp.assert((r->>'hype_amount')::numeric = 125000 and pv = bl_spray_points(125000) and pv > bl_spray_points(100000), 'VIP +25% hype: ' || r::text);
  perform pg_temp.assert(exists (select 1 from hype_template_recent where location_id = 'club_raptor' and kind = 'spray_vip'), 'VIP pool used');
  update game_config set value = '50' where key = 'club.vip_hype_bonus_pct';
  perform pg_temp.advance(11);
  r := spray_custom('club_raptor', 100000, true);
  perform pg_temp.assert((r->>'hype_amount')::numeric = 150000, 'VIP bonus from config');
  update game_config set value = '25' where key = 'club.vip_hype_bonus_pct';
  -- the booking expires
  perform pg_temp.advance(24 * 3600);  -- the next night, same time
  perform pg_temp.assert(pg_temp.hint_of($q$ select spray_custom('club_raptor', 200000, true) $q$) = 'not_vip', 'booking does not last to the next night');
  update game_config set value = 'false' where key = 'club.vip_spray_needs_booking';
  perform pg_temp.sp_at(2, 23);
  perform pg_temp.advance(3600);
  perform pg_temp.assert(pg_temp.hint_of($q$ select spray_custom('club_raptor', 200000, true) $q$) = 'ok', 'booking switch off');
  update game_config set value = 'true' where key = 'club.vip_spray_needs_booking';
  raise notice 'ok 7: VIP booking, VIP min, +hype bonus, VIP pool + tag';

  -- 8. bonuses, thresholds from config, no repeats, while dancing, hype off
  perform pg_temp.advance(11);
  r := spray_custom('club_raptor', 1000000, false);
  perform pg_temp.assert((r->>'hype_amount')::numeric = 1000000, 'no bonus: ' || r::text);
  perform bl_give_item(v, 'iphone_18', 1);
  perform pg_temp.advance(11);
  r := spray_custom('club_raptor', 1000000, false);
  perform pg_temp.assert((r->>'hype_amount')::numeric = round(1000000 * (1 + bl_yahoo_num('yahoo.iphone_hype_pct', 10) / 100.0)),
    'iPhone hype bonus: ' || r::text);
  perform pg_temp.assert((r->'hype'->>'amount')::bigint = 1000000, 'the shown amount stays the real spray');
  update game_config set value = '2000' where key = 'club.spray_tier_nice';
  perform pg_temp.assert(bl_spray_tier(2500) = 'nice', 'tier from config');
  update game_config set value = '50000' where key = 'club.spray_tier_nice';
  -- 9 small sprays at a fresh place: 9 different lines
  delete from hype_template_recent where location_id = 'club_raptor' and kind = 'spray_small';
  for n in 1..9 loop
    perform pg_temp.advance(11);
    perform spray_custom('club_raptor', 2000, false);
  end loop;
  perform pg_temp.assert((select count(distinct template_id) from hype_template_recent where location_id = 'club_raptor' and kind = 'spray_small') = 9,
    'no repeated small lines');
  -- dancing (busy) is fine
  update profiles set busy_until = bl_now() + interval '1 minute', busy_label = 'Dance' where id = v;
  perform pg_temp.advance(11);
  perform pg_temp.assert(pg_temp.hint_of($q$ select spray_custom('club_raptor', 2000, false) $q$) = 'ok', 'spray while dancing');
  -- hype off: the spray still works, no announcement
  update game_config set value = 'false' where key = 'hype.enabled';
  select count(*) into n from place_announcements where user_id = v;
  perform pg_temp.advance(11);
  r := spray_custom('club_raptor', 2000, false);
  perform pg_temp.assert(r->'hype' = 'null'::jsonb and (select count(*) from place_announcements where user_id = v) = n, 'hype off: no shout-out');
  update game_config set value = 'true' where key = 'hype.enabled';
  -- the other player in the club can read the record (the broadcast path)
  update profiles set location_id = 'club_raptor' where id = w;
  perform pg_temp.login(w);
  set local role authenticated;
  perform pg_temp.assert(exists (select 1 from place_announcements where user_id = v and amount = 2000000000000 and tier = 'trillionaire'),
    'other players read the ₦2T shout-out');
  reset role;
  perform pg_temp.login(v);
  raise notice 'ok 8: bonuses, config thresholds, no repeats, dancing, hype off, others see it';

  -- 9. status
  perform pg_temp.advance(1);
  r := get_spray_status('club_raptor');
  perform pg_temp.assert((r->>'in_club')::boolean and (r->>'open')::boolean and (r->>'min')::numeric = 1000 and (r->>'vip_min')::numeric = 100000
     and (r->>'max')::numeric = 10000000000000 and (r->>'cooldown_left')::int between 1 and 10 and jsonb_array_length(r->'chips') = 8
     and jsonb_array_length(r->'vip_chips') = 6 and (r->>'points')::bigint > 0 and jsonb_array_length(r->'tiers') = 7, 'status: ' || r::text);
  raise notice 'ok 9: get_spray_status';
end $$;
