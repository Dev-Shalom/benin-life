-- R6 Yahoo strategy (20261018000300_yahoo_strategy.sql). Rolled back. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/yahoo_strategy_test.sql
-- Time moves with bl.test_offset_seconds; every roll is pinned with bl.test_rand (bl_rand, so bl_crime_roll too):
-- a roll of 0.0 is always caught, 0.99 never.
-- Groups: 1 grants / helpers private · 2 seeds (cash-out config, group missions, HK Quarters, zones, Elon job) · 3 cash-out quote
-- (full / half / launder: chances, fee, half amount, timer, admin edits, floor, Yahoo level cut) · 4 cash-out flows with forced rolls ·
-- 5 group refusals (friends, online, laptop, place, level, switch) · 6 group invite, accept, auto start, alert, push ·
-- 7 pay split + finish · 8 cooldown (host and invitee) · 9 start timer, bust for all with fair penalties · 10 dropped member,
-- not enough, decline, cancel · 11 HK Quarters as a work spot + its interior · 12 Elon format gate · 13 RLS + admin table.
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

create or replace function pg_temp.cfg(p_key text, p_val text) returns void
language sql as $$ update game_config set value = p_val::jsonb where key = p_key; $$;

create or replace function pg_temp.qty(p_uid uuid, p_item text) returns int
language sql as $$ select coalesce((select qty from inventory where user_id = p_uid and item_id = p_item), 0); $$;

-- free, standing at a place (default home), online now
create or replace function pg_temp.at(p_uid uuid, p_loc text default null) returns void
language sql as $$
  update profiles set location_id = coalesce(p_loc, home_location_id), travel_to = null, travel_mode = null, travel_started_at = null,
                      travel_arrives_at = null, busy_until = null, busy_label = null, busy_started_at = null, busy_needs_from = null,
                      jailed_until = null, jail_reason = null, hospitalized_until = null, home_visit_host_id = null,
                      last_seen = bl_now(), rent_due_at = null
   where id = p_uid;
$$;

create or replace function pg_temp.laptop(p_uid uuid, p_item text) returns void
language plpgsql as $$
begin
  delete from inventory where user_id = p_uid and item_id in (select item_id from laptop_specs);
  if p_item is not null then perform bl_give_item(p_uid, p_item, 1); end if;
end $$;

-- Yahoo skill XP (level 2 = 40, 3 = 120, 4 = 260, 10 = 3300)
create or replace function pg_temp.xp(p_uid uuid, p_xp int) returns void
language sql as $$
  insert into player_skills (user_id, skill_id, xp) values (p_uid, 'yahoo', p_xp)
  on conflict (user_id, skill_id) do update set xp = excluded.xp;
$$;

create or replace function pg_temp.dirty(p_uid uuid, p_amount bigint) returns void
language plpgsql as $$
begin
  perform bl_yahoo_row(p_uid);
  update yahoo_players set dirty = p_amount where user_id = p_uid;
end $$;

-- a cash out in one mode to the end with a pinned roll
create or replace function pg_temp.cash(p_uid uuid, p_mode text, p_rand text) returns jsonb
language plpgsql as $$
declare v jsonb;
begin
  perform pg_temp.login(p_uid);
  perform set_config('bl.test_rand', '', true);
  v := yahoo_cashout_start(p_mode);
  perform pg_temp.advance((v->>'seconds')::numeric + 1);
  perform set_config('bl.test_rand', p_rand, true);
  v := yahoo_finish();
  perform set_config('bl.test_rand', '', true);
  return v;
end $$;

create or replace function pg_temp.friends(a uuid, b uuid) returns void
language sql as $$
  insert into player_friendships (user_a, user_b, status, requested_by) values (least(a, b), greatest(a, b), 'accepted', a)
  on conflict do nothing;
$$;

-- ---------- setup ----------
do $$
declare
  adm uuid := pg_temp.new_user('r6_admin@yy.bl');
  a uuid := pg_temp.new_user('r6_a@yy.bl');
  b uuid := pg_temp.new_user('r6_b@yy.bl');
  c uuid := pg_temp.new_user('r6_c@yy.bl');
  d uuid := pg_temp.new_user('r6_d@yy.bl');
  e uuid := pg_temp.new_user('r6_e@yy.bl');
  u uuid;
  i int := 0;
