-- R9 Benin Market, player-to-player trading (20261018000800_market.sql). Rolled back. Run (migration applied):
--   bash scripts/sql-test.sh -- supabase/tests/market_test.sql
-- Or with the migration first: bash scripts/sql-test.sh supabase/migrations/20261018000800_market.sql -- supabase/tests/market_test.sql
-- Groups: 1 grants / RLS / private helpers · 2 setup · 3 list an item (escrow, quote rolls back, not tradeable, price floor and
-- ceiling) · 4 buy (atomic money + item + fee + ledger + trade + alerts, not your own, gone) · 5 per-kind fee · 6 trust rule
-- (new account cannot sell, trusted sender can) · 7 offers (low / high refused, decline, accept, buyer broke, expiry, no offers) ·
-- 8 listing expiry and cancel return the thing · 9 cars keep plate and wear · 10 land (plot transfer, cost basis, open deal
-- refused) · 11 furniture (placed refused, house piece refused, transfer) · 12 private listing to a friend · 13 daily cap and
-- max open · 14 report + hide · 15 browse filters / sort · 16 admin remove + audit + overview + flags · 17 weekly earnings
-- exclude market · 18 switches · 19 two buyers, one wins (row lock) · 20 admin content spec.
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

create or replace function pg_temp.bank(p_uid uuid) returns bigint language sql as $$ select bank from profiles where id = p_uid $$;
create or replace function pg_temp.cash(p_uid uuid) returns bigint language sql as $$ select cash from profiles where id = p_uid $$;
create or replace function pg_temp.qty(p_uid uuid, p_item text) returns int language sql as
$$ select coalesce((select qty from inventory where user_id = p_uid and item_id = p_item), 0) $$;
create or replace function pg_temp.cfg(p_key text, p_val text) returns void
language sql as $$ update game_config set value = p_val::jsonb where key = p_key; $$;
create or replace function pg_temp.advance(p_seconds numeric) returns void
language plpgsql as $$
declare v numeric := coalesce(nullif(current_setting('bl.test_offset_seconds', true), '')::numeric, 0) + p_seconds;
begin
  perform set_config('bl.test_offset_seconds', v::text, true);
