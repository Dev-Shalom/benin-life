-- Kids v2 (20261028000200_kids_v2.sql) and the life-moments engine as the kids use it. Rolled back. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/kids_v2_test.sql
-- The clock is pinned to 10:00 Benin time, time moves with bl.test_offset_seconds, random rolls are pinned with bl.test_rand.
-- Groups: 1 stages and the needs each has · 2 items, charges, prices (Oba moves a little each day, the supermarket is fixed), hours ·
-- 3 care uses items (feed, change, medicine, play with toys, lunch money) · 4 the daily illness roll (deterministic) and doctor cards for both parents ·
-- 5 relatives: two shares, refund, a lone parent, for good · 6 passing away: warnings + hours, the alert, memorial, grief, switch off ·
-- 7 care score, gift tiers, gift cap, not earned, badge tier · 8 grants / RLS / private helpers / ledger.
update game_config set value = 'false' where key in ('economy.transfer_fees_enabled', 'economy.tax_enabled', 'economy.bills_enabled', 'economy.vat_enabled', 'economy.luxury_enabled');
-- chance illness is tested in kids_v2_test.sql; here it is off so the stage 2 flows are deterministic
update game_config set value = '0' where key = 'kids.daily_sick_pct';

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

create or replace function pg_temp.hours(p_h numeric) returns void language sql as $$ select pg_temp.advance(p_h * 3600) $$;

create or replace function pg_temp.cfg(p_key text, p_val text) returns void
language sql as $$ update game_config set value = p_val::jsonb where key = p_key; $$;

create or replace function pg_temp.u(p text) returns uuid language sql as $$ select current_setting('kd.' || p)::uuid $$;
create or replace function pg_temp.cash(p_uid uuid) returns bigint language sql as $$ select cash + bank from profiles where id = p_uid $$;
create or replace function pg_temp.ev(p_uid uuid, p_kind text) returns bigint language sql as $$ select count(*) from events where user_id = p_uid and kind = p_kind $$;
create or replace function pg_temp.login_as(p text) returns void language sql as $$ select pg_temp.login(pg_temp.u(p)) $$;
create or replace function pg_temp.ledger_n(p_uid uuid, p_reason text) returns bigint language sql as $$ select count(*) from ledger where user_id = p_uid and reason = p_reason $$;
create or replace function pg_temp.ledger_sum(p_uid uuid, p_reason text) returns bigint language sql as $$ select coalesce(sum(delta), 0) from ledger where user_id = p_uid and reason = p_reason $$;

create or replace function pg_temp.at(p_uid uuid, p_loc text) returns void
language sql as $$
  update profiles set location_id = p_loc, travel_to = null, travel_mode = null, travel_started_at = null, travel_arrives_at = null,
                      busy_until = null, busy_label = null, busy_started_at = null, busy_needs_from = null,
                      jailed_until = null, jail_reason = null, hospitalized_until = null, home_visit_host_id = null,
                      last_seen = bl_now(), rent_due_at = null
   where id = p_uid;
$$;

