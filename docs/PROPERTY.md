# Own your home

Owner request: go back to a house you left, buy houses, build a house (very expensive, real prices by area), and buy houses to let to other players.
Migrations `20261103000100_property.sql` (everything) and `20261103000200_property_links.sql` (foreign keys to profiles, retry loop). Test `supabase/tests/property_test.sql`.
Client: Phone -> Houses, tabs **Home / Rent / Buy / Build / My properties / Past homes** (`src/screens/game/phone/HousesApp.tsx`, `phone/property/*`). Admin: `/admin/property`, Content (Property areas, Home types, Home prices, Build designs), Settings -> Own your home.

## Past homes (go back)
- Moving out of a rented home keeps it in **Past homes** for `house.return_days` (30 real days).
- **Upgrades, the garage and where the furniture stood stay with the house** (a "stash"). Moving back costs the normal move-in fee (4 weeks of rent) and brings them all back.
- Why this rule: it is the cleanest. The upgrade money is never lost or double-counted. The old "50 % back when you move" now happens only when the slot **expires** or the player taps **Give up**: the upgrades are paid at `house.upgrade_resale_pct` (50 %), builds in progress in full. Builders keep working in a past home.
- Players who moved out before this update got their old homes back as past homes (30 days from the update).
- **Owned homes are never lost**: their stash lives on the property.

## Buying
- Each area has a price per home type (Content -> Home prices). Buy = price + agent fee 3 % + legal fee 1.5 % (at least N20,000), both sinks, with a receipt.
- An owned home pays **no rent**, but still pays the weekly **house bill** (the bill of the same home type) and **ground rent** (0.1 % of its value a week).
- A player can own up to `property.max_owned` (20) homes and **live in any one** ("Live here": free). The home you leave becomes a past home (rented) or keeps its stash (owned).
- **Sell** (only a home nobody lives in): the market pays 85 % of the value (the price paid, growing 0.1 % a week up to +10 %), **never more than the home cost**, minus a 2 % agent fee, plus the upgrades at the resale %. So there is no buy-then-sell profit.
- Upgrades work on owned homes (no landlord consent fee, no in-place tier upgrade: buy or build a bigger home). The UNIBEN hostel can never be upgraded.

## Building
- Needs plots from Invest -> Land in the **same area**. Pick a design; cost = base cost x the area's build factor, plus a 2 % plan approval fee. Paid up front.
- Real time in stages (Foundation, Blockwork, Roofing, Finishing). Lazy, no cron: finished builds settle on the next call.
- Plots are **locked** while building and under the finished house: the Land sell and the Market refuse them. Cancel while building gives back 60 % of the works. Selling the finished house takes the plots with it (a block of flats frees them when the last unit is sold).
- A finished build is worth its cost plus the plots' share, then grows 0.1 % a week up to +10 %. Not a money printer.
- A block gives several homes (units), each listed and rented separately.
- Designs map to the closest existing 3D layout (no layout edits): rooms -> face-me, self-contain -> self-contain, flats and bungalows -> mini-flat, duplexes -> duplex. The mapping is `property_types.template_home`.

| Design | Plots | Base cost | Time | Gives |
|---|---|---|---|---|
| 2-bedroom bungalow | 1 | N28M | 12 h | 1 home |
| 3-bedroom bungalow | 1 | N42M | 18 h | 1 home |
| 4-bedroom duplex | 2 | N95M | 36 h | 1 home |
| 5-bedroom duplex | 2 | N160M | 48 h | 1 home |
| Block of 6 self-contains | 2 | N45M | 36 h | 6 units |
| Block of 4 flats | 3 | N85M | 72 h | 4 units |

Build factor by area: GRA 1.40, Ugbowo 1.15, Sapele Road 1.05, Airport Road 1.00, Ikpoba Hill 0.95, Okhoro 0.92, Ekenwan 0.90 (a GRA duplex costs 40 % more than at Airport Road). Plot prices are the Invest land prices (GRA N12M ... Ekenwan N1.2M).

