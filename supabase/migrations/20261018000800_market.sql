-- R9: player-to-player trading, "Benin Market" (docs/MARKET.md).
-- Players list inventory items, furniture, cars and land plots at a fixed price (optionally open to offers, optionally
-- private to one friend). A listing ESCROWS the thing (it leaves the seller's bag / garage / house / land holdings, so it
-- can't be used, placed or driven), the buyer pays bank first then cash, the seller is paid into the bank minus the
-- market fee (a money sink), and the thing moves to the buyer, all in one transaction under a row lock on the listing.
--   1. config `market.*` (game_config, Settings -> Market) and `market_settings` (one row per kind: on/off, fee %,
--      price floor % and ceiling % of the catalogue value; Content -> Market settings).
--   2. items.tradeable / furniture.tradeable (admin Content columns). Default true; false for food, drink, health,
--      hygiene, offerings, phone credit and anything that is not sellable (quest / starter-locked); cars stay true
--      (their sellable flag only turns off the shop buy-back, cars sell through car_sell / the market).
--   3. tables: market_listings, market_offers, market_trades (audit + suspicious flags), market_reports, player_cars
--      (plate + wear per owned car, created lazily, travels with the car).
--   4. RPCs: market_info, market_quote, market_list, market_cancel, market_browse, market_mine, market_buy,
--      market_offer, market_offer_respond, market_offer_cancel, market_report; admin_market_overview,
--      admin_market_remove (audited, returns the thing to the seller).
--   5. ledger reasons market_buy / market_sale / market_fee. bl_earn_reasons() now never counts market_* (weekly top
--      earners and the challenge "earn" counter ignore market sales even if an admin types them into the setting).
--   6. trust rule: a brand-new account (younger than bank.transfer_min_account_real_minutes, not transfer_trusted)
--      can't SELL to other players. IP / device sharing is not tracked anywhere in the game, so there is no IP rule.
-- Expiry is lazy (no cron in the database): every market RPC first runs bl_market_sweep(), which returns expired
-- listings to their sellers and expires old offers.
-- Idempotent and safe on a non-empty DB: tables `if not exists`, seeds `on conflict do nothing` (admin edits survive),
-- functions `create or replace`, live functions patched ONLY through a guarded replace on pg_get_functiondef (raises when
-- the marker is missing, skips when already applied; create or replace keeps the grants). Private bl_* helpers are
-- revoked from anon/authenticated.

create or replace function pg_temp.bl_patch1(p_sig text, p_done text, p_marker text, p_new text) returns void
language plpgsql as $$
declare v_def text; v_n int;
begin
  select pg_get_functiondef(p_sig::regprocedure) into v_def;
  if position(p_done in v_def) > 0 then return; end if;
  v_n := (length(v_def) - length(replace(v_def, p_marker, ''))) / length(p_marker);
  if v_n = 0 then raise exception '% : marker not found: %', p_sig, p_marker; end if;
  if v_n > 1 then raise exception '% : marker not unique (% times): %', p_sig, v_n, p_marker; end if;
  execute replace(v_def, p_marker, p_new);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 1. Settings
-- ---------------------------------------------------------------------------------------------
insert into public.game_config (key, value, category, label, description, kind, min, max) values
('market.enabled', 'true', 'market', 'Benin Market on',
 'R9 (docs/MARKET.md): players can list items, furniture, cars and land for other players. Off = listing, buying and offers are refused; open listings stay locked until they expire or an admin removes them. Per-kind switches, fee and price limits: Content -> Market settings.', 'bool', null, null),
('market.daily_listing_cap', '10', 'market', 'New listings per player per 24 hours',
 'R9: how many listings one player can create in a rolling 24 real hours. Stops spam and alt-account laundering.', 'number', 1, 200),
('market.max_active', '20', 'market', 'Open listings per player',
 'R9: most listings one player can have open at the same time.', 'number', 1, 500),
('market.expire_days', '7', 'market', 'Listings last (days)',
 'R9: after this many real days a listing expires and the thing goes back to its seller (returned the next time anyone opens the market).', 'number', 1, 90),
('market.offer_expire_hours', '24', 'market', 'Offers last (hours)',
 'R9: an offer the seller has not answered expires after this many real hours (never later than the listing itself).', 'number', 1, 720),
('market.min_offer_pct', '50', 'market', 'Lowest offer (% of asking price)',
 'R9: an offer must be below the asking price but not under this % of it.', 'percent', 1, 99),
('market.max_open_offers', '10', 'market', 'Open offers per buyer',
 'R9: how many offers one player can have waiting at once.', 'number', 1, 100),
('market.min_price', '100', 'market', 'Lowest price (naira)',
 'R9: no listing can be cheaper than this, whatever the price floor says.', 'naira', 1, null),
('market.report_hide_count', '3', 'market', 'Reports that hide a listing',
 'R9: a listing with this many player reports disappears from Browse (Admin -> Market still shows it and can remove it). 0 = never hide.', 'number', 0, 100),
('market.private_enabled', 'true', 'market', 'Sell to a friend (private listing) on',
 'R9: a seller can make a listing that only one accepted friend can buy.', 'bool', null, null),
('market.flag_low_pct', '50', 'market', 'Suspicious: sale under (% of value)',
 'R9: Admin -> Market flags a trade "far_low" when the price was under this % of the catalogue value (money pushed to an alt can look like a cheap sale).', 'percent', 1, 100),
('market.flag_high_pct', '200', 'market', 'Suspicious: sale over (% of value)',
 'R9: Admin -> Market flags a trade "far_high" when the price was over this % of the catalogue value (money pushed to an alt can look like a very dear sale).', 'percent', 100, 10000),
('market.flip_hours', '24', 'market', 'Suspicious: back-and-forth window (hours)',
 'R9: a trade is flagged "flip" when the same two players traded the other way round inside this window, and "repeat_pair" when they have traded three or more times in it.', 'number', 1, 720)
on conflict (key) do nothing;

create table if not exists public.market_settings (
  kind        text primary key check (kind in ('item', 'furniture', 'car', 'land')),
  label       text not null,
  enabled     boolean not null default true,
  fee_pct     numeric not null default 5 check (fee_pct >= 0 and fee_pct <= 50),
  floor_pct   numeric not null default 20 check (floor_pct >= 1 and floor_pct <= 1000),
  ceiling_pct numeric not null default 300 check (ceiling_pct >= 1 and ceiling_pct <= 10000),
  sort        int not null default 100,
  check (ceiling_pct >= floor_pct)
);
alter table public.market_settings enable row level security;
revoke all on public.market_settings from public, anon, authenticated;
grant select on public.market_settings to authenticated;
drop policy if exists market_settings_read on public.market_settings;
create policy market_settings_read on public.market_settings for select to authenticated using (true);

insert into public.market_settings (kind, label, enabled, fee_pct, floor_pct, ceiling_pct, sort) values
('item',      'Items',     true, 5, 20, 300, 10),
('furniture', 'Furniture', true, 5, 20, 300, 20),
('car',       'Cars',      true, 5, 20, 300, 30),
('land',      'Land',      true, 5, 20, 300, 40)
on conflict (kind) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 2. tradeable flags (only when the column is first added, so admin edits survive a re-run)
-- ---------------------------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'items' and column_name = 'tradeable') then
    alter table public.items add column tradeable boolean not null default true;
    update public.items set tradeable = false
     where category in ('food', 'drink', 'health', 'hygiene', 'offering', 'phone') or (sellable = false and category <> 'vehicle');
  end if;
  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'furniture' and column_name = 'tradeable') then
    alter table public.furniture add column tradeable boolean not null default true;
  end if;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 3. Tables
-- ---------------------------------------------------------------------------------------------
create table if not exists public.player_cars (
  id         bigserial primary key,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  item_id    text not null references public.items(id) on delete cascade,
  plate      text not null,
  wear       numeric not null default 0 check (wear >= 0 and wear <= 100),
  created_at timestamptz not null default now()
);
create unique index if not exists player_cars_plate_uq on public.player_cars (plate);
create index if not exists player_cars_user_idx on public.player_cars (user_id, item_id);

