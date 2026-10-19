-- E3 economy balance audit (docs/BALANCE.md, section "E3 audit"). One migration, every change guarded.
--
-- Rule for every tuning below: it only changes a value that is STILL at the old default. If the owner already edited it in
-- Admin the row is left alone and a NOTICE "E3 SKIPPED ..." names it (the report lists them). Nothing here touches the
-- owner's explicit values: LAPO start cash 85,000, Babalawo prices and x1.2 offerings, the yahoo "fairer" catch chances /
-- seize / confiscate, club weekend x1.5, the money pick (10,000 a tap, 20 % drop).
--
-- The ladder this tunes towards (risk-adjusted, per day at the daily cap):
--   safe legit jobs: low and steady  ->  hustles with gear: a bit more  ->  skills / certificates / businesses: more over time
--   ->  crime (yahoo, crews): 1.3 to 2 x the legit option of the SAME tier, with real risk, never 10 x or 1000 x.
--
-- Also fixes (code): a daily cap for yahoo jobs and group missions (they had none), a free-money loop in the Market (business
-- bought at 250 % of its value and sold back at 60 % of what was paid), a disband refund that moved crew money between accounts
-- with no cost, and a running-job EFCC % that did not show the Yahoo level cut.

-- ---------------------------------------------------------------------------------------------
-- 0. helpers (session only)
-- ---------------------------------------------------------------------------------------------
create or replace function pg_temp.e3_cfg(p_key text, p_old text, p_new text, p_why text) returns void
language plpgsql as $$
declare n int;
begin
  update public.game_config set value = p_new::jsonb where key = p_key and value = p_old::jsonb;
  get diagnostics n = row_count;
  if n = 1 then
    insert into public.config_audit (admin_id, key, old_value, new_value) values (null, p_key, p_old::jsonb, p_new::jsonb);
    raise notice 'E3 changed % : % -> % (%)', p_key, p_old, p_new, p_why;
  elsif exists (select 1 from public.game_config where key = p_key) then
    raise notice 'E3 SKIPPED % (owner value %, expected old default %, wanted %)', p_key,
      (select value::text from public.game_config where key = p_key), p_old, p_new;
  end if;
end $$;

-- p_old and p_new are jsonb objects {column: value}; the row is updated only when EVERY column in p_old still matches.
create or replace function pg_temp.e3_row(p_tbl text, p_id text, p_old jsonb, p_new jsonb, p_why text) returns void
language plpgsql as $$
declare k text; v_where text := format('id = %L', p_id); v_set text := ''; n int; v_now text;
begin
  for k in select jsonb_object_keys(p_old) loop
    v_where := v_where || format(' and %I::text = %L', k, p_old->>k);
  end loop;
  for k in select jsonb_object_keys(p_new) loop
    v_set := v_set || case when v_set = '' then '' else ', ' end || format('%I = %L', k, p_new->>k);
  end loop;
  execute format('update public.%I set %s where %s', p_tbl, v_set, v_where);
  get diagnostics n = row_count;
  if n = 1 then
    raise notice 'E3 changed %.% : % -> % (%)', p_tbl, p_id, p_old, p_new, p_why;
  else
    execute format('select count(*) from public.%I where id = %L', p_tbl, p_id) into n;
    if n = 1 then
      execute format('select jsonb_object_agg(k, to_jsonb(t) -> k) from public.%I t, jsonb_object_keys(%L::jsonb) k where t.id = %L', p_tbl, p_old::text, p_id) into v_now;
      raise notice 'E3 SKIPPED %.% (owner value %, expected old default %)', p_tbl, p_id, v_now, p_old;
    end if;
  end if;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 1. new setting + daily caps for yahoo jobs and group missions
-- ---------------------------------------------------------------------------------------------
insert into public.game_config (key, value, category, label, description, kind, min, max) values
('crew.disband_fee_pct', '10', 'crew', 'Disband fee (share of the crew bank)',
 'E3: when a Boss disbands the crew, this percent of the bank is kept as legal fees and the rest is shared to the members. Stops disbanding being a free way to move money between accounts. 0 = no fee. An admin disband never charges it.', 'percent', 0, 100)
on conflict (key) do nothing;

alter table public.yahoo_jobs     add column if not exists daily_cap int not null default 0 check (daily_cap >= 0 and daily_cap <= 10000);
alter table public.group_missions add column if not exists daily_cap int not null default 0 check (daily_cap >= 0 and daily_cap <= 10000);
comment on column public.yahoo_jobs.daily_cap     is 'E3: most runs of this job per player per Benin day. 0 = no cap (cash out is never capped).';
comment on column public.group_missions.daily_cap is 'E3: most runs of this mission per player per Benin day. 0 = no cap.';

