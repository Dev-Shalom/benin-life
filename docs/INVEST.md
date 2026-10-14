# Invest & Save (I1)

Bank app, phone tabs **Save** and **Invest**. Spec: `docs/ECONOMY_PLAN.md` section 2 (owner-approved).
Server: `supabase/migrations/20261014000200_invest_save.sql` (idempotent, seeds `on conflict do nothing`). Tests: `supabase/tests/invest_save_test.sql`.
Client: `src/api/invest.ts`, `src/screens/game/phone/invest/{InvestApp.tsx,Spark.tsx,useInvest.ts}`, `src/styles/invest.css`, tabs wired in `phone/BankApp.tsx`.

## Rules
- Every naira moves from / to the player's **bank** balance (never cash). Short of bank money: the UI says "deposit cash first" (Where tab) and the server refuses with hint `not_enough_bank`.
- Amounts are whole naira (bigint); each product has min / max per purchase; `bl_me()` locks the profile row (FOR UPDATE) for every RPC, holdings rows are locked too, and money only moves through `bl_add_money` (no negative balances). Jailed players can't use it. `invest.enabled = false` stops buying, selling still works.
- **Time**: 1 game year = `invest.year_days` real days (30). One *invest day* = year / 365 (about 1.97 real hours at 30). Terms, cycles and daily income are in invest days. Interest is simple, accrued continuously: `floor(amount * rate% * seconds / (year_days*86400))`, computed lazily from timestamps (no jobs). Risk events for transport / POS / flats are rolled lazily on the next visit, once per invest day since last visit (cap `invest.event_days_cap` days; older days pay income with no rolls).
- Prices: deterministic seeded random walk per market per step (hash of market id + step), stored once in `invest_prices` (extended lazily under an advisory lock), so all players see identical prices. `log return = ln(1+drift)*step/year + vol*z - vol^2/2`, z about N(0,1) from three hashed uniforms. Land / bond / property index add a smooth bounded swing (`swing_pct`, value noise). Admin `price_mult` rescales a market instantly.

## Products (Content → Invest & Save products; Invest markets)
| Product | Rate / rule |
|---|---|
| Bronze Savings | 10% per game year, withdraw any time (min ₦500) |
| SafeLock 7 / 30 / 90 d | 15 / 18 / 22%; locked, break early = lose ALL interest, principal back |
| Money market fund | 18%, any time |
| Fixed deposit 30 d / 90 d | 16 / 19%; early exit loses interest |
| Treasury bill 91 / 182 / 364 d | 16 / 17.75 / 21.85%; early sell: 2% of (principal+accrued) fee, keep accrued interest; none at maturity (min ₦50k) |
| FGN bond | 19% coupon on face; bought / sold at the market price (±3% wobble), 0.5% sale fee |
| NGX stocks (Okomu Oil, Presco, Dangote Cement, MTN Nigeria, GTCO, Zenith Bank) | hourly steps, drift 10-16%/yr, vol 0.8-1.3% per hour; whole shares; broker fee 0.5% each way (own ledger row); dividends (0.25% chance per hourly step, 2.5-3.5% of price) paid to holders into the bank |
| Farms per unit: poultry ₦150k / fish pond ₦400k / cassava ₦250k / plantain ₦300k | cycle 150 / 180 / 270 / 240 invest days; payout gain rolled at purchase (25-35 / 28-38 / 30-40 / 25-35%); at harvest each event rolls: bird flu 10% (-60%), flood 8-10% (-40..50%), theft 5-6% (-25..30%) of the payout, so harvests can be below cost; collect, or collect + re-invest (profit paid out, capital stays, new cycle), or sell back early at 80% (loses the cycle) |
| Transport: keke ₦2.4M (₦3,800/day), okada ₦900k (₦1,500/day), Sienna ₦9.5M (₦14,000/day) | daily income accrues, collect any time; daily breakdown 1.2-2% costs 3-3.5% of price (accident 10%), checkpoint / go-slow lose a day's income; resale 88% of cost less 12%/yr depreciation (floor 35%) |
| POS stand ₦450k (₦600/day), POS shop ₦1.2M (₦1,700/day) | fraud 0.5%/day loses 8% of price, network-down 3%/day loses the day's income; resale 85% |
| Land by area: GRA ₦12M, Ugbowo ₦6M, Sapele Rd ₦4.5M, Airport Rd ₦3.5M, Ikpoba Hill ₦2.5M, Okhoro ₦1.8M, Ekenwan ₦1.2M per plot | 6 h steps; growth 22 / 28 / 24 / 30 / 26 / 33 / 35% per game year with swings; unlimited plots (max 100 per deal); buy = plot price + agent fee (5-7%) + community settlement (4 / 7 / 9 / 10 / 12 / 15 / 18%) + chance of a development levy (8 / 15 / 18 / 20 / 25 / 30 / 35% chance, 3-15% of the subtotal); sell any time at current price minus agent fee |
| Rental flats: room & parlour ₦6M (₦3,200/day), 2-bed ₦18M (₦9,500/day), duplex ₦45M (₦24,000/day) | price follows the property index; vacancy spell (0.45%/day, 30 invest days without rent), repairs (0.25%/day, 4% of price); sale at market minus 3% agent fee |
| Crypto: BTC (₦150M, drift 55%, vol 0.55% per 15 min), USDT (₦1,550, drift 6%) | fractional to 8 decimals; fee 0.8% / 0.5% |