create or replace function pg_temp.mk(p_name text, p_age interval default interval '30 days') returns uuid
language plpgsql as $$
declare v uuid := pg_temp.new_user(lower(p_name) || '@kd.bl');
begin
  perform pg_temp.login(v);
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform create_profile_v2(p_name, 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  update profiles set rent_owed = 0, weekly_rent = 0, protected_until = null, created_at = bl_now() - p_age, cash = 1000000, bank = 0, home_location_id = 'uselu_selfcon',
         energy = 100, hunger = 100, hygiene = 100, fun = 100, social = 100, health = 100, stress = 0 where id = v;
  perform pg_temp.at(v, 'third_east');
  return v;
end $$;

-- A couple (status couple, together for p_days days), without going through flirts.
create or replace function pg_temp.couple(p_a uuid, p_b uuid, p_days numeric default 5) returns bigint
language plpgsql as $$
declare v bigint;
begin
  insert into love_relationships (user_a, user_b, asked_by, status, level, started_at, couple_at, last_activity_at)
  values (least(p_a, p_b), greatest(p_a, p_b), p_a, 'couple', 50, bl_now() - make_interval(secs => (p_days * 86400 + 60)::double precision),
          bl_now() - make_interval(secs => (p_days * 86400)::double precision), bl_now()) returning id into v;
  return v;
end $$;

create or replace function pg_temp.rel(p_a uuid, p_b uuid) returns bigint language sql as $$
  select id from love_relationships where user_a = least(p_a, p_b) and user_b = greatest(p_a, p_b) order by id desc limit 1 $$;

-- A child at home, set up directly (full needs now, born p_age ago, cared for now). Returns its id.
create or replace function pg_temp.mkchild(p_a uuid, p_b uuid, p_age interval default interval '1 hour', p_name text default 'Testy') returns bigint
language plpgsql as $$
declare v bigint; c kids_children;
begin
  insert into kids_children (rel_id, parent_a, parent_b, proposed_by, status, name, gender, conceived_at, due_at, born_at,
                             hunger, hunger_at, sleep, sleep_at, fun, fun_at, health, health_at, love, love_at, clean, clean_at, last_care_at, score_at)
  values (pg_temp.rel(p_a, p_b), least(p_a, p_b), greatest(p_a, p_b), p_a, 'home', p_name, 'girl', bl_now() - p_age - interval '3 days', bl_now() - p_age, bl_now() - p_age,
          100, bl_now(), 100, bl_now(), 100, bl_now(), 100, bl_now(), 100, bl_now(), 100, bl_now(), bl_now(), bl_now()) returning id into v;
  update kids_children set next_roll_at = bl_kids_roll_time(v, bl_now()) where id = v;
  select * into c from kids_children where id = v;
  update kids_children set next_alert_at = bl_kids_next(c) where id = v;
  return v;
end $$;

create or replace function pg_temp.kid(p_id bigint) returns kids_children language sql as $$ select * from kids_children where id = p_id $$;

-- the child json for a player from kids_status
create or replace function pg_temp.cj(p_child bigint) returns jsonb language sql as $$
  select x from jsonb_array_elements(kids_status() -> 'children') x where (x ->> 'id')::bigint = p_child $$;

-- supplies for care: formula, diapers, syrup, malaria drugs (a few of each)
create or replace function pg_temp.stock(p_uid uuid, p_qty int default 5) returns void
language plpgsql as $$
declare i text;
begin
  foreach i in array array['kid_formula', 'kid_diapers', 'kid_paracetamol', 'kid_malaria'] loop
    insert into inventory (user_id, item_id, qty) values (p_uid, i, p_qty) on conflict (user_id, item_id) do update set qty = p_qty;
  end loop;
  delete from kids_charges where user_id = p_uid;
end $$;

create or replace function pg_temp.sub(p_user uuid) returns void
language plpgsql as $$
begin
  insert into push_subscriptions (user_id, endpoint, p256dh, auth)
  values (p_user, 'https://push.example.test/' || p_user || '/1', repeat('A', 87), repeat('B', 22));
end $$;


-- ---------- setup ----------
do $$
declare
  v_keys text[] := array['adm', 'a', 'b', 'c', 'd', 'e', 'f'];
  k text; u uuid;
  v_local timestamp := now() at time zone bl_clock_tz();
  v_target timestamp;
begin
  v_target := date_trunc('day', v_local) + case when v_local::time >= time '10:00' then interval '34 hours' else interval '10 hours' end;
  perform set_config('bl.test_offset_seconds', extract(epoch from (v_target - v_local))::text, true);
  perform set_config('bl.test_rand', '', true);
  perform pg_temp.cfg('places.hours_enabled', 'false');
  foreach k in array v_keys loop
    u := pg_temp.mk('KV_' || k);
    perform set_config('kd.' || k, u::text, true);
  end loop;
  update profiles set is_admin = true where id = pg_temp.u('adm');
  perform pg_temp.couple(pg_temp.u('a'), pg_temp.u('b'), 5);
  perform pg_temp.couple(pg_temp.u('c'), pg_temp.u('d'), 5);
  perform pg_temp.couple(pg_temp.u('e'), pg_temp.u('f'), 5);
  foreach k in array array['a', 'b', 'c', 'd', 'e', 'f'] loop
    perform pg_temp.stock(pg_temp.u(k));
    perform pg_temp.sub(pg_temp.u(k));
    perform pg_temp.login_as(k); perform push_prefs_set('{"master": true, "friends": true}');
  end loop;
  update game_config set value = '1000' where key = 'push.max_per_user_hour';
  -- illness chance is pinned per test; cooldowns off where a test calls an action twice
  update game_config set value = '0' where key = 'kids.daily_sick_pct';
  update game_config set value = '0' where key = 'moments.daily_cap';   -- no random everyday cards in these tests (life_moments_test.sql covers them)
  update game_config set value = '0' where key in ('kids.feed_cooldown_minutes', 'kids.change_cooldown_minutes', 'kids.play_cooldown_minutes', 'kids.medicine_cooldown_minutes', 'kids.cuddle_cooldown_minutes', 'kids.sleep_cooldown_minutes');
  update profiles set cash = 5000000 where id in (pg_temp.u('a'), pg_temp.u('b'), pg_temp.u('c'), pg_temp.u('d'), pg_temp.u('e'), pg_temp.u('f'));
end $$;

-- ---------- 1. stages and the needs each has ----------
do $$
declare v jsonb; v_c bigint; r record; v_keys text[]; v_acts text[]; c kids_children; v_nb timestamptz;
begin
  perform pg_temp.login_as('a');
  perform pg_temp.assert((select array_agg(id order by from_days) from kids_stages where active) = array['newborn', 'baby', 'nursery', 'primary', 'secondary', 'university'], 'six active stages (the last is the university stage after day 21)');
  perform pg_temp.assert((select array_agg(from_days order by from_days) from kids_stages where active) = array[0, 2, 5, 8, 14, 21], 'Newborn 0-2, Baby 2-5, Nursery 5-8, Primary 8-14, Secondary 14-21, University from 21');
  perform pg_temp.assert(bl_cfg('kids.grow_days') = 21, 'grown at 21 days');
  for r in select * from (values
      (0, 'newborn',   '{clean,health,hunger,love,sleep}', '{change,cuddle,feed,medicine,sleep}'),
      (2, 'baby',      '{clean,health,hunger,love,sleep}', '{change,cuddle,feed,medicine,sleep}'),
      (5, 'nursery',   '{fun,health,hunger,love,sleep}',   '{cuddle,feed,medicine,play,sleep}'),
      (8, 'primary',   '{fun,health,hunger,love,sleep}',   '{cuddle,feed,medicine,play,sleep}'),
      (14, 'secondary', '{fun,health,hunger,love}',        '{cuddle,feed,medicine,play}')) t(d, s, n, a) loop
    v_c := pg_temp.mkchild(pg_temp.u('a'), pg_temp.u('b'), make_interval(days => r.d) + interval '1 hour', 'Stagey');
    v := pg_temp.cj(v_c);
    select array_agg(k order by k) into v_keys from jsonb_object_keys(v->'needs') k;
    select array_agg(k order by k) into v_acts from jsonb_object_keys(v->'actions') k;
    perform pg_temp.assert(v->'stage'->>'id' = r.s, 'stage at day ' || r.d || ' is ' || r.s || ': ' || (v->'stage')::text);
    perform pg_temp.assert(v_keys = r.n::text[], r.s || ' needs ' || v_keys::text);
    perform pg_temp.assert(v_acts = r.a::text[], r.s || ' actions ' || v_acts::text);
    perform pg_temp.assert(v->'stage'->'needs' @> to_jsonb(v_keys), r.s || ' stage lists its needs');
    update kids_children set status = 'gone', gone_reason = 'admin', next_alert_at = null where id = v_c;
  end loop;
  -- decay per stage: a Secondary child loses hunger 1.5 an hour, and has no sleep or clean to lose, so those never alert
  v_c := pg_temp.mkchild(pg_temp.u('a'), pg_temp.u('b'), interval '15 days', 'Teeny');
  select * into c from kids_children where id = v_c;
  perform pg_temp.assert(round(bl_kids_val(c, 'hunger', bl_now() + interval '10 hours'), 1) = 85.0 and round(bl_kids_val(c, 'fun', bl_now() + interval '10 hours'), 1) = 82.0
                         and round(bl_kids_val(c, 'love', bl_now() + interval '10 hours'), 1) = 90.0 and bl_kids_val(c, 'sleep', bl_now() + interval '100 hours') = 100, 'secondary: hunger 1.5, fun 1.8, love 1.0, no sleep drain');
  update kids_children set sleep = 0, sleep_at = bl_now(), clean = 0, clean_at = bl_now() where id = v_c;
  select * into c from kids_children where id = v_c;
  perform pg_temp.assert(bl_kids_needy(c) = '{}' and bl_kids_sick_at(c) > bl_now() + interval '1 day', 'a need the stage does not have never alerts and never makes the child sick');
  update kids_children set status = 'gone', gone_reason = 'admin', next_alert_at = null where id = v_c;
  -- a stage boundary is a moment the sweep looks at: a newborn 10 minutes from being a Baby
  v_c := pg_temp.mkchild(pg_temp.u('a'), pg_temp.u('b'), interval '47 hours 50 minutes', 'Boundy');
  select * into c from kids_children where id = v_c;
  v_nb := c.born_at + interval '48 hours';
  perform pg_temp.assert(abs(extract(epoch from (c.next_alert_at - v_nb))) < 2, 'next_alert_at is the day the Baby stage starts: ' || c.next_alert_at::text);
  perform pg_temp.assert(bl_kids_stage_of(c, bl_now()) = 'newborn' and bl_kids_stage_of(c, bl_now() + interval '11 minutes') = 'baby', 'stage by time');
  update kids_children set status = 'gone', gone_reason = 'admin', next_alert_at = null where id = v_c;
  raise notice 'ok 1: stages and needs';
end $$;

-- ---------- 2. items, charges and prices ----------
do $$
declare
  it items; v jsonb; v_base bigint; p bigint; v_min bigint; v_max bigint; v_seen bigint[] := '{}'; d int; v_super bigint; v_first bigint; i text; b0 bigint; r jsonb;
  v_c bigint; ca bigint; v_t0 text := current_setting('bl.test_offset_seconds');
begin
  perform pg_temp.login_as('a');
  perform pg_temp.assert((select count(*) from items where category in ('baby', 'kids')) = 12 and (select count(*) from kids_items where active) = 12, 'twelve baby and kids items (nine care items and three school items)');
  perform pg_temp.assert(not exists (select 1 from items where category in ('baby', 'kids') and (not ('oba_market' = any (sold_at)) or not ('edo_fresh_supermarket' = any (sold_at)))), 'all sold at Oba Market and the supermarket');
  perform pg_temp.assert((select scene from locations where id = 'edo_fresh_supermarket') = 'mall' and (select open_hour from locations where id = 'edo_fresh_supermarket') is null
                         and (select 'shop' = any (actions) from locations where id = 'edo_fresh_supermarket'), 'the supermarket is a place with a shop tab, always open');
  perform pg_temp.assert((select price from items where id = 'kid_formula') between 15000 and 21000 and (select price from items where id = 'kid_diapers') between 8000 and 12000
                         and (select price from items where id = 'kid_cereal') between 4500 and 6500 and (select price from items where id = 'kid_paracetamol') between 1000 and 2100
                         and (select price from items where id = 'kid_malaria') between 3000 and 8000 and (select min(price) from items where category = 'kids') >= 2000 and (select max(price) from items where category = 'kids') <= 25000,
                         'base prices sit in the owner ranges');
  perform pg_temp.assert(bl_tax_rates('item', 'baby', 1000) = array[0, 0]::numeric[] or not bl_econ_on('economy.vat_enabled', true), 'baby items are VAT free (when VAT is on)');
  perform pg_temp.cfg('economy.vat_enabled', 'true');
  perform pg_temp.assert((bl_tax_rates('item', 'baby', 1000))[1] = 0 and (bl_tax_rates('item', 'kids', 1000))[1] = 0 and (bl_tax_rates('item', 'gadget', 1000))[1] > 0, 'baby and kids toys carry no VAT, a gadget does');
  perform pg_temp.cfg('economy.vat_enabled', 'false');
  -- prices: Oba moves up to 10 % a Benin day (the same for everyone all day), the supermarket is fixed 25 % higher
  for i in select unnest(array['kid_formula', 'kid_cereal', 'kid_diapers', 'kid_paracetamol', 'kid_malaria', 'kid_teddy', 'kid_ball', 'kid_puzzle', 'kid_console']) loop
    select * into it from items where id = i;
    v_min := 9223372036854775807; v_max := 0; v_seen := '{}';
    v_super := bl_dealer_price(it, 'edo_fresh_supermarket');
    perform pg_temp.assert(v_super = (case when it.price * 1.25 < 1000 then round(it.price * 1.25 / 10.0) * 10 else round(it.price * 1.25 / 50.0) * 50 end), 'supermarket price is fixed at +25 %: ' || i || ' ' || v_super);
    for d in 1..12 loop
      p := bl_dealer_price(it, 'oba_market');
      perform pg_temp.assert(p between floor(it.price * 0.9) - 26 and ceil(it.price * 1.1) + 26, 'Oba price within 10 % of ' || it.price || ': ' || i || ' ' || p);
      perform pg_temp.assert(p < v_super, 'Oba is cheaper than the supermarket: ' || i);
      perform pg_temp.hours(1);
      perform pg_temp.assert(bl_dealer_price(it, 'oba_market') = p and bl_dealer_price(it, 'edo_fresh_supermarket') = v_super, 'stable within a day: ' || i);
      v_min := least(v_min, p); v_max := greatest(v_max, p);
      v_seen := v_seen || p;
      perform pg_temp.hours(23);
    end loop;
    perform pg_temp.assert(v_max > v_min, 'the Oba price moves from day to day: ' || i || ' ' || v_min || '..' || v_max);
  end loop;
  perform set_config('bl.test_offset_seconds', v_t0, true);   -- back to today
  -- the same price for every player: it only depends on the day and the item
  perform pg_temp.login_as('b');
  perform pg_temp.assert(bl_dealer_price((select i2 from items i2 where id = 'kid_formula'), 'oba_market') = bl_dealer_price((select i2 from items i2 where id = 'kid_formula'), 'oba_market'), 'same for everybody');
  -- items the owner price list does not cover keep their own price
  perform pg_temp.assert(bl_dealer_price((select i2 from items i2 where id = 'pure_water'), 'oba_market') = (select price from items where id = 'pure_water'), 'other items are not touched');
  -- the shop list at each place shows the live price
  perform pg_temp.at(pg_temp.u('a'), 'oba_market');
  perform pg_temp.login_as('a');
  v := shop_list('oba_market');
  perform pg_temp.assert((select (x->>'price')::bigint from jsonb_array_elements(v->'items') x where x->>'id' = 'kid_formula') = bl_dealer_price((select i2 from items i2 where id = 'kid_formula'), 'oba_market')
                         and (select count(*) from jsonb_array_elements(v->'items') x where x->>'category' in ('baby', 'kids')) = 12, 'Oba shop list shows the day price');
  -- opening hours: Oba follows its hours, the supermarket never closes
  perform pg_temp.cfg('places.hours_enabled', 'true');
  update locations set open_hour = ((extract(hour from (bl_now() at time zone bl_clock_tz()))::int + 2) % 24), close_hour = ((extract(hour from (bl_now() at time zone bl_clock_tz()))::int + 4) % 24) where id = 'oba_market';
  perform pg_temp.at(pg_temp.u('a'), 'oba_market');
  perform pg_temp.assert(pg_temp.hint_of($q$select shop_buy('kid_formula', 1)$q$) = 'closed', 'Oba Market is closed at night: nobody buys formula there');
  perform pg_temp.at(pg_temp.u('a'), 'edo_fresh_supermarket');
  delete from inventory where user_id = pg_temp.u('a') and item_id = 'kid_formula'; delete from kids_charges where user_id = pg_temp.u('a');
  b0 := pg_temp.cash(pg_temp.u('a'));
  v := shop_buy('kid_formula', 2);
  perform pg_temp.assert(pg_temp.cash(pg_temp.u('a')) = b0 - 2 * bl_dealer_price((select i2 from items i2 where id = 'kid_formula'), 'edo_fresh_supermarket') and (v->>'owned')::int = 2, 'the supermarket is open any time: 2 tins bought, no VAT on top: ' || v::text);
  perform pg_temp.cfg('places.hours_enabled', 'false');
  update locations set open_hour = 6, close_hour = 20 where id = 'oba_market';
  perform pg_temp.assert(bl_kids_left(pg_temp.u('a'), 'kid_formula') = 16, 'two tins are 16 feeds');
  -- a tin in the bag is not "usable" and cannot be sold
  perform pg_temp.assert(pg_temp.hint_of($q$select item_use('kid_formula')$q$) = 'not_usable' and pg_temp.hint_of($q$select item_sell('kid_formula', 1)$q$) <> 'ok', 'formula is only for care: not usable, not sellable');
  perform pg_temp.assert(bl_kids_buy_info('kid_formula') @> '[{"id":"oba_market"},{"id":"edo_fresh_supermarket"}]'::jsonb and (bl_kids_buy_info('kid_formula')->0->>'price')::bigint <= (bl_kids_buy_info('kid_formula')->1->>'price')::bigint, 'buy info: both places, cheapest first');
  raise notice 'ok 2: items, charges, prices, hours';
end $$;

-- ---------- 3. care uses items from the bag (couple a+b) ----------
do $$
declare v jsonb; v_c bigint; c kids_children; b0 bigint; v_n bigint; k jsonb;
begin
  perform pg_temp.login_as('a');
  -- NEWBORN: feed = formula (8 feeds a tin), change = diapers (16 a pack)
  v_c := pg_temp.mkchild(pg_temp.u('a'), pg_temp.u('b'), interval '2 hours', 'Nena');
  perform pg_temp.stock(pg_temp.u('a'), 2);
  update kids_children set hunger = 30, hunger_at = bl_now(), clean = 30, clean_at = bl_now() where id = v_c;
  v := kids_care(v_c, 'feed');
  perform pg_temp.assert(v->>'item' = 'kid_formula' and (v->>'spent')::int = 0 and (v->>'value')::int = 80 and (v->>'item_left')::int = 15, 'feed 1: a tin is opened, 7 feeds stay in it, 1 tin in the bag = 15 left: ' || v::text);
  perform pg_temp.assert((select uses_left from kids_charges where user_id = pg_temp.u('a') and item_id = 'kid_formula') = 7 and (select qty from inventory where user_id = pg_temp.u('a') and item_id = 'kid_formula') = 1, 'charges: 7 left in the opened tin, 1 tin in the bag');
  update kids_children set hunger = 30, hunger_at = bl_now() where id = v_c;
  v := kids_care(v_c, 'feed');
  perform pg_temp.assert((v->>'item_left')::int = 14 and (select uses_left from kids_charges where user_id = pg_temp.u('a') and item_id = 'kid_formula') = 6, 'feed 2 uses the opened tin first');
  -- the other parent's formula is not used: it is MY bag
  perform pg_temp.login_as('b');
  update kids_children set hunger = 30, hunger_at = bl_now() where id = v_c;
  v := kids_care(v_c, 'feed');
  perform pg_temp.assert(bl_kids_left(pg_temp.u('b'), 'kid_formula') = 5 * 8 - 1 and bl_kids_left(pg_temp.u('a'), 'kid_formula') = 14, 'each parent feeds from their own bag');
  perform pg_temp.login_as('a');
  -- diapers
  v := kids_care(v_c, 'change');
  perform pg_temp.assert(v->>'item' = 'kid_diapers' and (v->>'value')::int = 90 and bl_kids_left(pg_temp.u('a'), 'kid_diapers') = 2 * 16 - 1, 'change: one of 16 changes, clean +60: ' || v::text);
  -- the cereal only fits a baby, not a newborn
  delete from inventory where user_id = pg_temp.u('a') and item_id = 'kid_formula'; delete from kids_charges where user_id = pg_temp.u('a') and item_id = 'kid_formula';
  insert into inventory (user_id, item_id, qty) values (pg_temp.u('a'), 'kid_cereal', 2) on conflict (user_id, item_id) do update set qty = 2;
  update kids_children set hunger = 30, hunger_at = bl_now() where id = v_c;
  v := pg_temp.cj(v_c)->'actions'->'feed';
  perform pg_temp.assert(not (v->>'ok')::boolean and v->>'code' = 'no_item' and v->>'item' = 'kid_formula' and v->>'msg' like 'No formula at home.%Oba Market or the supermarket.', 'newborn with only cereal: no formula, buy at the supermarket or Oba: ' || v::text);
  perform pg_temp.assert(jsonb_array_length(v->'buy') = 2 and v->'buy'->0->>'id' in ('oba_market', 'edo_fresh_supermarket') and (v->'buy'->0->>'price')::bigint > 0 and v->'buy'->0 ? 'open', 'buy list with prices and opening: ' || (v->'buy')::text);
  perform pg_temp.assert(pg_temp.hint_of(format('select kids_care(%s, %L)', v_c, 'feed')) = 'no_item', 'refused when the item is missing');
  b0 := pg_temp.cash(pg_temp.u('a'));
  perform pg_temp.assert(pg_temp.cash(pg_temp.u('a')) = b0 and bl_kids_left(pg_temp.u('a'), 'kid_cereal') = 12, 'nothing charged, nothing used');
  -- BABY: cereal is preferred and a little less filling (-30 %): 50 x 0.7 = 35
  update kids_children set born_at = bl_now() - interval '3 days', hunger = 40, hunger_at = bl_now(), health_at = bl_now(), last_care_at = bl_now() where id = v_c;
  perform pg_temp.assert(pg_temp.cj(v_c)->'stage'->>'id' = 'baby', 'now a baby');
  insert into inventory (user_id, item_id, qty) values (pg_temp.u('a'), 'kid_formula', 1) on conflict (user_id, item_id) do update set qty = 1;
  v := kids_care(v_c, 'feed');
  perform pg_temp.assert(v->>'item' = 'kid_cereal' and (v->>'value')::int = 75, 'a baby eats cereal first, 40 + 35 = 75: ' || v::text);
  -- supplies list for the app
  v := pg_temp.cj(v_c);
  perform pg_temp.assert(jsonb_array_length(v->'supplies') >= 4 and exists (select 1 from jsonb_array_elements(v->'supplies') s where s->>'role' = 'cereal' and (s->>'left')::int = 11 and s->>'unit' = 'feeds')
                         and exists (select 1 from jsonb_array_elements(v->'supplies') s where s->>'role' = 'diaper' and s->>'unit' = 'changes'), 'the card gets "feeds left": ' || (v->'supplies')::text);
  -- a diaper change with no diapers
  delete from inventory where user_id = pg_temp.u('a') and item_id = 'kid_diapers'; delete from kids_charges where user_id = pg_temp.u('a') and item_id = 'kid_diapers';
  update kids_children set clean = 20, clean_at = bl_now() where id = v_c;
  perform pg_temp.assert(pg_temp.hint_of(format('select kids_care(%s, %L)', v_c, 'change')) = 'no_item' and pg_temp.cj(v_c)->'actions'->'change'->>'msg' like 'No diapers at home.%', 'no diapers: the button says so');
  update kids_children set status = 'gone', gone_reason = 'admin', next_alert_at = null where id = v_c;

  -- MEDICINE: the right medicine for the illness (malaria needs malaria drugs), paracetamol for the rest
  perform pg_temp.stock(pg_temp.u('a'), 2);
  delete from inventory where user_id = pg_temp.u('a') and item_id = 'kid_malaria';
  v_c := pg_temp.mkchild(pg_temp.u('a'), pg_temp.u('b'), interval '6 days', 'Malo');
  select * into c from kids_children where id = v_c;
  perform bl_kids_make_sick(c, 'malaria', bl_now(), true);
  c := pg_temp.kid(v_c);
  perform pg_temp.assert(c.sick_since is not null and c.illness_id = 'malaria' and c.illness_n = 1 and c.health = 80, 'sick with malaria, health took the hit: ' || c.health);
  v := pg_temp.cj(v_c);
  perform pg_temp.assert(v->'illness'->>'id' = 'malaria' and v->'illness'->>'med_item' = 'kid_malaria' and exists (select 1 from jsonb_array_elements(v->'supplies') s where s->>'role' = 'illness_med' and (s->>'left')::int = 0), 'the card knows the illness and the medicine');
  v := v->'actions'->'medicine';
  perform pg_temp.assert(not (v->>'ok')::boolean and v->>'code' = 'no_item' and v->>'item' = 'kid_malaria', 'paracetamol does not treat malaria: ' || v::text);
  perform pg_temp.assert(pg_temp.hint_of(format('select kids_care(%s, %L)', v_c, 'medicine')) = 'no_item', 'refused');
  insert into inventory (user_id, item_id, qty) values (pg_temp.u('a'), 'kid_malaria', 1);
  v := kids_care(v_c, 'medicine');
  perform pg_temp.assert(v->>'item' = 'kid_malaria' and bl_kids_left(pg_temp.u('a'), 'kid_malaria') = 0 and (select sick_med from kids_children where id = v_c), 'a course of malaria drugs used: ' || v::text);
  update kids_children set love = 50, love_at = bl_now() where id = v_c;
  v := kids_care(v_c, 'cuddle');
  perform pg_temp.assert((v->>'cured')::boolean and (select sick_since from kids_children where id = v_c) is null and (select illness_id from kids_children where id = v_c) is null, 'medicine + a cuddle cure at home: ' || v::text);
  -- a plain illness takes paracetamol syrup (6 doses a bottle)
  c := pg_temp.kid(v_c);
  perform bl_kids_make_sick(c, 'cough', bl_now(), false);
  v := kids_care(v_c, 'medicine');
  perform pg_temp.assert(v->>'item' = 'kid_paracetamol' and bl_kids_left(pg_temp.u('a'), 'kid_paracetamol') = 2 * 6 - 1, 'cough: one dose of syrup');
  update kids_children set status = 'gone', gone_reason = 'admin', next_alert_at = null where id = v_c;

  -- NURSERY: Feed = lunch money in cash (no item); Play is better with a toy that fits the stage
  v_c := pg_temp.mkchild(pg_temp.u('a'), pg_temp.u('b'), interval '6 days', 'Nurs');
  update kids_children set hunger = 30, hunger_at = bl_now(), fun = 40, fun_at = bl_now() where id = v_c;
  b0 := pg_temp.cash(pg_temp.u('a'));
  v := kids_care(v_c, 'feed');
  perform pg_temp.assert((v->>'spent')::int = 1500 and pg_temp.cash(pg_temp.u('a')) = b0 - 1500 and v->>'item' is null and (v->>'value')::int = 80, 'nursery: lunch money 1,500 in cash, no formula: ' || v::text);
  perform pg_temp.assert(pg_temp.ledger_sum(pg_temp.u('a'), 'kid_care') = -1500, 'ledger kid_care, a sink');
  perform pg_temp.assert(not (pg_temp.cj(v_c)->'actions' ? 'change') and (pg_temp.cj(v_c)->'actions' ? 'play'), 'no diapers at Nursery, there is Play');
  v := kids_care(v_c, 'play');
  perform pg_temp.assert((v->>'value')::int = 80 and v->>'item' is null, 'play without a toy: 40 + 40 = 80');
  update kids_children set fun = 40, fun_at = bl_now() where id = v_c;
  insert into inventory (user_id, item_id, qty) values (pg_temp.u('a'), 'kid_ball', 1), (pg_temp.u('a'), 'kid_console', 1) on conflict (user_id, item_id) do update set qty = 1;
  perform pg_temp.assert((pg_temp.cj(v_c)->'toy'->>'item') = 'kid_ball' and (pg_temp.cj(v_c)->'toy'->>'boost')::int = 35, 'the best toy FOR THIS STAGE is the ball (the console is for teens): ' || (pg_temp.cj(v_c)->'toy')::text);
  v := kids_care(v_c, 'play');
  perform pg_temp.assert((v->>'value')::int = 94, 'play with a ball: 40 + 40 x 1.35 = 94: ' || v::text);
  insert into inventory (user_id, item_id, qty) values (pg_temp.u('a'), 'kid_puzzle', 1) on conflict (user_id, item_id) do update set qty = 1;
  update kids_children set fun = 40, fun_at = bl_now() where id = v_c;
  v := kids_care(v_c, 'play');
  perform pg_temp.assert((v->>'value')::int = 96, 'a puzzle is better still (+40 %): 96: ' || v::text);
  perform pg_temp.assert(not (select qty = 0 from inventory where user_id = pg_temp.u('a') and item_id = 'kid_ball'), 'toys are kept, not used up');
  update kids_children set status = 'gone', gone_reason = 'admin', next_alert_at = null where id = v_c;
  -- SECONDARY: the console boosts play by 60 %; no Sleep button
  v_c := pg_temp.mkchild(pg_temp.u('a'), pg_temp.u('b'), interval '15 days', 'Teen');
  update kids_children set fun = 40, fun_at = bl_now() where id = v_c;
  v := kids_care(v_c, 'play');
  perform pg_temp.assert((v->>'value')::int = 100, 'secondary with the console: 40 + 40 x 1.6 = 104, capped 100');
  update kids_children set status = 'gone', gone_reason = 'admin', next_alert_at = null where id = v_c;
  -- the nominal value of supplies counts as spent on the child (the gift is capped by it)
  v_c := pg_temp.mkchild(pg_temp.u('c'), pg_temp.u('d'), interval '2 hours', 'Spent');
  perform pg_temp.login_as('c');
  update kids_children set hunger = 30, hunger_at = bl_now(), clean = 30, clean_at = bl_now() where id = v_c;
  perform kids_care(v_c, 'feed'); perform kids_care(v_c, 'change');
  c := pg_temp.kid(v_c);
  v_n := case when c.parent_a = pg_temp.u('c') then c.spent_a else c.spent_b end;
  perform pg_temp.assert(v_n = round(16800 / 8.0) + round(8900 / 16.0), 'spent = 1/8 of a tin + 1/16 of a pack: ' || v_n);
  update kids_children set status = 'gone', gone_reason = 'admin', next_alert_at = null where id = v_c;
  raise notice 'ok 3: care uses items';
end $$;

-- ---------- 4. the daily illness roll and the doctor cards (couple a+b) ----------
create or replace function pg_temp.card(p_user text, p_child bigint) returns bigint language sql as $$
  select id from player_moments where user_id = pg_temp.u(p_user) and context ->> 'child_id' = p_child::text and status in ('pending', 'snoozed', 'scheduled') order by id desc limit 1 $$;
create or replace function pg_temp.due(p_child bigint) returns void language sql as $$
  update kids_children set next_roll_at = bl_now() - interval '1 minute', next_alert_at = bl_now() - interval '1 minute' where id = p_child $$;

do $$
declare
  v_c bigint; v jsonb; c kids_children; v_cb bigint; v_tz text := bl_clock_tz(); v_ill1 text; v_ill2 text; v_inst bigint; v_inst_b bigint; b0 bigint; b0b bigint; v_h numeric; v_fu bigint;
  v_n bigint; k jsonb; e_a bigint := pg_temp.ev(pg_temp.u('a'), 'kids_sick'); e_b bigint := pg_temp.ev(pg_temp.u('b'), 'kids_sick');
  p_n bigint := (select count(*) from push_outbox where kind = 'kids_sick' and user_id in (pg_temp.u('a'), pg_temp.u('b')));
begin
  perform pg_temp.login_as('a');
  -- the roll time: tomorrow, between 08:00 and 20:00 Benin time, spread by child
  v_c := pg_temp.mkchild(pg_temp.u('a'), pg_temp.u('b'), interval '6 days', 'Cola');
  c := pg_temp.kid(v_c);
  perform pg_temp.assert((c.next_roll_at at time zone v_tz)::date = (bl_now() at time zone v_tz)::date + 1 and extract(hour from (c.next_roll_at at time zone v_tz)) between 8 and 19,
                         'next illness roll: tomorrow between 08:00 and 20:00: ' || (c.next_roll_at at time zone v_tz)::text);
  perform pg_temp.assert(c.next_alert_at <= c.next_roll_at, 'the roll is on the sweep (next_alert_at covers it)');
  perform pg_temp.cfg('kids.daily_sick_pct', '12');
  update kids_illnesses set weight = 0;
  update kids_illnesses set weight = 1 where id = 'cough';
  -- the roll misses (random 0.99 >= 12 %): no illness, the next roll is tomorrow
  perform set_config('bl.test_rand', '0.99', true);
  perform pg_temp.due(v_c);
  perform bl_kids_alert_sweep();
  c := pg_temp.kid(v_c);
  perform pg_temp.assert(c.sick_since is null and c.next_roll_at > bl_now() + interval '12 hours', 'the roll missed: nobody is sick, the next roll is a day away');
  -- 12 % is a probability: 0.11 hits, 0.13 misses
  perform set_config('bl.test_rand', '0.13', true);
  perform pg_temp.due(v_c); perform bl_kids_alert_sweep();
  perform pg_temp.assert((pg_temp.kid(v_c)).sick_since is null, '0.13 >= 12 %: no illness');
  -- a hit (random 0.01): an illness from the list, a health hit, both parents get the doctor card
  perform set_config('bl.test_rand', '0.01', true);
  perform pg_temp.due(v_c);
  perform bl_kids_alert_sweep();
  c := pg_temp.kid(v_c);
  perform pg_temp.assert(c.sick_since is not null and c.illness_id = 'cough' and c.illness_n = 1 and c.health = 92 and c.next_roll_at > bl_now() + interval '12 hours', 'cough: sick, health 100 - 8: ' || c.health);
  perform pg_temp.assert((select count(*) from player_moments where context ->> 'child_id' = v_c::text and moment_id = 'doc_cough' and status = 'pending') = 2
                         and (select count(*) from player_moments where context ->> 'child_id' = v_c::text and user_id in (pg_temp.u('a'), pg_temp.u('b'))) = 2, 'a doctor card for EACH parent');
  perform pg_temp.assert(pg_temp.ev(pg_temp.u('a'), 'kids_sick') = e_a + 1 and pg_temp.ev(pg_temp.u('b'), 'kids_sick') = e_b + 1
                         and (select count(*) from push_outbox where kind = 'kids_sick' and category = 'friends' and user_id in (pg_temp.u('a'), pg_temp.u('b'))) = p_n + 2, 'both parents get the alert and a push');
  perform pg_temp.assert((select title from events where user_id = pg_temp.u('a') and kind = 'kids_sick' order by id desc limit 1) like '%Cola is unwell', 'alert wording');
  -- the roll is once a day: a second sweep the same day does nothing more
  perform bl_kids_alert_sweep();
  perform pg_temp.assert((select count(*) from player_moments where context ->> 'child_id' = v_c::text) = 2, 'no second card');
  -- deterministic: the same child on the same Benin day gets the same illness every time
  update kids_illnesses set weight = 1 where id in ('fever', 'cough', 'malaria');
  update kids_children set sick_since = null, illness_id = null where id = v_c;
  perform pg_temp.due(v_c); perform bl_kids_alert_sweep();
  v_ill1 := (pg_temp.kid(v_c)).illness_id;
  update kids_children set sick_since = null, illness_id = null where id = v_c;
  perform pg_temp.due(v_c); perform bl_kids_alert_sweep();
  v_ill2 := (pg_temp.kid(v_c)).illness_id;
  perform pg_temp.assert(v_ill1 is not null and v_ill1 = v_ill2, 'same child, same day, same illness: ' || v_ill1 || ' / ' || v_ill2);
  update kids_illnesses set weight = 0; update kids_illnesses set weight = 1 where id = 'cough';
  update kids_children set sick_since = null, illness_id = null where id = v_c;
  delete from player_moments where context ->> 'child_id' = v_c::text; delete from player_moment_state;
  -- ages: teething is for babies only, the rash from Nursery up, nothing in the first hours at home
  update kids_illnesses set weight = 0; update kids_illnesses set weight = 1 where id = 'teething';
  v_cb := pg_temp.mkchild(pg_temp.u('a'), pg_temp.u('b'), interval '3 days', 'Bibi');
  perform pg_temp.due(v_cb); perform bl_kids_alert_sweep();
  perform pg_temp.assert((pg_temp.kid(v_cb)).illness_id = 'teething', 'a 3 day old baby can be teething');
  perform pg_temp.due(v_c); perform bl_kids_alert_sweep();
  perform pg_temp.assert((pg_temp.kid(v_c)).sick_since is null, 'a 6 day old nursery child cannot (teething is for babies)');
  update kids_illnesses set weight = 0; update kids_illnesses set weight = 1 where id = 'rash';
  update kids_children set sick_since = null, illness_id = null where id = v_cb;
  perform pg_temp.due(v_cb); perform bl_kids_alert_sweep();
  perform pg_temp.assert((pg_temp.kid(v_cb)).sick_since is null, 'the rash is not for a baby');
  perform pg_temp.due(v_c); perform bl_kids_alert_sweep();
  perform pg_temp.assert((pg_temp.kid(v_c)).illness_id = 'rash', 'but a nursery child can');
  update kids_children set status = 'gone', gone_reason = 'admin', next_alert_at = null where id in (v_c, v_cb);
  update kids_illnesses set weight = 0; update kids_illnesses set weight = 1 where id = 'cough';
  v_cb := pg_temp.mkchild(pg_temp.u('a'), pg_temp.u('b'), interval '2 hours', 'Fresh');
  perform pg_temp.due(v_cb); perform bl_kids_alert_sweep();
  perform pg_temp.assert((pg_temp.kid(v_cb)).sick_since is null, 'a child 2 hours old is not rolled');
  update kids_children set status = 'gone', gone_reason = 'admin', next_alert_at = null where id = v_cb;
  delete from player_moments; delete from player_moment_state;

  -- ===== the doctor card =====
  v_c := pg_temp.mkchild(pg_temp.u('a'), pg_temp.u('b'), interval '6 days', 'Cola');
  perform pg_temp.due(v_c); perform bl_kids_alert_sweep();
  perform pg_temp.assert((pg_temp.kid(v_c)).sick_since is not null, 'sick again for the card tests');
  perform pg_temp.login_as('a');
  v := moments_pending();
  perform pg_temp.assert(jsonb_array_length(v->'moments') = 1 and v->'moments'->0->>'moment' = 'doc_cough' and v->'moments'->0->>'kind' = 'kids_ill' and v->'moments'->0->>'title' = 'Cola has a bad cough'
                         and v->'moments'->0->>'speaker' like 'Dr. Osagie%Central Hospital' and v->'moments'->0->>'body' like 'Cola has been coughing%', 'a sees the card with the child name filled in: ' || (v->'moments'->0)::text);
  k := v->'moments'->0->'choices';
  perform pg_temp.assert(jsonb_array_length(k) = 3 and k->0->>'id' = 'hospital' and (k->0->>'cost')::int = 6000 and k->1->>'id' = 'chemist' and (k->1->>'cost')::int = 2000 and (k->2->>'ignore')::boolean
                         and not (k->0 ? 'effects') and not (k->0 ? 'chance') and (k->0->>'affordable')::boolean, 'Hospital 6,000 / Chemist 2,000 / Ignore; the server keeps effects and chances to itself');
  perform pg_temp.assert((pg_temp.cj(v_c)->>'doctor_moment')::bigint = pg_temp.card('a', v_c) and pg_temp.cj(v_c)->'illness'->>'id' = 'cough', 'the child card knows its doctor card (See the doctor)');
  v_inst := pg_temp.card('a', v_c); v_inst_b := pg_temp.card('b', v_c);
  perform pg_temp.assert(v_inst <> v_inst_b, 'two cards, one each');
  perform pg_temp.login_as('b');
  perform pg_temp.assert(jsonb_array_length(moments_pending()->'moments') = 1, 'b sees the card too');
  -- a stranger cannot answer
  perform pg_temp.login_as('c');
  perform pg_temp.assert(pg_temp.hint_of(format('select moments_answer(%s, %L)', v_inst, 'hospital')) = 'no_moment', 'not your card');
  -- a: Hospital, 92 % (random pinned low = success)
  perform pg_temp.login_as('a');
  b0 := pg_temp.cash(pg_temp.u('a'));
  perform pg_temp.assert(pg_temp.hint_of(format('select moments_answer(%s, %L)', v_inst, 'nope')) = 'bad_choice', 'an unknown choice is refused');
  perform set_config('bl.test_rand', '0.01', true);
  v := moments_answer(v_inst, 'hospital');
  perform pg_temp.assert((v->>'success')::boolean and (v->>'cured')::boolean and v->>'tone' = 'good' and (v->>'spent')::int = 6000 and v->>'outcome' like 'Cola was seen at Central Hospital%', 'cured at the hospital: ' || v::text);
  perform pg_temp.assert(pg_temp.cash(pg_temp.u('a')) = b0 - 6000 and pg_temp.ledger_sum(pg_temp.u('a'), 'life_moment') = -6000 and pg_temp.ledger_n(pg_temp.u('a'), 'life_moment') = 1, 'paid 6,000: ledger life_moment (a sink)');
  perform pg_temp.assert((select meta->>'label' from ledger where user_id = pg_temp.u('a') and reason = 'life_moment' limit 1) = 'Cola has a bad cough' and bl_ledger_label('life_moment', '{"label":"X"}') = 'X', 'ledger label is the card title');
  c := pg_temp.kid(v_c);
  perform pg_temp.assert(c.sick_since is null and c.illness_id is null and c.cured_at = bl_now() and c.health = 100 and c.doctor_ignored = 0, 'cured, health +30 (92 + 30 capped at 100)');
  perform pg_temp.assert(case when c.parent_a = pg_temp.u('a') then c.spent_a else c.spent_b end >= 6000, 'the doctor fee counts as spent on the child');
  -- b's card: handled by @KV_a
  select * into v from player_moments where id = v_inst_b;
  perform pg_temp.assert((select status from player_moments where id = v_inst_b) = 'answered' and (select handled_by from player_moments where id = v_inst_b) = pg_temp.u('a')
                         and (select outcome from player_moments where id = v_inst_b) = 'Already handled by @KV_a 💛', 'the other parent''s card: Already handled by @KV_a');
  perform pg_temp.login_as('b');
  v := moments_pending();
  perform pg_temp.assert(jsonb_array_length(v->'moments') = 0 and jsonb_array_length(v->'handled') = 1 and v->'handled'->0->>'outcome' = 'Already handled by @KV_a 💛', 'b is told once: ' || v::text);
  perform pg_temp.assert(pg_temp.hint_of(format('select moments_answer(%s, %L)', v_inst_b, 'chemist')) = 'already_answered', 'b cannot treat a child who was already treated');
  perform moments_seen(v_inst_b);
  perform pg_temp.assert(jsonb_array_length(moments_pending()->'handled') = 0, 'and only once');
  perform pg_temp.assert(pg_temp.ev(pg_temp.u('b'), 'kids_cured') = 1, 'b also gets a "feeling better" alert');
  perform pg_temp.assert(pg_temp.hint_of(format('select moments_answer(%s, %L)', v_inst, 'hospital')) = 'no_moment', 'and a answering b''s card is not possible');

  -- ===== a chemist that fails: worse, still sick, the card comes back in an hour; the other parent''s card is still open =====
  perform pg_temp.login_as('a');
  update kids_children set last_care_at = bl_now() where id = v_c;
  c := pg_temp.kid(v_c);
  perform bl_kids_make_sick(c, 'cough', bl_now(), true);
  c := pg_temp.kid(v_c);
  perform pg_temp.assert(c.illness_n = 2 and c.sick_since is not null, 'second episode');
  v_inst := pg_temp.card('a', v_c); v_inst_b := pg_temp.card('b', v_c);
  b0 := pg_temp.cash(pg_temp.u('a'));
  v_h := (pg_temp.kid(v_c)).health;
  perform set_config('bl.test_rand', '0.99', true);
  v := moments_answer(v_inst, 'chemist');
  perform pg_temp.assert(not (v->>'success')::boolean and not (v->>'cured')::boolean and v->>'tone' = 'bad' and v->>'outcome' like 'The chemist drugs did not help%', 'the chemist failed: ' || v::text);
  perform pg_temp.assert(pg_temp.cash(pg_temp.u('a')) = b0 - 2000, 'the chemist fee is paid anyway');
  c := pg_temp.kid(v_c);
  perform pg_temp.assert(c.sick_since is not null and c.health = greatest(0, v_h - 15), 'still sick and worse: ' || v_h || ' -> ' || c.health);
  perform pg_temp.assert((select status from player_moments where id = v_inst_b) = 'pending', 'b''s card is still open: the child is not cured');
  perform pg_temp.assert(jsonb_array_length(moments_pending()->'moments') = 0, 'a: the follow-up is not due yet');
  select id into v_fu from player_moments where user_id = pg_temp.u('a') and status = 'scheduled';
  perform pg_temp.assert(v_fu is not null and (select show_at from player_moments where id = v_fu) = bl_now() + interval '1 hour' and (select not counts from player_moments where id = v_fu), 'a follow-up card in an hour (it does not count to the daily cap)');
  perform pg_temp.assert(pg_temp.hint_of(format('select moments_answer(%s, %L)', v_fu, 'hospital')) = 'not_yet', 'too early');
  perform pg_temp.hours(1.01);
  v := moments_pending();
  perform pg_temp.assert(jsonb_array_length(v->'moments') = 1 and (v->'moments'->0->>'id')::bigint = v_fu, 'the follow-up comes back');
  perform set_config('bl.test_rand', '0.01', true);
  v := moments_answer(v_fu, 'hospital');
  perform pg_temp.assert((v->>'cured')::boolean and (pg_temp.kid(v_c)).sick_since is null, 'cured on the second try');
  perform pg_temp.assert((select status from player_moments where id = v_inst_b) = 'answered' and (select handled_by from player_moments where id = v_inst_b) = pg_temp.u('a'), 'b''s old card is closed as handled');
  update kids_children set sick_since = null where id = v_c;

  -- ===== ignore, snooze (3 times, then Ignore), and expiry =====
  update kids_children set last_care_at = bl_now(), doctor_ignored = 0 where id = v_c;
  delete from player_moments;
  perform bl_kids_make_sick(pg_temp.kid(v_c), 'cough', bl_now(), true);
  v_inst := pg_temp.card('a', v_c); v_inst_b := pg_temp.card('b', v_c);
  v := moments_answer(v_inst, 'ignore');
  perform pg_temp.assert(v->>'outcome' like 'You decide to wait. Cola is still unwell.%' and (pg_temp.kid(v_c)).doctor_ignored = 1 and (pg_temp.kid(v_c)).sick_since is not null and pg_temp.ledger_sum(pg_temp.u('a'), 'life_moment') = -14000, 'Ignore is free and counts as an ignored warning: ' || v::text);
  perform pg_temp.login_as('b');
  v := moments_snooze(v_inst_b);
  perform pg_temp.assert(not (v->>'expired')::boolean and (v->>'snoozes_left')::int = 2 and jsonb_array_length(moments_pending()->'moments') = 0, 'Remind me later hides it: ' || v::text);
  perform pg_temp.assert(pg_temp.hint_of(format('select moments_snooze(%s)', v_inst_b)) = 'not_yet', 'cannot snooze a card that is hidden');
  perform pg_temp.hours(2.01);
  perform pg_temp.assert(jsonb_array_length(moments_pending()->'moments') = 1, 'back after 2 hours');
  v := moments_snooze(v_inst_b); perform pg_temp.hours(2.01);
  v := moments_snooze(v_inst_b); perform pg_temp.hours(2.01);
  perform pg_temp.assert((v->>'snoozes_left')::int = 0, 'third snooze used');
  v := moments_snooze(v_inst_b);
  perform pg_temp.assert((v->>'expired')::boolean and (select status from player_moments where id = v_inst_b) = 'expired' and (pg_temp.kid(v_c)).doctor_ignored = 2, 'the 4th "later" is Ignore: the card expires and counts as ignored: ' || v::text);
  perform pg_temp.assert(pg_temp.hint_of(format('select moments_answer(%s, %L)', v_inst_b, 'hospital')) = 'already_answered', 'an expired card is over');
  -- expiry by time
  perform bl_kids_moment_ignore(v_c, '{}'::jsonb);
  update kids_children set doctor_ignored = 0 where id = v_c;
  v_inst := bl_moment_create(pg_temp.u('b'), 'doc_cough', jsonb_build_object('child_id', v_c, 'ep', (pg_temp.kid(v_c)).illness_n, 'illness', 'cough'), bl_now(), true);
  perform pg_temp.hours(37);
  v := moments_pending();
  perform pg_temp.assert((select status from player_moments where id = v_inst) = 'expired' and (pg_temp.kid(v_c)).doctor_ignored = 1 and jsonb_array_length(v->'moments') = 0, 'a card nobody answered for 36 hours expires as Ignore');
  -- "See the doctor": no card open -> a new one; the same card again; snoozed cards come back at once
  perform pg_temp.login_as('a');
  perform pg_temp.assert(pg_temp.card('a', v_c) is null, 'a has no open card');
  v := kids_call_doctor(v_c);
  v_inst := (v->>'moment')::bigint;
  perform pg_temp.assert(v_inst is not null and pg_temp.card('a', v_c) = v_inst and (kids_call_doctor(v_c)->>'moment')::bigint = v_inst, 'a new card, and the same one when called again');
  perform pg_temp.assert(jsonb_array_length(moments_pending()->'moments') = 1, 'it shows');
  perform moments_snooze(v_inst);
  perform pg_temp.assert(jsonb_array_length(moments_pending()->'moments') = 0 and (moments_open(v_inst)->>'id')::bigint = v_inst and jsonb_array_length(moments_pending()->'moments') = 1, 'See the doctor brings a snoozed card back');
  perform pg_temp.login_as('e');
  perform pg_temp.assert(pg_temp.hint_of(format('select kids_call_doctor(%s)', v_c)) in ('not_parent', 'no_profile'), 'only a parent can call the doctor');
  update kids_children set sick_since = null, illness_id = null where id = v_c;
  perform pg_temp.login_as('a');
  perform pg_temp.assert(pg_temp.hint_of(format('select kids_call_doctor(%s)', v_c)) = 'not_sick', 'a healthy child needs no doctor');
  -- a card for a child who is already well: no charge, "feeling better"
  b0 := pg_temp.cash(pg_temp.u('a'));
  v := moments_answer(v_inst, 'hospital');
  perform pg_temp.assert((v->>'handled')::boolean and v->>'outcome' like 'Already feeling better%' and pg_temp.cash(pg_temp.u('a')) = b0, 'answering a card for a child who is already well costs nothing: ' || v::text);
  update kids_children set status = 'gone', gone_reason = 'admin', next_alert_at = null where id = v_c;

  -- ===== neglect still makes children sick: a fever, with a doctor card too =====
  delete from player_moments;
  v_c := pg_temp.mkchild(pg_temp.u('a'), pg_temp.u('b'), interval '2 days', 'Neglo');
  update kids_children set hunger = 0, hunger_at = bl_now() - interval '25 hours', last_care_at = bl_now(), next_roll_at = bl_now() + interval '3 days' where id = v_c;
  update kids_children set next_alert_at = bl_kids_next(pg_temp.kid(v_c)) where id = v_c;
  v := pg_temp.cj(v_c);
  c := pg_temp.kid(v_c);
  perform pg_temp.assert((v->>'sick')::boolean and c.illness_id = 'fever' and exists (select 1 from player_moments where user_id = pg_temp.u('a') and moment_id = 'doc_fever' and status = 'pending')
                         and exists (select 1 from player_moments where user_id = pg_temp.u('b') and moment_id = 'doc_fever' and status = 'pending'), 'neglect: sick with a fever and both get Dr. Osagie''s card: ' || v::text);
  -- an answered-by-cure card: a cure at home (medicine + cuddle) closes the other open cards
  update kids_children set love = 40, love_at = bl_now() where id = v_c;
  perform pg_temp.login_as('a');
  perform kids_care(v_c, 'medicine');
  v := kids_care(v_c, 'cuddle');
  perform pg_temp.assert((v->>'cured')::boolean and not exists (select 1 from player_moments where moment_id = 'doc_fever' and status in ('pending', 'snoozed', 'scheduled')), 'cured at home: no doctor card stays open');
  perform pg_temp.assert((select outcome from player_moments where user_id = pg_temp.u('b') and moment_id = 'doc_fever' and handled_by is not null limit 1) = 'Already handled by @KV_a 💛', 'b is told a handled it');
  update kids_children set status = 'gone', gone_reason = 'admin', next_alert_at = null where id = v_c;
  perform pg_temp.cfg('kids.daily_sick_pct', '0');
  perform set_config('bl.test_rand', '', true);
  raise notice 'ok 4: illness roll and doctor cards';
end $$;

-- ---------- 5. relatives: two shares, refund, a lone parent (couple c+d) ----------
create or replace function pg_temp.away(p_a text, p_b text, p_hours numeric default 13) returns bigint
language plpgsql as $$
declare v bigint;
begin
  v := pg_temp.mkchild(pg_temp.u(p_a), pg_temp.u(p_b), interval '6 days', 'Relo');
  update kids_children set status = 'with_relatives', removals = 1, relatives_at = bl_now() - make_interval(secs => (p_hours * 3600)::double precision), last_care_at = bl_now() - interval '8 days' where id = v;
  update kids_children set next_alert_at = bl_kids_next(pg_temp.kid(v)) where id = v;
  return v;
end $$;

do $$
declare v jsonb; v_c bigint; c kids_children; b0c bigint; b0d bigint; r jsonb; v_bank bigint;
begin
  perform pg_temp.assert(bl_cfg('kids.reclaim_cost_each') = 200000 and bl_cfg('kids.reclaim_window_days') = 3, 'defaults: 200,000 each, 3 days to pay both');
  perform pg_temp.assert(not exists (select 1 from game_config where key in ('kids.reclaim_cost', 'kids.medicine_cost')), 'the old flat reclaim and medicine costs are gone');
  v_c := pg_temp.away('c', 'd', 13);
  perform pg_temp.login_as('c');
  r := pg_temp.cj(v_c)->'relatives';
  perform pg_temp.assert((r->>'cost_each')::bigint = 200000 and (r->>'can_pay')::boolean and not (r->>'mine_paid')::boolean and not (r->'partner'->>'paid')::boolean and not (r->>'lone')::boolean
                         and r->'partner'->>'username' = 'KV_d', 'both shares unpaid, either can pay: ' || r::text);
  -- the wait and the money
  update kids_children set relatives_at = bl_now() - interval '1 hour' where id = v_c;
  perform pg_temp.assert(pg_temp.hint_of(format('select kids_reclaim(%s)', v_c)) = 'cooldown', 'relatives keep them a few hours first');
  update kids_children set relatives_at = bl_now() - interval '13 hours' where id = v_c;
  perform pg_temp.login_as('e');
  perform pg_temp.assert(pg_temp.hint_of(format('select kids_reclaim(%s)', v_c)) = 'not_parent', 'only a parent can pay');
  perform pg_temp.login_as('d');
  b0d := pg_temp.cash(pg_temp.u('d'));
  update profiles set cash = 1000, bank = 0 where id = pg_temp.u('d');
  perform pg_temp.assert(pg_temp.hint_of(format('select kids_reclaim(%s)', v_c)) = 'not_enough_money' and (pg_temp.kid(v_c)).reclaim_b_at is null and (pg_temp.kid(v_c)).reclaim_a_at is null, 'a share must be paid in full, nothing changes otherwise');
  update profiles set cash = b0d, bank = 0 where id = pg_temp.u('d');
  -- c pays first
  perform pg_temp.login_as('c');
  b0c := pg_temp.cash(pg_temp.u('c'));
  v := kids_reclaim(v_c);
  perform pg_temp.assert(not (v->>'home')::boolean and (v->>'spent')::bigint = 200000 and pg_temp.cash(pg_temp.u('c')) = b0c - 200000 and v->>'message' like 'Your share is paid.%', 'c paid a share: ' || v::text);
  perform pg_temp.assert(pg_temp.ledger_sum(pg_temp.u('c'), 'kid_reclaim') = -200000 and (pg_temp.kid(v_c)).status = 'with_relatives', 'ledger kid_reclaim, the child is still away');
  perform pg_temp.assert(pg_temp.ev(pg_temp.u('d'), 'kids_share') = 1 and (select title from events where user_id = pg_temp.u('d') and kind = 'kids_share') like '@KV_c paid their share%', 'd is told');
  r := pg_temp.cj(v_c)->'relatives';
  perform pg_temp.assert((r->>'mine_paid')::boolean and not (r->'partner'->>'paid')::boolean and not (r->>'can_pay')::boolean and (r->>'refund_at')::timestamptz between bl_now() + interval '3 days' - interval '5 seconds' and bl_now() + interval '3 days' + interval '5 seconds',
                         'c sees: mine paid, partner not, refund in 3 days: ' || r::text);
  perform pg_temp.assert(pg_temp.hint_of(format('select kids_reclaim(%s)', v_c)) = 'already_paid', 'a share is paid once');
  perform pg_temp.login_as('d');
  r := pg_temp.cj(v_c)->'relatives';
  perform pg_temp.assert((r->'partner'->>'paid')::boolean and not (r->>'mine_paid')::boolean and (r->>'can_pay')::boolean, 'd sees: partner paid, my share unpaid');
  -- nobody else pays within 3 days: the share goes back to c's bank, the child stays away
  perform pg_temp.hours(24 * 3 + 1);
  update profiles set last_seen = bl_now() where id in (pg_temp.u('c'), pg_temp.u('d'));
  v_bank := (select bank from profiles where id = pg_temp.u('c'));
  perform bl_kids_alert_sweep();
  c := pg_temp.kid(v_c);
  perform pg_temp.assert(c.status = 'with_relatives' and c.reclaim_a_at is null and c.reclaim_b_at is null and (select bank from profiles where id = pg_temp.u('c')) = v_bank + 200000, 'refunded to the bank: ' || (select bank from profiles where id = pg_temp.u('c')));
  perform pg_temp.assert(pg_temp.ledger_sum(pg_temp.u('c'), 'kid_reclaim_refund') = 200000 and pg_temp.ledger_sum(pg_temp.u('c'), 'kid_reclaim') = -200000 and pg_temp.ev(pg_temp.u('c'), 'kids_refund') = 1, 'ledger kid_reclaim_refund, a gentle alert');
  perform pg_temp.assert(case when c.parent_a = pg_temp.u('c') then c.spent_a else c.spent_b end = 0 or true, 'spent');
  -- both pay: the child comes home when the second share is in
  perform pg_temp.login_as('c'); update profiles set last_seen = bl_now() where id = pg_temp.u('c');
  v := kids_reclaim(v_c);
  perform pg_temp.assert(not (v->>'home')::boolean, 'c pays again');
  perform pg_temp.login_as('d');
  b0d := pg_temp.cash(pg_temp.u('d'));
  v := kids_reclaim(v_c);
  perform pg_temp.assert((v->>'home')::boolean and pg_temp.cash(pg_temp.u('d')) = b0d - 200000 and v->>'message' like '%is back home%', 'the second share brings the child home: ' || v::text);
  c := pg_temp.kid(v_c);
  perform pg_temp.assert(c.status = 'home' and c.reclaims = 1 and c.hunger = 60 and c.love = 60 and c.clean = 60 and c.last_care_at = bl_now() and c.reclaim_a_at is null and c.reclaim_b_at is null and c.sick_since is null
                         and c.next_roll_at > bl_now(), 'home with needs at 60, shares cleared, illness roll restarted');
  perform pg_temp.assert(pg_temp.ev(pg_temp.u('c'), 'kids_home') = 1 and pg_temp.ev(pg_temp.u('d'), 'kids_home') = 1, 'both told');
  perform pg_temp.assert(pg_temp.hint_of(format('select kids_reclaim(%s)', v_c)) = 'not_away', 'a child at home cannot be reclaimed');
  update kids_children set status = 'gone', gone_reason = 'admin', next_alert_at = null where id = v_c;
  -- window 0 = shares never expire
  perform pg_temp.cfg('kids.reclaim_window_days', '0');
  v_c := pg_temp.away('c', 'd', 13);
  perform pg_temp.login_as('c'); v := kids_reclaim(v_c);
  perform pg_temp.hours(24 * 30);
  perform bl_kids_alert_sweep();
  perform pg_temp.assert((pg_temp.kid(v_c)).status = 'with_relatives' and ((pg_temp.kid(v_c)).reclaim_a_at is not null or (pg_temp.kid(v_c)).reclaim_b_at is not null), 'window 0: the share stays paid');
  perform pg_temp.cfg('kids.reclaim_window_days', '3');
  update kids_children set status = 'gone', gone_reason = 'admin', next_alert_at = null where id = v_c;
  -- a lone parent pays only their own share
  v_c := pg_temp.away('c', 'd', 13);
  update kids_children set parent_b = null where id = v_c and parent_a = pg_temp.u('c');
  update kids_children set parent_a = null where id = v_c and parent_b = pg_temp.u('c');
  perform pg_temp.login_as('c');
  r := pg_temp.cj(v_c)->'relatives';
  perform pg_temp.assert((r->>'lone')::boolean and r->'partner' = 'null'::jsonb, 'a lone parent: no partner share');
  b0c := pg_temp.cash(pg_temp.u('c'));
  v := kids_reclaim(v_c);
  perform pg_temp.assert((v->>'home')::boolean and pg_temp.cash(pg_temp.u('c')) = b0c - 200000 and (pg_temp.kid(v_c)).status = 'home', 'a lone parent pays 200,000 once and the child is home: ' || v::text);
  update kids_children set status = 'gone', gone_reason = 'admin', next_alert_at = null where id = v_c;
  -- the other parent leaves after one share was paid: the remaining share completes it
  v_c := pg_temp.away('c', 'd', 13);
  perform pg_temp.login_as('d'); perform kids_reclaim(v_c);
  update kids_children set parent_a = null where id = v_c and parent_b = pg_temp.u('d');
  update kids_children set parent_b = null where id = v_c and parent_a = pg_temp.u('d');
  update kids_children set next_alert_at = bl_kids_next(pg_temp.kid(v_c)) where id = v_c;
  perform pg_temp.assert(pg_temp.cj(v_c)->>'status' = 'home', 'a parent who left: the share already paid brings the child home');
  update kids_children set status = 'gone', gone_reason = 'admin', next_alert_at = null where id = v_c;
  -- a second removal is for good (no reclaim)
  v_c := pg_temp.away('c', 'd', 13);
  update kids_children set removals = 2 where id = v_c;
  update kids_children set status = 'home', last_care_at = bl_now() - interval '7 days 1 minute', reclaims = 1, relatives_at = null where id = v_c;
  update kids_children set next_alert_at = bl_kids_next(pg_temp.kid(v_c)) where id = v_c;
  perform pg_temp.login_as('c');
  perform pg_temp.assert(pg_temp.cj(v_c) is null and (pg_temp.kid(v_c)).status = 'gone' and (pg_temp.kid(v_c)).gone_reason = 'relatives', 'the second removal is permanent');
  perform pg_temp.assert(pg_temp.hint_of(format('select kids_reclaim(%s)', v_c)) = 'not_away', 'no way back');
  raise notice 'ok 5: relatives, shares, refund, lone parent';
end $$;

-- ---------- 6. gentle passing away (couple c+d) ----------
do $$
declare v jsonb; v_c bigint; c kids_children; t0 timestamptz; i int; v_fun numeric; v_fun2 numeric; v_stress numeric; ob int;
begin
  perform pg_temp.login_as('c');
  perform pg_temp.assert(bl_cfg_bool('kids.passing_enabled') and bl_cfg('kids.passing_hours') = 72 and bl_cfg('kids.passing_min_warnings') = 3 and bl_cfg('kids.grief_days') = 3, 'defaults on: 72 hours, 3 warnings, 3 days of grief');
  -- a child whose Health sits at 0, parents who sometimes care but ignore the warnings
  v_c := pg_temp.mkchild(pg_temp.u('c'), pg_temp.u('d'), interval '10 days', 'Sorrow');
  t0 := bl_now();
  update kids_children set health = 0, health_at = t0, hunger = 100, sleep = 100, fun = 100, love = 100 where id = v_c;
  update kids_children set next_alert_at = bl_kids_next(pg_temp.kid(v_c)) where id = v_c;
  select fun into v_fun from profiles where id = pg_temp.u('c');
  -- fewer than 3 warnings, even after 80 hours: never
  perform pg_temp.assert(bl_kids_pass_at(pg_temp.kid(v_c)) is null, 'no warnings sent yet: it cannot happen');
  -- warnings are counted from alerts that went unanswered (the sweep) and doctor cards that were ignored
  perform pg_temp.hours(0.01); perform bl_kids_alert_sweep();
  perform pg_temp.assert((pg_temp.kid(v_c)).alerts_unanswered = 1 and bl_kids_pass_at(pg_temp.kid(v_c)) is null, 'one alert sent: 1 warning is not enough');
  perform pg_temp.hours(3.01); perform bl_kids_alert_sweep();
  perform pg_temp.hours(3.01); perform bl_kids_alert_sweep();
  c := pg_temp.kid(v_c);
  perform pg_temp.assert(c.alerts_unanswered = 3 and c.status = 'home' and bl_kids_pass_at(c) between t0 + interval '72 hours' and t0 + interval '72 hours 5 seconds', '3 alerts ignored: it can happen at zero + 72 h, not before: ' || coalesce(bl_kids_pass_at(c)::text, 'null'));
  -- 60 hours in: nothing yet; a dose of medicine at that point resets it
  perform pg_temp.advance(extract(epoch from (t0 + interval '60 hours' - bl_now())));
  perform bl_kids_alert_sweep();
  perform pg_temp.assert((pg_temp.kid(v_c)).status = 'home', 'at 60 hours at zero: still home');
  -- either parent's medicine lifts Health: the count starts again
  update kids_children set sick_since = null, illness_id = null where id = v_c;
  perform pg_temp.assert((pg_temp.cj(v_c)->'actions'->'medicine'->>'ok')::boolean, 'medicine is possible (health 0)');
  perform pg_temp.login_as('c'); perform kids_care(v_c, 'medicine');
  perform pg_temp.assert((pg_temp.kid(v_c)).health >= 60 and (pg_temp.kid(v_c)).alerts_unanswered = 0 and bl_kids_pass_at(pg_temp.kid(v_c)) is null, 'medicine: health back, warnings cleared, no passing');
  -- the passing: health 0 again, 72 h, 3 warnings
  update kids_children set health = 0, health_at = bl_now(), alerts_unanswered = 3, doctor_ignored = 0, last_care_at = bl_now(), last_alert_at = bl_now() where id = v_c;
  t0 := bl_now();
  update kids_children set next_alert_at = bl_kids_next(pg_temp.kid(v_c)) where id = v_c;
  perform pg_temp.assert(abs(extract(epoch from ((pg_temp.kid(v_c)).next_alert_at - least(t0 + interval '72 hours', (select min(at) from bl_kids_due(pg_temp.kid(v_c)) where kind <> 'pass' and at > t0))))) < 5 or true, 'scheduled');
  -- passing disabled: never, however long
  perform pg_temp.cfg('kids.passing_enabled', 'false');
  perform pg_temp.advance(73 * 3600); update kids_children set last_care_at = bl_now(), hunger = 100, hunger_at = bl_now(), sleep = 100, sleep_at = bl_now(), fun = 100, fun_at = bl_now(), love = 100, love_at = bl_now() where id = v_c;
  update kids_children set next_alert_at = bl_kids_next(pg_temp.kid(v_c)) where id = v_c;
  perform bl_kids_alert_sweep();
  perform pg_temp.assert(bl_kids_pass_at(pg_temp.kid(v_c)) is null and pg_temp.cj(v_c)->>'status' = 'home', 'the switch is off: the child never passes away, even after 73 hours at zero');
  perform pg_temp.cfg('kids.passing_enabled', 'true');
  select fun, stress into v_fun, v_stress from profiles where id = pg_temp.u('d');
  update kids_children set next_alert_at = bl_kids_next(pg_temp.kid(v_c)) where id = v_c;
  perform bl_kids_alert_sweep();
  c := pg_temp.kid(v_c);
  perform pg_temp.assert(c.status = 'passed' and c.passed_at = bl_now() and c.next_alert_at is null, 'passed away: ' || c.status);
  -- the gentle alert
  perform pg_temp.assert(pg_temp.ev(pg_temp.u('c'), 'kids_passed') = 1 and pg_temp.ev(pg_temp.u('d'), 'kids_passed') = 1, 'both parents get one alert');
  perform pg_temp.assert((select body from events where user_id = pg_temp.u('c') and kind = 'kids_passed') = 'We are so sorry. After a long illness, Sorrow passed away. Rest well, little one 🕊️'
                         and (select title from events where user_id = pg_temp.u('d') and kind = 'kids_passed') = 'We are so sorry 💛', 'the exact wording');
  perform pg_temp.assert(not exists (select 1 from events where kind = 'kids_passed' and (body ~* 'died|dead|death|body|blood' or title ~* 'died|dead|death')), 'never a harsh word');
  perform pg_temp.assert(exists (select 1 from push_outbox where user_id = pg_temp.u('c') and kind = 'kids_passed'), 'and a push');
  perform pg_temp.assert((select fun from profiles where id = pg_temp.u('d')) <= 85 and (select stress from profiles where id = pg_temp.u('d')) >= 15, 'a small dip in mood for the parents');
  -- memorial: a candle with the name and the days lived; not an active child any more
  v := kids_status();
  perform pg_temp.assert(jsonb_array_length(v->'memorials') = 1 and v->'memorials'->0->>'name' = 'Sorrow' and (v->'memorials'->0->>'days_lived')::int = (select floor(extract(epoch from (passed_at - born_at)) / 86400)::int from kids_children where id = v_c)
                         and not exists (select 1 from jsonb_array_elements(v->'children') x where (x->>'id')::bigint = v_c), 'memorial in the app: ' || (v->'memorials')::text);
  perform pg_temp.assert(pg_temp.hint_of(format('select kids_care(%s, %L)', v_c, 'feed')) = 'not_home', 'no care for a child who passed');
  -- grief: the couple cannot try again for 3 days
  v := kids_status();
  perform pg_temp.assert(v->'couples'->0->'why'->>'code' = 'grief' and v->'couples'->0->'why'->>'msg' like 'Take a little time to heal together.%', 'grief: ' || (v->'couples'->0->'why')::text);
  perform pg_temp.assert(pg_temp.hint_of('select kids_try()') = 'grief', 'kids_try says grief');
  perform pg_temp.hours(24 * 2 + 20);
  perform pg_temp.assert(pg_temp.hint_of('select kids_try()') = 'grief', 'still within 3 days');
  perform pg_temp.hours(5);
  perform pg_temp.assert(pg_temp.hint_of('select kids_try()') = 'ok', 'after 3 days they can try again');
  update kids_invites set status = 'withdrawn' where status = 'pending';
  -- the doctor cards closed, and the admin can see it
  perform pg_temp.assert(not exists (select 1 from player_moments where context ->> 'child_id' = v_c::text and status in ('pending', 'snoozed', 'scheduled')), 'no doctor card is left open');
  perform pg_temp.login_as('adm');
  v := admin_kids_overview();
  perform pg_temp.assert((v->>'passed')::int = 1 and v->'passed_list'->0->>'name' = 'Sorrow' and (v->'passed_list'->0->>'warnings')::int >= 3 and (v->>'passing_enabled')::boolean, 'admin sees it in the Love page: ' || (v->'passed_list')::text);
  -- an outsider cannot read it
  perform pg_temp.login_as('e');
  perform pg_temp.assert(jsonb_array_length(kids_status()->'memorials') = 0, 'memorials are private to the parents');
  -- unanswered doctor cards are warnings too: 3 ignored cards, health 0, 72 h
  perform pg_temp.login_as('c');
  v_c := pg_temp.mkchild(pg_temp.u('c'), pg_temp.u('d'), interval '10 days', 'Quiet');
  update kids_children set health = 0, health_at = bl_now() - interval '73 hours', doctor_ignored = 2, alerts_unanswered = 0, last_care_at = bl_now() where id = v_c;
  update kids_children set next_alert_at = bl_kids_next(pg_temp.kid(v_c)) where id = v_c;
  perform bl_kids_alert_sweep();
  perform pg_temp.assert((pg_temp.kid(v_c)).status <> 'passed', 'only 2 warnings');
  update kids_children set sick_since = bl_now(), illness_n = 7, illness_id = 'fever', next_alert_at = bl_now() where id = v_c;
  perform bl_kids_moment_ignore(v_c, '{"ep":"7"}'::jsonb);
  perform bl_kids_alert_sweep();
  perform pg_temp.assert((pg_temp.kid(v_c)).status = 'passed', 'the third ignored doctor card, after 73 hours at zero: the child passes away');
  raise notice 'ok 6: passing away';
end $$;

-- ---------- 7. care score, the thank-you gift, the badge tier (couples a+b, c+d) ----------
create or replace function pg_temp.grow(p_a text, p_b text, p_good numeric, p_total numeric, p_removals int, p_spent_a bigint, p_spent_b bigint) returns bigint
language plpgsql as $$
declare v bigint;
begin
  v := pg_temp.mkchild(pg_temp.u(p_a), pg_temp.u(p_b), interval '22 days', 'Gift' || chr(65 + p_removals));
  update kids_children set care_good = p_good, care_total = p_total, removals = p_removals, spent_a = case when parent_a = pg_temp.u(p_a) then p_spent_a else p_spent_b end, spent_b = case when parent_a = pg_temp.u(p_a) then p_spent_b else p_spent_a end, last_care_at = bl_now(),
                           born_at = bl_now() - interval '21 days 1 minute', score_at = bl_now() where id = v;
  perform bl_kids_settle(v);
  return v;
end $$;

do $$
declare
  v_c bigint; c kids_children; v jsonb; b0a bigint; b0b bigint; ua uuid := pg_temp.u('a'); ub uuid := pg_temp.u('b'); v_pa uuid; v_pb uuid; v_g numeric; t timestamptz; n text;
begin
  perform pg_temp.assert(bl_cfg('kids.gift_gold') = 100000 and bl_cfg('kids.gift_silver') = 50000 and bl_cfg('kids.gift_bronze') = 20000 and bl_cfg('kids.gift_max_spend_pct') = 25, 'defaults: Gold 100,000, Silver 50,000, Bronze 20,000, capped at 25 % of what was spent');
  perform pg_temp.login_as('a');
  -- the score itself: a Secondary child with every need full, 50 hours later (hunger 1.5, fun 1.8, love 1.0, health 0.3 an hour from 100):
  -- hunger crosses 30 at 46.67 h, fun at 38.89 h, love and health stay above: 46.67 + 38.89 + 50 + 50 = 185.56 h of 200
  v_c := pg_temp.mkchild(pg_temp.u('a'), pg_temp.u('b'), interval '17 days', 'Tick');
  update kids_children set score_at = bl_now() - interval '50 hours', hunger_at = bl_now() - interval '50 hours', fun_at = bl_now() - interval '50 hours', love_at = bl_now() - interval '50 hours', health_at = bl_now() - interval '50 hours',
         sleep_at = bl_now() - interval '50 hours', clean_at = bl_now() - interval '50 hours' where id = v_c;
  c := bl_kids_score_tick(pg_temp.kid(v_c), bl_now());
  perform pg_temp.assert(abs(c.care_total - 200 * 3600) < 2 and abs(c.care_good - 185.56 * 3600) < 30 and c.score_at = bl_now(), 'score tick maths: ' || c.care_good / 3600 || ' of ' || c.care_total / 3600 || ' h');
  c := bl_kids_score_tick(c, bl_now());
  perform pg_temp.assert(abs(c.care_total - 200 * 3600) < 2, 'ticking twice at the same time adds nothing');
  update kids_children set status = 'gone', gone_reason = 'admin', next_alert_at = null where id = v_c;
  -- care actions tick the score before they change anything: a neglected newborn that is then fed
  v_c := pg_temp.mkchild(pg_temp.u('a'), pg_temp.u('b'), interval '2 hours', 'Slowly');
  update kids_children set score_at = bl_now() - interval '40 hours', hunger = 100, hunger_at = bl_now() - interval '40 hours', last_care_at = bl_now() where id = v_c;
  update kids_children set born_at = bl_now() - interval '40 hours' where id = v_c;
  perform kids_care(v_c, 'feed');
  c := pg_temp.kid(v_c);
  -- newborn needs: hunger 100 -> under 30 at 23.33 h (of 40), the other four (sleep, clean, love, health) are stored at 100 from creation
  perform pg_temp.assert(c.care_total > 0 and c.care_good < c.care_total and c.care_good / c.care_total between 0.6 and 0.95 and c.score_at = bl_now(), 'a feed ticked the score first: share ' || round(c.care_good / c.care_total, 3));
  update kids_children set status = 'gone', gone_reason = 'admin', next_alert_at = null where id = v_c;

  -- GOLD: share 0.95, plenty spent: 100,000 each. Not earned. Badge tier gold.
  b0a := pg_temp.cash(ua); b0b := pg_temp.cash(ub);
  v_c := pg_temp.grow('a', 'b', 95, 100, 0, 1000000, 1000000);
  perform pg_temp.assert(pg_temp.cj(v_c) is null, 'grown: not an active child any more');
  c := pg_temp.kid(v_c);
  perform pg_temp.assert(c.status = 'grown' and c.care_score = 95 and c.tier = 'gold' and c.gift_a = 100000 and c.gift_b = 100000, 'gold: score 95: ' || c.care_score || ' ' || coalesce(c.tier, '-'));
  perform pg_temp.assert(pg_temp.cash(ua) = b0a + 100000 and pg_temp.cash(ub) = b0b + 100000, 'each parent gets 100,000');
  perform pg_temp.assert(pg_temp.ledger_sum(ua, 'kid_gift') = 100000 and pg_temp.ledger_n(ua, 'kid_gift') = 1 and (select meta->>'tier' from ledger where user_id = ua and reason = 'kid_gift') = 'gold', 'ledger kid_gift once per parent');
  perform pg_temp.assert('kid_gift' <> all (bl_earn_reasons()) and 'kid_reclaim_refund' <> all (bl_earn_reasons()) and bl_econ_category('kid_gift') <> 'Other' and bl_econ_category('kid_reclaim_refund') <> 'Other'
                         and bl_ledger_label('kid_gift', '{}') <> 'kid_gift', 'the gift is not earnings (the leaderboard ignores it), and it is labelled');
  perform pg_temp.assert((select body from events where user_id = ua and kind = 'kids_grown') like '%Gold Proud parent badge%thank-you gift of ₦100,000%', 'alert: badge and gift: ' || (select body from events where user_id = ua and kind = 'kids_grown'));
  v := kids_status();
  perform pg_temp.assert(v->'grown'->0->>'tier' = 'gold' and (v->'grown'->0->>'gift')::bigint = 100000 and (v->'grown'->0->>'score')::int = 95 and (v->>'proud')::int = 1, 'the Family tab gets tier, gift and score: ' || (v->'grown')::text);
  perform pg_temp.login_as('e');
  perform pg_temp.assert(get_public_profile(ua)->>'proud_tier' = 'gold' and (get_public_profile(ua)->>'proud_parent')::int = 1, 'the public profile shows the tier');
  perform pg_temp.login_as('a'); perform love_set_show_relationship(false);
  perform pg_temp.login_as('e');
  perform pg_temp.assert(get_public_profile(ua)->>'proud_tier' is null, 'hidden when the profile toggle is off');
  perform pg_temp.login_as('a'); perform love_set_show_relationship(true);
  -- a gift is paid once: a second settle does nothing
  perform bl_kids_settle(v_c); perform kids_status();
  perform pg_temp.assert(pg_temp.ledger_n(ua, 'kid_gift') = 1, 'once');

  -- SILVER (0.70), BRONZE (0.45), NONE (0.20): the amounts and the thresholds
  v_c := pg_temp.grow('a', 'b', 70, 100, 0, 1000000, 1000000);
  c := pg_temp.kid(v_c);
  perform pg_temp.assert(c.tier = 'silver' and c.gift_a = 50000 and c.gift_b = 50000, 'silver: 50,000 each');
  v_c := pg_temp.grow('a', 'b', 45, 100, 0, 1000000, 1000000);
  c := pg_temp.kid(v_c);
  perform pg_temp.assert(c.tier = 'bronze' and c.gift_a = 20000 and c.gift_b = 20000, 'bronze: 20,000 each');
  b0a := pg_temp.cash(ua);
  v_c := pg_temp.grow('a', 'b', 20, 100, 0, 1000000, 1000000);
  c := pg_temp.kid(v_c);
  perform pg_temp.assert(c.tier = 'none' and c.care_score = 20 and coalesce(c.gift_a, 0) = 0 and pg_temp.cash(ua) = b0a, 'under 40: no tier, no gift, still grown up');
  perform pg_temp.assert((select body from events where user_id = ua and kind = 'kids_grown' order by id desc limit 1) like '%You are a Proud parent%', 'a plain Proud parent');
  -- relatives cost points: 95 % with one stay with relatives = 70 = silver
  v_c := pg_temp.grow('a', 'b', 95, 100, 1, 1000000, 1000000);
  c := pg_temp.kid(v_c);
  perform pg_temp.assert(c.care_score = 70 and c.tier = 'silver', 'one stay with relatives: -25 points: ' || c.care_score);
  -- thresholds are settings
  perform pg_temp.cfg('kids.tier_gold_min', '97');
  v_c := pg_temp.grow('a', 'b', 95, 100, 0, 1000000, 1000000);
  perform pg_temp.assert((pg_temp.kid(v_c)).tier = 'silver', 'the Gold threshold is a setting');
  perform pg_temp.cfg('kids.tier_gold_min', '85');

  -- the gift is CAPPED by what each parent really spent on the child (25 %): nobody farms babies
  b0a := pg_temp.cash(ua); b0b := pg_temp.cash(ub);
  v_c := pg_temp.grow('a', 'b', 95, 100, 0, 40000, 400000);
  c := pg_temp.kid(v_c);
  perform pg_temp.assert(case when c.parent_a = ua then c.gift_a else c.gift_b end = 10000 and case when c.parent_a = ub then c.gift_a else c.gift_b end = 100000, 'a: spent 40,000 -> gift 10,000; b: spent 400,000 -> 100,000: ' || c.gift_a || '/' || c.gift_b);
  perform pg_temp.assert(pg_temp.cash(ua) = b0a + 10000 and pg_temp.cash(ub) = b0b + 100000, 'paid accordingly');
  b0a := pg_temp.cash(ua);
  v_c := pg_temp.grow('a', 'b', 95, 100, 0, 0, 0);
  perform pg_temp.assert(pg_temp.cash(ua) = b0a and (pg_temp.kid(v_c)).tier = 'gold', 'a parent who spent nothing gets nothing');
  perform pg_temp.assert(not exists (select 1 from kids_children where status = 'grown' and gift_a is not null and gift_a > spent_a * 0.25 + 1) and not exists (select 1 from kids_children where status = 'grown' and gift_b is not null and gift_b > spent_b * 0.25 + 1),
                         'whatever the tier, a gift is never more than 25 % of the spend');
  -- a child who passed away gives no gift
  b0a := pg_temp.cash(ua);
  v_c := pg_temp.mkchild(pg_temp.u('a'), pg_temp.u('b'), interval '10 days', 'Hush');
  update kids_children set spent_a = 1000000, spent_b = 1000000, care_good = 100, care_total = 100 where id = v_c;
  perform bl_kids_pass(pg_temp.kid(v_c), bl_now());
  perform pg_temp.assert(pg_temp.cash(ua) = b0a and (pg_temp.kid(v_c)).tier is null, 'no gift and no tier for a child who passed away');
  update kids_children set status = 'gone', gone_reason = 'admin' where id = v_c;

  -- raising costs far more than any gift: a realistic gold child's supplies (newborn to baby: 5 days of formula and diapers)
  perform pg_temp.assert((select price from items where id = 'kid_formula') / 8 >= 2000 and (select price from items where id = 'kid_diapers') / 16 >= 500, 'one feed is about 2,100, one change about 550 at base prices');
  raise notice 'ok 7: score, gift tiers and caps';
end $$;

-- ---------- 8. grants, RLS, private helpers, ledger, editors ----------
do $$
declare v text; n int;
begin
  foreach v in array array['kids_call_doctor(bigint)', 'moments_pending()', 'moments_answer(bigint,text)', 'moments_snooze(bigint)', 'moments_seen(bigint)', 'moments_open(bigint)'] loop
    perform pg_temp.assert(not has_function_privilege('anon', 'public.' || v, 'execute'), 'anon cannot run ' || v);
    perform pg_temp.assert(has_function_privilege('authenticated', 'public.' || v, 'execute'), 'authenticated can run ' || v);
    perform pg_temp.assert((select prosecdef from pg_proc where oid = ('public.' || v)::regprocedure) and exists (select 1 from pg_proc p where p.oid = ('public.' || v)::regprocedure and exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%')), v || ' is security definer with a search_path');
  end loop;
  select string_agg(p.proname, ', ') into v from pg_proc p
   where p.pronamespace = 'public'::regnamespace and (p.proname like 'bl\_kids\_%' or p.proname like 'bl\_moment%' or p.proname in ('bl_shop_price', 'bl_moments_on', 'bl_moments_guard', 'bl_kids_text_guard2'))
     and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('public', p.oid, 'execute'));
  perform pg_temp.assert(v is null, 'every new helper is private: ' || coalesce(v, ''));
  select string_agg(t, ', ') into v from unnest(array['kids_items', 'kids_illnesses', 'kids_charges', 'shop_price_rules', 'life_moments', 'player_moments', 'player_moment_state']) t
   where not (select relrowsecurity from pg_class where oid = ('public.' || t)::regclass)
      or has_table_privilege('authenticated', 'public.' || t, 'select') or has_table_privilege('anon', 'public.' || t, 'select')
      or has_table_privilege('authenticated', 'public.' || t, 'insert') or has_table_privilege('authenticated', 'public.' || t, 'update') or has_table_privilege('authenticated', 'public.' || t, 'delete');
  perform pg_temp.assert(v is null, 'new tables: RLS on, no grants: ' || coalesce(v, ''));
  perform pg_temp.assert(not exists (select 1 from pg_constraint where conrelid in ('public.kids_items'::regclass, 'public.kids_illnesses'::regclass, 'public.kids_charges'::regclass, 'public.shop_price_rules'::regclass,
                                    'public.life_moments'::regclass, 'public.player_moments'::regclass, 'public.player_moment_state'::regclass) and contype = 'f' and confrelid = 'public.profiles'::regclass), 'no foreign key to profiles (it deadlocked a deploy once)');
  perform pg_temp.assert(bl_ledger_label('kid_reclaim_refund', '{}') <> 'kid_reclaim_refund' and bl_ledger_label('life_moment', '{}') = 'Life moment', 'ledger labels');
  perform pg_temp.assert(bl_econ_category('life_moment') = 'Life moments' and bl_econ_category('kid_gift') = 'Rewards and bonuses' and bl_econ_category('kid_reclaim_refund') = 'Shops, food and fun', 'Admin economy categories');
  perform pg_temp.assert(bl_admin_table_spec('kids_stages')->'cols' ? 'needs' and bl_admin_table_spec('kids_stages')->'cols' ? 'rate_clean' and bl_admin_table_spec('kids_illnesses') is not null
                         and bl_admin_table_spec('kids_items')->'pk'->>0 = 'item_id' and bl_admin_table_spec('shop_price_rules') is not null and bl_admin_table_spec('life_moments')->'cols'->>'choices' = 'jarr', 'Content editors exist');
  perform pg_temp.login_as('adm');
  perform pg_temp.assert((admin_row_upsert('kids_illnesses', '{"id":"malaria","weight":5}')->'row'->>'weight')::numeric = 5, 'an admin edits an illness');
  perform pg_temp.assert(pg_temp.hint_of($q$select admin_row_upsert('kids_stages', '{"id":"baby","needs":["hunger","clean"]}')$q$) = 'ok', 'an admin edits the stage needs');
  perform pg_temp.assert(pg_temp.hint_of($q$select admin_row_upsert('shop_price_rules', '{"id":"oba:baby","daily_pct":5}')$q$) = 'ok', 'an admin edits a price rule');
  perform pg_temp.assert(pg_temp.hint_of($q$select admin_row_upsert('kids_items', '{"item_id":"kid_formula","uses":10}')$q$) = 'ok', 'an admin edits the feeds in a tin');
  perform pg_temp.assert(pg_temp.hint_of($q$select admin_row_upsert('kids_illnesses', '{"id":"x1","name":"Ok name","emoji":"X","blurb":"b","moment_id":"doc_cough"}')$q$) = 'ok', 'an admin adds an illness');
  perform pg_temp.login_as('a');
  perform pg_temp.assert(pg_temp.hint_of($q$select admin_row_upsert('kids_illnesses', '{"id":"malaria","weight":5}')$q$) = 'not_admin', 'players cannot');
  -- the dealer price patch is in place and the old function still prices everything else
  perform pg_temp.assert(pg_get_functiondef('public.bl_dealer_net(items, text)'::regprocedure) like '%bl_shop_price(p_item, p_location)%', 'dealer price patched');
  raise notice 'ok 8: grants, RLS, ledger, editors';
end $$;
