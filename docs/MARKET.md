# Benin Market: player-to-player trading (R9)

Players sell items, furniture, cars and land plots to each other. The phone has a **Market** app (Browse, My listings,
My offers). Selling starts next to every "Sell to shop": the Bag, Phone > Cars and the garage, Buy > Arrange > My
items, and Bank > Invest (land). Houses are rented, so there is no house trading.

Migration: `supabase/migrations/20261018000800_market.sql`. Tests: `supabase/tests/market_test.sql`.
Client: `src/api/market.ts`, `src/screens/game/phone/MarketApp.tsx`, `src/screens/game/SellToPlayers.tsx`,
`src/screens/game/market.css`. Admin: `src/admin/Market.tsx` plus Content > Market settings and Settings > Benin Market.

## How a trade works
1. **List.** `market_list(kind, ref, qty, price, open_to_offers, to, key)`. The thing is taken out of the seller's
   hands at once (escrow): out of the Bag, the garage, the house or the land holdings. While listed it cannot be
   used, placed or driven.
2. **Buy.** `market_buy(listing, expected_price)`. One transaction: the listing row is locked first
   (`select ... for update`), then both players, then money and the thing move together. Two buyers queue on the lock
   and the second one is told it is gone (verified with two real database sessions, not only in the test).
3. **Money.** The buyer pays from the **bank first, then cash**. The seller is paid the full price into the **bank**
   and the market fee is taken from it. Ledger reasons: `market_buy` (buyer, one row per account used),
   `market_sale` (seller, +price), `market_fee` (seller, -fee).
4. **Fee.** Per kind in `market_settings.fee_pct`, default 5%, rounded down. It is a money sink.
5. **Receipt.** The buyer gets a normal receipt (`kind: market`) when the price reaches `receipts.min_amount`.
6. **Ending without a sale.** The seller can take it down (`market_cancel`), an admin can remove it
   (`admin_market_remove`), or it expires after `market.expire_days`. The thing goes back, with its condition.

Expiry is **lazy**: there is no cron in the database, so every market RPC first runs `bl_market_sweep()`
(returns expired listings, expires old offers, skips rows other transactions are working on, never lets one bad row
block the rest). A listing that nobody opens the market for stays locked until the next market call by anyone. A call that
raises rolls its own sweep back (the next call does it).

## What can be sold
| Kind | What | Notes |
|---|---|---|
| `item` | An inventory item, any quantity you hold | Needs `items.tradeable`. Whole stack price. Cars are `car`, not `item`. |
| `car` | One car from the garage | Keeps its **plate** and **wear** (see below). |
| `furniture` | One bought copy of a furniture piece | Needs `furniture.tradeable`. **Placed pieces are refused** ("pick it up first"), and so are pieces that came with the house. Arrives in the buyer's My items (stored). The buyer's max copies still applies. |
| `land` | N plots of one area | The seller's pending land deal (levy to pay or walk away from) must be finished first. Cost basis moves with the plots: the seller keeps the rest, the buyer's cost basis is the price paid. A cancelled or expired listing gives the plots back at their old cost. |

`items.tradeable` is added by the migration: true by default, set to **false** for food, drink, health, hygiene,
offering and phone-credit items and for anything with `sellable = false` (quest or starter-locked), except cars, which stay
true (their `sellable` flag only turns off the shop buy-back). Furniture is true for everything. The wardrobe (clothes) is
**not** tradeable in this release: clothes are tied to saved outfits.

### Cars: plate and wear
The game had no per-car state, so the migration adds `player_cars (user_id, item_id, plate, wear)`, created lazily the first
time a car is listed. Plates look like `BEN-123-AB` and are unique. Wear is the hustle wear (`hustle_players.car_wear`) of the
car you drive for hustles (your most valuable car); other cars carry the wear stored in `player_cars`. On listing the seller's
hustle wear resets to 0 (the car leaves with it). When the buyer receives it and it becomes their hustle car, their wear is
raised to the car's wear. The plate is shown on the listing card and the same plate comes back if it is re-listed or cancelled.

## Safety rules
- **Price band.** A listing price must be between `floor_pct` and `ceiling_pct` of the catalogue value, per kind in
  `market_settings` (default 20% to 300%). Catalogue value: items and cars `items.price` (x quantity), furniture
  `furniture.price`, land the **current** plot price x plots. `market.min_price` is a global minimum (default ₦100).
