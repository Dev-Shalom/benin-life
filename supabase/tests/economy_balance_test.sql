-- E3 economy balance (20261019000100_economy_balance.sql). Rolled back. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/economy_balance_test.sql
-- Groups: 1 seeds after the migration (tuned values, new column, new setting) · 2 yahoo daily cap (solo job, status card, next day, cash out
-- never capped) · 3 group mission daily cap · 4 Market business loop closed (invested is capped at the catalogue value) · 5 crew disband fee ·
-- 6 referral milestone needs real play · 7 the ladder: risk-adjusted crime vs the legit tier next to it · 8 business payback with stock.
-- Chances (the percentages) are in odds_test.sql.
-- The owner removed the Yahoo daily limits (20261019000300). Pin the E3 caps so the cap mechanism is still tested.
update public.yahoo_jobs set daily_cap = case id when 'chat_client' then 15 when 'romance_job' then 8 when 'elon_format' then 4 when 'big_job' then 3 else 0 end;
update public.group_missions set daily_cap = 3 where id in ('crew_hustle', 'hk_big_table');
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

create or replace function pg_temp.at(p_uid uuid, p_loc text default null) returns void
language sql as $$
  update profiles set location_id = coalesce(p_loc, home_location_id), travel_to = null, travel_mode = null, travel_started_at = null,
                      travel_arrives_at = null, busy_until = null, busy_label = null, busy_started_at = null, busy_needs_from = null,
                      jailed_until = null, jail_reason = null, hospitalized_until = null, home_visit_host_id = null,
                      last_seen = now(), rent_due_at = null, energy = 100, hunger = 100, health = 100
   where id = p_uid;
$$;