begin
  perform set_config('r6.adm', adm::text, true); perform set_config('r6.a', a::text, true);
  perform set_config('r6.b', b::text, true); perform set_config('r6.c', c::text, true);
  perform set_config('r6.d', d::text, true); perform set_config('r6.e', e::text, true);
  perform set_config('bl.test_offset_seconds', '0', true);
  perform set_config('bl.test_rand', '', true);
  foreach u in array array[adm, a, b, c, d, e] loop
    i := i + 1;
    update game_config set value = '"lapo"' where key = 'origin.force_next';
    perform pg_temp.login(u);
    perform create_profile_v2('R6_P' || i, 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
    perform choose_start_home('ekenwan_face_me');
    perform pg_temp.at(u);
    perform bl_yahoo_row(u);
  end loop;
  update profiles set is_admin = true where id = adm;
  update profiles set created_at = now() - interval '30 days', protected_until = null, cash = 0, bank = 0 where id in (adm, a, b, c, d, e);
  delete from inventory where user_id in (adm, a, b, c, d, e);
  perform pg_temp.friends(a, b); perform pg_temp.friends(a, c); perform pg_temp.friends(a, d);
  perform pg_temp.friends(b, c); perform pg_temp.friends(b, d);
end $$;

-- ---------- 1. grants ----------
do $$
declare v_rpc text;
begin
  foreach v_rpc in array array['yahoo_cashout_quote()', 'yahoo_cashout_start(text)', 'yahoo_group_status()', 'yahoo_group_create(text,uuid[])',
                               'yahoo_group_respond(bigint,boolean)', 'yahoo_group_start(bigint)', 'yahoo_group_cancel(bigint)', 'yahoo_group_finish()'] loop
    perform pg_temp.assert(not has_function_privilege('anon', ('public.' || v_rpc)::regprocedure, 'execute'), 'anon blocked ' || v_rpc);
    perform pg_temp.assert(has_function_privilege('authenticated', ('public.' || v_rpc)::regprocedure, 'execute'), 'auth may ' || v_rpc);
    perform pg_temp.assert((select prosecdef from pg_proc where oid = ('public.' || v_rpc)::regprocedure), 'secdef ' || v_rpc);
  end loop;
  foreach v_rpc in array array['bl_yahoo_cash_quote(uuid,text)', 'bl_yahoo_online(timestamptz)', 'bl_yahoo_is_friend(uuid,uuid)', 'bl_yahoo_caught_skill()',
                               'bl_yahoo_group_pct(uuid[],numeric)', 'bl_yahoo_group_spot(profiles)', 'bl_yahoo_group_gate(uuid,group_missions,text)',
                               'bl_yahoo_group_json(bigint,uuid)', 'bl_yahoo_bust(uuid,bigint,text,text,text)',
                               'bl_yahoo_group_notify(uuid,profiles,group_missions,bigint)', 'bl_yahoo_group_cancel(bigint,text)',
                               'bl_yahoo_group_start(bigint)', 'bl_yahoo_group_resolve(bigint)', 'bl_yahoo_group_tick(bigint)',
                               'bl_yahoo_group_tick_user(uuid)'] loop
    perform pg_temp.assert(not has_function_privilege('authenticated', ('public.' || v_rpc)::regprocedure, 'execute')
                           and not has_function_privilege('anon', ('public.' || v_rpc)::regprocedure, 'execute'), 'helper private ' || v_rpc);
  end loop;
  -- the patched live functions keep their grants
  perform pg_temp.assert(has_function_privilege('authenticated', 'public.yahoo_status()'::regprocedure, 'execute')
                         and has_function_privilege('authenticated', 'public.yahoo_job_start(text,bigint)'::regprocedure, 'execute')
                         and not has_function_privilege('authenticated', 'public.bl_yahoo_resolve(bigint)'::regprocedure, 'execute')
                         and not has_function_privilege('authenticated', 'public.bl_yahoo_run_json(yahoo_runs)'::regprocedure, 'execute'), 'patched functions keep grants');
  raise notice 'ok 1: grants / helpers private';
end $$;

-- ---------- 2. seeds ----------
do $$
declare r record; v jsonb; n int;
begin
  perform pg_temp.assert(position('hk_quarters' in (select value #>> '{}' from game_config where key = 'yahoo.cafe_locations')) > 0, 'HK Quarters is a work spot by default');
  perform pg_temp.assert((select value #>> '{}' from game_config where key = 'yahoo.group_locations') = 'hk_quarters', 'group place config');
  perform pg_temp.assert((select (value #>> '{}')::numeric from game_config where key = 'yahoo.launder_fee_pct') = 15
                         and (select (value #>> '{}')::numeric from game_config where key = 'yahoo.launder_caught_mult') = 25
                         and (select (value #>> '{}')::numeric from game_config where key = 'yahoo.cashout_half_caught_mult') = 60
                         and (select (value #>> '{}')::numeric from game_config where key = 'yahoo.cashout_half_pct') = 50
                         and (select (value #>> '{}')::numeric from game_config where key = 'yahoo.launder_seconds') = 90
                         and (select (value #>> '{}')::numeric from game_config where key = 'yahoo.group_member_bonus_pct') = 10, 'cash-out and group defaults');
  perform pg_temp.assert((select count(*) from game_config where key in ('yahoo.cashout_full_caught_mult', 'yahoo.cashout_half_pct', 'yahoo.cashout_half_caught_mult',
    'yahoo.launder_fee_pct', 'yahoo.launder_caught_mult', 'yahoo.launder_seconds', 'yahoo.cashout_floor_pct', 'yahoo.launder_contact', 'yahoo.group_enabled',
    'yahoo.group_locations', 'yahoo.group_member_bonus_pct') and category = 'yahoo') = 11, 'eleven Settings rows in the Yahoo category');
  select * into r from group_missions where id = 'crew_hustle';
  perform pg_temp.assert((r.min_members, r.max_members, r.duration_seconds, r.min_yahoo_level) = (2, 4, 90, 2) and r.active, 'crew hustle row');
  perform pg_temp.assert((select count(*) from group_missions) >= 2 and exists (select 1 from group_missions where id = 'hk_big_table' and min_members = 3 and min_yahoo_level = 4), 'big table row');
  -- HK Quarters on the map
  select * into r from locations where id = 'hk_quarters';
  perform pg_temp.assert(r.scene = 'cyber' and r.x = 395 and r.y = 195 and r.district = 'uselu' and r.active and 'shop' = any (r.actions), 'HK Quarters place');
  perform pg_temp.assert(exists (select 1 from items where id = 'laptop' and 'hk_quarters' = any (sold_at)) and exists (select 1 from items where id = 'data_bundle' and 'hk_quarters' = any (sold_at)), 'laptops sold at HK');
  -- the Elon format
  select * into r from yahoo_jobs where id = 'elon_format';
  perform pg_temp.assert((r.seconds, r.pay_min, r.pay_max, r.caught_pct, r.min_skill_level, r.min_tier, r.kind) = (50, 200000, 1200000, 20::numeric, 4, 1, 'job')
                         and r.active and r.blurb like '%billionaire%crypto%', 'Elon format row');
  perform pg_temp.assert(r.pay_min > (select pay_max from yahoo_jobs where id = 'chat_client') and r.pay_max < (select pay_max from yahoo_jobs where id = 'big_job')
                         and r.caught_pct > (select caught_pct from yahoo_jobs where id = 'romance_job') and r.caught_pct < (select caught_pct from yahoo_jobs where id = 'big_job'),
                         'Elon sits between romance and the big job');
  perform pg_temp.assert((select sort from yahoo_jobs where id = 'elon_format') > (select sort from yahoo_jobs where id = 'romance_job')
                         and (select sort from yahoo_jobs where id = 'elon_format') < (select sort from yahoo_jobs where id = 'big_job'), 'Elon is listed between them');
  perform pg_temp.assert(exists (select 1 from skill_sources where kind = 'yahoo' and ref = 'elon_format' and skill_id = 'yahoo' and active), 'Elon gives Yahoo XP (the level gate needs a skill source)');
  -- no real how-to in any new copy: flavour only
  perform pg_temp.assert(not exists (select 1 from yahoo_jobs where id = 'elon_format' and blurb ~* '(step|script|template|how to|wallet address|send the)'), 'flavour text only');
  raise notice 'ok 2: seeds';
end $$;

-- ---------- 3. cash-out quote ----------
do $$
declare a uuid := current_setting('r6.a')::uuid; q jsonb; o jsonb;
begin
  perform pg_temp.login(a);
  perform pg_temp.cfg('skills.enabled', 'false');
  perform pg_temp.cfg('yahoo.seize_laptop_pct', '0');
  perform pg_temp.cfg('yahoo.confiscate_pct', '50');
  perform pg_temp.cfg('yahoo.caught_floor_pct', '5');
  update yahoo_jobs set caught_pct = 32, cooldown_seconds = 60 where id = 'cash_out';
  update yahoo_jobs set active = true;
  perform pg_temp.at(a);
  perform pg_temp.laptop(a, 'laptop');
  perform pg_temp.dirty(a, 1000000);
  q := yahoo_cashout_quote();
  perform pg_temp.assert(jsonb_array_length(q->'options') = 3 and q->>'contact' like 'Mallam%', 'three options + the contact');
  -- full: everything, the job's own chance
  o := q->'options'->0;
  perform pg_temp.assert(o->>'mode' = 'full' and (o->>'amount')::bigint = 1000000 and (o->>'fee')::bigint = 0 and (o->>'caught_pct')::numeric = 32
                         and (o->>'seconds')::int = 15 and (o->>'ok')::boolean, 'full: all, no fee, 32 %, 15 s');
  -- half: half the balance, 60 % of the chance
  o := q->'options'->1;
  perform pg_temp.assert(o->>'mode' = 'half' and (o->>'amount')::bigint = 500000 and (o->>'fee')::bigint = 0 and (o->>'caught_pct')::numeric = 19.2
                         and (o->>'seconds')::int = 15, 'half: 500k, 19.2 %');
  -- launder: fee 15 %, 25 % of the chance, 90 s
  o := q->'options'->2;
  perform pg_temp.assert(o->>'mode' = 'launder' and (o->>'amount')::bigint = 1000000 and (o->>'fee')::bigint = 150000 and (o->>'net')::bigint = 850000
                         and (o->>'caught_pct')::numeric = 8 and (o->>'seconds')::int = 90, 'launder: fee 150k, net 850k, 8 %, 90 s');
  perform pg_temp.assert((q->'options'->0->>'caught_pct')::numeric > (q->'options'->1->>'caught_pct')::numeric
                         and (q->'options'->1->>'caught_pct')::numeric > (q->'options'->2->>'caught_pct')::numeric, 'full > half > launder');
  perform pg_temp.assert(q->>'blocked' is not null, 'blocked at home without MiFi');
  update yahoo_players set mifi_until = bl_now() + interval '30 days' where user_id = a;
  perform pg_temp.assert(yahoo_cashout_quote()->>'blocked' is null, 'open with MiFi');
  -- laptop points and the EFCC blindfold lower the base for every option
  perform pg_temp.laptop(a, 'macbook_pro_m4');
  q := yahoo_cashout_quote();
  perform pg_temp.assert((q->'options'->0->>'caught_pct')::numeric = 24 and (q->'options'->1->>'caught_pct')::numeric = 14.4
                         and (q->'options'->2->>'caught_pct')::numeric = 6, 'MacBook Pro -8 pts on the base (24 / 14.4 / 6)');
  perform pg_temp.laptop(a, 'laptop');
  -- admin edits move the numbers
  perform pg_temp.cfg('yahoo.launder_fee_pct', '20');
  perform pg_temp.cfg('yahoo.cashout_half_pct', '40');
  perform pg_temp.cfg('yahoo.cashout_half_caught_mult', '50');
  perform pg_temp.cfg('yahoo.launder_caught_mult', '10');
  perform pg_temp.cfg('yahoo.launder_seconds', '120');
  perform pg_temp.cfg('yahoo.cashout_full_caught_mult', '110');
  q := yahoo_cashout_quote();
  perform pg_temp.assert((q->'options'->1->>'amount')::bigint = 400000 and (q->'options'->1->>'caught_pct')::numeric = 16, 'admin: half 40 % at x50');
  perform pg_temp.assert((q->'options'->2->>'fee')::bigint = 200000 and (q->'options'->2->>'net')::bigint = 800000
                         and (q->'options'->2->>'caught_pct')::numeric = 3.2 and (q->'options'->2->>'seconds')::int = 120, 'admin: fee 20 %, x10, 120 s');
  perform pg_temp.assert((q->'options'->0->>'caught_pct')::numeric = 35.2, 'admin: full x110');
  perform pg_temp.cfg('yahoo.launder_fee_pct', '15'); perform pg_temp.cfg('yahoo.cashout_half_pct', '50');
  perform pg_temp.cfg('yahoo.cashout_half_caught_mult', '60'); perform pg_temp.cfg('yahoo.launder_caught_mult', '25');
  perform pg_temp.cfg('yahoo.launder_seconds', '90'); perform pg_temp.cfg('yahoo.cashout_full_caught_mult', '100');
  -- the floor: half and launder never go under yahoo.cashout_floor_pct (1)
  update yahoo_jobs set caught_pct = 3 where id = 'cash_out';
  update game_config set value = '5' where key = 'yahoo.caught_floor_pct';
  q := yahoo_cashout_quote();
  perform pg_temp.assert((q->'options'->0->>'caught_pct')::numeric = 3 and (q->'options'->1->>'caught_pct')::numeric = 1.8
                         and (q->'options'->2->>'caught_pct')::numeric = 1, 'floor: 3 / 1.8 / 1');
  update yahoo_jobs set caught_pct = 32 where id = 'cash_out';
  -- the Yahoo level cut still applies (level 10 = -36 %)
  perform pg_temp.cfg('skills.enabled', 'true');
  perform pg_temp.xp(a, 3300);
  q := yahoo_cashout_quote();
  perform pg_temp.assert((q->'options'->0->>'caught_pct')::numeric = 20.48 and (q->'options'->0->>'base_caught_pct')::numeric = 32
                         and (q->'options'->1->>'caught_pct')::numeric = 12.29 and (q->'options'->2->>'caught_pct')::numeric = 5.12, 'level 10 cuts all three by 36 %');
  perform pg_temp.cfg('skills.enabled', 'false');
  -- empty or tiny balances
  perform pg_temp.dirty(a, 0);
  q := yahoo_cashout_quote();
  perform pg_temp.assert((select count(*) from jsonb_array_elements(q->'options') x where (x->>'ok')::boolean) = 0, 'empty: no option is ok');
  perform pg_temp.dirty(a, 1500);
  q := yahoo_cashout_quote();
  perform pg_temp.assert((q->'options'->0->>'ok')::boolean and not (q->'options'->1->>'ok')::boolean and q->'options'->1->>'why' like '%at least%', 'half of 1,500 is under the minimum');
  perform pg_temp.assert(pg_temp.hint_of('select yahoo_cashout_start(''half'')') = 'too_small', 'half too small refused');
  perform pg_temp.assert(pg_temp.hint_of('select yahoo_cashout_start(''nonsense'')') = 'bad_mode', 'bad mode');
  perform pg_temp.dirty(a, 0);
  perform pg_temp.assert(pg_temp.hint_of('select yahoo_cashout_start(''full'')') = 'nothing_to_cash', 'nothing to cash');
  raise notice 'ok 3: cash-out quote (chances, fee, half amount, timer, admin edits, floor, level cut)';
end $$;

-- ---------- 4. cash-out flows with forced rolls ----------
do $$
declare a uuid := current_setting('r6.a')::uuid; r jsonb; v jsonb; n int; v_run yahoo_runs;
begin
  perform pg_temp.login(a);
  perform pg_temp.at(a);
  perform pg_temp.laptop(a, 'laptop');
  update yahoo_players set mifi_until = bl_now() + interval '90 days' where user_id = a;
  update profiles set cash = 0 where id = a;
  perform pg_temp.cfg('yahoo.jail_seconds', '90');
  perform pg_temp.advance(1000);

  -- FULL, caught at 32 % (roll 0.30)
  perform pg_temp.dirty(a, 1000000);
  r := pg_temp.cash(a, 'full', '0.30');
  perform pg_temp.assert(r->>'status' = 'caught' and (r->>'seized')::bigint = 500000 and (select dirty from yahoo_players where user_id = a) = 500000, 'full: 0.30 is caught, half the balance taken');
  update jail_cases set status = 'released' where user_id = a and status = 'open';
  perform pg_temp.at(a); perform pg_temp.advance(100);
  -- FULL, safe at roll 0.33
  perform pg_temp.dirty(a, 1000000);
  r := pg_temp.cash(a, 'full', '0.33');
  perform pg_temp.assert(r->>'status' = 'cashed' and (r->>'amount')::bigint = 1000000 and (r->>'fee')::bigint = 0 and r->>'mode' = 'full', 'full: 0.33 is safe');
  perform pg_temp.assert((select cash from profiles where id = a) = 1000000 and (select dirty from yahoo_players where user_id = a) = 0, 'full: +1M cash, yahoo balance empty');
  perform pg_temp.advance(100);

  -- HALF: the same 0.30 roll is now safe (chance 19.2 %)
  update profiles set cash = 0 where id = a;
  perform pg_temp.dirty(a, 1000000);
  v := yahoo_cashout_start('half');
  select * into v_run from yahoo_runs where id = (v->>'run_id')::bigint;
  perform pg_temp.assert(v_run.mode = 'half' and v_run.amount = 500000 and v_run.fee = 0 and v_run.caught_pct = 19.2, 'half: run stores mode, amount and 19.2 %');
  perform pg_temp.advance(16);
  perform set_config('bl.test_rand', '0.30', true);
  r := yahoo_finish();
  perform set_config('bl.test_rand', '', true);
  perform pg_temp.assert(r->>'status' = 'cashed' and (r->>'amount')::bigint = 500000, 'half: 0.30 is safe');
  perform pg_temp.assert((select cash from profiles where id = a) = 500000 and (select dirty from yahoo_players where user_id = a) = 500000, 'half: +500k cash, 500k stays');
  perform pg_temp.advance(100);
  -- HALF caught at 0.19 (< 19.2)
  r := pg_temp.cash(a, 'half', '0.19');
  perform pg_temp.assert(r->>'status' = 'caught', 'half: 0.19 is caught');
  update jail_cases set status = 'released' where user_id = a and status = 'open';
  perform pg_temp.at(a); perform pg_temp.advance(100);

  -- LAUNDER: longer timer, fee to the contact, much lower chance
  update profiles set cash = 0 where id = a;
  perform pg_temp.dirty(a, 1000000);
  v := yahoo_cashout_start('launder');
  perform pg_temp.assert((v->>'seconds')::int = 90 and (v->>'fee')::bigint = 150000 and (v->>'net')::bigint = 850000 and v->>'mode' = 'launder'
                         and (v->>'caught_pct')::numeric = 8, 'launder start: 90 s, fee, net, 8 %');
  perform pg_temp.assert((select busy_until from profiles where id = a) = (v->>'resolve_at')::timestamptz
                         and (v->>'resolve_at')::timestamptz > bl_now() + interval '85 seconds', 'launder: busy for the longer timer');
  perform pg_temp.assert(pg_temp.hint_of('select yahoo_finish()') = 'not_yet', 'launder: not before 90 s');
  perform pg_temp.advance(91);
  perform set_config('bl.test_rand', '0.09', true);   -- caught would need < 8
  r := yahoo_finish();
  perform set_config('bl.test_rand', '', true);
  perform pg_temp.assert(r->>'status' = 'cashed' and (r->>'amount')::bigint = 1000000 and (r->>'fee')::bigint = 150000 and r->>'mode' = 'launder', 'launder: 0.09 is safe');
  perform pg_temp.assert((select cash from profiles where id = a) = 850000 and (select dirty from yahoo_players where user_id = a) = 0, 'launder: net 850k cash, balance empty');
  perform pg_temp.assert((r->>'message') like '%fee%', 'launder message mentions the fee');
  perform pg_temp.assert(exists (select 1 from ledger where user_id = a and reason = 'yahoo_cashout' and account = 'cash' and delta = 850000), 'cash ledger line is the net');
  perform pg_temp.assert(exists (select 1 from yahoo_ledger where user_id = a and reason = 'cashout' and delta = -1000000 and (meta->>'fee')::bigint = 150000 and meta->>'mode' = 'launder'), 'yahoo ledger: whole amount out, fee in the meta');
  perform pg_temp.assert((select cashed_out from yahoo_players where user_id = a) >= 2350000, 'cashed_out counts the moved amount');
  perform pg_temp.advance(100);
  -- LAUNDER caught at 0.07 (< 8)
  perform pg_temp.dirty(a, 1000000);
  update profiles set cash = 0 where id = a;
  r := pg_temp.cash(a, 'launder', '0.07');
  perform pg_temp.assert(r->>'status' = 'caught' and (select cash from profiles where id = a) = 0, 'launder: 0.07 is caught, no cash');
  update jail_cases set status = 'released' where user_id = a and status = 'open';
  perform pg_temp.at(a); perform pg_temp.advance(100);

  -- the Yahoo level cut is applied at the roll: level 10 turns 32 % into 20.48 %
  perform pg_temp.cfg('skills.enabled', 'true');
  perform pg_temp.xp(a, 3300);
  perform pg_temp.dirty(a, 1000000);
  r := pg_temp.cash(a, 'full', '0.21');
  perform pg_temp.assert(r->>'status' = 'cashed', 'level 10: 0.21 is safe (it would be caught at the base 32 %)');
  perform pg_temp.advance(100);
  perform pg_temp.dirty(a, 1000000);
  r := pg_temp.cash(a, 'full', '0.20');
  perform pg_temp.assert(r->>'status' = 'caught', 'level 10: 0.20 is still caught');
  update jail_cases set status = 'released' where user_id = a and status = 'open';
  perform pg_temp.at(a); perform pg_temp.advance(100);
  perform pg_temp.cfg('skills.enabled', 'false');
  perform pg_temp.xp(a, 0);

  -- cooldown shared by every option; the old direct job still works as a full cash out
  perform pg_temp.dirty(a, 1000000);
  perform pg_temp.login(a);
  v := yahoo_cashout_start('full');
  perform pg_temp.assert(pg_temp.hint_of('select yahoo_cashout_start(''half'')') <> 'ok', 'one cash out at a time');
  perform pg_temp.advance(16);
  perform set_config('bl.test_rand', '0.99', true); r := yahoo_finish(); perform set_config('bl.test_rand', '', true);
  perform pg_temp.assert(pg_temp.hint_of('select yahoo_cashout_start(''half'')') = 'cooldown', 'cash out cooldown');
  perform pg_temp.advance(100);
  perform pg_temp.dirty(a, 400000);
  v := yahoo_job_start('cash_out', null);
  select * into v_run from yahoo_runs where id = (v->>'run_id')::bigint;
  perform pg_temp.assert(v_run.mode is null and v_run.fee = 0 and v_run.caught_pct = 32 and v_run.amount = 400000, 'yahoo_job_start cash out: plain full cash out');
  perform pg_temp.advance(16);
  perform set_config('bl.test_rand', '0.99', true); r := yahoo_finish(); perform set_config('bl.test_rand', '', true);
  perform pg_temp.assert(r->>'status' = 'cashed' and (r->>'amount')::bigint = 400000 and (r->>'fee')::bigint = 0, 'plain cash out lands whole');
  perform pg_temp.assert(yahoo_status()->'jobs' @> '[{"id":"cash_out"}]'::jsonb, 'status still lists the cash-out job');
  raise notice 'ok 4: cash-out flows with forced rolls (full / half / launder, fee, timer, level cut)';
end $$;

-- ---------- 5. group refusals ----------
do $$
declare
  a uuid := current_setting('r6.a')::uuid; b uuid := current_setting('r6.b')::uuid; c uuid := current_setting('r6.c')::uuid;
  d uuid := current_setting('r6.d')::uuid; e uuid := current_setting('r6.e')::uuid; v jsonb;
begin
  perform pg_temp.cfg('skills.enabled', 'true');
  perform pg_temp.cfg('yahoo.group_enabled', 'true');
  perform pg_temp.cfg('yahoo.group_member_bonus_pct', '10');
  perform pg_temp.cfg('yahoo.confiscate_pct', '50');
  perform pg_temp.cfg('yahoo.seize_laptop_pct', '100');
  update group_missions set min_members = 2, max_members = 4, duration_seconds = 90, reward_min = 400000, reward_max = 1600000, caught_pct = 20,
         min_yahoo_level = 2, invite_seconds = 120, cooldown_seconds = 600, active = true where id = 'crew_hustle';
  update group_missions set min_members = 3, max_members = 4, duration_seconds = 150, reward_min = 3000000, reward_max = 12000000, caught_pct = 32,
         min_yahoo_level = 4, invite_seconds = 180, cooldown_seconds = 1200, active = true where id = 'hk_big_table';
  perform pg_temp.xp(a, 120); perform pg_temp.xp(b, 40); perform pg_temp.xp(c, 40); perform pg_temp.xp(d, 0);
  perform pg_temp.advance(5000);
  perform pg_temp.login(a);
  update yahoo_players set mifi_until = null where user_id = a;
  -- everybody at HK Quarters with a laptop (except where a test says otherwise)
  perform pg_temp.at(a, 'hk_quarters'); perform pg_temp.at(b, 'hk_quarters'); perform pg_temp.at(c, 'hk_quarters'); perform pg_temp.at(d, 'hk_quarters');
  perform pg_temp.laptop(a, 'laptop'); perform pg_temp.laptop(b, 'laptop'); perform pg_temp.laptop(c, 'laptop'); perform pg_temp.laptop(d, 'laptop');

  perform pg_temp.assert(pg_temp.hint_of(format('select yahoo_group_create(%L, %L)', 'crew_hustle', '{}'::uuid[])) = 'no_friends', 'invite at least one friend');
  perform pg_temp.assert(pg_temp.hint_of(format('select yahoo_group_create(%L, %L)', 'crew_hustle', array[e])) = 'not_friend', 'only friends');
  perform pg_temp.assert(pg_temp.hint_of(format('select yahoo_group_create(%L, %L)', 'crew_hustle', array[b, c, d, e])) = 'too_many', 'at most max-1 friends');
  perform pg_temp.assert(pg_temp.hint_of(format('select yahoo_group_create(%L, %L)', 'no_such', array[b])) = 'bad_mission', 'bad mission');
  update profiles set last_seen = bl_now() - interval '1 hour' where id = b;
  perform pg_temp.assert(pg_temp.hint_of(format('select yahoo_group_create(%L, %L)', 'crew_hustle', array[b])) = 'friend_offline', 'offline friend refused');
  update profiles set last_seen = bl_now() where id = b;
  -- the host needs a laptop, a spot and the level
  perform pg_temp.laptop(a, null);
  perform pg_temp.assert(pg_temp.hint_of(format('select yahoo_group_create(%L, %L)', 'crew_hustle', array[b])) = 'no_laptop', 'host needs a laptop');
  perform pg_temp.laptop(a, 'laptop');
  perform pg_temp.at(a, 'oba_market');
  perform pg_temp.assert(pg_temp.hint_of(format('select yahoo_group_create(%L, %L)', 'crew_hustle', array[b])) = 'wrong_place', 'host must be at HK Quarters or home');
  perform pg_temp.at(a);
  perform pg_temp.assert(pg_temp.hint_of(format('select yahoo_group_create(%L, %L)', 'crew_hustle', array[b])) = 'no_mifi', 'home without MiFi refused');
  perform pg_temp.at(a, 'hk_quarters');
  perform pg_temp.login(d);
  perform pg_temp.assert(pg_temp.hint_of(format('select yahoo_group_create(%L, %L)', 'crew_hustle', array[b])) = 'skill_level', 'level 1 can''t host a level 2 mission');
  perform pg_temp.login(a);
  perform pg_temp.cfg('yahoo.group_enabled', 'false');
  perform pg_temp.assert(pg_temp.hint_of(format('select yahoo_group_create(%L, %L)', 'crew_hustle', array[b])) = 'disabled', 'switch off');
  perform pg_temp.assert((yahoo_group_status()->>'enabled')::boolean = false, 'status says off');
  perform pg_temp.cfg('yahoo.group_enabled', 'true');
  -- home on MiFi works too (then cancelled)
  perform pg_temp.at(a);
  update yahoo_players set mifi_until = bl_now() + interval '7 days' where user_id = a;
  v := yahoo_group_create('crew_hustle', array[b]);
  perform pg_temp.assert(v->'group'->>'status' = 'inviting', 'home + MiFi can host');
  perform yahoo_group_cancel((v->'group'->>'id')::bigint);
  update yahoo_players set mifi_until = null where user_id = a;
  perform pg_temp.at(a, 'hk_quarters');
  -- status shows who is ready
  v := yahoo_group_status();
  perform pg_temp.assert((v->'spot'->>'ok')::boolean and v->'spot'->>'place' = 'hk' and (v->>'has_laptop')::boolean and jsonb_array_length(v->'missions') >= 2
                         and jsonb_array_length(v->'friends') = 3 and (select count(*) from jsonb_array_elements(v->'friends') f where (f->>'ready')::boolean) = 3, 'status: spot, laptop, missions, three friends ready');
  raise notice 'ok 5: group refusals';
end $$;

-- ---------- 6. invite, accept, auto start, alert ----------
do $$
declare
  a uuid := current_setting('r6.a')::uuid; b uuid := current_setting('r6.b')::uuid; c uuid := current_setting('r6.c')::uuid;
  d uuid := current_setting('r6.d')::uuid; v jsonb; g bigint; v_pct numeric;
begin
  insert into push_subscriptions (user_id, endpoint, p256dh, auth) values (b, 'https://push.test/r6-b', 'k', 'a');
  perform pg_temp.login(a);
  v := yahoo_group_create('crew_hustle', array[b, c]);
  g := (v->'group'->>'id')::bigint;
  perform set_config('r6.g', g::text, true);
  perform pg_temp.assert(v->'group'->>'status' = 'inviting' and (v->'group'->>'ready')::int = 1 and jsonb_array_length(v->'group'->'members') = 3, 'created: inviting, host ready');
  perform pg_temp.assert((select count(*) from events where kind = 'yahoo_group_invite' and user_id in (b, c) and (data->>'group_id')::bigint = g) = 2, 'both friends get an alert');
  perform pg_temp.assert(not exists (select 1 from events where kind = 'yahoo_group_invite' and user_id in (a, d) and (data->>'group_id')::bigint = g), 'only the invited');
  perform pg_temp.assert(exists (select 1 from push_outbox where user_id = b and category = 'friends' and kind = 'yahoo_group_invite' and url = '/play?go=yahoo' and title like '%group mission%'),
                         'push in the friends category');
  perform pg_temp.assert(not exists (select 1 from push_outbox where user_id = c), 'no push without a saved device');
  -- the invite shows in the friend's app
  perform pg_temp.login(b);
  v := yahoo_group_status();
  perform pg_temp.assert(jsonb_array_length(v->'invites') = 1 and v->'invites'->0->>'host' = (select username from profiles where id = a), 'invitee sees the invite');
  -- refusals when accepting
  perform pg_temp.login(d);
  perform pg_temp.assert(pg_temp.hint_of(format('select yahoo_group_respond(%s, true)', g)) = 'not_invited', 'a stranger can''t accept');
  perform pg_temp.login(b);
  perform pg_temp.laptop(b, null);
  perform pg_temp.assert(pg_temp.hint_of(format('select yahoo_group_respond(%s, true)', g)) = 'no_laptop', 'member needs a laptop');
  perform pg_temp.laptop(b, 'laptop');
  perform pg_temp.at(b, 'oba_market');
  perform pg_temp.assert(pg_temp.hint_of(format('select yahoo_group_respond(%s, true)', g)) = 'wrong_place', 'member must be at HK or home on MiFi');
  perform pg_temp.at(b);
  perform pg_temp.assert(pg_temp.hint_of(format('select yahoo_group_respond(%s, true)', g)) = 'no_mifi', 'home without MiFi');
  perform pg_temp.at(b, 'hk_quarters');
  perform pg_temp.xp(b, 0);
  perform pg_temp.assert(pg_temp.hint_of(format('select yahoo_group_respond(%s, true)', g)) = 'skill_level', 'member level');
  perform pg_temp.xp(b, 40);
  -- b accepts: still inviting while c is pending
  v := yahoo_group_respond(g, true);
  perform pg_temp.assert(v->'group'->>'status' = 'inviting' and (v->'group'->>'ready')::int = 2 and v->'group'->>'my_status' = 'accepted', 'b accepted, c pending');
  perform pg_temp.assert(exists (select 1 from events where user_id = a and kind = 'yahoo_group_reply'), 'host told');
  -- everybody answered: it starts by itself
  perform pg_temp.login(c);
  v := yahoo_group_respond(g, true);
  perform pg_temp.assert(v->'group'->>'status' = 'running' and (select member_count from yahoo_groups where id = g) = 3, 'all accepted: running with 3');
  -- crew chance: base 20 cut by the AVERAGE level (3, 2, 2 -> 2.333; 4 % per level -> 5.33 %)
  v_pct := (select caught_pct from yahoo_groups where id = g);
  perform pg_temp.assert(v_pct = 18.93, 'group chance 18.93, got ' || v_pct);
  perform pg_temp.assert(bl_yahoo_group_pct(array[a, b, c], 20) = 18.93 and bl_yahoo_group_pct(array[d], 20) = 20
                         and bl_yahoo_group_pct(array[a], 20) = 18.4, 'the average level lowers the group chance');
  perform pg_temp.assert((select count(*) from profiles where id in (a, b, c) and busy_label = 'Yahoo: Crew hustle' and busy_until > bl_now()) = 3, 'the crew is busy');
  perform pg_temp.assert((select resolve_at - started_at from yahoo_groups where id = g) = interval '90 seconds', '90 s mission');
  perform pg_temp.assert((select count(*) from events where kind = 'yahoo_group_start' and user_id in (a, b, c)) = 3, 'start alerts');
  perform pg_temp.assert(pg_temp.hint_of(format('select yahoo_group_respond(%s, true)', g)) = 'closed', 'answers close once it runs');
  perform pg_temp.assert(pg_temp.hint_of('select yahoo_job_start(''chat_client'')') = 'busy', 'members can''t start a solo job meanwhile');
  raise notice 'ok 6: invite / accept / auto start / alert / push / average-level chance';
end $$;

-- ---------- 7. pay split + finish ----------
do $$
declare
  a uuid := current_setting('r6.a')::uuid; b uuid := current_setting('r6.b')::uuid; c uuid := current_setting('r6.c')::uuid;
  d uuid := current_setting('r6.d')::uuid; g bigint := current_setting('r6.g')::bigint; r jsonb; v jsonb; v_xp int;
begin
  perform pg_temp.dirty(a, 0); perform pg_temp.dirty(b, 0); perform pg_temp.dirty(c, 0); perform pg_temp.dirty(d, 0);
  select xp into v_xp from player_skills where user_id = b and skill_id = 'yahoo';
  perform pg_temp.login(a);
  perform pg_temp.assert(pg_temp.hint_of('select yahoo_group_finish()') = 'not_yet', 'not before the timer');
  perform pg_temp.advance(91);
  perform set_config('bl.test_rand', '0.99', true);   -- safe, and the pot roll lands near the top
  r := yahoo_group_finish();
  perform set_config('bl.test_rand', '', true);
  -- pot = 400k + floor(0.99 x 1,200,001) = 1,588,000; x 1.2 (3 members, +10 % each extra) = 1,905,600; /3 = 635,200 each
  perform pg_temp.assert(r->>'status' = 'paid' and (r->>'amount')::bigint = 635200 and (r->'group'->>'pot')::bigint = 1905600 and (r->'group'->>'per_member')::bigint = 635200, 'paid: pot 1,905,600 split 635,200');
  perform pg_temp.assert((select dirty from yahoo_players where user_id = a) = 635200 and (select dirty from yahoo_players where user_id = b) = 635200
                         and (select dirty from yahoo_players where user_id = c) = 635200 and (select dirty from yahoo_players where user_id = d) = 0, 'each member''s yahoo balance gets the share; others nothing');
  perform pg_temp.assert((select total_earned from yahoo_players where user_id = b) >= 635200 and (select jobs_done from yahoo_players where user_id = b) >= 1, 'earned + jobs_done count');
  perform pg_temp.assert((select count(*) from yahoo_ledger where reason = 'job' and (meta->>'group_id')::bigint = g and delta = 635200) = 3, 'three ledger lines');
  perform pg_temp.assert((select count(*) from profiles where id in (a, b, c) and busy_label is null and busy_until is null) = 3, 'busy cleared');
  perform pg_temp.assert((select status from yahoo_groups where id = g) = 'paid' and (select sum(payout) from yahoo_group_members where group_id = g) = 1905600, 'members record payouts');
  perform pg_temp.assert((select xp from player_skills where user_id = b and skill_id = 'yahoo') > v_xp, 'Yahoo XP awarded');
  perform pg_temp.assert((select count(*) from events where kind = 'yahoo_group_paid' and user_id in (a, b, c)) = 3, 'result alerts');
  -- another member sees it as "last", no open group
  perform pg_temp.login(b);
  v := yahoo_group_status();
  perform pg_temp.assert(v->'group' = 'null'::jsonb and v->'last'->>'status' = 'paid' and (v->'last'->>'per_member')::bigint = 635200, 'b sees the result with the split');
  perform pg_temp.assert(pg_temp.hint_of('select yahoo_group_finish()') = 'no_group', 'nothing left to finish');
  -- a status poll alone also settles an overdue group (nobody called finish)
  perform pg_temp.at(a, 'hk_quarters'); perform pg_temp.at(b, 'hk_quarters');
  raise notice 'ok 7: pay split / finish / ledger / XP';
end $$;

-- ---------- 8. cooldown for the host and the invitee ----------
do $$
declare
  a uuid := current_setting('r6.a')::uuid; b uuid := current_setting('r6.b')::uuid; c uuid := current_setting('r6.c')::uuid;
  d uuid := current_setting('r6.d')::uuid; v jsonb; g bigint;
begin
  perform pg_temp.at(a, 'hk_quarters'); perform pg_temp.at(b, 'hk_quarters'); perform pg_temp.at(c, 'hk_quarters'); perform pg_temp.at(d, 'hk_quarters');
  perform pg_temp.login(a);
  perform pg_temp.assert(pg_temp.hint_of(format('select yahoo_group_create(%L, %L)', 'crew_hustle', array[b])) = 'cooldown', 'host cooldown');
  perform pg_temp.assert((select (m->>'cooldown_until') is not null from jsonb_array_elements(yahoo_group_status()->'missions') m where m->>'id' = 'crew_hustle'), 'status shows the cooldown');
  -- another mission has its own cooldown (level 4 needed: a is level 3)
  perform pg_temp.assert(pg_temp.hint_of(format('select yahoo_group_create(%L, %L)', 'hk_big_table', array[b, c])) = 'skill_level', 'big table needs level 4');
  -- the invitee's cooldown: d (level 2) hosts, b was in the last crew
  perform pg_temp.xp(d, 40);
  perform pg_temp.login(d);
  v := yahoo_group_create('crew_hustle', array[b]);
  g := (v->'group'->>'id')::bigint;
  perform pg_temp.login(b);
  perform pg_temp.assert(pg_temp.hint_of(format('select yahoo_group_respond(%s, true)', g)) = 'cooldown', 'invitee cooldown');
  perform pg_temp.login(d);
  perform yahoo_group_cancel(g);
  -- after the cooldown it works again
  perform pg_temp.advance(601);
  perform pg_temp.at(a, 'hk_quarters'); perform pg_temp.at(b, 'hk_quarters'); perform pg_temp.at(d, 'hk_quarters');
  perform pg_temp.login(a);
  v := yahoo_group_create('crew_hustle', array[b]);
  perform pg_temp.assert(v->'group'->>'status' = 'inviting', 'cooldown over: can host again');
  g := (v->'group'->>'id')::bigint;
  perform pg_temp.login(b);
  perform yahoo_group_respond(g, true);
  perform pg_temp.assert((select status from yahoo_groups where id = g) = 'running' and (select member_count from yahoo_groups where id = g) = 2, 'a + b answered: it started with 2');
  perform set_config('r6.g2', g::text, true);
  raise notice 'ok 8: cooldown';
end $$;

-- ---------- 9. bust for all (fair penalties), then the start timer ----------
do $$
declare
  a uuid := current_setting('r6.a')::uuid; b uuid := current_setting('r6.b')::uuid; c uuid := current_setting('r6.c')::uuid;
  d uuid := current_setting('r6.d')::uuid; g bigint := current_setting('r6.g2')::bigint; r jsonb; v jsonb;
  v_busts_a int; v_busts_b int; v_wanted_a int;
begin
  perform pg_temp.dirty(a, 1000000); perform pg_temp.dirty(b, 400000); perform pg_temp.dirty(c, 300000);
  select busts into v_busts_a from yahoo_players where user_id = a;
  select busts into v_busts_b from yahoo_players where user_id = b;
  select wanted into v_wanted_a from profiles where id = a;
  perform pg_temp.cfg('yahoo.seize_laptop_pct', '100');
  perform pg_temp.login(b);
  perform pg_temp.advance(91);
  perform set_config('bl.test_rand', '0.0', true);   -- always caught
  r := yahoo_group_finish();
  perform set_config('bl.test_rand', '', true);
  perform pg_temp.assert(r->>'status' = 'caught' and r->'case' is not null and (r->>'amount')::bigint = 0, 'caught: the caller gets the EFCC popup data');
  perform pg_temp.assert((select count(*) from jail_cases where user_id in (a, b) and status = 'open' and kind = 'efcc' and (meta->>'group_id')::bigint = g) = 2, 'EVERY member gets an EFCC case');
  perform pg_temp.assert(not exists (select 1 from jail_cases where user_id in (c, d) and status = 'open'), 'non-members are untouched');
  perform pg_temp.assert((select dirty from yahoo_players where user_id = a) = 500000 and (select dirty from yahoo_players where user_id = b) = 200000
                         and (select dirty from yahoo_players where user_id = c) = 300000, 'fair penalty: half of each member''s yahoo balance taken');
  perform pg_temp.assert(pg_temp.qty(a, 'laptop') = 0 and pg_temp.qty(b, 'laptop') = 0 and pg_temp.qty(c, 'laptop') = 1, 'laptops seized (seize 100 %), only for members');
  perform pg_temp.assert((select busts from yahoo_players where user_id = a) = v_busts_a + 1 and (select busts from yahoo_players where user_id = b) = v_busts_b + 1, 'busts +1 each');
  perform pg_temp.assert((select wanted from profiles where id = a) = least(5, v_wanted_a + 1), 'wanted +1');
  perform pg_temp.assert((select count(*) from events where kind = 'efcc_caught' and user_id in (a, b) and (data->>'group_id')::bigint = g) = 2, 'both told');
  perform pg_temp.assert((select status from yahoo_groups where id = g) = 'caught' and (select sum(payout) from yahoo_group_members where group_id = g) = 0
                         and (select sum(seized) from yahoo_group_members where group_id = g) = 700000, 'group caught, nothing paid, 700k seized');
  perform pg_temp.assert((select count(*) from yahoo_ledger where reason = 'seized' and (meta->>'group_id')::bigint = g) = 2, 'EFCC seized ledger lines');
  perform pg_temp.assert((select jailed_until > bl_now() and location_id = 'police_hq' from profiles where id = a), 'jailed at police HQ');
  perform pg_temp.login(a);
  v := yahoo_group_status();
  perform pg_temp.assert(v->'last'->>'status' = 'caught' and (select bool_and((m->>'seized')::bigint >= 0) from jsonb_array_elements(v->'last'->'members') m), 'a sees the busted result');
  update jail_cases set status = 'released' where user_id in (a, b) and status = 'open';

  -- start timer: only the accepted come along, the silent one is expired; seize 0 % keeps the laptops
  update group_missions set cooldown_seconds = 0 where id = 'crew_hustle';
  perform pg_temp.cfg('yahoo.seize_laptop_pct', '0');
  perform pg_temp.advance(200);
  perform pg_temp.at(a, 'hk_quarters'); perform pg_temp.at(b, 'hk_quarters'); perform pg_temp.at(c, 'hk_quarters');
  perform pg_temp.laptop(a, 'laptop'); perform pg_temp.laptop(b, 'laptop');
  perform pg_temp.dirty(a, 600000); perform pg_temp.dirty(b, 600000);
  perform pg_temp.login(a);
  v := yahoo_group_create('crew_hustle', array[b, c]);
  g := (v->'group'->>'id')::bigint;
  perform pg_temp.login(b);
  perform yahoo_group_respond(g, true);
  perform pg_temp.assert((select status from yahoo_groups where id = g) = 'inviting', 'c is silent: still inviting');
  perform pg_temp.advance(121);
  perform pg_temp.login(a);
  v := yahoo_group_status();
  perform pg_temp.assert(v->'group'->>'status' = 'running' and (v->'group'->>'ready')::int = 2, 'the timer started it with the 2 who accepted');
  perform pg_temp.assert((select status from yahoo_group_members where group_id = g and user_id = c) = 'expired', 'the silent friend is expired');
  perform pg_temp.login(c);
  perform pg_temp.assert(jsonb_array_length(yahoo_group_status()->'invites') = 0, 'c has no open invite left');
  perform pg_temp.assert(pg_temp.hint_of(format('select yahoo_group_respond(%s, true)', g)) = 'closed', 'too late for c');
  -- an overdue group settles on a plain status poll (nobody calls finish)
  perform pg_temp.advance(91);
  perform pg_temp.login(a);
  perform set_config('bl.test_rand', '0.0', true);
  v := yahoo_group_status();
  perform set_config('bl.test_rand', '', true);
  perform pg_temp.assert((select status from yahoo_groups where id = g) = 'caught' and v->'group' = 'null'::jsonb and v->'last'->>'status' = 'caught', 'status poll settles an overdue group');
  perform pg_temp.assert((select count(*) from jail_cases where user_id in (a, b) and status = 'open' and (meta->>'group_id')::bigint = g) = 2
                         and pg_temp.qty(a, 'laptop') = 1 and pg_temp.qty(b, 'laptop') = 1, 'both busted; seize 0 % keeps the laptops');
  perform pg_temp.assert((select dirty from yahoo_players where user_id = a) = 300000, 'half confiscated again');
  update jail_cases set status = 'released' where user_id in (a, b) and status = 'open';
  raise notice 'ok 9: bust for all (fair penalties), start timer, overdue group settled by a poll';
end $$;

-- ---------- 10. dropped member, not enough, decline, cancel, start now ----------
do $$
declare
  a uuid := current_setting('r6.a')::uuid; b uuid := current_setting('r6.b')::uuid; c uuid := current_setting('r6.c')::uuid;
  d uuid := current_setting('r6.d')::uuid; v jsonb; g bigint;
begin
  perform pg_temp.advance(300);
  perform pg_temp.at(a, 'hk_quarters'); perform pg_temp.at(b, 'hk_quarters'); perform pg_temp.at(c, 'hk_quarters'); perform pg_temp.at(d, 'hk_quarters');
  perform pg_temp.laptop(a, 'laptop'); perform pg_temp.laptop(b, 'laptop'); perform pg_temp.laptop(c, 'laptop');
  -- a member who wandered off before the start is dropped; too few left = cancelled, nobody is stuck busy
  perform pg_temp.login(a);
  v := yahoo_group_create('crew_hustle', array[b, c]);
  g := (v->'group'->>'id')::bigint;
  perform pg_temp.login(b);
  perform yahoo_group_respond(g, true);
  perform pg_temp.at(b, 'oba_market');
  perform pg_temp.advance(121);
  perform pg_temp.login(a);
  v := yahoo_group_status();
  perform pg_temp.assert((select status from yahoo_groups where id = g) = 'cancelled' and v->'group' = 'null'::jsonb, 'b left HK: dropped, 1 of 2 left, cancelled');
  perform pg_temp.assert((select status from yahoo_group_members where group_id = g and user_id = b) = 'dropped'
                         and exists (select 1 from events where user_id = b and kind = 'yahoo_group_drop'), 'b dropped and told');
  perform pg_temp.assert((select busy_until is null from profiles where id = a), 'host not stuck busy');
  -- a laptop sold before the start also drops the member
  perform pg_temp.at(b, 'hk_quarters');
  -- hk_big_table: min 3, level 4; manual start refused while short, decline cancels
  perform pg_temp.xp(a, 260); perform pg_temp.xp(b, 260); perform pg_temp.xp(c, 260);
  perform pg_temp.login(a);
  v := yahoo_group_create('hk_big_table', array[b, c]);
  g := (v->'group'->>'id')::bigint;
  perform pg_temp.login(b);
  perform yahoo_group_respond(g, true);
  perform pg_temp.login(a);
  perform pg_temp.assert(pg_temp.hint_of(format('select yahoo_group_start(%s)', g)) = 'not_enough', '2 of 3 needed: start refused');
  perform pg_temp.assert(pg_temp.hint_of(format('select yahoo_group_respond(%s, false)', g)) = 'host', 'the host can''t decline, only cancel');
  perform pg_temp.login(c);
  v := yahoo_group_respond(g, false);
  perform pg_temp.assert((select status from yahoo_groups where id = g) = 'cancelled' and exists (select 1 from events where user_id = a and kind = 'yahoo_group_reply' and title like '%no dey follow%'),
                         'c declined: host told, 2 of 3 can''t run, cancelled');
  -- host cancel; non-host can't; closed afterwards
  perform pg_temp.login(a);
  v := yahoo_group_create('crew_hustle', array[b]);
  g := (v->'group'->>'id')::bigint;
  perform pg_temp.login(b);
  perform pg_temp.assert(pg_temp.hint_of(format('select yahoo_group_cancel(%s)', g)) = 'not_host', 'only the host cancels');
  perform pg_temp.assert(pg_temp.hint_of(format('select yahoo_group_start(%s)', g)) = 'not_host', 'only the host starts');
  perform pg_temp.login(a);
  perform yahoo_group_cancel(g);
  perform pg_temp.assert((select status from yahoo_groups where id = g) = 'cancelled', 'cancelled');
  perform pg_temp.login(b);
  perform pg_temp.assert(jsonb_array_length(yahoo_group_status()->'invites') = 0 and pg_temp.hint_of(format('select yahoo_group_respond(%s, true)', g)) = 'closed', 'invite gone, closed');
  -- start now with whoever accepted: 2 of 3 invited, an even split of the pot
  perform pg_temp.login(a);
  v := yahoo_group_create('crew_hustle', array[b, c]);
  g := (v->'group'->>'id')::bigint;
  perform pg_temp.login(b);
  perform yahoo_group_respond(g, true);
  perform pg_temp.login(a);
  perform pg_temp.dirty(a, 0); perform pg_temp.dirty(b, 0);
  v := yahoo_group_start(g);
  perform pg_temp.assert(v->'group'->>'status' = 'running' and (v->'group'->>'ready')::int = 2, 'host started it now with 2');
  perform pg_temp.assert((select status from yahoo_group_members where group_id = g and user_id = c) = 'expired', 'c expired');
  perform pg_temp.advance(91);
  perform set_config('bl.test_rand', '0.99', true);
  v := yahoo_group_finish();
  perform set_config('bl.test_rand', '', true);
  -- pot 1,588,000 x 1.1 (2 members) = 1,746,800 -> 873,400 each
  perform pg_temp.assert(v->>'status' = 'paid' and (v->>'amount')::bigint = 873400 and (select dirty from yahoo_players where user_id = a) = 873400
                         and (select dirty from yahoo_players where user_id = b) = 873400, 'even split between two: 873,400 each');
  raise notice 'ok 10: dropped / not enough / decline / cancel / start now';
end $$;

-- ---------- 11. HK Quarters as a work spot, and its interior ----------
do $$
declare
  c uuid := current_setting('r6.c')::uuid; v jsonb; r jsonb; v_keys text[]; n int;
begin
  perform pg_temp.login(c);
  perform pg_temp.advance(1000);
  perform pg_temp.at(c, 'hk_quarters');
  perform pg_temp.laptop(c, 'laptop');
  update profiles set cash = 20000, bank = 0 where id = c;
  update yahoo_players set mifi_until = null, desk_until = null where user_id = c;
  update yahoo_jobs set cooldown_seconds = 0 where id = 'chat_client';
  perform pg_temp.assert(pg_temp.hint_of('select yahoo_job_start(''chat_client'')') = 'no_desk', 'HK needs a desk pass, like the Wi-Fi Joint');
  v := yahoo_status();
  perform pg_temp.assert(v->'where'->>'message' like '%desk%' and v->'where'->>'hint' = 'no_desk', 'status: rent a desk');
  perform pg_temp.assert(v->'cafes' @> '[{"id":"hk_quarters"}]'::jsonb and v->'cafes' @> '[{"id":"wifi_joint"}]'::jsonb, 'cafes list HK Quarters and the Wi-Fi Joint');
  perform yahoo_buy_pass('desk');
  perform pg_temp.assert((yahoo_status()->'where'->>'ok')::boolean and yahoo_status()->'where'->>'place' = 'cafe', 'with a desk HK is a work spot');
  v := yahoo_job_start('chat_client');
  perform pg_temp.assert((select place = 'cafe' and location_id = 'hk_quarters' from yahoo_runs where id = (v->>'run_id')::bigint), 'job runs from HK');
  perform pg_temp.advance((v->>'seconds')::numeric + 1);
  perform set_config('bl.test_rand', '0.99', true);
  r := yahoo_finish();
  perform set_config('bl.test_rand', '', true);
  perform pg_temp.assert(r->>'status' = 'paid', 'paid from HK Quarters');
  -- other places still refuse
  perform pg_temp.at(c, 'oba_market');
  perform pg_temp.assert(pg_temp.hint_of('select yahoo_job_start(''chat_client'')') = 'wrong_place', 'a market is not a work spot');
  perform pg_temp.assert(yahoo_status()->'where'->>'message' like '%HK Quarters%', 'the message names HK Quarters');
  -- the interior is built from existing parts
  perform pg_temp.at(c, 'hk_quarters');
  v := place_interior('hk_quarters');
  select array_agg(z->>'key' order by z->>'key') into v_keys from jsonb_array_elements(v->'zones') z;
  perform pg_temp.assert(v_keys @> array['couches', 'desks', 'gen', 'laptops', 'snacks', 'wifi'], 'zones: ' || array_to_string(v_keys, ','));
  perform pg_temp.assert((select count(*) from jsonb_array_elements(v->'zones') z where jsonb_array_length(z->'actions') = 0) = 0, 'every zone has a card');
  perform pg_temp.assert((select z->>'prop' from jsonb_array_elements(v->'zones') z where z->>'key' = 'couches') = 'couches'
                         and (select z->>'prop' from jsonb_array_elements(v->'zones') z where z->>'key' = 'gen') = 'generator'
                         and (select z->>'prop' from jsonb_array_elements(v->'zones') z where z->>'key' = 'wifi') = 'router'
                         and (select z->>'prop' from jsonb_array_elements(v->'zones') z where z->>'key' = 'laptops') = 'desks', 'props: couches, generator, router, laptop desks');
  perform pg_temp.assert(exists (select 1 from jsonb_array_elements(v->'zones') z, jsonb_array_elements(z->'actions') ac where z->>'key' = 'wifi' and ac->>'kind' = 'panel' and ac->>'ref' = 'chat'), 'the Wi-Fi corner opens the place chat');
  perform pg_temp.assert(exists (select 1 from jsonb_array_elements(v->'zones') z, jsonb_array_elements(z->'actions') ac where z->>'key' = 'desks' and ac->>'ref' = 'laptop' and ac->>'locked' is null), 'laptops sold on the Computers desk');
  perform pg_temp.assert((v->>'open')::boolean and v->'location'->>'scene' = 'cyber', 'open all day');
  perform pg_temp.assert((select count(*) from place_moods where location_id = 'hk_quarters') = 3, 'mood lines');
  -- a hangout chat like other places
  perform pg_temp.assert(pg_temp.hint_of('select chat_send(''wetin dey, boys'')') = 'ok', 'chat_send works at HK Quarters');
  perform pg_temp.assert(exists (select 1 from chat_messages where location_id = 'hk_quarters' and user_id = c), 'the place chat stores the message at HK Quarters');
  raise notice 'ok 11: HK Quarters as a work spot + interior';
end $$;

-- ---------- 12. Elon format gate ----------
do $$
declare
  d uuid := current_setting('r6.d')::uuid; v jsonb; r jsonb; v_job jsonb; v_xp int;
begin
  perform pg_temp.login(d);
  perform pg_temp.advance(500);
  perform pg_temp.at(d, 'hk_quarters');
  update profiles set cash = 20000 where id = d;
  update yahoo_players set mifi_until = null, desk_until = bl_now() + interval '1 day' where user_id = d;
  perform pg_temp.xp(d, 40);
  perform pg_temp.laptop(d, 'laptop');
  perform pg_temp.assert(pg_temp.hint_of('select yahoo_job_start(''elon_format'')') = 'laptop_too_weak', 'the old laptop can''t carry the Elon format');
  perform pg_temp.laptop(d, 'thinkpad_t480');
  perform pg_temp.assert(pg_temp.hint_of('select yahoo_job_start(''elon_format'')') = 'skill_level', 'Yahoo level 2 is too low');
  select j into v_job from jsonb_array_elements(yahoo_status()->'jobs') j where j->>'id' = 'elon_format';
  perform pg_temp.assert(v_job->>'locked' = 'skill_level' and (v_job->>'min_skill_level')::int = 4, 'status: locked, level 4');
  -- admin tunes the gate
  update yahoo_jobs set min_skill_level = 5 where id = 'elon_format';
  perform pg_temp.xp(d, 260);
  perform pg_temp.assert(pg_temp.hint_of('select yahoo_job_start(''elon_format'')') = 'skill_level', 'admin raised the gate to level 5');
  update yahoo_jobs set min_skill_level = 4 where id = 'elon_format';
  select j into v_job from jsonb_array_elements(yahoo_status()->'jobs') j where j->>'id' = 'elon_format';
  perform pg_temp.assert(v_job->>'locked' is null and (v_job->>'caught_pct')::numeric = 19 and (v_job->>'skill_caught_pct')::numeric = 16.72, 'level 4: open, 20 - 1 ThinkPad pt = 19 %, level cut 12 % = 16.72 %');
  select xp into v_xp from player_skills where user_id = d and skill_id = 'yahoo';
  v := yahoo_job_start('elon_format');
  perform pg_temp.advance((v->>'seconds')::numeric + 1);
  perform set_config('bl.test_rand', '0.5', true);
  r := yahoo_finish();
  perform set_config('bl.test_rand', '', true);
  -- 200k + floor(0.5 x 1,000,001) = 700,000, + 5 % ThinkPad = 735,000
  perform pg_temp.assert(r->>'status' = 'paid' and (r->>'amount')::bigint = 735000, 'Elon format pays 735,000 at a mid roll with a ThinkPad');
  perform pg_temp.assert((select xp from player_skills where user_id = d and skill_id = 'yahoo') > v_xp, 'Yahoo XP');
  perform pg_temp.assert(pg_temp.hint_of('select yahoo_job_start(''elon_format'')') = 'cooldown', 'cooldown 180 s');
  raise notice 'ok 12: Elon format gate';
end $$;

-- ---------- 13. RLS + the admin table ----------
do $$
declare
  adm uuid := current_setting('r6.adm')::uuid; a uuid := current_setting('r6.a')::uuid; b uuid := current_setting('r6.b')::uuid;
  n int; v jsonb; v_denied boolean;
begin
  perform pg_temp.login(b);
  set local role authenticated;
  select count(*) into n from group_missions;
  perform pg_temp.assert(n >= 2, 'players read the mission catalogue');
  v_denied := false;
  begin perform count(*) from yahoo_groups; exception when insufficient_privilege then v_denied := true; end;
  perform pg_temp.assert(v_denied, 'yahoo_groups is server-only');
  v_denied := false;
  begin perform count(*) from yahoo_group_members; exception when insufficient_privilege then v_denied := true; end;
  perform pg_temp.assert(v_denied, 'yahoo_group_members is server-only');
  v_denied := false;
  begin insert into group_missions (id, name) values ('hack', 'Hack'); exception when insufficient_privilege then v_denied := true; end;
  perform pg_temp.assert(v_denied, 'players can''t write missions');
  reset role;
  set local role anon;
  v_denied := false;
  begin perform count(*) from group_missions; exception when insufficient_privilege then v_denied := true; end;
  reset role;
  perform pg_temp.assert(v_denied, 'anon can''t read missions');
  perform pg_temp.assert(not has_table_privilege('authenticated', 'public.yahoo_groups', 'select') and not has_table_privilege('anon', 'public.yahoo_group_members', 'select'), 'table privileges');
  perform pg_temp.assert((select relrowsecurity from pg_class where oid = 'public.yahoo_groups'::regclass)
                         and (select relrowsecurity from pg_class where oid = 'public.yahoo_group_members'::regclass)
                         and (select relrowsecurity from pg_class where oid = 'public.group_missions'::regclass), 'RLS on');
  -- the admin table
  perform pg_temp.assert(pg_temp.hint_of('select admin_row_upsert(''group_missions'', ''{"id":"crew_hustle","caught_pct":21}'')') <> 'ok', 'non-admin refused');
  perform pg_temp.login(adm);
  perform admin_row_upsert('group_missions', '{"id":"crew_hustle","caught_pct":21,"reward_max":1700000}');
  perform pg_temp.assert((select caught_pct = 21 and reward_max = 1700000 from group_missions where id = 'crew_hustle'), 'admin edits a mission');
  perform admin_row_upsert('group_missions', '{"id":"test_mission","name":"Test crew","icon":"🧪","blurb":"x","min_members":2,"max_members":3,"duration_seconds":30,"reward_min":1000,"reward_max":2000,"caught_pct":10,"min_yahoo_level":1,"invite_seconds":30,"cooldown_seconds":0,"sort":9,"active":true}');
  perform pg_temp.assert(exists (select 1 from group_missions where id = 'test_mission' and max_members = 3), 'admin adds a mission');
  perform pg_temp.assert(pg_temp.hint_of('select admin_row_upsert(''group_missions'', ''{"id":"test_mission","min_members":1}'')') <> 'ok', 'min members under 2 refused');
  perform pg_temp.login(a);
  perform pg_temp.assert((select m->>'caught_pct' from jsonb_array_elements(yahoo_group_status()->'missions') m where m->>'id' = 'crew_hustle') = '21'
                         and exists (select 1 from jsonb_array_elements(yahoo_group_status()->'missions') m where m->>'id' = 'test_mission'), 'players see the edits');
  raise notice 'ok 13: RLS / admin table';
  raise notice 'ALL YAHOO STRATEGY TESTS PASSED';
end $$;
