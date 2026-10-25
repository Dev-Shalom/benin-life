-- Money ranges on leaderboards (20261025000200_rank_bands.sql, docs/RANKS.md). Rolled back. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/rank_bands_test.sql
-- Groups: 1 helper labels + custom edges · 2 Rich list · 3 VIP list · 4 Weekly (rows, me, last week, prizes) · 5 Gangs · 6 Philanthropists
-- · 7 hide_amounts off restores the exact numbers · 8 the helpers are private.
create or replace function pg_temp.mk(p_name text, p_cash bigint) returns uuid
language plpgsql as $$
declare v uuid := pg_temp.new_user(lower(p_name) || '@band.bl');
begin
  perform pg_temp.login(v);
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform create_profile_v2(p_name, 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  update profiles set rent_owed = 0, busy_until = null, cash = p_cash, bank = 0 where id = v;
  return v;
end $$;

-- the row of a player in a board's rows array
create or replace function pg_temp.row_of(p_rows jsonb, p_name text) returns jsonb
language sql as $$ select r from jsonb_array_elements(p_rows) r where r->>'username' = p_name $$;

do $$
declare
  a uuid; b uuid; c uuid; adm uuid;
  r jsonb; x jsonb; v_wk date := bl_week_start(); v_crew1 bigint; v_crew2 bigint;
begin
  -- 1. helper labels at every edge
  perform pg_temp.assert(bl_money_band(null) is null and bl_money_band(0) is null, 'zero / null = no band');
  perform pg_temp.assert(bl_money_band(1) = 'Under ₦1M' and bl_money_band(999999) = 'Under ₦1M', 'under 1M: ' || bl_money_band(999999));
  perform pg_temp.assert(bl_money_band(1000000) = '₦1M – ₦10M' and bl_money_band(9999999) = '₦1M – ₦10M', '1M band');
  perform pg_temp.assert(bl_money_band(10000000) = '₦10M – ₦100M', '10M band');
  perform pg_temp.assert(bl_money_band(100000000) = '₦100M – ₦1B', '100M band');
  perform pg_temp.assert(bl_money_band(1000000000) = '₦1B – ₦10B' and bl_money_band(9999999999) = '₦1B – ₦10B', '1B band');
  perform pg_temp.assert(bl_money_band(10000000000) = '₦10B+' and bl_money_band(99000000000000) = '₦10B+', 'top band: ' || bl_money_band(10000000000));
  perform pg_temp.assert(bl_money_short(250000) = '₦250K' and bl_money_short(1500000000) = '₦1.5B' and bl_money_short(2000000000000) = '₦2T', 'short labels');
  update game_config set value = '"250000, 1500000,2000000000"' where key = 'ranks.band_edges';
  perform pg_temp.assert(bl_money_band(100) = 'Under ₦250K' and bl_money_band(250000) = '₦250K – ₦1.5M'
                         and bl_money_band(1500000) = '₦1.5M – ₦2B' and bl_money_band(2000000000) = '₦2B+', 'custom edges');
  update game_config set value = '"junk"' where key = 'ranks.band_edges';
  perform pg_temp.assert(bl_money_band(5000000) = '₦1M – ₦10M', 'bad edges fall back to the defaults');
  update game_config set value = '"1000000,10000000,100000000,1000000000,10000000000"' where key = 'ranks.band_edges';
  perform pg_temp.assert((select (value #>> '{}')::boolean from game_config where key = 'ranks.hide_amounts') is true, 'hide_amounts defaults on');

  a := pg_temp.mk('Band_Ada', 5000000);          -- ₦1M – ₦10M
  b := pg_temp.mk('Band_Bola', 250000000);       -- ₦100M – ₦1B
  c := pg_temp.mk('Band_Chi', 50000);            -- Under ₦1M
  adm := pg_temp.mk('Band_Boss', 50000000000);
  update profiles set is_admin = true where id = adm;
  -- a very rich bank balance is order only: 12B is the top band
  update profiles set bank = 12000000000 where id = b;

  -- 2. Rich list
  perform pg_temp.login(a);
  r := leaderboard_rich(100);
  x := pg_temp.row_of(r->'rows', 'Band_Bola');
  perform pg_temp.assert(x->>'band' = '₦10B+' and x->'total' = 'null'::jsonb, 'rich: other player band, no number: ' || x::text);
  x := pg_temp.row_of(r->'rows', 'Band_Ada');
  perform pg_temp.assert(x->>'band' = '₦1M – ₦10M' and x->'total' = 'null'::jsonb and (x->>'me')::boolean, 'rich: my row in the list: ' || x::text);
  perform pg_temp.assert(r->'me'->>'band' = '₦1M – ₦10M' and r->'me'->'total' = 'null'::jsonb and r->'me'->>'tier' is not null, 'rich: me row: ' || (r->'me')::text);
  perform pg_temp.assert((pg_temp.row_of(r->'rows', 'Band_Bola')->>'rank')::int < (pg_temp.row_of(r->'rows', 'Band_Ada')->>'rank')::int
                         and (pg_temp.row_of(r->'rows', 'Band_Ada')->>'rank')::int < (pg_temp.row_of(r->'rows', 'Band_Chi')->>'rank')::int, 'rich: still ordered by the real value');
  perform pg_temp.assert(not exists (select 1 from jsonb_array_elements(r->'rows') w where w->'total' <> 'null'::jsonb), 'rich: no exact number anywhere');
  perform pg_temp.assert(pg_temp.row_of(r->'rows', 'Band_Boss') is null, 'admin still hidden');
  perform pg_temp.assert((pg_temp.row_of(r->'rows', 'Band_Chi')->>'band') = 'Under ₦1M', 'rich: under 1M');

  -- 3. VIP list: amounts stay hidden unless the old flag is on; then the band shows, never the number
  insert into payments (user_id, pack_id, reference, amount_kobo, game_naira, status, provider, paid_at)
  values (b, 'small', 'BAND-' || gen_random_uuid(), 2500000000, 1000, 'success', 'paystack', now()),     -- ₦25,000,000 spent
         (a, 'small', 'BAND-' || gen_random_uuid(), 100000, 1000, 'success', 'paystack', now());         -- ₦1,000
  update game_config set value = 'false' where key = 'leaderboard.vip_show_amounts';
  perform pg_temp.login(a);
  r := leaderboard_vip(100);
  x := pg_temp.row_of(r->'rows', 'Band_Bola');
  perform pg_temp.assert(x->'band' = 'null'::jsonb and x->'amount' = 'null'::jsonb, 'vip: show_amounts off hides everything for others: ' || x::text);
  perform pg_temp.assert(r->'me'->>'band' = 'Under ₦1M' and r->'me'->'amount' = 'null'::jsonb, 'vip: my own row shows my band: ' || (r->'me')::text);
  update game_config set value = 'true' where key = 'leaderboard.vip_show_amounts';
  r := leaderboard_vip(100);
  x := pg_temp.row_of(r->'rows', 'Band_Bola');
  perform pg_temp.assert(x->>'band' = '₦10M – ₦100M' and x->'amount' = 'null'::jsonb, 'vip: band replaces the amount: ' || x::text);
  perform pg_temp.assert((pg_temp.row_of(r->'rows', 'Band_Bola')->>'rank')::int < (pg_temp.row_of(r->'rows', 'Band_Ada')->>'rank')::int, 'vip: order by spend');

  -- 4. Weekly: earnings from the ledger, last week's winners, prizes stay exact
  perform bl_add_money(b, 'bank', 30000000, 'salary', '{}');
  perform bl_add_money(a, 'bank', 2000000, 'hustle', '{}');
  insert into crew_weeks (week_start) values (v_wk - 7) on conflict do nothing;
  insert into weekly_earn_weeks (week_start) values (v_wk - 7) on conflict do nothing;
  delete from weekly_earn_winners where week_start = v_wk - 7;
  insert into weekly_earn_winners (week_start, rank, user_id, username, total, prize) values (v_wk - 7, 1, b, 'Band_Bola', 45000000, 200000);
  perform pg_temp.login(a);
  r := weekly_leaderboard(100);
  x := pg_temp.row_of(r->'rows', 'Band_Bola');
  perform pg_temp.assert(x->>'band' = '₦10M – ₦100M' and x->'total' = 'null'::jsonb, 'weekly: other player band: ' || x::text);
  perform pg_temp.assert(r->'me'->>'band' = '₦1M – ₦10M' and r->'me'->'total' = 'null'::jsonb and (r->'me'->>'rank')::int > (x->>'rank')::int, 'weekly: me row band, ranked below: ' || (r->'me')::text);
  perform pg_temp.assert(r->'last_week'->'winners'->0->>'band' = '₦10M – ₦100M' and r->'last_week'->'winners'->0->'total' = 'null'::jsonb
                         and (r->'last_week'->'winners'->0->>'prize')::bigint = 200000, 'weekly: last week winner band, exact prize: ' || (r->'last_week')::text);
  perform pg_temp.assert((r->'prizes'->0->>'amount')::bigint = 200000 and (r->'min_earned')::bigint = (select (value #>> '{}')::bigint from game_config where key = 'leaderboard.weekly_min_earned'),
                         'weekly: prizes and the minimum stay exact');
  perform pg_temp.login(c);
  r := weekly_leaderboard(100);
  perform pg_temp.assert(r->'me'->'band' = 'null'::jsonb and r->'me'->'total' = 'null'::jsonb and r->'me'->'rank' = 'null'::jsonb, 'weekly: nothing earned = no band: ' || (r->'me')::text);

  -- 5. Gangs: loot and last week's winners
  insert into crews (name, tag, created_by) values ('Band Lions', 'BNL', a) returning id into v_crew1;
  insert into crews (name, tag, created_by) values ('Band Foxes', 'BNF', b) returning id into v_crew2;
  insert into crew_members (crew_id, user_id, rank) values (v_crew1, a, 'boss');
  insert into crew_runs (crew_id, job_id, status, lobby_until, resolved_at, pot) values
    (v_crew1, 'market_shakedown', 'paid', bl_now(), bl_now(), 3000000),
    (v_crew2, 'market_shakedown', 'paid', bl_now(), bl_now(), 40000000);
  delete from crew_week_winners where week_start = v_wk - 7;
  insert into crew_week_winners (week_start, rank, crew_id, crew_name, tag, jobs, loot, prize) values (v_wk - 7, 1, v_crew2, 'Band Foxes', 'BNF', 2, 123456789, 500000);
  perform pg_temp.login(a);
  r := crew_top(50);
  x := (select w from jsonb_array_elements(r->'rows') w where (w->>'crew_id')::bigint = v_crew2);
  perform pg_temp.assert(x->>'band' = '₦10M – ₦100M' and x->'loot' = 'null'::jsonb, 'gangs: other gang band: ' || x::text);
  perform pg_temp.assert(r->'mine'->>'band' = '₦1M – ₦10M' and r->'mine'->'loot' = 'null'::jsonb, 'gangs: my gang band: ' || (r->'mine')::text);
  perform pg_temp.assert((x->>'rank')::int < (select (w->>'rank')::int from jsonb_array_elements(r->'rows') w where (w->>'crew_id')::bigint = v_crew1), 'gangs: ordered by real loot');
  perform pg_temp.assert(r->'last_week'->'winners'->0->>'band' = '₦100M – ₦1B' and r->'last_week'->'winners'->0->'loot' = 'null'::jsonb
                         and (r->'last_week'->'winners'->0->>'prize')::bigint = 500000 and (r->'prizes'->0->>'amount')::bigint = 500000, 'gangs: last week band, exact prizes: ' || (r->'last_week')::text);

  -- 6. Philanthropists
  insert into city_donors (user_id, total, donations) values (b, 25000000, 2), (a, 11000, 1), (adm, 9000000000, 1);
  perform pg_temp.login(a);
  r := donors_top(100);
  x := pg_temp.row_of(r->'rows', 'Band_Bola');
  perform pg_temp.assert(x->>'band' = '₦10M – ₦100M' and x->'total' = 'null'::jsonb, 'donors: other player band: ' || x::text);
  x := pg_temp.row_of(r->'rows', 'Band_Ada');
  perform pg_temp.assert(x->>'band' = 'Under ₦1M' and x->'total' = 'null'::jsonb and (x->>'me')::boolean, 'donors: my row band: ' || x::text);
  perform pg_temp.assert((pg_temp.row_of(r->'rows', 'Band_Bola')->>'rank')::int < (x->>'rank')::int, 'donors: ordered by the real total');
  perform pg_temp.assert((r->'me'->>'total')::bigint = 11000, 'donors: my own giving stays exact');
  perform pg_temp.assert(get_public_profile(b)::text !~ '25000000|250000000|12000000000', 'public profile shows no money');

  -- 7. hide_amounts off: the old exact numbers
  update game_config set value = 'false' where key = 'ranks.hide_amounts';
  perform pg_temp.login(a);
  r := leaderboard_rich(100);
  x := pg_temp.row_of(r->'rows', 'Band_Bola');
  perform pg_temp.assert((x->>'total')::bigint = 12280000000 and x->'band' = 'null'::jsonb and (r->'me'->>'total')::bigint = 7000000, 'off: rich exact: ' || x::text);
  r := leaderboard_vip(100);
  perform pg_temp.assert((pg_temp.row_of(r->'rows', 'Band_Bola')->>'amount')::bigint = 25000000 and (r->'me'->>'amount')::bigint = 1000 and r->'me'->'band' = 'null'::jsonb, 'off: vip exact');
  r := weekly_leaderboard(100);
  perform pg_temp.assert((pg_temp.row_of(r->'rows', 'Band_Bola')->>'total')::bigint = 30000000 and (r->'me'->>'total')::bigint = 2000000
                         and (r->'last_week'->'winners'->0->>'total')::bigint = 45000000, 'off: weekly exact: ' || r::text);
  r := crew_top(50);
  perform pg_temp.assert((r->'mine'->>'loot')::bigint = 3000000 and (r->'last_week'->'winners'->0->>'loot')::bigint = 123456789 and r->'mine'->'band' = 'null'::jsonb, 'off: gangs exact');
  r := donors_top(100);
  perform pg_temp.assert((pg_temp.row_of(r->'rows', 'Band_Bola')->>'total')::bigint = 25000000, 'off: donors exact');

  -- 8. private helpers
  set local role authenticated;
  perform pg_temp.assert(not has_function_privilege('authenticated', 'public.bl_money_band(numeric)', 'execute') and not has_function_privilege('authenticated', 'public.bl_money_short(numeric)', 'execute')
                         and not has_function_privilege('anon', 'public.bl_money_band(numeric)', 'execute')
                         and not has_function_privilege('authenticated', 'public.bl_ranks_hide()', 'execute'), 'helpers not executable by clients');
  perform pg_temp.assert(has_function_privilege('authenticated', 'public.leaderboard_rich(integer)', 'execute')
                         and has_function_privilege('authenticated', 'public.donors_top(integer)', 'execute'), 'the boards stay callable');
  reset role;
  raise notice 'ok rank_bands: helper, rich, vip, weekly, gangs, donors, off switch, grants';
end $$;