## Renting out (landlord)
- Only a home the owner does not live in (or a unit). The owner sets a weekly rent **inside a band** (50 % to 150 % of the market rent = value x the area's yield, 0.22 % GRA to 0.35 % Ekenwan a week) and an optional **caution** (up to 8 weeks of rent). Same trust rule as the Market: a brand-new account cannot let homes.
- Listings show in Rent -> By players, filter by area, price and type.
- Tenant move-in pays: caution (held, refundable) + 1 week rent in advance (to the landlord) + 1 week rent as agent and legal fee (sink).
- **Rent**: on every rent day the tenant pays the landlord from bank then cash (ledger `rent_paid_player`). The landlord gets it as `rent_income` (counts as **earnings**) minus a **5 % agent cut** (`agent_fee`, a sink). The tenant's call only writes an accrual row; the landlord collects it on his next call (and his dashboard charges tenants who have not played), so two player rows are never locked in a risky order.
- **Protection**: the landlord cannot evict at once: **3 days notice** (`property.notice_days`), withdrawable. The rent cannot change while someone lives there. A tenant can **leave any time**. A tenant who owes 3 weeks of rent (`property.evict_owed_weeks`, reusing the owed-rent rule) is moved out: the landlord keeps the caution, the rest is written off.
- A tenant who is evicted goes to his newest past home, else the cheapest city room. Moves are skipped while the tenant is visiting, travelling, jailed or in hospital (tried again later).
- No self-renting, and you cannot rent from your own tenant. The device / IP is not tracked in this game, so alts on different accounts cannot be detected (the new-account rule and the 5 % cut limit the benefit).
- The tenant lives in it like any home (3D scene, furniture, visits). The landlord cannot enter without an invite. A tenant sees the landlord's finished upgrades but cannot buy more.

## Prices by area (naira, Content -> Home prices)
Prices are my estimates for Benin City in 2026, in line with the Invest land prices (a home never costs less than a plot) and about 30 % above the cost of building the same bungalow or duplex yourself.

| Home | Ekenwan | Okhoro | Ikpoba Hill | Airport Rd | Sapele Rd | Ugbowo | GRA |
|---|---|---|---|---|---|---|---|
| Room (face-me) | 3.0M | 3.6M | 4.2M | 4.8M | 5.4M | 6.0M | - |
| Self-contain | 7.0M | 8.5M | 9.5M | 11M | 13M | 15M | 30M |
| 2-bed flat | - | 20M | 22M | 26M | 30M | 36M | 80M |
| 3-bed flat | - | 30M | 34M | 40M | 46M | 54M | 115M |
| 2-bed bungalow | 34M | 36M | 38M | 41M | 44M | 50M | 66M |
| 3-bed bungalow | 52M | 55M | 58M | 62M | 66M | 75M | 100M |
| 4-bed duplex | - | 122M | 128M | 138M | 148M | 165M | 215M |
| 5-bed duplex | - | - | 215M | 225M | 240M | 270M | 340M |
| (plot, Invest) | 1.2M | 1.8M | 2.5M | 3.5M | 4.5M | 6M | 12M |

Note the city landlord's weekly rents are small (N1,500 to N25,000, owner values), so player lets are for variety (area, type, upgrades). Market rent is N10,500 a week for an Ekenwan room and about N750,000 a week for a GRA 5-bed duplex.

## Settings (all with label, description, min and max)
`house.return_days` (Rent). Category `property`: enabled / buy / build / rent-out switches, max owned, max builds, agent fee %, legal fee % and minimum, resale %, sale agent %, value growth per week and cap, plan approval %, build time % (0 = at once), cancel refund %, rent band min / max %, caution max weeks, rent cut %, tenant agent weeks and advance weeks, notice days, eviction owed weeks.

## Ledger, receipts, earnings
New reasons: `house_buy`, `house_sell`, `build_cost`, `build_refund`, `rent_income`, `rent_paid_player`, `rent_caution`, `agent_fee`, `legal_fee`. Only `rent_income` is earned. Receipts (kind `house`) for buying, building and moving into a player's home. Admin audit: `property_end_tenancy`.

## Admin
- Content: Property areas, Home types, Home prices, Build designs.
- Property tab: stats, listings, tenancies with **Force end** (audited, tenant moved out, caution back), builds in progress, recent events.