create table if not exists public.market_listings (
  id             bigserial primary key,
  seller_id      uuid not null references public.profiles(id) on delete cascade,
  kind           text not null check (kind in ('item', 'furniture', 'car', 'land')),
  ref_id         text not null,
  qty            int not null default 1 check (qty >= 1),
  title          text not null,
  icon           text not null default '',
  price          bigint not null check (price >= 1),
  value          bigint not null default 0 check (value >= 0),
  open_to_offers boolean not null default false,
  buyer_only     uuid references public.profiles(id) on delete set null,
  status         text not null default 'active' check (status in ('active', 'sold', 'cancelled', 'expired', 'removed')),
  detail         jsonb not null default '{}'::jsonb,
  reports        int not null default 0,
  created_at     timestamptz not null default now(),
  expires_at     timestamptz not null,
  closed_at      timestamptz,
  buyer_id       uuid references public.profiles(id) on delete set null,
  sold_price     bigint,
  fee            bigint,
  removed_by     uuid,
  removed_reason text
);
create index if not exists market_listings_browse_idx on public.market_listings (status, kind, price);
create index if not exists market_listings_seller_idx on public.market_listings (seller_id, status, created_at desc);
create index if not exists market_listings_expiry_idx on public.market_listings (expires_at) where status = 'active';

create table if not exists public.market_offers (
  id         bigserial primary key,
  listing_id bigint not null references public.market_listings(id) on delete cascade,
  buyer_id   uuid not null references public.profiles(id) on delete cascade,
  amount     bigint not null check (amount >= 1),
  status     text not null default 'pending' check (status in ('pending', 'accepted', 'declined', 'expired', 'cancelled')),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  closed_at  timestamptz
);
create unique index if not exists market_offers_one_pending_uq on public.market_offers (listing_id, buyer_id) where status = 'pending';
create index if not exists market_offers_buyer_idx on public.market_offers (buyer_id, status, created_at desc);
create index if not exists market_offers_expiry_idx on public.market_offers (expires_at) where status = 'pending';

create table if not exists public.market_trades (
  id         bigserial primary key,
  listing_id bigint references public.market_listings(id) on delete set null,
  kind       text not null,
  ref_id     text not null,
  title      text not null,
  seller_id  uuid not null references public.profiles(id) on delete cascade,
  buyer_id   uuid not null references public.profiles(id) on delete cascade,
  price      bigint not null,
  fee        bigint not null default 0,
  value      bigint not null default 0,
  via        text not null default 'buy' check (via in ('buy', 'offer')),
  flags      text[] not null default '{}',
  created_at timestamptz not null default now()
);
create index if not exists market_trades_time_idx on public.market_trades (created_at desc);
create index if not exists market_trades_pair_idx on public.market_trades (seller_id, buyer_id, created_at desc);

create table if not exists public.market_reports (
  listing_id  bigint not null references public.market_listings(id) on delete cascade,
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  reason      text not null default '',
  created_at  timestamptz not null default now(),
  primary key (listing_id, reporter_id)
);

alter table public.player_cars      enable row level security;
alter table public.market_listings  enable row level security;
alter table public.market_offers    enable row level security;
alter table public.market_trades    enable row level security;
alter table public.market_reports   enable row level security;
revoke all on public.player_cars, public.market_listings, public.market_offers, public.market_trades, public.market_reports
  from public, anon, authenticated;
revoke all on sequence public.player_cars_id_seq, public.market_listings_id_seq, public.market_offers_id_seq,
  public.market_trades_id_seq from public, anon, authenticated;
-- players read only their own rows; every write goes through the RPCs. Trades and reports are admin-only (via RPC).
grant select on public.player_cars, public.market_listings, public.market_offers to authenticated;
drop policy if exists player_cars_own on public.player_cars;
create policy player_cars_own on public.player_cars for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists market_listings_own on public.market_listings;
create policy market_listings_own on public.market_listings for select to authenticated
  using (seller_id = (select auth.uid()) or buyer_id = (select auth.uid()));
drop policy if exists market_offers_own on public.market_offers;
create policy market_offers_own on public.market_offers for select to authenticated using (buyer_id = (select auth.uid()));

