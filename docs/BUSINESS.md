# Own a business (R10)

Players buy a real business on a fixed plot, run it, upgrade it and sell it. It earns every real hour, needs a little attention, and other
players can visit and spend there. It is the **active, ownable** version of the passive invest units in `docs/INVEST.md` (farms,
transport, POS), which are untouched.

Migration: `supabase/migrations/20261018000900_business.sql`. Tests: `supabase/tests/business_test.sql`.
Client: `src/api/business.ts`, `src/screens/game/phone/BusinessApp.tsx` (+ `BusinessApp.css`), `src/screens/game/BusinessStrip.tsx` (place card and map
sheet), map pins in `src/art/map/MapPins.tsx`. Admin: `src/admin/Business.tsx`, Players -> Businesses, Content -> Business types / Business plots,
Settings -> Business.

## How it works
1. **Buy.** Phone, Business, Buy a business. Pick a type, then a free plot in an allowed area, name it (3-28 letters, no rude words) and pay (bank first,
   then cash). The plot is gone for everybody (first come, first served). Builders need `setup_minutes` real minutes; income starts after that.
2. **Earn.** Each business rolls a base income inside its type's range when bought (naira per real 24 hours at level 1). It is multiplied by the level, by
   staff (+% each), by the owner's Business skill (`business.skill_pct_per_level`) and by stock and boost (below), minus running costs (rent, NEPA /
   diesel, staff wages, all per day). Takings never go below zero.
3. **Settle lazily, no cron.** `bl_biz_settle()` earns from the last settle up to now, one 24 h business day at a time, and runs on every read, collect and
   change. Opening the Business app settles all of your businesses.
4. **Cap.** Takings stop growing `business.cap_hours` (48) real hours after the last collect (or after setup ends). Collecting pays the takings into the
   **bank** (ledger `business_income`) and starts the clock again. Time past the cap is lost, so players have to log in.