create or replace function public.bl_yahoo_runs_today(p_uid uuid, p_job text) returns int
language sql stable set search_path to 'public' as $$
  select count(*)::int from yahoo_runs where user_id = p_uid and job_id = p_job and status <> 'cancelled' and started_at >= bl_hustle_day_start();
$$;
create or replace function public.bl_yahoo_group_runs_today(p_uid uuid, p_mission text) returns int
language sql stable set search_path to 'public' as $$
  select count(*)::int from yahoo_group_members x join yahoo_groups g on g.id = x.group_id
   where x.user_id = p_uid and x.status = 'accepted' and g.mission_id = p_mission and g.started_at >= bl_hustle_day_start();
$$;
revoke all on function public.bl_yahoo_runs_today(uuid, text), public.bl_yahoo_group_runs_today(uuid, text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- 2. CRIME: yahoo jobs. Before: pay 5k..50k every 30 s with no cap (about N2M an hour), Big job N500k..N3M every 5 minutes.
--    A tier-0 laptop costs N45k, so crime was 1,000 x the starter job. After: each job pays about 1.5 x the legit tier it sits
--    next to once the laptop it risks (35 % seizure) is counted, with a daily cap like every other earner.
--    The catch chances stay exactly as the owner set them (12 / 16 / 24 / 14).
-- ---------------------------------------------------------------------------------------------
do $e3$ begin
-- pay, gate and cap are separate guards, so an owner edit of one does not block the others
perform pg_temp.e3_row('yahoo_jobs', 'chat_client', '{"pay_min":5000,"pay_max":50000}', '{"pay_min":3000,"pay_max":10000}',
  'starter crime: about 1.5x a starter job after the laptop risk');
perform pg_temp.e3_row('yahoo_jobs', 'chat_client', '{"daily_cap":0}', '{"daily_cap":8}', '8 a day like every other earner has a cap');
perform pg_temp.e3_row('yahoo_jobs', 'romance_job', '{"pay_min":50000,"pay_max":400000}', '{"pay_min":28000,"pay_max":60000}',
  'mid tier: about 1.5x a mid-tier legit day once the ThinkPad it risks is counted');
perform pg_temp.e3_row('yahoo_jobs', 'romance_job', '{"min_tier":0,"min_skill_level":1}', '{"min_tier":1,"min_skill_level":2}',
  'needs a ThinkPad (N280k) and Yahoo level 2 so day 1 cannot reach mid-tier pay');
perform pg_temp.e3_row('yahoo_jobs', 'romance_job', '{"daily_cap":0}', '{"daily_cap":4}', '4 a day');
perform pg_temp.e3_row('yahoo_jobs', 'elon_format', '{"pay_min":200000,"pay_max":1200000}', '{"pay_min":70000,"pay_max":150000}',
  'senior tier: about 1.6x a senior legit day (Tech Lead / Resident Doctor level)');
perform pg_temp.e3_row('yahoo_jobs', 'elon_format', '{"min_tier":1}', '{"min_tier":2}', 'needs an EliteBook (N330k) as well as Yahoo level 4');
perform pg_temp.e3_row('yahoo_jobs', 'elon_format', '{"daily_cap":0}', '{"daily_cap":3}', '3 a day');
perform pg_temp.e3_row('yahoo_jobs', 'big_job', '{"pay_min":500000,"pay_max":3000000}', '{"pay_min":160000,"pay_max":320000}',
  'top crime: needs a Dell XPS (N1.1M); about 1.8x a senior legit day and below a CTO day, not 10x');
perform pg_temp.e3_row('yahoo_jobs', 'big_job', '{"daily_cap":0}', '{"daily_cap":2}', '2 a day');
perform pg_temp.e3_row('group_missions', 'crew_hustle', '{"reward_min":400000,"reward_max":1600000}', '{"reward_min":30000,"reward_max":80000}',
  'whole pot split between 2 to 4 friends; about a romance job each');
perform pg_temp.e3_row('group_missions', 'crew_hustle', '{"daily_cap":0}', '{"daily_cap":3}', '3 a day');
perform pg_temp.e3_row('group_missions', 'hk_big_table', '{"reward_min":3000000,"reward_max":12000000}', '{"reward_min":300000,"reward_max":550000}',
  'whole pot split between 3 to 4 friends (Yahoo level 4); about a Big job each');
perform pg_temp.e3_row('group_missions', 'hk_big_table', '{"daily_cap":0}', '{"daily_cap":2}', '2 a day');
perform pg_temp.e3_cfg('yahoo.launder_fee_pct', '15', '10',
  'launder was strictly worse than a full cash out (15 % fee vs about 8 % expected loss); 10 % makes it a real choice for people who fear the laptop seizure');

end $e3$;
-- ---------------------------------------------------------------------------------------------
-- 3. CRIME: crews. Before: Night market shakedown N300k..N900k a minute, 8 jobs a day = about N1M a member a day for the
--    first job on the board. After: a crew job pays per member about 1.2 to 2 x the legit tier it is next to, at 3 jobs a day.
-- ---------------------------------------------------------------------------------------------
do $e3$ begin
perform pg_temp.e3_row('crew_jobs', 'market_shakedown',     '{"reward_min":300000,"reward_max":900000}',     '{"reward_min":50000,"reward_max":110000}',
  'starter crew job: about N17k a member a job, 3 a day (legit mid job N36k a day)');
perform pg_temp.e3_row('crew_jobs', 'port_container',       '{"reward_min":1200000,"reward_max":3500000}',   '{"reward_min":250000,"reward_max":550000}',
  'N44k a member a job after the N20k buy-in; needs crew level 2 (N1M of upgrades)');
perform pg_temp.e3_row('crew_jobs', 'ring_road_warehouse',  '{"reward_min":2000000,"reward_max":5000000}',   '{"reward_min":350000,"reward_max":750000}',
  'N55k a member a job after the N30k buy-in; needs crew level 2');
perform pg_temp.e3_row('crew_jobs', 'bank_van',             '{"reward_min":8000000,"reward_max":25000000}',  '{"reward_min":1500000,"reward_max":3500000}',
  'N180k a member a job after the N100k buy-in; needs crew level 4 (N12M of upgrades and 700 XP); 3 hour cooldown');
perform pg_temp.e3_cfg('crew.max_jobs_per_day', '8', '3', '8 jobs a day x 7 hours of cooldown was a second full-time job; 3 keeps crime to a few minutes a day');

end $e3$;
-- ---------------------------------------------------------------------------------------------
-- 4. HUSTLES: gear-free hustles that paid more than gear hustles and 3 to 5 x a starter job; fish worth 3 x a shift each cast;
--    Bolt Premium / Black (N40M / N150M cars) paid back in 440 / 1,000 days.
-- ---------------------------------------------------------------------------------------------
do $e3$ begin
perform pg_temp.e3_row('hustles', 'tutor_session', '{"pay_min":6000,"pay_max":12000,"bonus_min":5000,"bonus_max":15000}', '{"pay_min":2500,"pay_max":5000,"bonus_min":3000,"bonus_max":8000}',
  'no gear, no certificate, day 1: N9k a run x 4 beat every starter job; now about 2x a starter day');
perform pg_temp.e3_row('hustles', 'mc_gig',        '{"pay_min":8000,"pay_max":18000,"bonus_min":5000,"bonus_max":15000}', '{"pay_min":4000,"pay_max":9000,"bonus_min":3000,"bonus_max":8000}',
  'no gear needed: was the best gear-free hustle at N13k a run');
perform pg_temp.e3_row('hustles', 'dj_set',        '{"pay_min":15000,"pay_max":35000,"bonus_min":10000,"bonus_max":30000}', '{"pay_min":10000,"pay_max":22000,"bonus_min":6000,"bonus_max":18000}',
  'N220k controller paid back in 4 days; the headline slot (certificate) still pays more');
perform pg_temp.e3_row('hustles', 'mech_quick',    '{"pay_min":3500,"pay_max":8000}', '{"pay_min":2500,"pay_max":6000}',
  'no gear and no certificate paid like a PoS machine');
perform pg_temp.e3_row('items', 'fish_tilapia_small', '{"price":1200}',  '{"price":600}',   'a cast was worth 3 x a starter shift (N2.7k a cast, 10 casts a day for an N8k rod)');
perform pg_temp.e3_row('items', 'fish_tilapia',       '{"price":2500}',  '{"price":1200}',  'same');
perform pg_temp.e3_row('items', 'fish_catfish',       '{"price":5500}',  '{"price":2600}',  'same');
perform pg_temp.e3_row('items', 'fish_mudfish',       '{"price":9000}',  '{"price":4200}',  'same');
perform pg_temp.e3_row('items', 'fish_giant_catfish', '{"price":30000}', '{"price":12000}', 'same');
perform pg_temp.e3_row('hustle_car_classes', 'premium', '{"pay_mult":2.2}', '{"pay_mult":3.0}', 'N40M car paid back in 440 days; now about 290');
perform pg_temp.e3_row('hustle_car_classes', 'luxury',  '{"pay_mult":3.5}', '{"pay_mult":5.0}', 'N150M car paid back in 1,000 days; now about 620');

end $e3$;
-- ---------------------------------------------------------------------------------------------
-- 5. BUSINESS: restock cost per 48 h was 60 to 127 % of the income of the same 48 h for five types (a stocked Chemist lost
--    N3k a day, a stocked Filling station lost N47k a day, so the best play was never to restock and payback was 120 to 237
--    days). Restock is now about 20 % of the 48 h income; every type pays back in 63 to 108 days with stock.
-- ---------------------------------------------------------------------------------------------
do $e3$ begin
perform pg_temp.e3_row('business_types', 'provision_shop',  '{"restock_cost":18000}',  '{"restock_cost":6000}',   'was 60 % of income');
perform pg_temp.e3_row('business_types', 'buka',            '{"restock_cost":25000}',  '{"restock_cost":8000}',   'was 62 % of income');
perform pg_temp.e3_row('business_types', 'beer_parlour',    '{"restock_cost":55000}',  '{"restock_cost":14000}',  'was 79 % of income');
perform pg_temp.e3_row('business_types', 'chemist',         '{"income_min":30000,"income_max":45000,"restock_cost":70000}', '{"income_min":36000,"income_max":54000,"restock_cost":15000}',
  'was 93 % of income; +20 % income so the N2.8M price pays back in 88 days');
perform pg_temp.e3_row('business_types', 'filling_station', '{"income_min":90000,"income_max":130000,"restock_cost":280000}', '{"income_min":100000,"income_max":145000,"restock_cost":44000}',
  'was 127 % of income; +11 % income so the N9M price pays back in 108 days');

end $e3$;
-- ---------------------------------------------------------------------------------------------
-- 6. INVEST: safe yields beat stocks and crypto (MMF 18 % vs Dangote 10 %, USDT 6 %), an any-time MMF paid more than a locked
--    FD, one game year is only 30 real days (so 18 % a "year" is 0.6 % a real day, risk free, with no cap on the amount), and the
--    poultry and fish farms paid 1.65 and 1.74 % a real day after their own bad events against 1.2 % for the other farms and
--    1.1 to 1.3 % for keke, Sienna and POS units (payback 80 to 90 days; those are fine and stay). Safe products come down, shares
--    and USDT go up so that risk is paid.
-- ---------------------------------------------------------------------------------------------
do $e3$ begin
perform pg_temp.e3_row('invest_products', 'bronze_savings', '{"rate_pct":10}',    '{"rate_pct":6}',    'any-time money: lowest yield');
perform pg_temp.e3_row('invest_products', 'mmf',            '{"rate_pct":18}',    '{"rate_pct":9}',    'any-time money must pay less than a locked deposit');
perform pg_temp.e3_row('invest_products', 'safelock_7',     '{"rate_pct":15}',    '{"rate_pct":9.5}',  '7 days locked');
perform pg_temp.e3_row('invest_products', 'safelock_30',    '{"rate_pct":18}',    '{"rate_pct":11}',   '30 days locked');
perform pg_temp.e3_row('invest_products', 'safelock_90',    '{"rate_pct":22}',    '{"rate_pct":13}',   '90 days locked');
perform pg_temp.e3_row('invest_products', 'fd_30',          '{"rate_pct":16}',    '{"rate_pct":10.5}', '30 days locked');
perform pg_temp.e3_row('invest_products', 'fd_90',          '{"rate_pct":19}',    '{"rate_pct":12.5}', '90 days locked');
perform pg_temp.e3_row('invest_products', 'tbill_91',       '{"rate_pct":16}',    '{"rate_pct":11}',   'sovereign, 91 days');
perform pg_temp.e3_row('invest_products', 'tbill_182',      '{"rate_pct":17.75}', '{"rate_pct":13.5}', 'sovereign, 182 days');
perform pg_temp.e3_row('invest_products', 'tbill_364',      '{"rate_pct":21.85}', '{"rate_pct":15}',   'sovereign, 364 days: the best safe yield');
perform pg_temp.e3_row('invest_products', 'fgn_bond',       '{"rate_pct":19}',    '{"rate_pct":12.5}', 'coupon; the price also wobbles +-3 %');
perform pg_temp.e3_row('invest_products', 'farm_poultry',   '{"gain_min_pct":25,"gain_max_pct":35}', '{"gain_min_pct":20,"gain_max_pct":30}', 'was 1.6 % a day after events (the best medium-risk yield by far); now about 1.3 %');
perform pg_temp.e3_row('invest_products', 'farm_fish',      '{"gain_min_pct":28,"gain_max_pct":38}', '{"gain_min_pct":22,"gain_max_pct":32}', 'was 1.7 % a day after events; now about 1.35 %');
perform pg_temp.e3_row('invest_markets', 'stk_dangcem', '{"drift_pct_year":10}', '{"drift_pct_year":15}', 'a risky share must beat the safe MMF (9 %): drift plus about 4 % dividends');
perform pg_temp.e3_row('invest_markets', 'stk_mtnn',    '{"drift_pct_year":12}', '{"drift_pct_year":16}', 'same');
perform pg_temp.e3_row('invest_markets', 'stk_gtco',    '{"drift_pct_year":15}', '{"drift_pct_year":19}', 'same');
perform pg_temp.e3_row('invest_markets', 'stk_zenith',  '{"drift_pct_year":13}', '{"drift_pct_year":18}', 'same');
perform pg_temp.e3_row('invest_markets', 'stk_okomu',   '{"drift_pct_year":14}', '{"drift_pct_year":18}', 'same');
perform pg_temp.e3_row('invest_markets', 'stk_presco',  '{"drift_pct_year":16}', '{"drift_pct_year":21}', 'same');
perform pg_temp.e3_row('invest_markets', 'crypto_usdt', '{"drift_pct_year":6}',  '{"drift_pct_year":10}', '"high risk" paid less (6 %) than the safe MMF (18 %)');
-- land, flats and Bitcoin were "high risk" but their price walks have low volatility (land 0.5 to 0.8 % a 6 h step, so about 7 to 9 % over 30
-- days) against a drift of 22 to 35 % a 30 days: after the 14 to 36 % round-trip fees, holding land for two months beat every share. Unlimited
-- plots and no cap made it the best money machine in the game. Drift now sits below the shares for the same horizon; the fees stay.
perform pg_temp.e3_row('invest_markets', 'land_gra',     '{"drift_pct_year":22}', '{"drift_pct_year":12}', 'land: break-even after about 35 days instead of 20');
perform pg_temp.e3_row('invest_markets', 'land_ugbowo',  '{"drift_pct_year":28}', '{"drift_pct_year":15}', 'same');
perform pg_temp.e3_row('invest_markets', 'land_sapele',  '{"drift_pct_year":24}', '{"drift_pct_year":13}', 'same');
perform pg_temp.e3_row('invest_markets', 'land_airport', '{"drift_pct_year":30}', '{"drift_pct_year":16}', 'same');
perform pg_temp.e3_row('invest_markets', 'land_ikpoba',  '{"drift_pct_year":26}', '{"drift_pct_year":14}', 'same');
perform pg_temp.e3_row('invest_markets', 'land_okhoro',  '{"drift_pct_year":33}', '{"drift_pct_year":17}', 'same');
perform pg_temp.e3_row('invest_markets', 'land_ekenwan', '{"drift_pct_year":35}', '{"drift_pct_year":18}', 'same');
perform pg_temp.e3_row('invest_markets', 'property_index', '{"drift_pct_year":14}', '{"drift_pct_year":8}', 'rental flats earned 0.65 % a day in rent plus 14 % a 30 days in price: about 1.1 % a day for a 0.5 % vol index');
perform pg_temp.e3_row('invest_markets', 'crypto_btc',   '{"drift_pct_year":55}', '{"drift_pct_year":30}', 'Bitcoin drifted +55 % every 30 days (x128 a year) with about 29 % vol: a Sharpe near 2 with no cap on the amount; 30 % still pays the risk');

end $e3$;
-- ---------------------------------------------------------------------------------------------
-- 7. POLITICS: office salary is paid for sitting in the seat (no job to do). A Commissioner (appointed by the Governor, so
--    an alt can hold one) earned N40k a day, more than a Staff Nurse works for. Salaries are now about a mid-level legit day
--    or less; the fees and the campaign costs stay.
-- ---------------------------------------------------------------------------------------------
do $e3$ begin
perform pg_temp.e3_row('offices', 'councillor', '{"salary_per_day":20000}', '{"salary_per_day":10000}', 'N280k a 14-day term for holding a seat');
perform pg_temp.e3_row('offices', 'chairman',   '{"salary_per_day":50000}', '{"salary_per_day":25000}', 'about a Senior Nurse day');
perform pg_temp.e3_row('offices', 'governor',   '{"salary_per_day":100000}','{"salary_per_day":50000}', 'about a Tech Lead day');
perform pg_temp.e3_row('offices', 'commissioner_works',       '{"salary_per_day":40000}', '{"salary_per_day":15000}', 'appointed, no campaign: below a Staff Nurse shift x 3');
perform pg_temp.e3_row('offices', 'commissioner_finance',     '{"salary_per_day":40000}', '{"salary_per_day":15000}', 'same');
perform pg_temp.e3_row('offices', 'commissioner_youth',       '{"salary_per_day":40000}', '{"salary_per_day":15000}', 'same');
perform pg_temp.e3_row('offices', 'commissioner_information', '{"salary_per_day":40000}', '{"salary_per_day":15000}', 'same');
perform pg_temp.e3_row('offices', 'commissioner_commerce',    '{"salary_per_day":40000}', '{"salary_per_day":15000}', 'same');
perform pg_temp.e3_row('offices', 'commissioner_security',    '{"salary_per_day":40000}', '{"salary_per_day":15000}', 'same');

end $e3$;
-- ---------------------------------------------------------------------------------------------
-- 8. SIDE MONEY that out-paid work: the gem hunt (N14k a day for walking), challenges + chests (N17k a day), referral bonus
--    (a 20-second shift paid N40k), the free starter car resale. All were bigger than a starter day of work (N6k to N10k).
-- ---------------------------------------------------------------------------------------------
do $e3$ begin
perform pg_temp.e3_cfg('daily.gem_prize',            '3000',  '1000',  'N14k a day for walking was more than a starter day of work (was already recommended in docs/BALANCE.md L1)');
perform pg_temp.e3_cfg('daily.gem_all_bonus',        '5000',  '2000',  'same');
perform pg_temp.e3_cfg('challenges.reward_mult',     '1',     '0.7',   'challenges + chests paid about N17k a day; now about N10k, still a nice extra on top of work');
perform pg_temp.e3_cfg('challenges.daily_chest_cash',  '3000',  '2000',  'same');
perform pg_temp.e3_cfg('challenges.weekly_chest_cash', '20000', '12000', 'same');
perform pg_temp.e3_cfg('referral.bonus_referrer',  '20000', '10000', 'a milestone ANY of one shift / 3 hustles / 60 minutes paid N40k per alt account');
perform pg_temp.e3_cfg('referral.bonus_referred',  '20000', '10000', 'same');
perform pg_temp.e3_cfg('referral.min_shifts',      '1',     '9',     'one 20-second shift completed the milestone; 9 shifts is 3 days of work');
perform pg_temp.e3_cfg('referral.min_hustles',     '3',     '15',    'same');
perform pg_temp.e3_cfg('referral.play_minutes',    '60',    '240',   'same');
perform pg_temp.e3_cfg('referral.daily_cap',       '5',     '3',     'less alt farming per day');
perform pg_temp.e3_cfg('referral.max_total',       '100',   '30',    'N10k x 100 = N1M per inviter was too big');
perform pg_temp.e3_cfg('tips.max_amount',        '1000000', '100000', 'a tip moved up to N5M a day with no fee and no count limit, while a bank transfer is N200k a day: tips were the loophole for moving farmed money to one account');
perform pg_temp.e3_cfg('tips.daily_max',          '5000000', '300000', 'same: now close to the bank transfer limit (N200k)');
perform pg_temp.e3_cfg('leaderboard.weekly_min_earned', '20000', '100000', 'N20k a week was a few starter shifts: three alt accounts could take all three weekly prizes (N350k)');
perform pg_temp.e3_cfg('crew.weekly_min_jobs',    '2',       '8',       'two jobs a week was enough for an alt crew to win the N500k Top crew prize');
perform pg_temp.e3_cfg('cars.resale_pct',          '60',    '50',    'the free Nepo car paid N1.5M on day 1 (N1.25M now); also keeps buy-then-sell under the 70 % a business owner earns back from visitors');

end $e3$;
-- ---------------------------------------------------------------------------------------------
-- 9. CODE: yahoo daily cap (yahoo_job_start, yahoo_status, group gate and status), the escape % shown to Yahoo players,
--    the Market business loop, the crew disband fee, the admin editor columns. Guarded replaces: raise when a marker is
--    missing, skip when already applied; create or replace keeps the grants.
-- ---------------------------------------------------------------------------------------------
do $$
declare v_def text;
begin
  -- 9a. yahoo_job_start: daily cap
  select pg_get_functiondef('public.yahoo_job_start(text,bigint)'::regprocedure) into v_def;
  if position('daily_cap' in v_def) = 0 then
    if position(E'  if j.kind = ''cashout'' then\n    v_amt := coalesce(p_amount, y.dirty);' in v_def) = 0 then
      raise exception 'yahoo_job_start: cashout marker not found';
    end if;
    v_def := replace(v_def, E'  if j.kind = ''cashout'' then\n    v_amt := coalesce(p_amount, y.dirty);',
      E'  if j.daily_cap > 0 and j.kind <> ''cashout'' and bl_yahoo_runs_today(v_me.id, j.id) >= j.daily_cap then\n'
      || E'    raise exception ''You don do enough % for today (% a day). Come back tomorrow.'', j.name, j.daily_cap using errcode = ''P0001'', hint = ''daily_cap'';\n'
      || E'  end if;\n'
      || E'  if j.kind = ''cashout'' then\n    v_amt := coalesce(p_amount, y.dirty);');
    execute v_def;
  end if;

  -- 9b. yahoo_status: daily cap in the job cards, locked state, and the escape % that really applies (vanishing charm, bad luck)
  select pg_get_functiondef('public.yahoo_status()'::regprocedure) into v_def;
  if position('daily_cap' in v_def) = 0 then
    if position('''min_tier'', j.min_tier,' in v_def) = 0 then raise exception 'yahoo_status: min_tier marker not found'; end if;
    if position('when bl_cert_gate(v_uid, j.req_cert) is not null then ''cert'' end,' in v_def) = 0 then raise exception 'yahoo_status: locked marker not found'; end if;
    v_def := replace(v_def, '''min_tier'', j.min_tier,',
      '''daily_cap'', j.daily_cap, ''cap_left'', case when j.daily_cap > 0 and j.kind <> ''cashout'' then greatest(0, j.daily_cap - bl_yahoo_runs_today(v_uid, j.id)) end, ''min_tier'', j.min_tier,');
    v_def := replace(v_def, 'when bl_cert_gate(v_uid, j.req_cert) is not null then ''cert'' end,',
      'when bl_cert_gate(v_uid, j.req_cert) is not null then ''cert'' '
      || 'when j.daily_cap > 0 and j.kind <> ''cashout'' and bl_yahoo_runs_today(v_uid, j.id) >= j.daily_cap then ''daily_cap'' end,');
    execute v_def;
  end if;
  select pg_get_functiondef('public.yahoo_status()'::regprocedure) into v_def;
  if position('E3 escape' in v_def) = 0 then
    if position('''escape_caught_pct'', bl_yahoo_num(''yahoo.escape_caught_pct'', 55)' in v_def) = 0 then raise exception 'yahoo_status: escape marker not found'; end if;
    v_def := replace(v_def, '''escape_caught_pct'', bl_yahoo_num(''yahoo.escape_caught_pct'', 55)',
      '''escape_caught_pct'', greatest(0, least(100, least(bl_yahoo_num(''yahoo.escape_caught_pct'', 55), coalesce(bl_charm_value(v_uid, ''vanishing''), 100)) + coalesce(bl_charm_value(v_uid, ''bad_luck'', ''caught_pts''), 0))) /* E3 escape: what the roll really uses (bl_escape_pct_peek for an EFCC case) */');
    execute v_def;
  end if;

  -- 9c. group missions: daily cap in the join gate and in the status list
  select pg_get_functiondef('public.bl_yahoo_group_gate(uuid,group_missions,text)'::regprocedure) into v_def;
  if position('daily_cap' in v_def) = 0 then
    if position('    select max(g.started_at) into v_last from yahoo_group_members x join yahoo_groups g on g.id = x.group_id' in v_def) = 0 then
      raise exception 'bl_yahoo_group_gate: marker not found';
    end if;
    v_def := replace(v_def, '    select max(g.started_at) into v_last from yahoo_group_members x join yahoo_groups g on g.id = x.group_id',
      E'    if m.daily_cap > 0 and bl_yahoo_group_runs_today(p_uid, m.id) >= m.daily_cap then\n'
      || E'      return jsonb_build_object(''hint'', ''daily_cap'', ''message'', ''You don run '' || m.name || '' enough for today ('' || m.daily_cap || '' a day). Come back tomorrow.'');\n'
      || E'    end if;\n'
      || '    select max(g.started_at) into v_last from yahoo_group_members x join yahoo_groups g on g.id = x.group_id');
    execute v_def;
  end if;
  select pg_get_functiondef('public.yahoo_group_status()'::regprocedure) into v_def;
  if position('daily_cap' in v_def) = 0 then
    if position('''cooldown_seconds'', m.cooldown_seconds,' in v_def) = 0 then raise exception 'yahoo_group_status: marker not found'; end if;
    v_def := replace(v_def, '''cooldown_seconds'', m.cooldown_seconds,',
      '''cooldown_seconds'', m.cooldown_seconds, ''daily_cap'', m.daily_cap, ''cap_left'', case when m.daily_cap > 0 then greatest(0, m.daily_cap - bl_yahoo_group_runs_today(v_uid, m.id)) end,');
    execute v_def;
  end if;

  -- 9d. Market: a business bought on the Market counts as invested at most its catalogue value. Before it counted the price
  --     paid (up to 250 % of value) and business_sell pays 60 % of invested back: list at 250 %, an alt buys, sells to the
  --     system for 150 % of value, net +30 % of the value per lap. Now the best case loses 40 % of the value plus the 8 % fee.
  select pg_get_functiondef('public.bl_biz_market_give(uuid,text,jsonb,bigint,boolean)'::regprocedure) into v_def;
  if position('bl_biz_value(b)' in v_def) = 0 then
    if position('greatest(0, coalesce(p_cost, 0)) else invested end' in v_def) = 0 then raise exception 'bl_biz_market_give: marker not found'; end if;
    v_def := replace(v_def, 'greatest(0, coalesce(p_cost, 0)) else invested end',
      'least(greatest(0, coalesce(p_cost, 0)), bl_biz_value(b)) else invested end');
    execute v_def;
  end if;

  -- 9e. crew disband: a fee (crew.disband_fee_pct) kept from the bank; an admin disband does not charge it
  select pg_get_functiondef('public.bl_crew_dissolve(bigint,uuid,text)'::regprocedure) into v_def;
  if position('disband_fee_pct' in v_def) = 0 then
    if position('v_first uuid; v_bank bigint;' in v_def) = 0 or position('v_bank := c.bank;' in v_def) = 0
       or position('v_share := floor(v_bank::numeric / v_n)::bigint;' in v_def) = 0 or position('v_rest := v_bank - v_share * v_n;' in v_def) = 0
       or position('jsonb_build_object(''members'', v_n, ''bank'', v_bank)' in v_def) = 0 then
      raise exception 'bl_crew_dissolve: marker not found';
    end if;
    v_def := replace(v_def, 'v_first uuid; v_bank bigint;', 'v_first uuid; v_bank bigint; v_fee bigint := 0;');
    v_def := replace(v_def, 'v_bank := c.bank;',
      'v_bank := c.bank; if p_admin is null then v_fee := floor(c.bank * least(100, greatest(0, bl_crew_num(''crew.disband_fee_pct'', 10))) / 100.0)::bigint; end if;');
    v_def := replace(v_def, 'v_share := floor(v_bank::numeric / v_n)::bigint;', 'v_share := floor((v_bank - v_fee)::numeric / v_n)::bigint;');
    v_def := replace(v_def, 'v_rest := v_bank - v_share * v_n;', 'v_rest := (v_bank - v_fee) - v_share * v_n;');
    v_def := replace(v_def, 'jsonb_build_object(''members'', v_n, ''bank'', v_bank)', 'jsonb_build_object(''members'', v_n, ''bank'', v_bank, ''fee'', v_fee)');
    execute v_def;
  end if;

  -- 9f. admin editor: the new daily_cap column
  select pg_get_functiondef('public.bl_admin_table_spec(text)'::regprocedure) into v_def;
  if position('"daily_cap":"int"' in v_def) = 0 then
    if position('"min_tier":"int",' in v_def) = 0 or position('"invite_seconds":"int",' in v_def) = 0 then raise exception 'bl_admin_table_spec: marker not found'; end if;
    v_def := replace(v_def, '"min_tier":"int",', '"min_tier":"int","daily_cap":"int",');
    v_def := replace(v_def, '"invite_seconds":"int",', '"invite_seconds":"int","daily_cap":"int",');
    execute v_def;
  end if;
end $$;

notify pgrst, 'reload schema';