-- ---------------------------------------------------------------------------------------------
-- 4. Private helpers
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_market_num(p_key text, p_default numeric) returns numeric
language sql stable set search_path = public as $$
  select coalesce((select (value #>> '{}')::numeric from game_config where key = p_key), p_default);
$$;

create or replace function public.bl_market_on() returns boolean
language sql stable set search_path = public as $$
  select coalesce((select (value #>> '{}')::boolean from game_config where key = 'market.enabled'), true);
$$;

-- Market door: switched on, and the player isn't in a police cell (the phone is taken).
create or replace function public.bl_market_guard(p_me public.profiles) returns void
language plpgsql set search_path = public as $$
begin
  if not bl_market_on() then
    raise exception 'Benin Market is closed for now. Check back later.' using errcode = 'P0001', hint = 'market_closed';
  end if;
  if p_me.jailed_until is not null and p_me.jailed_until > bl_now() then
    raise exception 'The police took your phone. The market can wait until you are out.' using errcode = 'P0001', hint = 'jailed';
  end if;
end $$;

-- Trust rule (same wait as bank transfers): new accounts can't SELL to other players. Admin "trusted senders" are exempt.
create or replace function public.bl_market_seller_ok(p_me public.profiles) returns void
language plpgsql set search_path = public as $$
declare v_age numeric := bl_market_num('bank.transfer_min_account_real_minutes', 1440) * 60; v_left numeric;
begin
  if coalesce(p_me.transfer_trusted, false) then return; end if;
  v_left := v_age - extract(epoch from bl_now() - p_me.created_at);
  if v_left > 0 then
    raise exception 'New accounts can sell to other players after % hour(s) of playing. About % to go.',
      greatest(1, round(v_age / 3600))::int,
      case when v_left >= 3600 then ceil(v_left / 3600)::int || ' h' else ceil(v_left / 60)::int || ' min' end
      using errcode = 'P0001', hint = 'new_account';
  end if;
end $$;

create or replace function public.bl_market_plate() returns text
language plpgsql set search_path = public as $$
declare v text; v_abc text := 'ABCDEFGHJKLMNPRSTUVWXY';
begin
  loop
    v := 'BEN-' || lpad((100 + floor(random() * 900))::int::text, 3, '0') || '-'
         || substr(v_abc, 1 + floor(random() * length(v_abc))::int, 1) || substr(v_abc, 1 + floor(random() * length(v_abc))::int, 1);
    exit when not exists (select 1 from player_cars where plate = v);
  end loop;
  return v;
end $$;

-- "Plate BEN-123-AB · wear 40%" / "3 plots" / "×4"
create or replace function public.bl_market_cond(p_kind text, p_detail jsonb, p_qty int) returns text
language sql immutable set search_path = public as $$
  select case p_kind
    when 'car' then 'Plate ' || coalesce(p_detail->>'plate', '-') || ' · wear ' || round(coalesce((p_detail->>'wear')::numeric, 0)) || '%'
    when 'land' then p_qty || ' plot' || case when p_qty > 1 then 's' else '' end
    when 'item' then case when p_qty > 1 then '×' || p_qty else 'Used' end
    else 'Used'
  end;
$$;

-- Take the thing out of the seller's hands (escrow). Raises the player-facing reason when it can't be listed.
-- Returns {title, icon, value, detail, qty}. The caller holds the player lock.
create or replace function public.bl_market_take(p_uid uuid, p_kind text, p_ref text, p_qty int, p_key text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  it items; f furniture; pf player_furniture; pos invest_positions; m invest_markets; pc player_cars;
  v_have int; v_wear numeric := 0; v_plate text; v_best boolean; v_copy int; v_bought int; v_key text; v_last text; v_b text;
  v_rel bigint; n int; v_price numeric;
begin
  if p_qty is null or p_qty < 1 then
    raise exception 'Put how many you want to sell.' using errcode = 'P0001', hint = 'bad_amount';
  end if;
  if p_kind = 'item' then
    select * into it from items where id = p_ref;
    if not found or it.category = 'vehicle' then
      raise exception 'That one no dey for the market.' using errcode = 'P0001', hint = 'not_tradeable';
    end if;
    if not it.tradeable or it.price <= 0 then
      raise exception '% can''t be sold to other players.', it.name using errcode = 'P0001', hint = 'not_tradeable';
    end if;
    select qty into v_have from inventory where user_id = p_uid and item_id = it.id for update;
    if coalesce(v_have, 0) < p_qty then
      raise exception 'You only have % of those.', coalesce(v_have, 0) using errcode = 'P0001', hint = 'not_owned';
    end if;
    perform bl_give_item(p_uid, it.id, -p_qty);
    return jsonb_build_object('title', it.name || case when p_qty > 1 then ' ×' || p_qty else '' end, 'icon', coalesce(it.icon, ''),
                              'value', it.price::bigint * p_qty, 'detail', '{}'::jsonb, 'qty', p_qty);

  elsif p_kind = 'car' then
    select * into it from items where id = p_ref and category = 'vehicle';
    if not found then
      raise exception 'That is not a car.' using errcode = 'P0001', hint = 'not_a_car';
    end if;
    if not it.tradeable or it.price <= 0 then
      raise exception '% can''t be sold to other players.', it.name using errcode = 'P0001', hint = 'not_tradeable';
    end if;
    if p_qty <> 1 then
      raise exception 'Cars are sold one at a time.' using errcode = 'P0001', hint = 'bad_amount';
    end if;
    select qty into v_have from inventory where user_id = p_uid and item_id = it.id for update;
    if coalesce(v_have, 0) < 1 then
      raise exception 'You don''t own a %.', it.name using errcode = 'P0001', hint = 'not_owned';
    end if;
    select * into pc from player_cars where user_id = p_uid and item_id = it.id order by id limit 1 for update;
    v_best := coalesce(bl_hustle_car(p_uid)->>'item_id', '') = it.id;
    v_wear := case when v_best then coalesce((select car_wear from hustle_players where user_id = p_uid), 0) else coalesce(pc.wear, 0) end;
    v_plate := coalesce(pc.plate, bl_market_plate());
    if pc.id is not null then delete from player_cars where id = pc.id; end if;
    if v_best then update hustle_players set car_wear = 0, updated_at = bl_now() where user_id = p_uid; end if;
    perform bl_give_item(p_uid, it.id, -1);
    return jsonb_build_object('title', it.name, 'icon', coalesce(it.icon, '🚗'), 'value', it.price::bigint,
                              'detail', jsonb_build_object('plate', v_plate, 'wear', least(100, v_wear)), 'qty', 1);

  elsif p_kind = 'furniture' then
    select * into f from furniture where id = p_ref;
    if not found or not f.active or not f.tradeable or f.price <= 0 then
      raise exception 'That piece can''t be sold to other players.' using errcode = 'P0001', hint = 'not_tradeable';
    end if;
    if p_qty <> 1 then
      raise exception 'Furniture is sold one piece at a time.' using errcode = 'P0001', hint = 'bad_amount';
    end if;
    -- every copy gets its row first, so placed / stored is known (and the renumbering below sees them all)
    perform bl_furniture_materialize(p_uid);
    select * into pf from player_furniture where user_id = p_uid and furniture_id = f.id for update;
    if not found then
      raise exception 'You don''t have that piece.' using errcode = 'P0001', hint = 'not_owned';
    end if;
    v_bought := pf.qty - pf.house_qty;
    if v_bought < 1 then
      raise exception '% came with your house. You fit keep am, but you no fit sell am to players.', f.name using errcode = 'P0001', hint = 'house_piece';
    end if;
    if p_key is not null then
      if bl_furniture_id_of(p_key) <> f.id or bl_furniture_copy_of(p_key) not between 1 and pf.qty then
        raise exception 'You don''t have that piece.' using errcode = 'P0001', hint = 'not_owned';
      end if;
      v_copy := bl_furniture_copy_of(p_key);
      if v_copy > v_bought then
        raise exception '% came with your house. You fit keep am, but you no fit sell am to players.', f.name using errcode = 'P0001', hint = 'house_piece';
      end if;
      if exists (select 1 from player_house_furniture h where h.owner_id = p_uid and h.furniture_key = bl_furniture_key(f.id, v_copy) and not h.stored) then
        raise exception 'Pick % up first (Arrange, then Store), and then you fit sell am.', f.name using errcode = 'P0001', hint = 'placed';
      end if;
    else
      for n in 1..v_bought loop
        if not exists (select 1 from player_house_furniture h where h.owner_id = p_uid and h.furniture_key = bl_furniture_key(f.id, n) and not h.stored) then
          v_copy := n; exit;
        end if;
      end loop;
      if v_copy is null then
        raise exception 'Pick % up first (Arrange, then Store), and then you fit sell am.', f.name using errcode = 'P0001', hint = 'placed';
      end if;
    end if;
    v_key := bl_furniture_key(f.id, v_copy);
    v_last := bl_furniture_key(f.id, pf.qty);
    delete from player_house_furniture where owner_id = p_uid and furniture_key = v_key;
    if pf.house_qty > 0 then
      -- came-with-house copies stay the highest numbers (same renumbering as furniture_sell)
      v_b := bl_furniture_key(f.id, v_bought);
      if v_b <> v_key then
        update player_house_furniture set furniture_key = v_key, updated_at = bl_now() where owner_id = p_uid and furniture_key = v_b;
      end if;
      update player_house_furniture set furniture_key = v_b, updated_at = bl_now() where owner_id = p_uid and furniture_key = v_last;
    elsif v_last <> v_key then
      update player_house_furniture set furniture_key = v_key, updated_at = bl_now() where owner_id = p_uid and furniture_key = v_last;
    end if;
    if pf.qty <= 1 then
      delete from player_furniture where user_id = p_uid and furniture_id = f.id;
    else
      update player_furniture set qty = qty - 1 where user_id = p_uid and furniture_id = f.id;
    end if;
    return jsonb_build_object('title', f.name, 'icon', coalesce(f.emoji, '🪑'), 'value', f.price::bigint,
                              'detail', jsonb_build_object('furniture', f.id), 'qty', 1);

  elsif p_kind = 'land' then
    select * into m from invest_markets where id = p_ref and kind = 'land';
    if not found then
      raise exception 'That area no dey.' using errcode = 'P0001', hint = 'bad_market';
    end if;
    -- a land deal still open (levy to pay or walk away from) must be finished first
    update invest_land_deals set status = 'expired', closed_at = bl_now() where user_id = p_uid and status = 'pending' and expires_at <= bl_now();
    if exists (select 1 from invest_land_deals where user_id = p_uid and status = 'pending') then
      raise exception 'You still have a land deal open. Pay the levy or walk away first, then you fit sell plots to players.'
        using errcode = 'P0001', hint = 'land_pending';
    end if;
    perform bl_inv_settle(p_uid);
    select * into pos from invest_positions where user_id = p_uid and ref_id = m.id and kind = 'land' for update;
    if not found or pos.qty < p_qty then
      raise exception 'You have % plot(s) in %.', coalesce(pos.qty, 0)::bigint, m.name using errcode = 'P0001', hint = 'not_owned';
    end if;
    v_price := bl_inv_price(m.id);
    v_rel := case when p_qty = pos.qty then pos.cost else floor(pos.cost * p_qty / pos.qty)::bigint end;
    if p_qty = pos.qty then
      delete from invest_positions where id = pos.id;
    else
      update invest_positions set qty = qty - p_qty, cost = greatest(0, cost - v_rel) where id = pos.id;
    end if;
    return jsonb_build_object('title', p_qty || ' plot' || case when p_qty > 1 then 's' else '' end || ' · ' || m.name,
                              'icon', coalesce(m.icon, '🏞️'), 'value', floor(p_qty * v_price)::bigint,
                              'detail', jsonb_build_object('area', m.id, 'cost', v_rel), 'qty', p_qty);
  end if;
  raise exception 'That kind of thing can''t be sold here.' using errcode = 'P0001', hint = 'bad_kind';
end $$;

-- Hand the thing to a player (the buyer, or the seller when a listing ends). p_cost = what the plots cost their holder.
-- p_strict = enforce the buyer's own limits (furniture max copies).
create or replace function public.bl_market_give(p_uid uuid, p_kind text, p_ref text, p_qty int, p_detail jsonb, p_cost bigint, p_strict boolean)
returns void language plpgsql security definer set search_path = public as $$
declare
  f furniture; pos invest_positions; v_qty int; v_key text; v_layout text; v_plate text; v_wear numeric; v_now timestamptz := bl_now();
begin
  if p_kind = 'item' then
    perform bl_give_item(p_uid, p_ref, p_qty);

  elsif p_kind = 'car' then
    perform bl_give_item(p_uid, p_ref, 1);
    v_plate := coalesce(p_detail->>'plate', bl_market_plate());
    v_wear := coalesce((p_detail->>'wear')::numeric, 0);
    if exists (select 1 from player_cars where plate = v_plate) then v_plate := bl_market_plate(); end if;
    insert into player_cars (user_id, item_id, plate, wear, created_at) values (p_uid, p_ref, v_plate, v_wear, v_now);
    -- the car you drive for hustles carries its wear with it
    if v_wear > 0 and coalesce(bl_hustle_car(p_uid)->>'item_id', '') = p_ref then
      insert into hustle_players (user_id, car_wear, updated_at) values (p_uid, v_wear, v_now)
      on conflict (user_id) do update set car_wear = greatest(hustle_players.car_wear, excluded.car_wear), updated_at = excluded.updated_at;
    end if;

  elsif p_kind = 'furniture' then
    select * into f from furniture where id = p_ref;
    if p_strict and coalesce((select qty from player_furniture where user_id = p_uid and furniture_id = f.id), 0) >= f.max_qty then
      raise exception 'You already have % of these. Na the maximum.', f.max_qty using errcode = 'P0001', hint = 'max_owned';
    end if;
    v_layout := bl_furniture_materialize(p_uid);
    insert into player_furniture (user_id, furniture_id, slot, source, qty)
    values (p_uid, f.id, null, 'market', 1)
    on conflict (user_id, furniture_id) do update set qty = player_furniture.qty + 1
    returning qty into v_qty;
    v_key := bl_furniture_key(f.id, v_qty);
    -- came-with-house copies stay the highest numbers: the new copy takes the first came-with-house number
    if coalesce((select house_qty from player_furniture where user_id = p_uid and furniture_id = f.id), 0) > 0 then
      delete from player_house_furniture where owner_id = p_uid and furniture_key = v_key;
      v_key := (select bl_furniture_key(f.id, qty - house_qty) from player_furniture where user_id = p_uid and furniture_id = f.id);
      update player_house_furniture set furniture_key = bl_furniture_key(f.id, v_qty), updated_at = v_now
       where owner_id = p_uid and furniture_key = v_key;
    end if;
    insert into player_house_furniture (owner_id, furniture_key, x, z, rotation, stored, layout, updated_at)
    values (p_uid, v_key, 0, 0, 0, true, v_layout, v_now)
    on conflict (owner_id, furniture_key) do update set stored = true, layout = excluded.layout, updated_at = excluded.updated_at;

  elsif p_kind = 'land' then
    select * into pos from invest_positions where user_id = p_uid and ref_id = p_ref and kind = 'land' for update;
    if found then
      update invest_positions set qty = qty + p_qty, cost = cost + coalesce(p_cost, 0) where id = pos.id;
    else
      insert into invest_positions (user_id, ref_id, kind, qty, cost, opened_at, last_at)
      values (p_uid, p_ref, 'land', p_qty, coalesce(p_cost, 0), v_now, v_now);
    end if;
  end if;
end $$;

-- Suspicious-trade flags (Admin -> Market). IP / device are not tracked in this game, so there is no same-ip flag.
create or replace function public.bl_market_flags(p_seller uuid, p_buyer uuid, p_price bigint, p_value bigint)
returns text[] language plpgsql stable set search_path = public as $$
declare
  v text[] := '{}'; v_now timestamptz := bl_now(); v_hours numeric := bl_market_num('market.flip_hours', 24);
  v_age numeric := bl_market_num('bank.transfer_min_account_real_minutes', 1440) * 60;
begin
  if p_value > 0 and p_price < p_value * bl_market_num('market.flag_low_pct', 50) / 100 then v := array_append(v, 'far_low'); end if;
  if p_value > 0 and p_price > p_value * bl_market_num('market.flag_high_pct', 200) / 100 then v := array_append(v, 'far_high'); end if;
  if exists (select 1 from market_trades t where t.seller_id = p_buyer and t.buyer_id = p_seller
              and t.created_at > v_now - make_interval(hours => v_hours::int)) then v := array_append(v, 'flip'); end if;
  if (select count(*) from market_trades t where t.seller_id = p_seller and t.buyer_id = p_buyer
       and t.created_at > v_now - make_interval(hours => v_hours::int)) >= 2 then v := array_append(v, 'repeat_pair'); end if;
  if exists (select 1 from profiles p where p.id in (p_seller, p_buyer) and extract(epoch from v_now - p.created_at) < v_age) then
    v := array_append(v, 'new_account');
  end if;
  return v;
end $$;

create or replace function public.bl_market_card(l public.market_listings, p_viewer uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', l.id, 'kind', l.kind, 'ref', l.ref_id, 'title', l.title, 'icon', l.icon, 'qty', l.qty,
    'price', l.price, 'value', l.value, 'pct', case when l.value > 0 then round(l.price * 100.0 / l.value) end,
    'open_to_offers', l.open_to_offers, 'private', l.buyer_only is not null,
    'private_to', (select username from profiles where id = l.buyer_only),
    'seller', (select username from profiles where id = l.seller_id), 'mine', l.seller_id = p_viewer,
    'detail', l.detail, 'cond', bl_market_cond(l.kind, l.detail, l.qty),
    'status', l.status, 'created_at', l.created_at, 'expires_at', l.expires_at, 'reports', l.reports,
    'sold_price', l.sold_price, 'fee', l.fee,
    'my_offer', (select jsonb_build_object('id', o.id, 'amount', o.amount, 'expires_at', o.expires_at)
                   from market_offers o where o.listing_id = l.id and o.buyer_id = p_viewer and o.status = 'pending'),
    'offers', case when l.seller_id = p_viewer
                   then (select count(*) from market_offers o where o.listing_id = l.id and o.status = 'pending') end);
$$;

-- Does everything for a sale: money (buyer pays bank first, then cash; seller gets the price in the bank minus the market
-- fee: three kinds of ledger row), the thing to the buyer, the listing, the trade log, alerts. The caller holds the
-- listing lock and both player locks.
create or replace function public.bl_market_settle(p_listing bigint, p_buyer uuid, p_price bigint, p_via text, p_offer bigint default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  l market_listings; st market_settings; b profiles; s profiles; v_fee bigint; v_bpart bigint; v_cpart bigint;
  v_flags text[]; v_meta jsonb; v_rcpt jsonb; v_bank bigint; v_net bigint; v_now timestamptz := bl_now();
begin
  select * into l from market_listings where id = p_listing;
  select * into st from market_settings where kind = l.kind;
  select * into b from profiles where id = p_buyer;
  select * into s from profiles where id = l.seller_id;
  if b.cash + greatest(b.bank, 0) < p_price then
    raise exception 'Not enough money. This costs % and you have % (bank % + cash %).', bl_naira(p_price),
      bl_naira(b.cash + greatest(b.bank, 0)), bl_naira(greatest(b.bank, 0)), bl_naira(b.cash)
      using errcode = 'P0001', hint = 'not_enough_cash';
  end if;
  v_fee := floor(p_price * coalesce(st.fee_pct, 5) / 100.0)::bigint;
  v_net := p_price - v_fee;
  v_bpart := least(greatest(b.bank, 0), p_price);
  v_cpart := p_price - v_bpart;
  v_meta := jsonb_build_object('listing', l.id, 'title', l.title, 'kind', l.kind, 'seller', s.username, 'buyer', b.username);
  if v_bpart > 0 then perform bl_add_money(b.id, 'bank', -v_bpart, 'market_buy', v_meta); end if;
  if v_cpart > 0 then perform bl_add_money(b.id, 'cash', -v_cpart, 'market_buy', v_meta); end if;
  v_bank := bl_add_money(s.id, 'bank', p_price, 'market_sale', v_meta);
  if v_fee > 0 then
    v_bank := bl_add_money(s.id, 'bank', -v_fee, 'market_fee', v_meta || jsonb_build_object('fee_pct', st.fee_pct));
  end if;
  perform bl_market_give(b.id, l.kind, l.ref_id, l.qty, l.detail, p_price, true);
  v_flags := bl_market_flags(s.id, b.id, p_price, l.value);
  update market_listings set status = 'sold', buyer_id = b.id, sold_price = p_price, fee = v_fee, closed_at = v_now where id = l.id;
  insert into market_trades (listing_id, kind, ref_id, title, seller_id, buyer_id, price, fee, value, via, flags, created_at)
  values (l.id, l.kind, l.ref_id, l.title, s.id, b.id, p_price, v_fee, l.value, p_via, v_flags, v_now);
  update market_offers set status = 'declined', closed_at = v_now where listing_id = l.id and status = 'pending' and id is distinct from p_offer;
  -- alerts: whoever pressed the button already sees the result, so their own alert is quiet (Alerts only, no toast)
  perform bl_event(s.id, 'market_sold', 'Sold: ' || l.title,
    '@' || b.username || ' paid ' || bl_naira(p_price) || '. ' || bl_naira(v_net) || ' in your bank after the ' || bl_naira(v_fee) || ' market fee.',
    jsonb_build_object('listing', l.id, 'price', p_price, 'fee', v_fee, 'buyer', b.username, 'quiet', p_via = 'offer'));
  if p_via = 'buy' then
    perform bl_push_enqueue(s.id, 'money', 'market_sold', 'Your ' || l.title || ' don sell 💰',
      '@' || b.username || ' paid ' || bl_naira(p_price) || '. You get ' || bl_naira(v_net) || ' after the market fee.',
      '/play?go=market', b.id);
  else
    perform bl_event(b.id, 'market_offer_accepted', '@' || s.username || ' accepted your offer',
      l.title || ' is yours for ' || bl_naira(p_price) || '. Check your bag, garage or home.',
      jsonb_build_object('listing', l.id, 'price', p_price, 'seller', s.username));
    perform bl_push_enqueue(b.id, 'money', 'market_offer_accepted', '@' || s.username || ' accept your offer 🎉',
      l.title || ' for ' || bl_naira(p_price) || ' don land with you.', '/play?go=market', s.id);
  end if;
  v_rcpt := bl_receipt_issue(b.id, 'market', l.title, p_price, '@' || s.username || ' (Benin Market)',
                             jsonb_build_object('listing', l.id, 'kind', l.kind));
  return jsonb_build_object('listing', l.id, 'title', l.title, 'price', p_price, 'fee', v_fee, 'net', v_net, 'seller', s.username,
                            'buyer', b.username, 'seller_bank', v_bank, 'flags', v_flags) || v_rcpt;
end $$;

-- A listing ends without a sale: the thing goes back to its seller, open offers close. The caller holds the listing lock.
create or replace function public.bl_market_release(p_listing bigint, p_status text, p_reason text default null, p_by uuid default null)
returns void language plpgsql security definer set search_path = public as $$
declare l market_listings; v_now timestamptz := bl_now();
begin
  select * into l from market_listings where id = p_listing;
  if not found or l.status <> 'active' then return; end if;
  perform bl_market_give(l.seller_id, l.kind, l.ref_id, l.qty, l.detail, coalesce((l.detail->>'cost')::bigint, 0), false);
  update market_listings set status = p_status, closed_at = v_now, removed_by = p_by, removed_reason = p_reason where id = l.id;
  update market_offers set status = case when p_status = 'expired' then 'expired' else 'cancelled' end, closed_at = v_now
   where listing_id = l.id and status = 'pending';
end $$;

-- Lazy expiry: listings past their time go back to their sellers; offers past their time expire. Skips rows another
-- transaction is working on (it never waits or deadlocks), and one bad listing never blocks the rest.
create or replace function public.bl_market_sweep(p_limit int default 25) returns int
language plpgsql security definer set search_path = public as $$
declare r market_listings; n int := 0; v_now timestamptz := bl_now();
begin
  update market_offers set status = 'expired', closed_at = v_now where status = 'pending' and expires_at <= v_now;
  for r in select * from market_listings where status = 'active' and expires_at <= v_now order by expires_at, id limit p_limit for update skip locked loop
    begin
      perform bl_market_release(r.id, 'expired');
      perform bl_event(r.seller_id, 'market_expired', 'Listing ended: ' || r.title, 'Nobody bought am in time, so e don come back to you.',
                       jsonb_build_object('listing', r.id));
      n := n + 1;
    exception when others then
      raise warning 'market sweep: listing % not released: %', r.id, sqlerrm;
    end;
  end loop;
  return n;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 5. Player RPCs
-- ---------------------------------------------------------------------------------------------
create or replace function public.market_info() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid(); v_me profiles; v_age numeric; v_left numeric;
begin
  perform bl_market_sweep();
  select * into v_me from profiles where id = v_uid;
  v_age := bl_market_num('bank.transfer_min_account_real_minutes', 1440) * 60;
  v_left := case when coalesce(v_me.transfer_trusted, false) then 0 else greatest(0, v_age - extract(epoch from bl_now() - v_me.created_at)) end;
  return jsonb_build_object(
    'enabled', bl_market_on(),
    'kinds', coalesce((select jsonb_agg(jsonb_build_object('kind', kind, 'label', label, 'enabled', enabled, 'fee_pct', fee_pct,
                              'floor_pct', floor_pct, 'ceiling_pct', ceiling_pct) order by sort, kind) from market_settings), '[]'::jsonb),
    'tradeable_items', coalesce((select jsonb_agg(id order by id) from items where tradeable and price > 0 and category <> 'vehicle'), '[]'::jsonb),
    'tradeable_cars', coalesce((select jsonb_agg(id order by id) from items where tradeable and price > 0 and category = 'vehicle'), '[]'::jsonb),
    'tradeable_furniture', coalesce((select jsonb_agg(id order by id) from furniture where tradeable and active and price > 0), '[]'::jsonb),
    'daily_cap', bl_market_num('market.daily_listing_cap', 10)::int,
    'daily_used', (select count(*) from market_listings where seller_id = v_uid and created_at > bl_now() - interval '24 hours'),
    'max_active', bl_market_num('market.max_active', 20)::int,
    'active', (select count(*) from market_listings where seller_id = v_uid and status = 'active'),
    'expire_days', bl_market_num('market.expire_days', 7),
    'min_offer_pct', bl_market_num('market.min_offer_pct', 50),
    'min_price', bl_market_num('market.min_price', 100)::bigint,
    'private_enabled', coalesce((select (value #>> '{}')::boolean from game_config where key = 'market.private_enabled'), true),
    'sell_wait_seconds', ceil(v_left)::int,
    'can_sell', v_left <= 0);
end $$;

-- Read-only check for the sell sheet: what the thing is, what it is worth, the allowed price range, or why it can't be
-- listed. It runs the real escrow code inside a sub-transaction that is always rolled back.
create or replace function public.market_quote(p_kind text, p_ref text, p_qty int default 1, p_key text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid(); v_me profiles := bl_me(); st market_settings; t jsonb; v_msg text; v_hint text; v_val bigint;
begin
  select * into st from market_settings where kind = p_kind;
  if not found then
    return jsonb_build_object('ok', false, 'message', 'That kind of thing can''t be sold here.');
  end if;
  begin
    begin
      t := bl_market_take(v_uid, p_kind, p_ref, coalesce(p_qty, 1), p_key);
      raise exception using errcode = 'P0002', message = 'quote_rollback';
    exception when sqlstate 'P0002' then
      null;   -- the sub-transaction is rolled back: nothing was taken
    end;
  exception when others then
    get stacked diagnostics v_msg = message_text, v_hint = pg_exception_hint;
    return jsonb_build_object('ok', false, 'message', v_msg, 'hint', v_hint);
  end;
  v_val := (t->>'value')::bigint;
  return jsonb_build_object('ok', true, 'kind', p_kind, 'title', t->>'title', 'icon', t->>'icon', 'value', v_val, 'qty', (t->>'qty')::int,
    'detail', t->'detail', 'cond', bl_market_cond(p_kind, t->'detail', (t->>'qty')::int),
    'fee_pct', st.fee_pct, 'enabled', st.enabled and bl_market_on(),
    'min_price', greatest(bl_market_num('market.min_price', 100)::bigint, ceil(v_val * st.floor_pct / 100)::bigint),
    'max_price', floor(v_val * st.ceiling_pct / 100)::bigint,
    'floor_pct', st.floor_pct, 'ceiling_pct', st.ceiling_pct);
end $$;

create or replace function public.market_list(p_kind text, p_ref text, p_qty int default 1, p_price bigint default null,
                                              p_open_offers boolean default false, p_to text default null, p_key text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid(); v_me profiles; st market_settings; t jsonb; r profiles; v_val bigint; v_min bigint; v_max bigint;
  v_to uuid; l market_listings; v_now timestamptz := bl_now();
begin
  perform bl_market_sweep();
  perform 1 from profiles where id = v_uid for update;
  v_me := bl_me();
  perform bl_market_guard(v_me);
  perform bl_assert_free(v_me);
  perform bl_market_seller_ok(v_me);
  select * into st from market_settings where kind = p_kind;
  if not found then
    raise exception 'That kind of thing can''t be sold here.' using errcode = 'P0001', hint = 'bad_kind';
  end if;
  if not st.enabled then
    raise exception '% are not on the market right now.', st.label using errcode = 'P0001', hint = 'kind_off';
  end if;
  if (select count(*) from market_listings where seller_id = v_uid and created_at > v_now - interval '24 hours') >= bl_market_num('market.daily_listing_cap', 10) then
    raise exception 'You have made % listings in the last 24 hours. That is the daily limit. Try again later.',
      bl_market_num('market.daily_listing_cap', 10)::int using errcode = 'P0001', hint = 'daily_cap';
  end if;
  if (select count(*) from market_listings where seller_id = v_uid and status = 'active') >= bl_market_num('market.max_active', 20) then
    raise exception 'You already have % listings open. Cancel one first.', bl_market_num('market.max_active', 20)::int
      using errcode = 'P0001', hint = 'max_active';
  end if;
  if p_price is null or p_price < 1 then
    raise exception 'Put a price, abeg.' using errcode = 'P0001', hint = 'bad_price';
  end if;
  if p_to is not null and btrim(p_to) <> '' then
    if not coalesce((select (value #>> '{}')::boolean from game_config where key = 'market.private_enabled'), true) then
      raise exception 'Selling to one friend is switched off.' using errcode = 'P0001', hint = 'private_off';
    end if;
    r := bl_find_player(p_to);
    if r.id = v_uid then
      raise exception 'You can''t sell to yourself.' using errcode = 'P0001', hint = 'self';
    end if;
    if not bl_yahoo_is_friend(v_uid, r.id) then
      raise exception '@% is not your friend yet. You can only sell privately to a friend.', r.username using errcode = 'P0001', hint = 'not_friend';
    end if;
    v_to := r.id;
  end if;
  t := bl_market_take(v_uid, p_kind, p_ref, coalesce(p_qty, 1), p_key);   -- escrow (raises when it can't be listed)
  v_val := (t->>'value')::bigint;
  v_min := greatest(bl_market_num('market.min_price', 100)::bigint, ceil(v_val * st.floor_pct / 100)::bigint);
  v_max := floor(v_val * st.ceiling_pct / 100)::bigint;
  if p_price < v_min or p_price > v_max then
    raise exception 'For this one the price must be between % and % (% to % of what it is worth).', bl_naira(v_min), bl_naira(v_max),
      st.floor_pct::text || '%', st.ceiling_pct::text || '%' using errcode = 'P0001', hint = 'price_range';
  end if;
  insert into market_listings (seller_id, kind, ref_id, qty, title, icon, price, value, open_to_offers, buyer_only, detail, created_at, expires_at)
  values (v_uid, p_kind, p_ref, (t->>'qty')::int, t->>'title', t->>'icon', p_price, v_val, coalesce(p_open_offers, false) and v_to is null, v_to,
          t->'detail', v_now, v_now + make_interval(days => bl_market_num('market.expire_days', 7)::int))
  returning * into l;
  return jsonb_build_object('message', l.title || ' is on the market for ' || bl_naira(l.price) || '. It is locked until it sells or you take it down.',
                            'listing', bl_market_card(l, v_uid));
end $$;

create or replace function public.market_cancel(p_listing bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); l market_listings;
begin
  perform bl_market_sweep();
  select * into l from market_listings where id = p_listing for update;
  if not found or l.seller_id <> v_uid then
    raise exception 'That listing no dey.' using errcode = 'P0001', hint = 'gone';
  end if;
  if l.status <> 'active' then
    raise exception 'That listing is already closed.' using errcode = 'P0001', hint = 'gone';
  end if;
  perform 1 from profiles where id = v_uid for update;
  perform bl_market_release(l.id, 'cancelled');
  return jsonb_build_object('message', l.title || ' is back with you.', 'listing', l.id);
end $$;

create or replace function public.market_browse(p_kind text default null, p_search text default null, p_min bigint default null,
                                                p_max bigint default null, p_sort text default 'new', p_limit int default 40,
                                                p_offset int default 0)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid(); v_q text := nullif(replace(replace(btrim(coalesce(p_search, '')), '%', ''), '_', ''), '');
  v_hide int := bl_market_num('market.report_hide_count', 3)::int; v_rows jsonb; v_total bigint; v_now timestamptz := bl_now();
begin
  perform bl_market_sweep();
  with f as (
    select l.id, l.price, l.value, l.created_at from market_listings l
     where l.status = 'active' and l.expires_at > v_now and l.seller_id <> v_uid
       and (l.buyer_only is null or l.buyer_only = v_uid)
       and (v_hide = 0 or l.reports < v_hide)
       and (p_kind is null or p_kind = '' or l.kind = p_kind)
       and (p_min is null or l.price >= p_min) and (p_max is null or l.price <= p_max)
       and (v_q is null or l.title ilike '%' || v_q || '%'
            or exists (select 1 from profiles p where p.id = l.seller_id and p.username ilike '%' || v_q || '%'))
  ), pg as (
    select f.id, row_number() over (order by
             case when p_sort = 'price_asc' then f.price end asc,
             case when p_sort = 'price_desc' then f.price end desc,
             case when p_sort = 'deal' then f.price * 1.0 / nullif(f.value, 0) end asc nulls last,
             f.created_at desc, f.id desc) as rn
      from f
  )
  select (select count(*) from f),
         coalesce((select jsonb_agg(bl_market_card(l, v_uid) order by x.rn)
                     from (select * from pg order by rn limit least(greatest(coalesce(p_limit, 40), 1), 100) offset greatest(coalesce(p_offset, 0), 0)) x
                     join market_listings l on l.id = x.id), '[]'::jsonb)
    into v_total, v_rows;
  return jsonb_build_object('rows', v_rows, 'total', v_total);
end $$;

create or replace function public.market_mine() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid();
begin
  perform bl_market_sweep();
  return jsonb_build_object(
    'listings', coalesce((select jsonb_agg(bl_market_card(l, v_uid) order by (l.status = 'active') desc, l.created_at desc)
                            from (select id from market_listings where seller_id = v_uid
                                   and (status = 'active' or closed_at > bl_now() - interval '3 days')
                                   order by (status = 'active') desc, created_at desc limit 60) x
                            join market_listings l on l.id = x.id), '[]'::jsonb),
    'offers_in', coalesce((select jsonb_agg(jsonb_build_object('id', o.id, 'listing', o.listing_id, 'title', l.title, 'icon', l.icon,
                              'price', l.price, 'amount', o.amount, 'buyer', p.username, 'expires_at', o.expires_at, 'created_at', o.created_at)
                              order by o.created_at desc)
                             from market_offers o join market_listings l on l.id = o.listing_id join profiles p on p.id = o.buyer_id
                            where l.seller_id = v_uid and o.status = 'pending' and l.status = 'active'), '[]'::jsonb),
    'offers_out', coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'listing', x.listing_id, 'title', x.title, 'icon', x.icon,
                              'price', x.price, 'amount', x.amount, 'status', x.status, 'seller', x.seller, 'expires_at', x.expires_at,
                              'created_at', x.created_at) order by x.created_at desc)
                              from (select o.id, o.listing_id, l.title, l.icon, l.price, o.amount, o.status, p.username as seller,
                                           o.expires_at, o.created_at
                                      from market_offers o join market_listings l on l.id = o.listing_id join profiles p on p.id = l.seller_id
                                     where o.buyer_id = v_uid and (o.status = 'pending' or o.closed_at > bl_now() - interval '3 days')
                                     order by o.created_at desc limit 40) x), '[]'::jsonb),
    'history', coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'title', t.title, 'price', t.price, 'fee', t.fee,
                              'side', case when t.seller_id = v_uid then 'sold' else 'bought' end,
                              'other', (select username from profiles where id = case when t.seller_id = v_uid then t.buyer_id else t.seller_id end),
                              'at', t.created_at) order by t.created_at desc)
                           from (select * from market_trades where seller_id = v_uid or buyer_id = v_uid order by created_at desc limit 20) t), '[]'::jsonb));
end $$;

create or replace function public.market_buy(p_listing bigint, p_expected bigint default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); l market_listings; v_me profiles; r jsonb;
begin
  perform bl_market_sweep();
  -- the listing lock comes first: two buyers queue here, and the second one finds it sold
  select * into l from market_listings where id = p_listing for update;
  if not found or l.status <> 'active' or l.expires_at <= bl_now() then
    raise exception 'Somebody don buy am, or the seller comot am.' using errcode = 'P0001', hint = 'gone';
  end if;
  if l.seller_id = v_uid then
    raise exception 'You no fit buy your own listing.' using errcode = 'P0001', hint = 'own_listing';
  end if;
  if l.buyer_only is not null and l.buyer_only <> v_uid then
    raise exception 'That one na private deal for somebody else.' using errcode = 'P0001', hint = 'private';
  end if;
  if p_expected is not null and p_expected <> l.price then
    raise exception 'The price don change to %. Look again.', bl_naira(l.price) using errcode = 'P0001', hint = 'price_changed';
  end if;
  perform 1 from profiles where id in (v_uid, l.seller_id) order by id for update;
  v_me := bl_me();
  perform bl_market_guard(v_me);
  r := bl_market_settle(l.id, v_uid, l.price, 'buy');
  return r || jsonb_build_object('message', 'You bought ' || l.title || ' for ' || bl_naira(l.price) || '. E don land with you.');
end $$;

create or replace function public.market_offer(p_listing bigint, p_amount bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid(); l market_listings; v_me profiles; v_min bigint; o market_offers; v_now timestamptz := bl_now();
  v_exp timestamptz;
begin
  perform bl_market_sweep();
  select * into l from market_listings where id = p_listing for update;
  if not found or l.status <> 'active' or l.expires_at <= v_now then
    raise exception 'Somebody don buy am, or the seller comot am.' using errcode = 'P0001', hint = 'gone';
  end if;
  if l.seller_id = v_uid then
    raise exception 'You no fit make an offer on your own listing.' using errcode = 'P0001', hint = 'own_listing';
  end if;
  if l.buyer_only is not null and l.buyer_only <> v_uid then
    raise exception 'That one na private deal for somebody else.' using errcode = 'P0001', hint = 'private';
  end if;
  if not l.open_to_offers then
    raise exception 'The seller is not taking offers on this one. Buy at the price or leave am.' using errcode = 'P0001', hint = 'no_offers';
  end if;
  perform 1 from profiles where id = v_uid for update;
  v_me := bl_me();
  perform bl_market_guard(v_me);
  v_min := ceil(l.price * bl_market_num('market.min_offer_pct', 50) / 100)::bigint;
  if p_amount is null or p_amount >= l.price then
    raise exception 'An offer must be below the price of %. To pay the full price, just buy am.', bl_naira(l.price) using errcode = 'P0001', hint = 'bad_offer';
  end if;
  if p_amount < v_min then
    raise exception 'That offer is too low. The lowest you can offer is % (% of the price).', bl_naira(v_min),
      bl_market_num('market.min_offer_pct', 50)::int::text || '%' using errcode = 'P0001', hint = 'bad_offer';
  end if;
  if v_me.cash + greatest(v_me.bank, 0) < p_amount then
    raise exception 'You don''t have % yet. Your bank and cash together are %.', bl_naira(p_amount), bl_naira(v_me.cash + greatest(v_me.bank, 0))
      using errcode = 'P0001', hint = 'not_enough_cash';
  end if;
  if not exists (select 1 from market_offers where listing_id = l.id and buyer_id = v_uid and status = 'pending')
     and (select count(*) from market_offers where buyer_id = v_uid and status = 'pending') >= bl_market_num('market.max_open_offers', 10) then
    raise exception 'You already have % offers waiting. Wait for answers or withdraw one.', bl_market_num('market.max_open_offers', 10)::int
      using errcode = 'P0001', hint = 'max_offers';
  end if;
  v_exp := least(l.expires_at, v_now + make_interval(hours => bl_market_num('market.offer_expire_hours', 24)::int));
  insert into market_offers (listing_id, buyer_id, amount, created_at, expires_at)
  values (l.id, v_uid, p_amount, v_now, v_exp)
  on conflict (listing_id, buyer_id) where status = 'pending'
  do update set amount = excluded.amount, expires_at = excluded.expires_at, created_at = excluded.created_at
  returning * into o;
  perform bl_event(l.seller_id, 'market_offer', '@' || v_me.username || ' wants your ' || l.title || ' for ' || bl_naira(p_amount),
    'Asking ' || bl_naira(l.price) || '. Open Benin Market, then My listings, to accept or decline.',
    jsonb_build_object('listing', l.id, 'offer', o.id, 'amount', p_amount, 'buyer', v_me.username));
  perform bl_push_enqueue(l.seller_id, 'money', 'market_offer', '@' || v_me.username || ' wants your ' || l.title || ' for ' || bl_naira(p_amount),
    'You are asking ' || bl_naira(l.price) || '. Tap to accept or decline.', '/play?go=market', v_uid);
  return jsonb_build_object('message', 'Offer of ' || bl_naira(p_amount) || ' sent to @' || (select username from profiles where id = l.seller_id) || '.',
                            'offer', o.id, 'expires_at', o.expires_at);
end $$;

create or replace function public.market_offer_respond(p_offer bigint, p_accept boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid(); v_lid bigint; l market_listings; o market_offers; v_me profiles; b profiles; r jsonb; v_now timestamptz := bl_now();
begin
  perform bl_market_sweep();
  select listing_id into v_lid from market_offers where id = p_offer;
  if v_lid is null then
    raise exception 'That offer no dey.' using errcode = 'P0001', hint = 'gone';
  end if;
  select * into l from market_listings where id = v_lid for update;      -- listing first, like buying
  select * into o from market_offers where id = p_offer for update;
  if l.seller_id <> v_uid then
    raise exception 'That offer is not for you.' using errcode = 'P0001', hint = 'not_yours';
  end if;
  if o.status <> 'pending' or o.expires_at <= v_now or l.status <> 'active' then
    raise exception 'That offer don close or expire.' using errcode = 'P0001', hint = 'gone';
  end if;
  if not coalesce(p_accept, false) then
    update market_offers set status = 'declined', closed_at = v_now where id = o.id;
    perform bl_event(o.buyer_id, 'market_offer_declined', '@' || (select username from profiles where id = v_uid) || ' declined your offer',
      'Your ' || bl_naira(o.amount) || ' offer for ' || l.title || ' was not accepted. You can still buy at ' || bl_naira(l.price) || '.',
      jsonb_build_object('listing', l.id, 'amount', o.amount));
    return jsonb_build_object('message', 'Offer declined.', 'accepted', false);
  end if;
  perform 1 from profiles where id in (v_uid, o.buyer_id) order by id for update;
  v_me := bl_me();
  perform bl_market_guard(v_me);
  select * into b from profiles where id = o.buyer_id;
  if b.banned or b.cash + greatest(b.bank, 0) < o.amount then
    update market_offers set status = 'cancelled', closed_at = v_now where id = o.id;
    return jsonb_build_object('message', '@' || b.username || ' no longer has ' || bl_naira(o.amount) || ', so the offer is cancelled. Your listing is still open.',
                              'accepted', false, 'failed', true);
  end if;
  r := bl_market_settle(l.id, o.buyer_id, o.amount, 'offer', o.id);
  update market_offers set status = 'accepted', closed_at = v_now where id = o.id;
  return r || jsonb_build_object('accepted', true,
    'message', 'Sold ' || l.title || ' to @' || b.username || ' for ' || bl_naira(o.amount) || '. You get ' || bl_naira((r->>'net')::bigint) || ' after the market fee.');
end $$;

create or replace function public.market_offer_cancel(p_offer bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); n int;
begin
  update market_offers set status = 'cancelled', closed_at = bl_now() where id = p_offer and buyer_id = v_uid and status = 'pending';
  get diagnostics n = row_count;
  if n = 0 then
    raise exception 'That offer don close already.' using errcode = 'P0001', hint = 'gone';
  end if;
  return jsonb_build_object('message', 'Offer withdrawn.');
end $$;

create or replace function public.market_report(p_listing bigint, p_reason text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); l market_listings; n int;
begin
  select * into l from market_listings where id = p_listing;
  if not found or l.status <> 'active' then
    raise exception 'That listing no dey again.' using errcode = 'P0001', hint = 'gone';
  end if;
  if l.seller_id = v_uid then
    raise exception 'You no fit report your own listing.' using errcode = 'P0001', hint = 'own_listing';
  end if;
  insert into market_reports (listing_id, reporter_id, reason, created_at)
  values (l.id, v_uid, left(btrim(regexp_replace(coalesce(p_reason, ''), '[[:cntrl:]]+', ' ', 'g')), 200), bl_now())
  on conflict (listing_id, reporter_id) do nothing;
  select count(*) into n from market_reports where listing_id = l.id;
  update market_listings set reports = n where id = l.id;
  return jsonb_build_object('message', 'Thanks. We don note am, and the admins go look am.', 'reports', n);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 6. Admin RPCs
-- ---------------------------------------------------------------------------------------------
create or replace function public.admin_market_overview(p_limit int default 100) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_lim int := least(greatest(coalesce(p_limit, 100), 1), 300);
begin
  perform bl_admin_guard();
  perform bl_market_sweep();
  return jsonb_build_object(
    'stats', jsonb_build_object(
      'active', (select count(*) from market_listings where status = 'active'),
      'sold_7d', (select count(*) from market_trades where created_at > bl_now() - interval '7 days'),
      'volume_7d', (select coalesce(sum(price), 0) from market_trades where created_at > bl_now() - interval '7 days'),
      'fees_7d', (select coalesce(sum(fee), 0) from market_trades where created_at > bl_now() - interval '7 days'),
      'flagged_7d', (select count(*) from market_trades where created_at > bl_now() - interval '7 days' and cardinality(flags) > 0),
      'reported', (select count(*) from market_listings where status = 'active' and reports > 0)),
    'live', coalesce((select jsonb_agg(jsonb_build_object('id', l.id, 'kind', l.kind, 'title', l.title, 'icon', l.icon, 'qty', l.qty,
                          'price', l.price, 'value', l.value, 'pct', case when l.value > 0 then round(l.price * 100.0 / l.value) end,
                          'seller', p.username, 'seller_id', l.seller_id, 'open_to_offers', l.open_to_offers,
                          'private_to', (select username from profiles where id = l.buyer_only),
                          'cond', bl_market_cond(l.kind, l.detail, l.qty), 'reports', l.reports,
                          'reasons', (select coalesce(jsonb_agg(r.reason) filter (where r.reason <> ''), '[]'::jsonb) from market_reports r where r.listing_id = l.id),
                          'created_at', l.created_at, 'expires_at', l.expires_at)
                          order by l.reports desc, l.created_at desc)
                        from (select * from market_listings where status = 'active' order by reports desc, created_at desc limit v_lim) l
                        join profiles p on p.id = l.seller_id), '[]'::jsonb),
    'trades', coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'title', t.title, 'kind', t.kind, 'price', t.price, 'fee', t.fee,
                          'value', t.value, 'pct', case when t.value > 0 then round(t.price * 100.0 / t.value) end, 'via', t.via,
                          'flags', t.flags, 'seller', s.username, 'buyer', b.username, 'created_at', t.created_at)
                          order by t.created_at desc)
                        from (select * from market_trades order by created_at desc limit v_lim) t
                        join profiles s on s.id = t.seller_id join profiles b on b.id = t.buyer_id), '[]'::jsonb));
end $$;

create or replace function public.admin_market_remove(p_listing bigint, p_reason text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); l market_listings; v_reason text := left(btrim(coalesce(p_reason, '')), 200);
begin
  select * into l from market_listings where id = p_listing for update;
  if not found or l.status <> 'active' then
    raise exception 'That listing is not open any more.' using errcode = 'P0001', hint = 'gone';
  end if;
  perform 1 from profiles where id = l.seller_id for update;
  perform bl_market_release(l.id, 'removed', v_reason, v_admin);
  insert into admin_audit (admin_id, action, target_user, data)
  values (v_admin, 'market_remove', l.seller_id,
          jsonb_build_object('listing', l.id, 'title', l.title, 'kind', l.kind, 'price', l.price, 'reason', v_reason));
  perform bl_event(l.seller_id, 'market_removed', 'Listing removed: ' || l.title,
    'An admin took it off the market and returned it to you.' || case when v_reason <> '' then ' Reason: ' || v_reason else '' end,
    jsonb_build_object('listing', l.id));
  return jsonb_build_object('message', l.title || ' removed and returned to the seller.', 'listing', l.id);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 7. Patches to live functions (guarded)
-- ---------------------------------------------------------------------------------------------
-- weekly top earners / challenge "earn": market money is never earnings
select pg_temp.bl_patch1('public.bl_earn_reasons()', 'market\_%',
  $m$btrim(x) <> 'challenge'$m$,
  $m$btrim(x) <> 'challenge' and btrim(x) not like 'market\_%'$m$);

-- ledger text
select pg_temp.bl_patch1('public.bl_ledger_label(text, jsonb)', 'when ''market_sale'' then',
  E'    when ''garage'' then return',
  E'    when ''market_sale'' then return ''Market sale: '' || coalesce(nullif(p_meta->>''title'', ''''), ''item'');\n    when ''market_buy'' then return ''Market buy: '' || coalesce(nullif(p_meta->>''title'', ''''), ''item'');\n    when ''market_fee'' then return ''Market fee'';\n    when ''garage'' then return');

-- admin Content editor: Market settings, and the tradeable flag on items and furniture
select pg_temp.bl_patch1('public.bl_admin_table_spec(text)', 'when ''market_settings'' then',
  E'    when ''house_upgrades'' then',
  E'    when ''market_settings'' then ''{"pk":["kind"],"insert":false,"order":"sort, kind",\n      "cols":{"enabled":"bool","fee_pct":"num","floor_pct":"num","ceiling_pct":"num"}}''\n    when ''house_upgrades'' then');
select pg_temp.bl_patch1('public.bl_admin_table_spec(text)', '"sellable":"bool","tradeable":"bool"',
  '"sellable":"bool","resale_pct":"num"',
  '"sellable":"bool","tradeable":"bool","resale_pct":"num"');
select pg_temp.bl_patch1('public.bl_admin_table_spec(text)', '"buyable":"bool","tradeable":"bool"',
  '"bonus":"obj","buyable":"bool"}}',
  '"bonus":"obj","buyable":"bool","tradeable":"bool"}}');

-- ---------------------------------------------------------------------------------------------
-- 8. Grants (private helpers revoked; RPCs for signed-in players only)
-- ---------------------------------------------------------------------------------------------
revoke all on function public.bl_market_num(text, numeric) from public, anon, authenticated;
revoke all on function public.bl_market_on() from public, anon, authenticated;
revoke all on function public.bl_market_guard(public.profiles) from public, anon, authenticated;
revoke all on function public.bl_market_seller_ok(public.profiles) from public, anon, authenticated;
revoke all on function public.bl_market_plate() from public, anon, authenticated;
revoke all on function public.bl_market_cond(text, jsonb, int) from public, anon, authenticated;
revoke all on function public.bl_market_take(uuid, text, text, int, text) from public, anon, authenticated;
revoke all on function public.bl_market_give(uuid, text, text, int, jsonb, bigint, boolean) from public, anon, authenticated;
revoke all on function public.bl_market_flags(uuid, uuid, bigint, bigint) from public, anon, authenticated;
revoke all on function public.bl_market_card(public.market_listings, uuid) from public, anon, authenticated;
revoke all on function public.bl_market_settle(bigint, uuid, bigint, text, bigint) from public, anon, authenticated;
revoke all on function public.bl_market_release(bigint, text, text, uuid) from public, anon, authenticated;
revoke all on function public.bl_market_sweep(int) from public, anon, authenticated;

revoke all on function public.market_info() from public, anon;
grant execute on function public.market_info() to authenticated, service_role;
revoke all on function public.market_quote(text, text, int, text) from public, anon;
grant execute on function public.market_quote(text, text, int, text) to authenticated, service_role;
revoke all on function public.market_list(text, text, int, bigint, boolean, text, text) from public, anon;
grant execute on function public.market_list(text, text, int, bigint, boolean, text, text) to authenticated, service_role;
revoke all on function public.market_cancel(bigint) from public, anon;
grant execute on function public.market_cancel(bigint) to authenticated, service_role;
revoke all on function public.market_browse(text, text, bigint, bigint, text, int, int) from public, anon;
grant execute on function public.market_browse(text, text, bigint, bigint, text, int, int) to authenticated, service_role;
revoke all on function public.market_mine() from public, anon;
grant execute on function public.market_mine() to authenticated, service_role;
revoke all on function public.market_buy(bigint, bigint) from public, anon;
grant execute on function public.market_buy(bigint, bigint) to authenticated, service_role;
revoke all on function public.market_offer(bigint, bigint) from public, anon;
grant execute on function public.market_offer(bigint, bigint) to authenticated, service_role;
revoke all on function public.market_offer_respond(bigint, boolean) from public, anon;
grant execute on function public.market_offer_respond(bigint, boolean) to authenticated, service_role;
revoke all on function public.market_offer_cancel(bigint) from public, anon;
grant execute on function public.market_offer_cancel(bigint) to authenticated, service_role;
revoke all on function public.market_report(bigint, text) from public, anon;
grant execute on function public.market_report(bigint, text) to authenticated, service_role;
revoke all on function public.admin_market_overview(int) from public, anon;
grant execute on function public.admin_market_overview(int) to authenticated, service_role;
revoke all on function public.admin_market_remove(bigint, text) from public, anon;
grant execute on function public.admin_market_remove(bigint, text) to authenticated, service_role;

notify pgrst, 'reload schema';