end $$;
create or replace function pg_temp.mk(p_name text, p_old boolean) returns uuid
language plpgsql as $$
declare v uuid := pg_temp.new_user(lower(p_name) || '@mk.bl');
begin
  perform pg_temp.login(v);
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform create_profile_v2(p_name, 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  update profiles set rent_owed = 0, busy_until = null, travel_to = null, protected_until = null,
         created_at = case when p_old then now() - interval '30 days' else bl_now() end, cash = 0, bank = 0
   where id = v;
  return v;
end $$;

-- ---------- 1. grants / RLS ----------
do $$
declare f text; v_n int;
begin
  foreach f in array array['market_info()', 'market_quote(text,text,int,text)', 'market_list(text,text,int,bigint,boolean,text,text)',
    'market_cancel(bigint)', 'market_browse(text,text,bigint,bigint,text,int,int)', 'market_mine()', 'market_buy(bigint,bigint)',
    'market_offer(bigint,bigint)', 'market_offer_respond(bigint,boolean)', 'market_offer_cancel(bigint)', 'market_report(bigint,text)',
    'admin_market_overview(int)', 'admin_market_remove(bigint,text)'] loop
    perform pg_temp.assert(not has_function_privilege('anon', 'public.' || f, 'execute'), 'anon cannot run ' || f);
    perform pg_temp.assert(has_function_privilege('authenticated', 'public.' || f, 'execute'), 'authenticated can run ' || f);
  end loop;
  foreach f in array array['bl_market_take(uuid,text,text,int,text)', 'bl_market_give(uuid,text,text,int,jsonb,bigint,boolean)',
    'bl_market_settle(bigint,uuid,bigint,text,bigint)', 'bl_market_release(bigint,text,text,uuid)', 'bl_market_sweep(int)',
    'bl_market_flags(uuid,uuid,bigint,bigint)', 'bl_market_seller_ok(profiles)', 'bl_market_guard(profiles)', 'bl_market_plate()',
    'bl_market_card(market_listings,uuid)', 'bl_market_num(text,numeric)', 'bl_market_on()', 'bl_market_cond(text,jsonb,int)'] loop
    perform pg_temp.assert(not has_function_privilege('anon', 'public.' || f, 'execute')
                           and not has_function_privilege('authenticated', 'public.' || f, 'execute'), 'private helper locked: ' || f);
  end loop;
  foreach f in array array['market_listings', 'market_offers', 'market_trades', 'market_reports', 'player_cars', 'market_settings'] loop
    perform pg_temp.assert((select relrowsecurity from pg_class where oid = ('public.' || f)::regclass), 'RLS on ' || f);
    perform pg_temp.assert(not has_table_privilege('anon', 'public.' || f, 'select'), 'anon cannot read ' || f);
    perform pg_temp.assert(not has_table_privilege('authenticated', 'public.' || f, 'insert')
                           and not has_table_privilege('authenticated', 'public.' || f, 'update')
                           and not has_table_privilege('authenticated', 'public.' || f, 'delete'), 'no client writes on ' || f);
  end loop;
  perform pg_temp.assert(not has_table_privilege('authenticated', 'public.market_trades', 'select')
                         and not has_table_privilege('authenticated', 'public.market_reports', 'select'), 'trades and reports are admin-only');
  select count(*) into v_n from pg_proc where pronamespace = 'public'::regnamespace and proname like 'market\_%' and prosecdef;
  perform pg_temp.assert(v_n >= 11, 'market RPCs are security definer');
  perform pg_temp.assert((select count(*) from market_settings) = 6 and (select bool_and(fee_pct = 5 and floor_pct = 20 and ceiling_pct = 300) from market_settings where kind not in ('business', 'company')),
                         'defaults: 5% fee, 20-300% band, four kinds (+ R10 businesses and Companies: 8%, 50-250%)');
  perform pg_temp.assert((select count(*) from market_settings where kind in ('business', 'company') and fee_pct = 8 and floor_pct = 50 and ceiling_pct = 250 and enabled) = 2,
                         'business and company kinds are on with the 8% fee and 50-250% band (the company listing flow itself is in companies_test group 11)');
  perform pg_temp.assert(not (select tradeable from items where id = 'soap') and not (select tradeable from items where id = 'airtime')
                         and (select tradeable from items where id = 'fish_catfish') and (select tradeable from items where id = 'laptop')
                         and (select tradeable from items where id = 'tokunbo_car'), 'tradeable defaults');
end $$;

-- ---------- 2. setup ----------
do $$
declare s uuid; b uuid; c uuid; n uuid; adm uuid;
begin
  s := pg_temp.mk('MkSeller', true); b := pg_temp.mk('MkBuyer', true); c := pg_temp.mk('MkThird', true);
  n := pg_temp.mk('MkNewbie', false); adm := pg_temp.mk('MkAdmin', true);
  update profiles set is_admin = true where id = adm;
  update profiles set bank = 50000000, cash = 100000 where id in (b, c);
  update profiles set bank = 10000, cash = 5000 where id in (s, n);
  perform set_config('mk.s', s::text, true); perform set_config('mk.b', b::text, true); perform set_config('mk.c', c::text, true);
  perform set_config('mk.n', n::text, true); perform set_config('mk.adm', adm::text, true);
  perform pg_temp.cfg('market.enabled', 'true');
  perform pg_temp.cfg('market.daily_listing_cap', '50');
  perform pg_temp.cfg('market.max_active', '50');
  perform pg_temp.cfg('market.expire_days', '7');
  perform pg_temp.cfg('market.offer_expire_hours', '24');
  perform pg_temp.cfg('market.report_hide_count', '3');
  perform pg_temp.cfg('market.private_enabled', 'true');
  update market_settings set enabled = true, fee_pct = 5, floor_pct = 20, ceiling_pct = 300;
  update items set price = 5500 where id = 'fish_catfish';
  update items set price = 2500000 where id = 'tokunbo_car';
  update furniture set price = 1250000, active = true, buyable = true, max_qty = 6, tradeable = true where id = 'tv_75';
  update furniture set price = 6500, active = true, buyable = true, max_qty = 6, tradeable = true where id = 'plastic_chair_red';
  perform pg_temp.login(s);
  perform bl_give_item(s, 'fish_catfish', 6);
  perform bl_give_item(s, 'soap', 2);
end $$;

-- ---------- 3. list an item ----------
do $$
declare s uuid := current_setting('mk.s')::uuid; q jsonb; r jsonb; v_id bigint;
begin
  perform pg_temp.login(s);
  q := market_quote('item', 'fish_catfish', 2);
  perform pg_temp.assert((q->>'ok')::boolean and (q->>'value')::bigint = 11000 and (q->>'min_price')::bigint = 2200 and (q->>'max_price')::bigint = 33000
                         and (q->>'fee_pct')::numeric = 5, 'quote: value 2 x 5,500, band 20-300%: ' || q::text);
  perform pg_temp.assert(pg_temp.qty(s, 'fish_catfish') = 6, 'a quote takes nothing (rolled back)');
  perform pg_temp.assert(not (market_quote('item', 'soap', 1)->>'ok')::boolean, 'quote says soap cannot be sold');
  perform pg_temp.assert(pg_temp.hint_of($q$ select market_list('item', 'soap', 1, 300) $q$) = 'not_tradeable', 'consumables are refused');
  perform pg_temp.assert(pg_temp.hint_of($q$ select market_list('item', 'airtime', 1, 500) $q$) = 'not_tradeable', 'phone credit refused');
  perform pg_temp.assert(pg_temp.hint_of($q$ select market_list('item', 'fish_catfish', 9, 50000) $q$) = 'not_owned', 'cannot list more than you own');
  perform pg_temp.assert(pg_temp.hint_of($q$ select market_list('item', 'fish_catfish', 2, 2199) $q$) = 'price_range', 'below the floor refused');
  perform pg_temp.assert(pg_temp.hint_of($q$ select market_list('item', 'fish_catfish', 2, 33001) $q$) = 'price_range', 'above the ceiling refused');
  perform pg_temp.assert(pg_temp.hint_of($q$ select market_list('item', 'fish_catfish', 2, 0) $q$) = 'bad_price', 'zero price refused');
  perform pg_temp.assert(pg_temp.qty(s, 'fish_catfish') = 6, 'refused listings take nothing');
  perform pg_temp.assert(pg_temp.hint_of($q$ select market_list('boat', 'x', 1, 5000) $q$) = 'bad_kind', 'unknown kind refused');
  r := market_list('item', 'fish_catfish', 2, 11000, true);
  v_id := (r->'listing'->>'id')::bigint;
  perform set_config('mk.l1', v_id::text, true);
  perform pg_temp.assert(pg_temp.qty(s, 'fish_catfish') = 4, 'listing LOCKS the fish: 2 left the bag');
  perform pg_temp.assert((select status = 'active' and qty = 2 and price = 11000 and open_to_offers and seller_id = s from market_listings where id = v_id), 'listing row');
  perform pg_temp.assert((r->'listing'->>'cond') = '×2' and r->'listing'->>'seller' = 'MkSeller', 'card shows seller and condition');
  -- a second listing from the same stack is fine, and cancelling it gives it all back
  r := market_list('item', 'fish_catfish', 4, 12000, false, null, null);
  perform pg_temp.assert(pg_temp.qty(s, 'fish_catfish') = 0, 'all the rest locked');
  perform market_cancel((r->'listing'->>'id')::bigint);
  perform pg_temp.assert(pg_temp.qty(s, 'fish_catfish') = 4, 'cancel gives them back');
end $$;

-- ---------- 4. buy ----------
do $$
declare s uuid := current_setting('mk.s')::uuid; b uuid := current_setting('mk.b')::uuid; v_id bigint := current_setting('mk.l1')::bigint;
  r jsonb; v_sb bigint; v_bb bigint; v_bc bigint; n int;
begin
  perform pg_temp.login(s);
  perform pg_temp.assert(pg_temp.hint_of(format('select market_buy(%s)', v_id)) = 'own_listing', 'you cannot buy your own listing');
  perform pg_temp.assert(pg_temp.hint_of(format('select market_offer(%s, 9000)', v_id)) = 'own_listing', 'nor offer on it');
  perform pg_temp.login(b);
  perform pg_temp.assert(not exists (select 1 from jsonb_array_elements(market_browse()->'rows') x where (x->>'id')::bigint = 0), 'browse works');
  perform pg_temp.assert(pg_temp.hint_of(format('select market_buy(%s, 999)', v_id)) = 'price_changed', 'expected price must match');
  v_sb := pg_temp.bank(s); v_bb := pg_temp.bank(b); v_bc := pg_temp.cash(b);
  r := market_buy(v_id, 11000);
  perform pg_temp.assert((r->>'price')::bigint = 11000 and (r->>'fee')::bigint = 550 and (r->>'net')::bigint = 10450, 'sale numbers: ' || r::text);
  perform pg_temp.assert(pg_temp.bank(b) = v_bb - 11000 and pg_temp.cash(b) = v_bc, 'buyer pays from the bank first');
  perform pg_temp.assert(pg_temp.bank(s) = v_sb + 11000 - 550, 'seller gets price minus the 5% fee in the bank');
  perform pg_temp.assert(pg_temp.qty(b, 'fish_catfish') = 2, 'the fish moved to the buyer');
  perform pg_temp.assert((select status = 'sold' and buyer_id = b and sold_price = 11000 and fee = 550 from market_listings where id = v_id), 'listing sold');
  perform pg_temp.assert((select count(*) from ledger where user_id = b and reason = 'market_buy' and delta = -11000) = 1, 'ledger market_buy');
  perform pg_temp.assert((select count(*) from ledger where user_id = s and reason = 'market_sale' and delta = 11000) = 1, 'ledger market_sale');
  perform pg_temp.assert((select count(*) from ledger where user_id = s and reason = 'market_fee' and delta = -550) = 1, 'ledger market_fee');
  perform pg_temp.assert(bl_ledger_label('market_sale', '{"title":"Catfish"}') = 'Market sale: Catfish' and bl_ledger_label('market_fee', '{}') = 'Market fee'
                         and bl_ledger_label('market_buy', '{"title":"Catfish"}') = 'Market buy: Catfish', 'ledger labels');
  perform pg_temp.assert((select count(*) from market_trades where listing_id = v_id and price = 11000 and fee = 550 and value = 11000 and via = 'buy') = 1, 'trade logged');
  perform pg_temp.assert((select count(*) from events where user_id = s and kind = 'market_sold' and not (data->>'quiet')::boolean) = 1, 'seller gets an alert (toast)');
  -- bank short: the cash covers the rest, and a broke buyer is refused with nothing moved
  perform pg_temp.login(s);
  update profiles set bank = 3000, cash = 1000 where id = b;
  perform pg_temp.login(b);
  perform pg_temp.login(s);
  r := market_list('item', 'fish_catfish', 1, 5500);
  perform pg_temp.login(b);
  v_bb := pg_temp.bank(b);
  perform pg_temp.assert(pg_temp.hint_of(format('select market_buy(%s)', (r->'listing'->>'id')::bigint)) = 'not_enough_cash', 'broke buyer refused');
  perform pg_temp.assert(pg_temp.bank(b) = v_bb and pg_temp.qty(b, 'fish_catfish') = 2 and (select status from market_listings where id = (r->'listing'->>'id')::bigint) = 'active',
                         'a refused buy changes nothing');
  update profiles set bank = 2000, cash = 4000 where id = b;
  perform market_buy((r->'listing'->>'id')::bigint);
  perform pg_temp.assert(pg_temp.bank(b) = 0 and pg_temp.cash(b) = 500, 'bank drained first, cash pays the rest');
  perform pg_temp.assert((select count(*) from ledger where user_id = b and reason = 'market_buy' and account = 'cash' and delta = -3500) = 1, 'second ledger row from cash');
  update profiles set bank = 50000000, cash = 100000 where id = b;
  -- sold already
  perform pg_temp.login(current_setting('mk.c')::uuid);
  perform pg_temp.assert(pg_temp.hint_of(format('select market_buy(%s)', v_id)) = 'gone', 'a sold listing is gone');
  perform pg_temp.assert(pg_temp.hint_of('select market_buy(99999999)') = 'gone', 'unknown listing is gone');
end $$;

-- ---------- 5. per-kind fee ----------
do $$
declare s uuid := current_setting('mk.s')::uuid; b uuid := current_setting('mk.b')::uuid; r jsonb; v_sb bigint;
begin
  update market_settings set fee_pct = 10 where kind = 'item';
  perform pg_temp.login(s);
  r := market_list('item', 'fish_catfish', 1, 6000);
  perform pg_temp.login(b);
  v_sb := pg_temp.bank(s);
  r := market_buy((r->'listing'->>'id')::bigint);
  perform pg_temp.assert((r->>'fee')::bigint = 600 and pg_temp.bank(s) = v_sb + 5400, 'fee follows the kind setting (10%)');
  update market_settings set fee_pct = 0 where kind = 'item';
  perform pg_temp.login(s);
  r := market_list('item', 'fish_catfish', 1, 6000);
  perform pg_temp.login(b);
  v_sb := pg_temp.bank(s);
  r := market_buy((r->'listing'->>'id')::bigint);
  perform pg_temp.assert((r->>'fee')::bigint = 0 and pg_temp.bank(s) = v_sb + 6000, 'zero fee works, no market_fee row');
  update market_settings set fee_pct = 5 where kind = 'item';
  update market_settings set floor_pct = 50, ceiling_pct = 150 where kind = 'item';
  perform pg_temp.login(s);
  perform pg_temp.assert(pg_temp.hint_of($q$ select market_list('item', 'fish_catfish', 1, 2700) $q$) = 'price_range', 'admin band: floor 50% refuses 2,700');
  perform pg_temp.assert(pg_temp.hint_of($q$ select market_list('item', 'fish_catfish', 1, 8300) $q$) = 'price_range', 'admin band: ceiling 150% refuses 8,300');
  update market_settings set floor_pct = 20, ceiling_pct = 300 where kind = 'item';
end $$;

-- ---------- 6. trust rule ----------
do $$
declare n uuid := current_setting('mk.n')::uuid; s uuid := current_setting('mk.s')::uuid; adm uuid := current_setting('mk.adm')::uuid; r jsonb;
begin
  perform bl_give_item(current_setting('mk.s')::uuid, 'fish_catfish', 10);
  perform pg_temp.login(n);
  perform bl_give_item(n, 'fish_catfish', 1);
  perform pg_temp.assert(pg_temp.hint_of($q$ select market_list('item', 'fish_catfish', 1, 5500) $q$) = 'new_account', 'new account cannot SELL');
  perform pg_temp.assert(pg_temp.qty(n, 'fish_catfish') = 1, 'refused: nothing escrowed');
  perform pg_temp.assert(not (market_info()->>'can_sell')::boolean and (market_info()->>'sell_wait_seconds')::int > 0, 'market_info shows the wait');
  -- but a new account may BUY
  perform pg_temp.login(s);
  r := market_list('item', 'fish_catfish', 1, 5500);
  perform pg_temp.login(n);
  update profiles set bank = 1000000 where id = n;
  perform market_buy((r->'listing'->>'id')::bigint);
  perform pg_temp.assert(pg_temp.qty(n, 'fish_catfish') = 2, 'a new account can buy');
  -- an admin-trusted sender is exempt
  perform pg_temp.login(adm);
  perform admin_set_transfer_trusted(n, true);
  perform pg_temp.login(n);
  perform pg_temp.assert((market_info()->>'can_sell')::boolean, 'trusted sender can sell');
  r := market_list('item', 'fish_catfish', 1, 5500);
  perform pg_temp.assert((r->'listing'->>'id')::bigint > 0, 'trusted new account listed');
  perform market_cancel((r->'listing'->>'id')::bigint);
  perform pg_temp.assert(pg_temp.qty(n, 'fish_catfish') = 2, 'cancel returned it');
  perform pg_temp.login(adm);
  perform admin_set_transfer_trusted(n, false);
  -- the wait setting is the same one as transfers: 0 = no wait
  perform pg_temp.cfg('bank.transfer_min_account_real_minutes', '0');
  perform pg_temp.login(n);
  r := market_list('item', 'fish_catfish', 1, 5500);
  perform market_cancel((r->'listing'->>'id')::bigint);
  perform pg_temp.cfg('bank.transfer_min_account_real_minutes', '1440');
end $$;

-- ---------- 7. offers ----------
do $$
declare s uuid := current_setting('mk.s')::uuid; b uuid := current_setting('mk.b')::uuid; c uuid := current_setting('mk.c')::uuid;
  r jsonb; v_l bigint; v_o bigint; v_sb bigint; v_o2 bigint; v_closed bigint;
begin
  perform bl_give_item(current_setting('mk.s')::uuid, 'fish_catfish', 10);
  perform pg_temp.login(s);
  r := market_list('item', 'fish_catfish', 1, 5500, false);   -- not open to offers
  v_closed := (r->'listing'->>'id')::bigint;
  r := market_list('item', 'fish_catfish', 2, 11000, true);
  v_l := (r->'listing'->>'id')::bigint;
  perform pg_temp.login(b);
  perform pg_temp.assert(pg_temp.hint_of(format('select market_offer(%s, 5000)', v_closed)) = 'no_offers', 'closed listing takes no offers');
  perform pg_temp.assert(pg_temp.hint_of(format('select market_offer(%s, 11000)', v_l)) = 'bad_offer', 'an offer must be below the price');
  perform pg_temp.assert(pg_temp.hint_of(format('select market_offer(%s, 5000)', v_l)) = 'bad_offer', 'an offer under 50% is refused');
  perform pg_temp.assert(pg_temp.hint_of(format('select market_offer(%s, 999999999)', v_l)) = 'bad_offer', 'huge offers are not offers');
  r := market_offer(v_l, 8000);
  v_o := (r->>'offer')::bigint;
  perform pg_temp.assert((select status = 'pending' and amount = 8000 from market_offers where id = v_o), 'offer saved');
  perform pg_temp.assert((select count(*) from events where user_id = s and kind = 'market_offer' and title = '@MkBuyer wants your Catfish ×2 for ₦8,000') = 1,
                         'seller alert reads "@x wants your item for ₦y"');
  perform pg_temp.assert((market_mine()->'offers_out'->0->>'amount')::bigint = 8000, 'buyer sees it under My offers');
  -- a new offer replaces the old one (one pending per buyer)
  r := market_offer(v_l, 9000);
  perform pg_temp.assert((r->>'offer')::bigint = v_o and (select amount from market_offers where id = v_o) = 9000
                         and (select count(*) from market_offers where listing_id = v_l and status = 'pending') = 1, 'raising an offer replaces it');
  -- decline
  perform pg_temp.login(c);
  perform pg_temp.assert(pg_temp.hint_of(format('select market_offer_respond(%s, true)', v_o)) = 'not_yours', 'only the seller answers');
  perform pg_temp.login(s);
  perform pg_temp.assert((market_mine()->'offers_in'->0->>'buyer') = 'MkBuyer', 'seller sees the offer in My listings');
  r := market_offer_respond(v_o, false);
  perform pg_temp.assert(not (r->>'accepted')::boolean and (select status from market_offers where id = v_o) = 'declined', 'declined');
  perform pg_temp.assert((select count(*) from events where user_id = b and kind = 'market_offer_declined') = 1, 'buyer told');
  perform pg_temp.assert(pg_temp.hint_of(format('select market_offer_respond(%s, true)', v_o)) = 'gone', 'a declined offer cannot be accepted');
  -- accept: sale at the OFFER price, fee on that
  perform pg_temp.login(b);
  r := market_offer(v_l, 9500);
  v_o := (r->>'offer')::bigint;
  perform pg_temp.login(s);
  v_sb := pg_temp.bank(s);
  r := market_offer_respond(v_o, true);
  perform pg_temp.assert((r->>'accepted')::boolean and (r->>'price')::bigint = 9500 and (r->>'fee')::bigint = 475, 'accepted at 9,500: ' || r::text);
  perform pg_temp.assert(pg_temp.bank(s) = v_sb + 9500 - 475, 'seller paid the offer minus fee');
  perform pg_temp.assert((select status from market_listings where id = v_l) = 'sold' and (select via from market_trades where listing_id = v_l) = 'offer', 'sold via offer');
  perform pg_temp.assert((select count(*) from events where user_id = b and kind = 'market_offer_accepted') = 1, 'buyer told it was accepted');
  -- buyer short of money at accept time: offer cancelled, listing stays open
  r := market_list('item', 'fish_catfish', 1, 5500, true);
  v_l := (r->'listing'->>'id')::bigint;
  perform pg_temp.login(b);
  r := market_offer(v_l, 4000);
  v_o := (r->>'offer')::bigint;
  update profiles set bank = 100, cash = 100 where id = b;
  perform pg_temp.login(s);
  r := market_offer_respond(v_o, true);
  perform pg_temp.assert(not (r->>'accepted')::boolean and (r->>'failed')::boolean, 'accept fails when the buyer no longer has the money');
  perform pg_temp.assert((select status from market_offers where id = v_o) = 'cancelled' and (select status from market_listings where id = v_l) = 'active', 'offer cancelled, listing open');
  update profiles set bank = 50000000, cash = 100000 where id = b;
  -- offers expire
  perform pg_temp.login(b);
  r := market_offer(v_l, 4500);
  v_o := (r->>'offer')::bigint;
  perform pg_temp.advance(25 * 3600);
  perform pg_temp.login(s);
  perform pg_temp.assert(pg_temp.hint_of(format('select market_offer_respond(%s, true)', v_o)) = 'gone', 'an expired offer cannot be accepted');
  perform market_info();   -- (an RPC that raises rolls its own sweep back; the next call does it)
  perform pg_temp.assert((select status from market_offers where id = v_o) = 'expired', 'offer marked expired');
  -- a buyer cannot offer more than they hold at offer time
  perform pg_temp.login(b);
  update profiles set bank = 100, cash = 100 where id = b;
  perform pg_temp.assert(pg_temp.hint_of(format('select market_offer(%s, 4000)', v_l)) = 'not_enough_cash', 'cannot offer money you do not have');
  update profiles set bank = 50000000, cash = 100000 where id = b;
  -- withdraw
  r := market_offer(v_l, 4100);
  v_o2 := (r->>'offer')::bigint;
  perform market_offer_cancel(v_o2);
  perform pg_temp.assert((select status from market_offers where id = v_o2) = 'cancelled', 'buyer withdrew');
  perform pg_temp.assert(pg_temp.hint_of(format('select market_offer_cancel(%s)', v_o2)) = 'gone', 'withdraw twice refused');
  -- other offers are closed when the listing sells
  r := market_offer(v_l, 4200);
  perform pg_temp.login(c);
  r := market_offer(v_l, 4300);
  perform pg_temp.login(b);
  perform market_buy(v_l);
  perform pg_temp.assert((select count(*) from market_offers where listing_id = v_l and status = 'pending') = 0, 'a sale closes the open offers');
end $$;

-- ---------- 8. expiry + cancel return the thing ----------
do $$
declare s uuid := current_setting('mk.s')::uuid; b uuid := current_setting('mk.b')::uuid; r jsonb; v_l bigint; v_o bigint; v_have int;
begin
  perform bl_give_item(current_setting('mk.s')::uuid, 'fish_catfish', 10);
  perform pg_temp.login(s);
  perform pg_temp.cfg('market.expire_days', '3');
  v_have := pg_temp.qty(s, 'fish_catfish');
  r := market_list('item', 'fish_catfish', 2, 11000, true);
  v_l := (r->'listing'->>'id')::bigint;
  perform pg_temp.assert(pg_temp.qty(s, 'fish_catfish') = v_have - 2, 'locked while listed');
  perform pg_temp.assert((select expires_at from market_listings where id = v_l) between bl_now() + interval '2 days 23 hours' and bl_now() + interval '3 days 1 hour', 'expires in N days');
  perform pg_temp.login(b);
  v_o := (market_offer(v_l, 9000)->>'offer')::bigint;
  perform pg_temp.advance(4 * 86400);
  -- anyone opening the market returns it (lazy sweep)
  perform pg_temp.login(b);
  perform pg_temp.assert(pg_temp.hint_of(format('select market_buy(%s)', v_l)) = 'gone', 'expired listing cannot be bought');
  perform market_info();
  perform pg_temp.assert((select status from market_listings where id = v_l) = 'expired', 'listing expired');
  perform pg_temp.assert(pg_temp.qty(s, 'fish_catfish') = v_have, 'the item came back to the seller');
  perform pg_temp.assert((select status from market_offers where id = v_o) = 'expired', 'its offer expired too');
  perform pg_temp.assert((select count(*) from events where user_id = s and kind = 'market_expired') >= 1, 'seller told');
  perform pg_temp.cfg('market.expire_days', '7');
  -- seller cancels
  perform pg_temp.login(s);
  r := market_list('item', 'fish_catfish', 3, 12000);
  v_l := (r->'listing'->>'id')::bigint;
  perform pg_temp.login(b);
  perform pg_temp.assert(pg_temp.hint_of(format('select market_cancel(%s)', v_l)) = 'gone', 'only the seller can cancel');
  perform pg_temp.login(s);
  perform market_cancel(v_l);
  perform pg_temp.assert(pg_temp.qty(s, 'fish_catfish') = v_have and (select status from market_listings where id = v_l) = 'cancelled', 'cancel returns the item');
  perform pg_temp.assert(pg_temp.hint_of(format('select market_cancel(%s)', v_l)) = 'gone', 'cancel twice refused');
end $$;

-- ---------- 9. cars keep plate and wear ----------
do $$
declare s uuid := current_setting('mk.s')::uuid; b uuid := current_setting('mk.b')::uuid; r jsonb; v_l bigint; v_plate text; q jsonb;
begin
  perform pg_temp.login(s);
  perform bl_give_item(s, 'tokunbo_car', 1);
  insert into hustle_players (user_id, car_wear) values (s, 40) on conflict (user_id) do update set car_wear = 40;
  q := market_quote('car', 'tokunbo_car', 1);
  perform pg_temp.assert((q->>'ok')::boolean and (q->'detail'->>'wear')::numeric = 40 and q->'detail'->>'plate' like 'BEN-___-__', 'quote shows plate and wear: ' || q::text);
  perform pg_temp.assert(pg_temp.qty(s, 'tokunbo_car') = 1, 'quote takes nothing');
  perform pg_temp.assert(pg_temp.hint_of($q$ select market_list('car', 'tokunbo_car', 2, 2500000) $q$) = 'bad_amount', 'one car at a time');
  perform pg_temp.assert(pg_temp.hint_of($q$ select market_list('car', 'lambo_urus', 1, 450000000) $q$) = 'not_owned', 'cannot list a car you do not own');
  perform pg_temp.assert(pg_temp.hint_of($q$ select market_list('car', 'tokunbo_car', 1, 400000) $q$) = 'price_range', 'car price floor (20% of 2.5M = 500,000)');
  r := market_list('car', 'tokunbo_car', 1, 2400000, true);
  v_l := (r->'listing'->>'id')::bigint;
  v_plate := r->'listing'->'detail'->>'plate';
  perform pg_temp.assert(pg_temp.qty(s, 'tokunbo_car') = 0, 'the car is locked: it left the garage');
  perform pg_temp.assert((select car_wear from hustle_players where user_id = s) = 0, 'seller no longer carries the wear');
  perform pg_temp.assert(r->'listing'->>'cond' = 'Plate ' || v_plate || ' · wear 40%', 'card condition text');
  perform pg_temp.assert(pg_temp.hint_of(format('select market_list(%L, %L, 1, 2400000)', 'car', 'tokunbo_car')) = 'not_owned', 'cannot list it twice');
  perform pg_temp.login(b);
  r := market_buy(v_l);
  perform pg_temp.assert(pg_temp.qty(b, 'tokunbo_car') = 1, 'buyer has the car');
  perform pg_temp.assert((select plate = v_plate and wear = 40 from player_cars where user_id = b and item_id = 'tokunbo_car'), 'plate and wear travelled with the car');
  perform pg_temp.assert((select car_wear from hustle_players where user_id = b) = 40, 'the buyer drives it with 40% wear');
  perform pg_temp.assert(r->'receipt'->>'kind' = 'market', 'a big purchase issues a receipt');
  -- and it can be re-listed with the same plate
  r := market_list('car', 'tokunbo_car', 1, 2500000);
  perform pg_temp.assert(r->'listing'->'detail'->>'plate' = v_plate and (r->'listing'->'detail'->>'wear')::numeric = 40, 're-listed with the same plate and wear');
  perform market_cancel((r->'listing'->>'id')::bigint);
  perform pg_temp.assert((select count(*) from player_cars where plate = v_plate) = 1 and pg_temp.qty(b, 'tokunbo_car') = 1, 'cancel brings the plate back');
  -- busy / on the road sellers cannot list
  update profiles set busy_until = bl_now() + interval '1 hour', busy_label = 'work' where id = b;
  perform pg_temp.assert(pg_temp.hint_of($q$ select market_list('car', 'tokunbo_car', 1, 2500000) $q$) = 'busy', 'busy seller refused');
  update profiles set busy_until = null where id = b;
end $$;

-- ---------- 10. land ----------
do $$
declare s uuid := current_setting('mk.s')::uuid; b uuid := current_setting('mk.b')::uuid; r jsonb; v_l bigint; v_cost bigint; v_pp bigint; v_deal jsonb; p invest_positions;
begin
  perform pg_temp.login(s);
  update profiles set bank = 900000000, cash = 0 where id = s;
  perform pg_temp.cfg('invest.enabled', 'true');
  perform set_config('bl.test_rand', '0.9999', true);
  r := invest_land_buy('land_ugbowo', 4);
  select * into p from invest_positions where user_id = s and ref_id = 'land_ugbowo';
  v_cost := p.cost;
  v_pp := bl_inv_price('land_ugbowo')::bigint;
  perform pg_temp.assert(p.qty = 4, 'seller holds 4 plots');
  -- a deal still waiting on a levy blocks the sale
  perform set_config('bl.test_rand', '0.0001', true);
  v_deal := invest_land_buy('land_sapele', 1);
  perform pg_temp.assert(v_deal->>'status' = 'levy', 'a levy deal is open');
  perform pg_temp.assert(pg_temp.hint_of($q$ select market_list('land', 'land_ugbowo', 1, 100000000) $q$) = 'land_pending', 'pending agent / levy state must be finished first');
  perform invest_land_levy((v_deal->>'deal_id')::bigint, false);
  perform set_config('bl.test_rand', '0.9999', true);
  perform pg_temp.assert(pg_temp.hint_of($q$ select market_list('land', 'land_ugbowo', 9, 100000000) $q$) = 'not_owned', 'cannot list more plots than you hold');
  perform pg_temp.assert(pg_temp.hint_of($q$ select market_list('land', 'land_gra', 1, 100000000) $q$) = 'not_owned', 'nor plots you do not hold');
  perform pg_temp.assert(pg_temp.hint_of(format('select market_list(%L, %L, 1, %s)', 'land', 'land_ugbowo', v_pp * 4)) = 'price_range', 'ceiling is 300% of one plot');
  r := market_list('land', 'land_ugbowo', 2, v_pp * 2, true);
  v_l := (r->'listing'->>'id')::bigint;
  select * into p from invest_positions where user_id = s and ref_id = 'land_ugbowo';
  perform pg_temp.assert(p.qty = 2 and p.cost = v_cost - floor(v_cost * 2 / 4.0)::bigint, 'two plots locked, cost basis split: ' || p.qty || '/' || p.cost);
  perform pg_temp.assert(r->'listing'->>'cond' = '2 plots', 'card says 2 plots');
  perform pg_temp.login(b);
  update profiles set bank = 900000000 where id = b;
  r := market_buy(v_l);
  select * into p from invest_positions where user_id = b and ref_id = 'land_ugbowo';
  perform pg_temp.assert(p.qty = 2 and p.cost = v_pp * 2 and p.kind = 'land', 'plots transferred; buyer cost basis = price paid');
  perform pg_temp.assert((select qty from invest_positions where user_id = s and ref_id = 'land_ugbowo') = 2, 'seller keeps the other 2');
  -- selling the whole position and getting it back by cancel restores the cost basis
  perform pg_temp.login(s);
  select cost into v_cost from invest_positions where user_id = s and ref_id = 'land_ugbowo';
  r := market_list('land', 'land_ugbowo', 2, v_pp * 2);
  perform pg_temp.assert(not exists (select 1 from invest_positions where user_id = s and ref_id = 'land_ugbowo'), 'whole position locked');
  perform market_cancel((r->'listing'->>'id')::bigint);
  perform pg_temp.assert((select qty = 2 and cost = v_cost from invest_positions where user_id = s and ref_id = 'land_ugbowo'), 'cancel restores plots and cost basis');
  -- the buyer (who already holds plots) adds to the same position
  perform pg_temp.login(s);
  r := market_list('land', 'land_ugbowo', 1, v_pp);
  perform pg_temp.login(b);
  perform market_buy((r->'listing'->>'id')::bigint);
  perform pg_temp.assert((select qty = 3 and cost = v_pp * 3 from invest_positions where user_id = b and ref_id = 'land_ugbowo'), 'buyer position grows');
  perform set_config('bl.test_rand', '', true);
end $$;

-- ---------- 11. furniture ----------
do $$
declare s uuid := current_setting('mk.s')::uuid; b uuid := current_setting('mk.b')::uuid; r jsonb; v_l bigint; v_starter text; v_q int; v_qb int;
begin
  perform pg_temp.login(s);
  update profiles set cash = 5000000, bank = 0 where id = s;
  perform furniture_buy('tv_75');
  perform furniture_buy('plastic_chair_red');
  perform furniture_buy('plastic_chair_red');
  -- placed pieces must be picked up first
  update player_house_furniture set stored = false, x = 2.0, z = 2.0 where owner_id = s and furniture_key = 'own_tv_75';
  perform pg_temp.assert(pg_temp.hint_of($q$ select market_list('furniture', 'tv_75', 1, 1250000) $q$) = 'placed', 'a placed TV is refused');
  perform pg_temp.assert(not (market_quote('furniture', 'tv_75', 1)->>'ok')::boolean and market_quote('furniture', 'tv_75', 1)->>'hint' = 'placed', 'quote explains why');
  update player_house_furniture set stored = true, x = 0, z = 0 where owner_id = s and furniture_key = 'own_tv_75';
  -- a piece that came with the house is not for sale
  select pf.furniture_id into v_starter from player_furniture pf where pf.user_id = s and pf.house_qty = pf.qty limit 1;
  perform pg_temp.assert(v_starter is not null, 'the seller has a came-with-house piece');
  if v_starter is not null then
    perform pg_temp.assert(pg_temp.hint_of(format('select market_list(%L, %L, 1, 100000)', 'furniture', v_starter)) in ('house_piece', 'not_tradeable'),
                           'house piece refused: ' || v_starter || ' ' || pg_temp.hint_of(format('select market_list(%L, %L, 1, 100000)', 'furniture', v_starter)));
  end if;
  update furniture set tradeable = false where id = 'plastic_chair_red';
  perform pg_temp.assert(pg_temp.hint_of($q$ select market_list('furniture', 'plastic_chair_red', 1, 6500) $q$) = 'not_tradeable', 'admin-flagged furniture refused');
  update furniture set tradeable = true where id = 'plastic_chair_red';
  -- list one of two chairs by key (copy 2 placed, copy 1 free -> pick copy 1)
  update player_house_furniture set stored = false, x = 3.0, z = 3.0 where owner_id = s and furniture_key = 'own_plastic_chair_red-2';
  perform pg_temp.assert(pg_temp.hint_of(format('select market_list(%L, %L, 1, 6500, false, null, %L)', 'furniture', 'plastic_chair_red', 'own_plastic_chair_red-2')) = 'placed',
                         'that copy is placed');
  select qty into v_q from player_furniture where user_id = s and furniture_id = 'plastic_chair_red';
  r := market_list('furniture', 'plastic_chair_red', 1, 6500);
  perform pg_temp.assert((select qty from player_furniture where user_id = s and furniture_id = 'plastic_chair_red') = v_q - 1, 'one chair locked');
  perform pg_temp.assert((select stored from player_house_furniture where owner_id = s and furniture_key = 'own_plastic_chair_red-2') is not null
                         or (select qty from player_furniture where user_id = s and furniture_id = 'plastic_chair_red') = 1, 'placed chair keeps its place after the renumbering');
  perform pg_temp.assert((select not stored from player_house_furniture where owner_id = s and furniture_key = 'own_plastic_chair_red'
                          and x = 3.0 and z = 3.0), 'the placed copy kept its spot (took the freed key)');
  perform market_cancel((r->'listing'->>'id')::bigint);
  update player_house_furniture set stored = true where owner_id = s;
  -- sell the TV
  r := market_list('furniture', 'tv_75', 1, 1250000);
  v_l := (r->'listing'->>'id')::bigint;
  perform pg_temp.assert(not exists (select 1 from player_furniture where user_id = s and furniture_id = 'tv_75'), 'the TV left the house');
  perform pg_temp.assert(not exists (select 1 from player_house_furniture where owner_id = s and furniture_key = 'own_tv_75'), 'and its placement row');
  perform pg_temp.login(b);
  select coalesce((select qty from player_furniture where user_id = b and furniture_id = 'tv_75'), 0) into v_qb;
  r := market_buy(v_l);
  perform pg_temp.assert((select qty from player_furniture where user_id = b and furniture_id = 'tv_75') = v_qb + 1, 'buyer owns the TV');
  perform pg_temp.assert((select stored from player_house_furniture where owner_id = b and furniture_key = 'own_tv_75'), 'it arrives stored (in My items)');
  -- buyer at max copies is refused (nothing moves)
  update furniture set max_qty = 1 where id = 'tv_75';
  perform pg_temp.login(s);
  perform furniture_buy('plastic_chair_red');   -- (any purchase; the TV is out of s's house)
  update furniture set max_qty = 6 where id = 'tv_75';
end $$;

-- ---------- 12. private listing to a friend ----------
do $$
declare s uuid := current_setting('mk.s')::uuid; b uuid := current_setting('mk.b')::uuid; c uuid := current_setting('mk.c')::uuid; r jsonb; v_l bigint;
begin
  perform pg_temp.login(s);
  perform bl_give_item(s, 'laptop', 1);
  perform pg_temp.assert(pg_temp.hint_of($q$ select market_list('item', 'laptop', 1, 45000, false, 'MkBuyer') $q$) = 'not_friend', 'only friends can get a private listing');
  perform pg_temp.assert(pg_temp.hint_of($q$ select market_list('item', 'laptop', 1, 45000, false, 'MkSeller') $q$) = 'self', 'not yourself');
  perform pg_temp.assert(pg_temp.qty(s, 'laptop') = 1, 'refused: still in the bag');
  insert into player_friendships (user_a, user_b, status, requested_by) values (least(s, b), greatest(s, b), 'accepted', s);
  r := market_list('item', 'laptop', 1, 45000, true, '@mkbuyer');
  v_l := (r->'listing'->>'id')::bigint;
  perform pg_temp.assert((r->'listing'->>'private')::boolean and r->'listing'->>'private_to' = 'MkBuyer' and not (r->'listing'->>'open_to_offers')::boolean,
                         'private listing, no offers');
  perform pg_temp.login(c);
  perform pg_temp.assert(not exists (select 1 from jsonb_array_elements(market_browse()->'rows') x where (x->>'id')::bigint = v_l), 'others do not see it in Browse');
  perform pg_temp.assert(pg_temp.hint_of(format('select market_buy(%s)', v_l)) = 'private', 'others cannot buy it');
  perform pg_temp.assert(pg_temp.hint_of(format('select market_offer(%s, 30000)', v_l)) = 'private', 'nor offer');
  perform pg_temp.login(b);
  perform pg_temp.assert(exists (select 1 from jsonb_array_elements(market_browse()->'rows') x where (x->>'id')::bigint = v_l and (x->>'private')::boolean), 'the friend sees it');
  perform market_buy(v_l);
  perform pg_temp.assert(pg_temp.qty(b, 'laptop') = 1, 'friend bought it');
  perform pg_temp.cfg('market.private_enabled', 'false');
  perform pg_temp.login(s);
  perform bl_give_item(s, 'laptop', 1);
  perform pg_temp.assert(pg_temp.hint_of($q$ select market_list('item', 'laptop', 1, 45000, false, 'MkBuyer') $q$) = 'private_off', 'switch turns private listings off');
  perform pg_temp.cfg('market.private_enabled', 'true');
end $$;

-- ---------- 13. daily cap + max open ----------
do $$
declare s uuid := current_setting('mk.s')::uuid; r jsonb; v_used int; v_ids bigint[] := '{}';
begin
  perform bl_give_item(current_setting('mk.s')::uuid, 'fish_catfish', 10);
  perform pg_temp.login(s);
  v_used := (market_info()->>'daily_used')::int;
  perform pg_temp.cfg('market.daily_listing_cap', (v_used + 2)::text);
  r := market_list('item', 'fish_catfish', 1, 5500); v_ids := v_ids || (r->'listing'->>'id')::bigint;
  r := market_list('item', 'fish_catfish', 1, 5500); v_ids := v_ids || (r->'listing'->>'id')::bigint;
  perform pg_temp.assert(pg_temp.hint_of($q$ select market_list('item', 'fish_catfish', 1, 5500) $q$) = 'daily_cap', 'daily listing cap');
  perform pg_temp.assert((market_info()->>'daily_used')::int = v_used + 2, 'market_info counts them');
  perform pg_temp.advance(25 * 3600);
  perform pg_temp.assert((market_info()->>'daily_used')::int < v_used + 2, 'the 24 hours roll');
  perform pg_temp.cfg('market.daily_listing_cap', '50');
  perform pg_temp.cfg('market.max_active', (select count(*) + 1 from market_listings where seller_id = s and status = 'active')::text);
  r := market_list('item', 'fish_catfish', 1, 5500); v_ids := v_ids || (r->'listing'->>'id')::bigint;
  perform pg_temp.assert(pg_temp.hint_of($q$ select market_list('item', 'fish_catfish', 1, 5500) $q$) = 'max_active', 'max open listings');
  perform pg_temp.cfg('market.max_active', '50');
  perform market_cancel(v_ids[1]);
  perform set_config('mk.open', v_ids[2]::text, true);
  perform set_config('mk.open2', v_ids[3]::text, true);
end $$;

-- ---------- 14. report + hide ----------
do $$
declare s uuid := current_setting('mk.s')::uuid; b uuid := current_setting('mk.b')::uuid; c uuid := current_setting('mk.c')::uuid; v_l bigint := current_setting('mk.open')::bigint; r jsonb;
begin
  perform pg_temp.login(s);
  perform pg_temp.assert(pg_temp.hint_of(format('select market_report(%s, %L)', v_l, 'x')) = 'own_listing', 'cannot report yourself');
  perform pg_temp.login(b);
  r := market_report(v_l, 'looks like a scam' || chr(10) || 'line two');
  perform pg_temp.assert((r->>'reports')::int = 1, 'one report');
  r := market_report(v_l, 'again');
  perform pg_temp.assert((r->>'reports')::int = 1, 'the same player counts once');
  perform pg_temp.assert((select reason from market_reports where listing_id = v_l and reporter_id = b) = 'looks like a scam line two', 'reason cleaned to one line');
  perform pg_temp.cfg('market.report_hide_count', '2');
  perform pg_temp.login(c);
  perform market_report(v_l, '');
  perform pg_temp.login(b);
  perform pg_temp.assert(not exists (select 1 from jsonb_array_elements(market_browse()->'rows') x where (x->>'id')::bigint = v_l), 'a reported listing drops out of Browse');
  perform pg_temp.login(current_setting('mk.adm')::uuid);
  perform pg_temp.assert(exists (select 1 from jsonb_array_elements(admin_market_overview()->'live') x where (x->>'id')::bigint = v_l and (x->>'reports')::int = 2),
                         'admin still sees it with the report count');
  perform pg_temp.cfg('market.report_hide_count', '3');
  perform pg_temp.login(b);
  perform pg_temp.assert(pg_temp.hint_of('select market_report(99999999, ''x'')') = 'gone', 'unknown listing');
end $$;

-- ---------- 15. browse ----------
do $$
declare s uuid := current_setting('mk.s')::uuid; b uuid := current_setting('mk.b')::uuid; r jsonb; v_cheap bigint; v_dear bigint;
begin
  perform pg_temp.login(s);
  perform bl_give_item(s, 'fishing_rod', 1);
  r := market_list('item', 'fishing_rod', 1, 16000);
  v_cheap := (r->'listing'->>'id')::bigint;
  perform pg_temp.assert(not exists (select 1 from jsonb_array_elements(market_browse()->'rows') x where (x->>'mine')::boolean), 'Browse never shows my own listings');
  perform pg_temp.login(b);
  r := market_browse('item', 'rod');
  perform pg_temp.assert(jsonb_array_length(r->'rows') = 1 and (r->>'total')::int = 1 and r->'rows'->0->>'title' = 'Fishing rod and line', 'search by title');
  r := market_browse(null, 'mkseller');
  perform pg_temp.assert((r->>'total')::int >= 2, 'search by seller name');
  perform pg_temp.assert(jsonb_array_length(market_browse('car')->'rows') = 0, 'kind filter');
  r := market_browse('item', null, 10000, 20000);
  perform pg_temp.assert((select bool_and((x->>'price')::bigint between 10000 and 20000) from jsonb_array_elements(r->'rows') x), 'price range filter');
  r := market_browse('item', null, null, null, 'price_asc');
  perform pg_temp.assert((r->'rows'->0->>'price')::bigint <= (r->'rows'->-1->>'price')::bigint, 'sort cheapest first');
  r := market_browse('item', null, null, null, 'price_desc');
  perform pg_temp.assert((r->'rows'->0->>'price')::bigint >= (r->'rows'->-1->>'price')::bigint, 'sort dearest first');
  r := market_browse('item', null, null, null, 'deal');
  perform pg_temp.assert((r->'rows'->0->>'pct')::numeric <= (r->'rows'->-1->>'pct')::numeric, 'sort best deal (lowest % of value) first');
  perform pg_temp.assert(jsonb_array_length(market_browse(null, null, null, null, 'new', 1, 0)->'rows') = 1, 'limit');
  perform pg_temp.assert(r->'rows'->0 ? 'seller' and r->'rows'->0 ? 'cond' and r->'rows'->0 ? 'price' and r->'rows'->0 ? 'pct', 'cards carry seller, condition, price, % of value');
  perform pg_temp.assert(not (market_browse(null, '%')->>'total')::int < 0, 'wildcards in search are harmless');
  perform pg_temp.login(s);
  perform market_cancel(v_cheap);
end $$;

-- ---------- 16. admin remove + audit + overview + flags ----------
do $$
declare s uuid := current_setting('mk.s')::uuid; b uuid := current_setting('mk.b')::uuid; adm uuid := current_setting('mk.adm')::uuid; v_l bigint := current_setting('mk.open')::bigint;
  r jsonb; v_have int; v_t jsonb; v_low bigint;
begin
  perform bl_give_item(current_setting('mk.s')::uuid, 'fish_catfish', 10);
  perform pg_temp.login(b);
  perform pg_temp.assert(pg_temp.hint_of(format('select admin_market_remove(%s)', v_l)) = 'not_admin', 'players cannot remove');
  perform pg_temp.assert(pg_temp.hint_of('select admin_market_overview()') = 'not_admin', 'players cannot open the admin view');
  perform pg_temp.login(adm);
  v_have := pg_temp.qty(s, 'fish_catfish');
  r := admin_market_remove(v_l, 'spam');
  perform pg_temp.assert(pg_temp.qty(s, 'fish_catfish') = v_have + 1, 'removal returns the item to the seller');
  perform pg_temp.assert((select status = 'removed' and removed_by = adm and removed_reason = 'spam' from market_listings where id = v_l), 'listing marked removed');
  perform pg_temp.assert((select count(*) from admin_audit where action = 'market_remove' and target_user = s and admin_id = adm and (data->>'listing')::bigint = v_l and data->>'reason' = 'spam') = 1,
                         'removal is audited');
  perform pg_temp.assert((select count(*) from events where user_id = s and kind = 'market_removed') = 1, 'seller told');
  perform pg_temp.assert(pg_temp.hint_of(format('select admin_market_remove(%s)', v_l)) = 'gone', 'cannot remove twice');
  -- suspicious flags: a far-low sale, then the buyer sells back (flip)
  perform pg_temp.login(s);
  v_low := ceil(5500 * 0.2);
  r := market_list('item', 'fish_catfish', 1, v_low);
  perform pg_temp.login(b);
  perform market_buy((r->'listing'->>'id')::bigint);
  perform pg_temp.assert((select flags from market_trades order by id desc limit 1) @> array['far_low'], 'cheap sale flagged far_low');
  r := market_list('item', 'fish_catfish', 1, 5500);
  perform pg_temp.login(s);
  perform market_buy((r->'listing'->>'id')::bigint);
  perform pg_temp.assert((select flags from market_trades order by id desc limit 1) @> array['flip'], 'back-and-forth flagged flip');
  perform pg_temp.login(b);
  r := market_list('item', 'fish_catfish', 1, 5500 * 3);
  perform pg_temp.login(s);
  perform market_buy((r->'listing'->>'id')::bigint);
  perform pg_temp.assert((select flags from market_trades order by id desc limit 1) @> array['far_high'], 'dear sale flagged far_high');
  perform pg_temp.login(adm);
  v_t := admin_market_overview(20);
  perform pg_temp.assert((v_t->'stats'->>'flagged_7d')::int >= 3 and jsonb_array_length(v_t->'trades') > 0 and jsonb_array_length(v_t->'live') > 0, 'overview has live listings, trades and flag count');
  perform pg_temp.assert((v_t->'trades'->0 ? 'flags') and (v_t->'trades'->0 ? 'seller') and (v_t->'trades'->0 ? 'buyer') and (v_t->'trades'->0 ? 'pct'), 'trade row shape');
  perform pg_temp.assert((v_t->'stats'->>'fees_7d')::bigint > 0, 'fees counted');
end $$;

-- ---------- 17. weekly earnings exclude market ----------
do $$
declare s uuid := current_setting('mk.s')::uuid; r record; v_in boolean := false;
begin
  perform pg_temp.assert(not ('market_sale' = any (bl_earn_reasons())) and not ('market_buy' = any (bl_earn_reasons())) and not ('market_fee' = any (bl_earn_reasons())),
                         'earn reasons exclude market by default');
  perform pg_temp.assert('salary' = any (bl_earn_reasons()), 'real earnings still count');
  -- even if an admin types them into the setting
  perform pg_temp.cfg('leaderboard.earn_reasons', '"salary,market_sale,market_buy,market_fee,market_x"');
  perform pg_temp.assert(not exists (select 1 from unnest(bl_earn_reasons()) x where x like 'market%') and 'salary' = any (bl_earn_reasons()),
                         'market_* filtered out of a hand-edited list');
  perform pg_temp.assert((select coalesce(sum(delta), 0) from ledger where user_id = s and reason = 'market_sale') > 0, 'the seller really earned market money');
  for r in select * from bl_weekly_ranked(bl_week_start()) loop
    if r.id = s then v_in := true; end if;
  end loop;
  perform pg_temp.assert(not v_in, 'weekly top earners do not include market sales');
  perform pg_temp.cfg('leaderboard.earn_reasons', '"salary,hustle,harvest,farm_harvest,invest_income"');
end $$;

-- ---------- 18. switches ----------
do $$
declare s uuid := current_setting('mk.s')::uuid; b uuid := current_setting('mk.b')::uuid; r jsonb; v_l bigint;
begin
  perform bl_give_item(current_setting('mk.s')::uuid, 'fish_catfish', 10);
  perform pg_temp.login(s);
  r := market_list('item', 'fish_catfish', 1, 5500);
  v_l := (r->'listing'->>'id')::bigint;
  update market_settings set enabled = false where kind = 'item';
  perform pg_temp.assert(pg_temp.hint_of($q$ select market_list('item', 'fish_catfish', 1, 5500) $q$) = 'kind_off', 'a kind can be switched off');
  perform pg_temp.assert(not (market_quote('item', 'fish_catfish', 1)->>'enabled')::boolean, 'quote says the kind is off');
  update market_settings set enabled = true where kind = 'item';
  perform pg_temp.cfg('market.enabled', 'false');
  perform pg_temp.assert(pg_temp.hint_of($q$ select market_list('item', 'fish_catfish', 1, 5500) $q$) = 'market_closed', 'master switch: no listing');
  perform pg_temp.login(b);
  perform pg_temp.assert(pg_temp.hint_of(format('select market_buy(%s)', v_l)) = 'market_closed', 'master switch: no buying');
  perform pg_temp.assert(pg_temp.hint_of(format('select market_offer(%s, 4000)', v_l)) in ('market_closed', 'no_offers'), 'master switch: no offers');
  perform pg_temp.assert(not (market_info()->>'enabled')::boolean, 'market_info shows closed');
  -- the seller can always take their thing back
  perform pg_temp.login(s);
  perform market_cancel(v_l);
  perform pg_temp.cfg('market.enabled', 'true');
  -- a jailed player has no phone
  update profiles set jailed_until = bl_now() + interval '1 hour' where id = b;
  perform pg_temp.login(b);
  perform pg_temp.assert(pg_temp.hint_of($q$ select market_offer(1, 1) $q$) in ('jailed', 'gone'), 'jailed players have no phone');
  update profiles set jailed_until = null where id = b;
end $$;

-- ---------- 19. two buyers, one wins ----------
do $$
declare s uuid := current_setting('mk.s')::uuid; b uuid := current_setting('mk.b')::uuid; c uuid := current_setting('mk.c')::uuid; r jsonb; v_l bigint; v_def text;
  v_have_b int; v_have_c int; v_sb bigint;
begin
  perform pg_temp.login(s);
  perform bl_give_item(s, 'dj_controller', 1);
  r := market_list('item', 'dj_controller', 1, 220000);
  v_l := (r->'listing'->>'id')::bigint;
  v_sb := pg_temp.bank(s);
  perform pg_temp.login(b);
  perform market_buy(v_l);
  perform pg_temp.login(c);
  v_have_c := pg_temp.qty(c, 'dj_controller');
  perform pg_temp.assert(pg_temp.hint_of(format('select market_buy(%s)', v_l)) = 'gone', 'the second buyer is told it is gone');
  perform pg_temp.assert(pg_temp.qty(c, 'dj_controller') = v_have_c and pg_temp.qty(b, 'dj_controller') = 1, 'only one item moved, to the first buyer');
  perform pg_temp.assert((select count(*) from ledger where reason = 'market_sale' and (meta->>'listing')::bigint = v_l) = 1, 'the seller was paid once');
  perform pg_temp.assert(pg_temp.bank(s) = v_sb + 220000 - 11000, 'paid exactly once (price minus fee)');
  perform pg_temp.assert((select count(*) from market_trades where listing_id = v_l) = 1, 'one trade row');
  -- both players contend for the same lock: the purchase takes the listing row lock before it touches any money
  select pg_get_functiondef('public.market_buy(bigint,bigint)'::regprocedure) into v_def;
  perform pg_temp.assert(position('from market_listings where id = p_listing for update' in v_def) > 0
                         and position('for update' in v_def) < position('bl_market_settle' in v_def), 'market_buy locks the listing row first');
  select pg_get_functiondef('public.market_offer_respond(bigint,boolean)'::regprocedure) into v_def;
  perform pg_temp.assert(position('from market_listings where id = v_lid for update' in v_def) > 0, 'accepting an offer locks the listing row too');
  select pg_get_functiondef('public.market_cancel(bigint)'::regprocedure) into v_def;
  perform pg_temp.assert(position('from market_listings where id = p_listing for update' in v_def) > 0, 'cancel locks the listing row');
  -- the seller cancels while a buyer's offer is open: the item comes back once, the offer closes
  perform pg_temp.login(s);
  perform bl_give_item(s, 'dj_controller', 1);
  r := market_list('item', 'dj_controller', 1, 220000, true);
  v_l := (r->'listing'->>'id')::bigint;
  perform pg_temp.login(b);
  perform market_offer(v_l, 150000);
  perform pg_temp.login(s);
  v_have_b := pg_temp.qty(s, 'dj_controller');
  perform market_cancel(v_l);
  perform pg_temp.assert(pg_temp.qty(s, 'dj_controller') = v_have_b + 1 and (select count(*) from market_offers where listing_id = v_l and status = 'pending') = 0, 'cancel returns once and closes offers');
  perform pg_temp.login(b);
  perform pg_temp.assert(pg_temp.hint_of(format('select market_buy(%s)', v_l)) = 'gone', 'cannot buy a cancelled listing');
end $$;

-- ---------- 20. admin content spec ----------
do $$
declare adm uuid := current_setting('mk.adm')::uuid; r jsonb; b uuid := current_setting('mk.b')::uuid;
begin
  perform pg_temp.login(b);
  perform pg_temp.assert(pg_temp.hint_of($q$ select admin_row_upsert('market_settings', '{"kind":"item","fee_pct":1}') $q$) = 'not_admin', 'players cannot edit market settings');
  perform pg_temp.login(adm);
  r := admin_row_upsert('market_settings', '{"kind":"car","fee_pct":7.5,"floor_pct":30,"ceiling_pct":200,"enabled":true}'::jsonb);
  perform pg_temp.assert((select fee_pct = 7.5 and floor_pct = 30 and ceiling_pct = 200 from market_settings where kind = 'car'), 'admin edits a kind (Content -> Market settings)');
  perform pg_temp.assert(jsonb_array_length(admin_table_rows('market_settings')) = 6, 'admin lists the kinds (four + R10 businesses + Companies)');
  perform admin_row_upsert('items', '{"id":"fish_catfish","tradeable":false}'::jsonb);
  perform pg_temp.assert(not (select tradeable from items where id = 'fish_catfish'), 'admin can flag an item untradeable');
  perform pg_temp.login(current_setting('mk.s')::uuid);
  perform pg_temp.assert(pg_temp.hint_of($q$ select market_list('item', 'fish_catfish', 1, 5500) $q$) = 'not_tradeable', 'and then it cannot be listed');
  perform pg_temp.assert(not ('fish_catfish' = any (select jsonb_array_elements_text(market_info()->'tradeable_items'))), 'market_info leaves it out');
  perform pg_temp.login(adm);
  perform admin_row_upsert('items', '{"id":"fish_catfish","tradeable":true}'::jsonb);
  perform admin_row_upsert('furniture', '{"id":"tv_75","tradeable":false}'::jsonb);
  perform pg_temp.assert(not (select tradeable from furniture where id = 'tv_75'), 'admin can flag furniture');
  update market_settings set fee_pct = 5, floor_pct = 20, ceiling_pct = 300 where kind = 'car';
  raise notice 'market OK';
end $$;