5. **Stock.** Types with a restock cost need stock. A restock adds `business.stock_hours` (48 h) of stock (never more than `business.stock_max_hours`
   from now; cost = the type's restock cost x the level multiplier). While there is stock income is 100 %. When it runs out, income slides linearly down to
   `business.stock_floor_pct` (50 %) over `business.stock_decay_hours` (24 h). Types with restock cost 0 (PoS, event centre) never run out.
6. **Staff.** Hire NPC staff (up to the type's slots): a signing fee of `business.hire_fee_days` days of wage, then the wage every day. Each adds
   `staff_income_pct` to income and cuts the robbery and levy chances by `business.staff_event_cut_pct` (max 50 %). Staff can also steal.
7. **Owner shift.** Go to your own place and tap Work a shift (Business app, or the place card). It keeps the Sim busy `business.shift_seconds`, costs
   `business.shift_energy`, gives the type's `boost_pct` income for `business.shift_boost_hours`, halves staff theft and robbery chances while the boost
   lasts, and trains the Business skill (`skill_sources` row `activity:business_shift:business`). At most `business.shift_daily_cap` a Benin day.
8. **Events.** Once per full business day of earning, every event rolls with `bl_crime_roll` (tests force it with `bl.test_rand`):
   robbery (takes `robbery_loss_pct` of the takings; **insurance** covers `insurance_cover_pct` of the loss), NEPA outage (`outage_loss_pct` of a day's
   income), task force / council levy (`levy_loss_pct` of a day), staff theft (only with staff, `theft_loss_pct` of a day) and a great day
   (`goodday_bonus_pct` of a day). Each one writes the events log (`business_log`, kinds `ev_*`) and sends the owner an alert event (toast).
   A type can override chance and size in Content -> Business types -> Events (the Event centre has a 35 % great-day chance, the filling station a higher
   robbery loss). No events roll past the cap.
9. **Upgrades.** Each level has a cost and an income multiplier (Content -> Business types -> Levels). The place shows the level on the map pin and the
   place blurb changes with it. Upgrades count as invested.
10. **Insurance.** `business_insure`: `business.insurance_cost_pct` of the buy price for `business.insurance_days` days.

## Plots and places
- `business_plots` is a table of fixed slots (seeded: 18 across Ring Road, Uselu, Ugbowo, Sapele Rd, Airport Rd, GRA, New Benin and Ikpoba Hill). Each
  plot IS a row of `locations` with the same id (`biz_...`): hidden (`active = false`) until somebody owns it, so a free plot is never on the map and
  the map does not fill up. Admin adds slots in Content -> Business plots; a trigger creates the place (x, y 0-1000, keep 34 units from other pins).
  A plot can carry a price multiplier (GRA is dearer) and an allowed-types list.
- When a plot is owned, `bl_biz_loc_sync` sets the place's name, interior scene (from the type), `active`, and `biz_id / biz_owner / biz_level / biz_type`
  columns. The map shows a small pin with a gold rim and the level, labelled "Name · @owner" (2D pin and the 3D city pill). The map sheet and the place card
  say "Owned by @x". The map re-reads places when it opens and they are over a minute old.
- The interior is built from the existing place parts of the type's scene (market, buka, lounge, salon, pos, street, motorpark, hotel): no new 3D art.
- **Visitors.** Another player who spends at the place (activity cards and shop items) pays the normal price; `business.visit_cut_pct` (30 %) of it goes to
  the owner's bank as ledger `business_income` (meta label "Customer at ...: @x"). Spending at your own place pays no cut. The shelf: an owned business sells
  every item that a plain place of the same scene sells (`bl_biz_sells`). If the owner's row is busy the cut waits in the takings (no deadlocks).
  `do_activity`, `shop_buy` and `place_interior` are patched with guarded replaces.

## Types seeded
| Type | Price | Income a day | Needs |
|---|---|---|---|
| Provision shop / mini-mart | ₦600k | ₦12k-18k | none |
| Buka / chop house | ₦900k | ₦16k-24k | none |
| Barbing and hair salon | ₦700k | ₦12k-19k | none |
| Car wash | ₦1M | ₦14k-22k | Business level 2 |
| PoS and business centre | ₦1.2M | ₦18k-27k | Business level 2 |
| Beer parlour / bar | ₦1.8M | ₦28k-42k | Business level 3 |
| Chemist shop | ₦2.8M | ₦30k-45k | Business level 3 + Accounting or Business Management |
| Filling station | ₦9M | ₦90k-130k | Business level 4 + Business Management |
| Event centre | ₦18M | ₦160k-260k | Business level 6 + Business Management |
Plot multipliers apply (0.9 outskirts to 1.35 GRA). Check Content -> Business types for the live numbers.

## Selling
- **To the system:** `business_sell` pays the takings plus `business.sell_back_pct` (60 %) of what the owner **invested** (buy price + upgrades; a gift invested
  nothing). Ledger `business_sell`. The plot goes back on sale.
- **On the Market (R9):** kind `business` in `market_settings` (fee 8 %, price band 50-250 % of value, editable in Content -> Market settings). Value = type price x
  plot multiplier + all upgrades. Listing escrows the business (`listed`: it earns nothing and nothing can be changed), pays out the takings first, and the
  buyer must be under `business.max_owned` and meet the type's requirement (else the whole purchase is refused and nothing moves). The buyer's `invested` is the price paid.
  Cancelling or expiry gives it back. The market RPCs `bl_market_take`, `bl_market_give` and `bl_market_cond` are patched.

## Admin
- **Content -> Business types** (everything above, including levels and per-type events), **Content -> Business plots** (add and switch off slots).
- **Business** tab: every owned business with owner, takings, level and source (buy / admin / market); Remove (pays the takings, tells the owner, audited as `business_remove`).
- **Players -> player -> Businesses**: list, Grant (free, instant, audited `business_grant`, invested 0) and Remove.
- **Settings -> Business**: all the keys below.

## Money and the ledger
| Reason | Counts as earned (weekly top earners, challenge "earn") |
|---|---|
| `business_income` (takings, customer cuts) | **yes** (added to `leaderboard.earn_reasons` once, by the migration) |
| `business_buy`, `business_upgrade`, `business_stock`, `business_hire`, `business_insure` | no (spending) |
| `business_sell` | no |
Market money stays `market_*`.

## Push
"Takings ready" (category money, link `/play?go=business`, kind `business_ready`) is queued for `business.push_hours` (36 h) after the last collect, one per player,
at most one per Benin day (dedupe key by date). Every collect, purchase or sale moves or cancels it. The push row is created with a future `created_at` so the
hourly "too old" sweep leaves it alone.

## Settings (Settings -> Business)
`business.enabled`, `max_owned` (3), `cap_hours` (48), `stock_hours` (48), `stock_max_hours` (168), `stock_decay_hours` (24), `stock_floor_pct` (50),
`skill_pct_per_level` (1.5), `hire_fee_days` (2), `insurance_cost_pct` (3), `insurance_days` (7), `insurance_cover_pct` (80), `shift_seconds` (60), `shift_energy` (12),
`shift_boost_hours` (8), `shift_daily_cap` (6), `visit_cut_pct` (30), `sell_back_pct` (60), `staff_event_cut_pct` (10), event chances per business day `robbery_pct` (6),
`outage_pct` (14), `levy_pct` (8), `goodday_pct` (10), `theft_pct` (8) and their sizes `robbery_loss_pct` (40), `outage_loss_pct` (50), `levy_loss_pct` (35),
`goodday_bonus_pct` (60), `theft_loss_pct` (20), and `push_hours` (36). `business.enabled = false` stops buying, upgrades, hiring, restocking, insuring and shifts;
collecting, selling and firing still work.

## Security
Tables have RLS; players can read only their own businesses and log, the type and plot catalogues are readable, nothing is writable by clients. Every RPC is
`security definer` with a fixed search path, granted to `authenticated` only (admin RPCs check `bl_admin_guard`). Private `bl_biz_*` helpers are revoked from anon
and authenticated. A business row that disappears any other way (account deleted) hides its place again (trigger).

## Defaults the owner should know
Three businesses each, takings stop after 48 hours, shelves last 48 hours and income falls to 50 % without a restock, owners get 30 % of visitor spending,
sell-back is 60 % of what you invested, the Market fee on a business is 8 %, a robbery is a 6 % chance per business day (insurance covers 80 %), NEPA 14 %,
levy 8 %, great day 10 %, staff theft 8 %. Incomes are tuned for a payback of roughly 40 to 100 real days; the E3 economy audit is the place to retune them.
Not built: an interior that changes by level (the pin, the blurb and income change), customers that are NPCs (only player visits pay the owner), renaming a business,
per-staff names saved (names are derived from the business id), and deleting plots (switch them off).


## E3 retune (migration `20261019000100_economy_balance.sql`, docs/BALANCE.md)
The "payback of roughly 40 to 100 real days" line above was wrong for five types: restock (per 48 h) cost 60 to 127 % of the income of the same 48 h, so a stocked Beer parlour made ₦0 a day, a stocked Chemist lost ₦3k and a stocked Filling station lost ₦47k a day (the best play was never to restock; payback 120 to 237 days). Now:

| Type | Restock before | Restock now | Income | Payback with stock |
|---|---|---|---|---|
| Provision shop | 18k | **6k** | 12-18k | 171 -> **63 days** |
| Buka | 25k | **8k** | 16-24k | 257 -> **75** |
| Beer parlour | 55k | **14k** | 28-42k | never -> **88** |
| Chemist | 70k | **15k** | 30-45k -> **36-54k** | never -> **88** |
| Filling station | 280k | **44k** | 90-130k -> **100-145k** | never -> **108** |
Salon, Car wash, PoS centre and Event centre were already 67-98 days and are unchanged.

- Market: a business bought on the Market now counts as invested at most its catalogue value (`bl_biz_value`), not the price paid. Before, list at 250 % of value, an alt buys, sells to the system for 60 % of what it paid (150 % of value): +30 % of the value per lap. Now a lap loses 40 % of the value plus the 8 % fee.
- The visitor cut (30 %) is not a loop: the visitor pays 100 %, the owner gets 30 %, 70 % leaves the economy.
- `business_test` pins the old restock costs and incomes.