- **Trust rule.** Same wait as bank transfers: an account younger than `bank.transfer_min_account_real_minutes`
  (default 24 real hours) **cannot sell** to others, unless an admin marked it trusted (`profiles.transfer_trusted`). New
  accounts can still buy. **IP and device sharing are not tracked anywhere in the game**, so there is no IP/device rule and the
  admin trade log has no same-IP flag. If tracking is added later, `bl_market_flags` and `bl_market_settle` are the places.
- **Daily cap.** `market.daily_listing_cap` new listings per rolling 24 real hours (default 10) and `market.max_active`
  open at once (default 20).
- **Not your own.** You cannot buy or make an offer on your own listing.
- **Not when busy.** Listing needs a free player (not travelling, busy, in hospital or in a cell). A jailed player has no
  phone for any market action.
- **Report.** `market_report(listing, reason)` (one per player per listing). At `market.report_hide_count` reports (default 3) the
  listing drops out of Browse; Admin still sees it.

## Offers
`market_offer(listing, amount)` on a listing marked "open to offers": below the price, not under `market.min_offer_pct`
(default 50%), and the buyer must hold the money (bank + cash) at offer time. One pending offer per buyer per listing (a new
offer replaces it), up to `market.max_open_offers` waiting. The seller gets an alert and a push ("@x wants your Benz for ₦4.5M").
`market_offer_respond(offer, accept)`: decline tells the buyer; accept runs the purchase at the offer price **if the buyer still
has the money**, otherwise the offer is cancelled and the listing stays open. Offers expire after `market.offer_expire_hours`
(never later than the listing); a sale closes the other offers.

## Private listing to a friend
`market_list(..., p_to => '@friend')`: only an accepted friend (not blocked) can see or buy it. No offers on private listings.
Switch: `market.private_enabled`.

## Alerts and push
- Events (the Alerts app, and a toast while playing): `market_sold`, `market_offer`, `market_offer_accepted`,
  `market_offer_declined`, `market_expired`, `market_removed`. When you pressed the button yourself the event is marked
  `quiet` (kept in Alerts, no second toast).
- Push (category `money`, deep link `/play?go=market`): a sale, an offer, an accepted offer.

## Admin
- **Content > Market settings:** per kind on/off, fee %, price floor %, ceiling %. **Content > Items / Furniture:** the
  "Players can sell it to players" switch.
- **Settings > Benin Market:** master switch, daily cap, open cap, listing and offer lifetime, lowest offer, open offers,
  report hide count, private listings, and the suspicious-trade thresholds.
- **Market tab** (`/admin/market`): live listings (reported ones first; Remove returns the thing to the seller, writes
  `admin_audit` action `market_remove` with the reason, and alerts the seller), and the recent trades log with flags:
  `far_low` / `far_high` (price outside `market.flag_low_pct` / `market.flag_high_pct` of the value), `flip` (the same two players
  traded the other way round inside `market.flip_hours`), `repeat_pair` (three or more trades between them in that window),
  `new_account` (either side still inside the new-account wait). Filter "Flagged only".

## Money, leaderboards and the ledger
- Ledger labels: "Market sale: <thing>", "Market buy: <thing>", "Market fee".
- Weekly top earners and the challenge "earn" counter use `bl_earn_reasons()`. The migration patches it so any reason starting
  with `market_` is **never** counted, even if an admin types it into `leaderboard.earn_reasons`.
- The admin Overview "created / destroyed" money table lists market rows like it lists transfers (buy = out, sale = in); the fee
  is the only real money sink.

## Security
Tables have RLS; players can only `select` their own listings, offers and cars, and nothing can be written by clients. Trades and
reports are admin-only through `admin_market_overview`. Every market RPC is `security definer` with a fixed search path, granted to
`authenticated` only. Private `bl_market_*` helpers are revoked from anon and authenticated.

## Defaults the owner should know
5% fee, 20% to 300% price band, 10 new listings a day, 20 open, 7-day listings, 24-hour offers, lowest offer 50%, 3 reports hide a
listing, flag a trade under 50% or over 200% of value, new accounts wait 24 real hours before they can sell. All editable as
above. Not built: IP/device checks (nothing tracks them), selling clothes, counter-offers, editing a price (take it down and list again).


## E3 retune (migration `20261019000100_economy_balance.sql`, docs/BALANCE.md)
A business bought here counts as invested at most its catalogue value, not the price paid (closes a loop worth +30 % of the value per lap; see docs/BUSINESS.md). The fees and price bands are unchanged. The Market stays the one way to move money between accounts without the ₦200k a day transfer limit, at a 5 to 8 % cost: kept on purpose, watch `admin_market_overview` for repeated pairs.