create or replace function pg_temp.mk(p_email text, p_name text) returns uuid
language plpgsql as $$
declare u uuid := pg_temp.new_user(p_email);
begin
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform pg_temp.login(u);
  perform create_profile_v2(p_name, 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  perform pg_temp.at(u);
  update profiles set created_at = now() - interval '30 days', protected_until = null, cash = 0, bank = 0, transfer_trusted = true where id = u;
  delete from inventory where user_id = u;
  return u;
end $$;

do $$
declare a uuid; b uuid; c uuid; d uuid;
begin
  perform set_config('bl.test_offset_seconds', '0', true);
  perform set_config('bl.test_rand', '', true);
  a := pg_temp.mk('e3_a@ee.bl', 'E3_A'); b := pg_temp.mk('e3_b@ee.bl', 'E3_B'); c := pg_temp.mk('e3_c@ee.bl', 'E3_C'); d := pg_temp.mk('e3_d@ee.bl', 'E3_D');
  perform set_config('e3.a', a::text, true); perform set_config('e3.b', b::text, true); perform set_config('e3.c', c::text, true); perform set_config('e3.d', d::text, true);
  update profiles set cash = 100000000, bank = 1000000000 where id in (a, b, c, d);
  update yahoo_jobs set active = true;
  perform pg_temp.cfg('yahoo.cafe_locations', '"wifi_joint"');
  perform pg_temp.cfg('skills.enabled', 'false');
end $$;

-- ---------- 1. seeds ----------
do $$
begin
  perform pg_temp.assert((select count(*) from information_schema.columns where table_name in ('yahoo_jobs', 'group_missions') and column_name = 'daily_cap') = 2, 'daily_cap on both tables');
  perform pg_temp.assert((select daily_cap from yahoo_jobs where id = 'chat_client') = 15 and (select daily_cap from yahoo_jobs where id = 'big_job') = 3
                         and (select daily_cap from yahoo_jobs where id = 'cash_out') = 0, 'yahoo caps (owner middle ground): chat 15, big 3, cash out uncapped');
  perform pg_temp.assert((select value::text from game_config where key = 'crew.disband_fee_pct') = '10', 'disband fee 10');
  -- the owner's explicit values are untouched
  perform pg_temp.assert((select value::text from game_config where key = 'origin.lapo.start_cash') = '85000', 'LAPO start cash is still 85,000');
  perform pg_temp.assert((select value::text from game_config where key = 'club.pick_note') = '10000' and (select value::text from game_config where key = 'club.pick_pct') = '20', 'money pick N10k / 20% untouched');
  perform pg_temp.assert((select value::text from game_config where key = 'club.weekend_price_mult') = '1.5', 'club weekend x1.5 untouched');
  perform pg_temp.assert((select caught_pct from yahoo_jobs where id = 'chat_client') = 12 and (select caught_pct from yahoo_jobs where id = 'romance_job') = 16
                         and (select caught_pct from yahoo_jobs where id = 'big_job') = 24 and (select caught_pct from yahoo_jobs where id = 'cash_out') = 14, 'yahoo fairer catch chances untouched');
  perform pg_temp.assert((select value::text from game_config where key = 'yahoo.seize_laptop_pct') = '35' and (select value::text from game_config where key = 'yahoo.confiscate_pct') = '50', 'seize / confiscate untouched');
  perform pg_temp.assert((select price from shrine_services where id = 'money_charm') = 3000000 and (select price from shrine_services where id = 'efcc_blindfold') = 1200000, 'Babalawo prices untouched');
  perform pg_temp.assert((select price from items where id = 'cow') = 1440000 and (select price from items where id = 'goat') = 102000, 'Babalawo offerings (x1.2) untouched');
  -- tuned
  -- owner decision: Yahoo pay and gates stay as approved; only daily caps were added
  perform pg_temp.assert((select pay_min = 5000 and pay_max = 50000 from yahoo_jobs where id = 'chat_client')
                         and (select pay_min = 500000 and pay_max = 3000000 from yahoo_jobs where id = 'big_job'), 'yahoo pay untouched (owner)');
  perform pg_temp.assert((select daily_cap from yahoo_jobs where id = 'romance_job') = 8 and (select daily_cap from yahoo_jobs where id = 'elon_format') = 4, 'romance 8, Elon 4 a day');
  perform pg_temp.assert((select restock_cost from business_types where id = 'filling_station') = 44000, 'filling station restock');
  perform pg_temp.assert((select salary_per_day from offices where id = 'governor') = 50000, 'governor salary');
  perform pg_temp.assert((select value::text from game_config where key = 'referral.min_shifts') = '9', 'referral milestone: 9 shifts');
  perform pg_temp.assert(has_function_privilege('authenticated', 'public.yahoo_job_start(text,bigint)', 'execute')
                         and not has_function_privilege('authenticated', 'public.bl_yahoo_runs_today(uuid,text)', 'execute')
                         and not has_function_privilege('anon', 'public.bl_yahoo_group_runs_today(uuid,text)', 'execute'), 'grants: RPC kept, helpers private');
  raise notice 'ok 1: seeds';
end $$;

-- ---------- 2. yahoo daily cap ----------
do $$
declare
  u uuid := current_setting('e3.a')::uuid; i int; v jsonb; st jsonb; x jsonb;
begin
  perform pg_temp.login(u);
  delete from inventory where user_id = u and item_id in (select item_id from laptop_specs);
  perform bl_give_item(u, 'laptop', 1);
  perform pg_temp.at(u); perform bl_yahoo_row(u);
  update yahoo_players set mifi_until = bl_now() + interval '30 days' where user_id = u;
  update yahoo_jobs set daily_cap = 3 where id = 'chat_client';
  for i in 1 .. 3 loop
    perform set_config('bl.test_rand', '0.9999999', true);                     -- never caught
    v := yahoo_job_start('chat_client', null);
    perform pg_temp.advance((v->>'seconds')::numeric + 40);
    perform yahoo_finish();
    perform set_config('bl.test_rand', '', true);
  end loop;
  perform pg_temp.assert(pg_temp.hint_of('select yahoo_job_start(''chat_client'', null)') = 'daily_cap', 'the 4th run today is refused with daily_cap');
  st := yahoo_status();
  select x2 into x from jsonb_array_elements(st->'jobs') x2 where x2->>'id' = 'chat_client';
  perform pg_temp.assert((x->>'daily_cap')::int = 3 and (x->>'cap_left')::int = 0 and x->>'locked' = 'daily_cap', 'the card says 0 left and locked daily_cap');
  select x2 into x from jsonb_array_elements(st->'jobs') x2 where x2->>'id' = 'romance_job';
  perform pg_temp.assert((x->>'cap_left')::int = 8, 'romance: 8 left today');
  -- cash out is never capped
  update yahoo_jobs set daily_cap = 1 where id = 'cash_out';
  update yahoo_players set dirty = 50000 where user_id = u;
  perform yahoo_cashout_start('full');
  perform pg_temp.advance(30);
  perform set_config('bl.test_rand', '0.9999999', true); perform yahoo_finish(); perform set_config('bl.test_rand', '', true);
  perform pg_temp.advance(70);
  update yahoo_players set dirty = 50000 where user_id = u;
  perform yahoo_cashout_start('full');                                          -- a second cash out the same day is fine
  perform pg_temp.advance(30);
  perform set_config('bl.test_rand', '0.9999999', true); perform yahoo_finish(); perform set_config('bl.test_rand', '', true);
  update yahoo_jobs set daily_cap = 0 where id = 'cash_out';
  -- tomorrow (Benin time) the cap is fresh
  perform pg_temp.advance(24 * 3600);
  perform pg_temp.assert(pg_temp.hint_of('select yahoo_job_start(''chat_client'', null)') = 'ok', 'next day: allowed again');
  update yahoo_jobs set daily_cap = 8 where id = 'chat_client';
  -- the escape % on the Yahoo screen is the one the roll uses (vanishing charm caps it, bad luck adds)
  perform pg_temp.assert((yahoo_status()->'prices'->>'escape_caught_pct')::numeric = 55, 'escape 55 on the Yahoo screen');
  insert into player_charms (user_id, kind, uses_left, data) values (u, 'vanishing', 3, '{"value":30}');
  perform pg_temp.assert((yahoo_status()->'prices'->>'escape_caught_pct')::numeric = 30, 'vanishing charm: the screen says 30');
  insert into player_charms (user_id, kind, data) values (u, 'bad_luck', '{"value":1,"caught_pts":10}');
  perform pg_temp.assert((yahoo_status()->'prices'->>'escape_caught_pct')::numeric = 40, 'plus bad luck: 40');
  delete from player_charms where user_id = u;
  raise notice 'ok 2: yahoo daily cap';
end $$;

-- ---------- 3. group mission daily cap ----------
do $$
declare
  a uuid := current_setting('e3.a')::uuid; b uuid := current_setting('e3.b')::uuid; m group_missions; g bigint; v_gate jsonb; st jsonb; x jsonb;
begin
  select * into m from group_missions where id = 'crew_hustle';
  perform pg_temp.assert(m.daily_cap = 3, 'crew hustle: 3 a day');
  update yahoo_jobs set min_tier = 0;
  perform pg_temp.at(a); perform pg_temp.at(b);
  delete from yahoo_runs where user_id in (a, b); delete from inventory where user_id in (a, b) and item_id in (select item_id from laptop_specs);
  perform bl_give_item(a, 'laptop', 1); perform bl_give_item(b, 'laptop', 1);
  perform bl_yahoo_row(b); update yahoo_players set mifi_until = bl_now() + interval '30 days' where user_id in (a, b);
  perform pg_temp.assert(bl_yahoo_group_gate(a, m, 'join') is null, 'before any run: the gate is open');
  for g in 1 .. 3 loop
    perform pg_temp.advance(1);
    insert into yahoo_groups (mission_id, name, host_id, status, start_at, started_at, resolved_at) values (m.id, m.name, a, 'paid', bl_now(), bl_now(), bl_now()) returning id into g;
    insert into yahoo_group_members (group_id, user_id, status) values (g, a, 'accepted'), (g, b, 'accepted');
  end loop;
  update group_missions set cooldown_seconds = 0 where id = m.id;
  select * into m from group_missions where id = 'crew_hustle';
  v_gate := bl_yahoo_group_gate(a, m, 'join');
  perform pg_temp.assert(v_gate->>'hint' = 'daily_cap', 'after 3 runs the join gate says daily_cap (got ' || coalesce(v_gate::text, 'null') || ')');
  perform pg_temp.assert(bl_yahoo_group_gate(a, m, 'start') is null, 'a mission that already started is not dropped by the cap');
  perform pg_temp.login(a);
  st := yahoo_group_status();
  select x2 into x from jsonb_array_elements(st->'missions') x2 where x2->>'id' = m.id;
  perform pg_temp.assert((x->>'cap_left')::int = 0 and (x->>'daily_cap')::int = 3, 'the mission card shows 0 left of 3');
  perform pg_temp.advance(24 * 3600);
  perform pg_temp.assert(bl_yahoo_group_gate(a, m, 'join') is null, 'next day the gate opens');
  raise notice 'ok 3: group cap';
end $$;

-- ---------- 4. Market: a business bought dear can no longer be sold back to the system for more than it is worth ----------
do $$
declare
  a uuid := current_setting('e3.a')::uuid; b uuid := current_setting('e3.b')::uuid; v_plot text; v_biz bigint; v_val bigint; v_price bigint; r jsonb; v_l bigint;
  v_tot0 bigint; v_tot1 bigint; v_inv bigint;
begin
  perform pg_temp.cfg('business.enabled', 'true');
  select p.id into v_plot from business_plots p where p.active and not exists (select 1 from businesses x where x.plot_id = p.id) and 'provision_shop' = any (select unnest(coalesce(nullif(p.type_ids, '{}'), array['provision_shop']))) limit 1;
  select (select bank + cash from profiles where id = a) + (select bank + cash from profiles where id = b) into v_tot0;
  perform pg_temp.login(a);
  r := business_buy('provision_shop', v_plot, 'Loop Shop');
  v_biz := (r->'business'->>'id')::bigint;
  select bl_biz_value(x) into v_val from businesses x where id = v_biz;
  v_price := floor(v_val * 2.5);                                                  -- the top of the band
  update businesses set ready_at = bl_now() - interval '1 hour', bought_at = bl_now() - interval '2 days' where id = v_biz;
  perform pg_temp.advance(25 * 3600);                                             -- past the flip wait
  update businesses set ready_at = bl_now() - interval '1 hour', last_collect_at = bl_now(), settled_at = bl_now() where id = v_biz;
  r := market_list('business', v_biz::text, 1, v_price);
  v_l := (r->'listing'->>'id')::bigint;
  perform pg_temp.login(b);
  perform market_buy(v_l);
  select invested into v_inv from businesses where id = v_biz;
  perform pg_temp.assert(v_inv = v_val, 'the buyer''s invested is the catalogue value ' || v_val || ', not the price paid ' || v_price || ' (got ' || v_inv || ')');
  perform business_sell(v_biz);
  select (select bank + cash from profiles where id = a) + (select bank + cash from profiles where id = b) into v_tot1;
  -- the pair paid the system the value, got 60% of it back and paid the 8% market fee: it can only lose
  perform pg_temp.assert(v_tot1 < v_tot0, 'a lap through the Market no longer creates money (before ' || v_tot0 || ', after ' || v_tot1 || ')');
  perform pg_temp.assert(v_tot1 - v_tot0 = -(floor(v_price * 0.08) + (v_val - floor(v_val * 0.6))), 'the loss is exactly the 8% fee plus 40% of the value (' || (v_tot1 - v_tot0) || ' vs ' || -(floor(v_price * 0.08) + (v_val - floor(v_val * 0.6))) || ')');
  raise notice 'ok 4: market loop (a lap costs % )', v_tot0 - v_tot1;
end $$;

-- ---------- 5. crew disband fee ----------
do $$
declare
  a uuid := current_setting('e3.a')::uuid; b uuid := current_setting('e3.b')::uuid; c uuid := current_setting('e3.c')::uuid; cr bigint; v jsonb; v_ba bigint; v_bb bigint; v_bc bigint; cr2 bigint;
begin
  delete from crew_members where user_id in (a, b, c);
  insert into crews (name, tag, created_by, bank) values ('Fee Crew', 'FEE', a, 1000000) returning id into cr;
  insert into crew_members (user_id, crew_id, rank) values (a, cr, 'boss'), (b, cr, 'member'), (c, cr, 'member');
  select bank into v_ba from profiles where id = a; select bank into v_bb from profiles where id = b; select bank into v_bc from profiles where id = c;
  perform pg_temp.login(a);
  v := bl_crew_dissolve(cr, null, 'fee test');
  perform pg_temp.assert((v->>'fee')::bigint = 100000 and (v->>'bank')::bigint = 1000000, 'fee 10% of the bank');
  perform pg_temp.assert((select bank from profiles where id = b) = v_bb + 300000 and (select bank from profiles where id = c) = v_bc + 300000
                         and (select bank from profiles where id = a) = v_ba + 300000 + 0, 'the other 900,000 is shared equally (300,000 each)');
  -- an admin disband charges nothing
  insert into crews (name, tag, created_by, bank) values ('Admin Crew', 'ADM', a, 900000) returning id into cr2;
  insert into crew_members (user_id, crew_id, rank) values (a, cr2, 'boss'), (b, cr2, 'member'), (c, cr2, 'member');
  select bank into v_bb from profiles where id = b;
  v := bl_crew_dissolve(cr2, a, 'admin');
  perform pg_temp.assert((v->>'fee')::bigint = 0 and (select bank from profiles where id = b) = v_bb + 300000, 'admin disband: no fee, 300,000 each');
  -- fee 0 = the old behaviour
  perform pg_temp.cfg('crew.disband_fee_pct', '0');
  insert into crews (name, tag, created_by, bank) values ('Free Crew', 'FRE', a, 600000) returning id into cr2;
  insert into crew_members (user_id, crew_id, rank) values (a, cr2, 'boss'), (b, cr2, 'member');
  select bank into v_bb from profiles where id = b;
  v := bl_crew_dissolve(cr2, null, 'no fee');
  perform pg_temp.assert((v->>'fee')::bigint = 0 and (select bank from profiles where id = b) = v_bb + 300000, 'fee 0: 300,000 each');
  perform pg_temp.cfg('crew.disband_fee_pct', '10');
  raise notice 'ok 5: disband fee';
end $$;

-- ---------- 6. referral milestone ----------
do $$
declare d uuid := current_setting('e3.d')::uuid; p jsonb;
begin
  update profiles set job_total_shifts = 1 where id = d;
  p := bl_referral_progress(d);
  perform pg_temp.assert(not (p->>'met')::boolean and (p->>'need_shifts')::int = 9, 'one shift no longer completes the milestone');
  update profiles set job_total_shifts = 9 where id = d;
  perform pg_temp.assert((bl_referral_progress(d)->>'met')::boolean, 'nine shifts do');
  update profiles set job_total_shifts = 0 where id = d;
  perform pg_temp.assert((select (value #>> '{}')::numeric from game_config where key = 'referral.bonus_referrer') = 10000, 'bonus 10,000 each');
  raise notice 'ok 6: referral';
end $$;

-- ---------- 7. the ladder ----------
-- Risk-adjusted crime per day at the cap, from the live tables, against the legit tier next to it (3 shifts a day):
--   starter = average level-1 pay (trade, pos, transport, health, tech) x 3, mid = average level 3 x 3, senior = average level 5 x 3.
-- Yahoo EV per run = (1 - caught) x pay - caught x (35 % x laptop price + 50 % x the balance in flight) - the cash-out leg; then x cap - desk.
create or replace function pg_temp.yahoo_day(p_job text, p_laptop text, p_level int, p_per_cash int default 4) returns numeric
language plpgsql as $$
declare
  j yahoo_jobs; co yahoo_jobs; sp laptop_specs; lp numeric; k skills; c numeric; cc numeric; pay numeric; ev numeric; v_cut numeric; v_bal numeric; f numeric; v_val numeric;
begin
  select * into j from yahoo_jobs where id = p_job; select * into co from yahoo_jobs where id = 'cash_out';
  select * into sp from laptop_specs where item_id = p_laptop; select price into lp from items where id = p_laptop;
  select * into k from skills where id = 'yahoo';
  v_cut := least(k.caught_cap_pct, (p_level - 1) * k.caught_pct_per_level);
  c := greatest(least(j.caught_pct, 5), j.caught_pct - sp.efcc_minus_pts) * (1 - v_cut / 100) / 100;
  cc := greatest(least(co.caught_pct, 5), co.caught_pct - sp.efcc_minus_pts) * (1 - v_cut / 100) / 100;
  pay := (j.pay_min + j.pay_max) / 2.0 * (1 + sp.pay_bonus_pct / 100);
  v_bal := pay * (p_per_cash - 1) / 2;
  ev := (1 - c) * pay - c * (0.35 * lp + 0.5 * v_bal);
  v_val := pay * p_per_cash * (1 - c);
  f := 1 - (1 - cc) / (1 - cc / 2);
  ev := ev - (f * v_val + cc * 0.35 * lp) / p_per_cash;
  return coalesce(nullif(j.daily_cap, 0), 1) * ev - 5000;
end $$;

do $$
declare v_start numeric; v_mid numeric; v_sen numeric; v_chat numeric; v_rom numeric; v_elon numeric; v_big numeric;
begin
  select avg(pay_per_shift) * 3 into v_start from career_levels where level = 1 and track_id in ('trade', 'pos', 'transport', 'health', 'tech');
  select avg(pay_per_shift) * 3 into v_mid   from career_levels where level = 3 and track_id in ('trade', 'pos', 'transport', 'health', 'tech', 'education');
  select avg(pay_per_shift) * 3 into v_sen   from career_levels where level = 5 and track_id in ('trade', 'health', 'tech', 'education');
  v_chat := pg_temp.yahoo_day('chat_client', 'laptop', 1);
  v_rom  := pg_temp.yahoo_day('romance_job', 'thinkpad_t480', 2);
  v_elon := pg_temp.yahoo_day('elon_format', 'elitebook_840', 4);
  v_big  := pg_temp.yahoo_day('big_job', 'dell_xps_13', 3);
  raise notice 'ladder: legit starter %, mid %, senior % a day | crime EV/day: chat % (x%), romance % (x%), elon % (x%), big % (x%)',
    round(v_start), round(v_mid), round(v_sen), round(v_chat), round(v_chat / v_start, 2), round(v_rom), round(v_rom / v_mid, 2), round(v_elon), round(v_elon / v_sen, 2), round(v_big), round(v_big / v_sen, 2);
  -- Yahoo ratios are reported, not asserted: the owner kept the approved pay (caps only).
  if false then perform pg_temp.assert(v_chat / v_start between 1.2 and 2.2, 'chat client is 1.2-2.2 x a starter day (' || round(v_chat / v_start, 2) || ')');
  perform pg_temp.assert(v_rom / v_mid between 1.2 and 2.2, 'romance is 1.2-2.2 x a mid-tier day (' || round(v_rom / v_mid, 2) || ')');
  perform pg_temp.assert(v_elon / v_sen between 1.0 and 2.2, 'Elon is 1-2.2 x a senior day (' || round(v_elon / v_sen, 2) || ')');
  perform pg_temp.assert(v_big / v_sen between 1.3 and 2.4, 'Big job is 1.3-2.4 x a senior day (' || round(v_big / v_sen, 2) || ')');
  perform pg_temp.assert(v_big < (select pay_per_shift * 3 from career_levels where track_id = 'tech' and level = 7), 'Big job per day is below a CTO day'); end if;
  -- crews: per member per job (3 members, no crew level bonus, the default 30 % to the bank) against the mid tier, 3 jobs a day
  perform pg_temp.assert((select ((reward_min + reward_max) / 2.0 * (1 + 0.08 * 2) * 0.7 / 3 * (1 - 0.22)) * 3 from crew_jobs where id = 'market_shakedown') between 0.9 * v_mid and 2.2 * v_mid,
    'shakedown, 3 jobs a day, is about the mid tier');
  -- group missions: owner kept the pots; 3 a day each
  perform pg_temp.assert((select daily_cap from group_missions where id = 'crew_hustle') = 3 and (select daily_cap from group_missions where id = 'hk_big_table') = 3, 'group missions 3 a day');
  raise notice 'ok 7: ladder';
end $$;

-- ---------- 8. business payback with stock: every type between 50 and 130 days, and stocking always pays more than not stocking ----------
do $$
declare t record; v_net numeric; v_unst numeric;
begin
  for t in select * from business_types where active loop
    v_net := (t.income_min + t.income_max) / 2.0 - t.rent_day - t.power_day - t.restock_cost / 2.0;
    v_unst := 0.5 * (t.income_min + t.income_max) / 2.0 - t.rent_day - t.power_day;
    perform pg_temp.assert(v_net > v_unst, t.id || ': stocking pays more than not stocking (' || round(v_net) || ' vs ' || round(v_unst) || ' a day)');
    perform pg_temp.assert(t.price / v_net between 50 and 130, t.id || ': payback ' || round(t.price / v_net) || ' days is between 50 and 130');
  end loop;
  raise notice 'ok 8: business payback';
end $$;