## Land deal flow
`invest_land_buy(area, plots)`: quote is locked, affordability checked (plot + agent + community), then the levy chance is rolled (`bl_rand`). No levy: deal closes at once (4 ledger rows). Levy: returns `status:'levy'` with the extra amount, **nothing charged**; `invest_land_levy(deal, true)` pays and closes, `false` walks away (no cost; `invest.land_walk_cooldown_seconds` wait before the next deal, deal expires after `invest.land_deal_minutes`). One open deal per player.

## Ledger labels and receipts
Reasons `invest_buy` / `invest_sell` / `invest_fee` / `invest_income`, label in `meta.label`: "Save: Bronze Savings", "Invest: Treasury bill 91 days", "Invest: NGX Okomu Oil ×8", "Invest: broker fee · Okomu Oil", "Dividend: Okomu Oil", "Harvest: poultry unit", "Income: Keke (tricycle)", "Land: 2 plots · Ugbowo", "Land: agent fee · Ugbowo", "Land: community settlement · Ugbowo", "Land: development levy · Ugbowo", "Land: sold 1 plot · Ugbowo", "Land: agent fee (sale) · Ugbowo". Buys of at least `receipts.min_amount` issue a receipt (kind `invest`) through `bl_receipt_issue`.

## RPCs (all authenticated only; anon refused)
`invest_overview()` (settles dividends / events, returns cash, bank, summary {invested, value, unrealized, realized, profit, today}, products, markets with sparklines, positions, log), `invest_market_series(market, points, hours)`, `invest_buy(product, amount_or_units)`, `invest_withdraw(position, amount?)`, `invest_collect(position, reinvest?)`, `invest_market_buy(market, qty)`, `invest_market_sell(market, qty?)`, `invest_land_quote / buy / levy / sell`.
Portfolio numbers: `value` = mark to model per position (`bl_inv_calc`, also used for exits so the screen and the payout agree); total profit = value - invested + realised (sum of `invest_log.profit`); today's change = per-position change over the last real 24 h (approximate: realised events are not re-applied).

## Admin keys
Settings → "Invest & Save": `invest.enabled`, `invest.year_days`, `invest.land_deal_minutes`, `invest.land_walk_cooldown_seconds`, `invest.event_days_cap`, `invest.spark_points`.
Content → "Invest & Save products" (`invest_products`: rate, term, exit fee, forfeits interest, unit price, min / max, cycle, gain range, income per day, resale %, depreciation, floor, `events` JSON `{"id":{"label","chance_pct","loss_of":"cycle|unit|income|vacancy","loss_pct","span_days"}}`, active) and "Invest markets" (`invest_markets`: price multiplier, drift, volatility, swing, fee %, community %, levy chance / min / max %, dividend chance / yield, min / max qty, active; markets can't be added from admin). Edits apply to new purchases (lock rates are stored at purchase).

## Not included
Rich list / leaderboards still count cash + bank only (not invested value). Price history is never pruned.
