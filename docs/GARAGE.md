# G1: garage and parked car

User request (binding): "If they buy a car, they should have the option: do you want to build a garage now? You cannot have a car and not see your car at your house. Building the garage has a price, an actual real-life price of building a garage. Everything in this game is related to real life."

Files: `supabase/migrations/20261010000400_garage.sql`, `supabase/tests/garage_test.sql`, `src/api/garage.ts`, `src/state/garage.ts`, `src/screens/game/GarageSheet.tsx`, parking in `src/art/home3d/engine/room.ts` (`buildParking`), camera framing in `HomeScene.tsx` (`room.frame`), admin entry in `src/admin/Content.tsx`.

## Player flow

- **After buying a car** (the dealer place, Phone → Cars, or a shop panel; any `shop_buy` that returns `car: true`), the **"Where will you park your new car?"** sheet opens. It lists every active garage type with its price and capacity. Types the home can't take are shown but disabled, with the reason ("Needs a self-contain or bigger", "Needs a duplex"). **Not now (park outside)** closes it. Bicycles and the Bajaj Boxer don't trigger the offer.
- **At home**, the Things to do sheet has a **Build a garage** row that opens the same sheet. It shows the current garage and the upgrade options. Guests don't get this row.
- **Building** is instant, with a toast. Live progress was left out because garage building is not a home activity and the busy/timer pattern is tied to `do_activity`.
- **Paying:** bank first, then cash, through `bl_add_money`. The ledger reason is `garage` with meta `{garage, name}`, and the statement label is **"Garage: <name>"**.
- **Upgrading or changing type** replaces the old garage at the **full new price**. There is no refund or trade-in. Building the type you already have is refused (`already_built`).
- **Moving home:** the garage belongs to the home it was built at (`housing_id` + `home_location_id` saved on the row). H1 moving house deletes the garage row: the garage stays behind, the cars stay owned (parked outside until a new garage is built), and the move sheet says so. You can never move back to an old home.

## Gating by home type

`bl_housing_kind(housing_id)` uses the same prefixes as the client's `homeLayoutFor`:

| Home kind | Allowed (defaults) |
|---|---|
| hostel, face_me (single room) | Carport only |
| self_contain, mini_flat | Carport or standard garage |
| duplex (GRA) | Any |

The hostel was not in the brief. It is treated like a single room (carport only), so no car is ever invisible. Admins change gating per type in `allowed_housing`.

## Prices (Benin City, 2025–2026) and sources

| Type | Default | Capacity | Basis |
|---|---|---|---|
| Carport | **₦1,500,000** | 1 | Lagos Jiji carport listings: most ads ₦450k–₦1.5M, a big band at ₦1.5M–₦4.1M (sample: a Danpalon carport at ₦1.5M). Adds a concrete pad and installation. |
| Standard garage | **₦5,000,000** | 1 | About 18–20 m² of blockwork, roof, floor, roller door and electrics. Based on the 2026 Nigerian per-m² build-cost guides (a basic 150 m² house costs ₦9.75M–₦13.5M for structure and finish), plus a steel roller door and finishing. Inside the brief's ₦4–6M band. |
| Luxury double garage | **₦12,000,000** | 2 | About 36–40 m², tiled floor, automatic sectional door, lighting, paved apron. Inside the brief's ₦10–15M band. |

Sources (searched 2026-10-10):
- Jiji Nigeria, carports (Lagos), price bands across about 617 ads: https://jiji.ng/lagos/165-carports/stainless-steel
- OwnKey, Nigeria build cost index per m²: https://ownkey.com/ng/blog/nigeria-build-cost-index-per-square-metre-rates
- OwnKey, building a house in Nigeria cost guide: https://ownkey.com/ng/blog/building-house-nigeria-cost-guide

No source gave a naira price for a finished garage, so the two garage prices are estimates from per-m² costs. They are admin-editable: **Content → Garage types**.

## Data

- `garage_types` (admin whitelist): id, name, description, price, capacity (1–4), allowed_housing text[], style (`carport` | `garage`, which sets the 3D drawing), sort, active. Clients can read it.
- `player_garages`: user_id (pk), garage_type, housing_id, home_location_id, price_paid, built_at. RLS lets the owner read it, and so can an **admitted house guest** (`bl_social_can_view_owner_home`). Clients have no write grants.
- `garage_build(p_type)`: hints `garage_disabled`, `unknown_garage`, `not_allowed_here`, `already_built`, `not_enough_cash`. It returns `message, garage, capacity, spent, from_bank, from_cash, cash, bank, replaced`.
- `garage_home(p_owner default me)`: returns `{enabled, owner, kind, garage|null, cars[{id,name,price}] most expensive first, types[]}`. `types` is the build menu with `allowed` and comes back for the owner only. Only the owner or an admitted guest can call it (`not_allowed`). Guests use it to load the host's cars, since `inventory` is private.
- Config `garage.enabled` (default true). Off means no offer and building is refused, but cars still show, parked outside.

## 3D home

- `HomeScene` takes `parking = { cars, garage: {style, capacity} | null }`. `Game.tsx` loads it with `garage_home(homeOwnerId)`, so a visitor sees the **host's** cars. Previously the visitor's own car showed up. It reloads after a car purchase or a build (`useGarage.version`) and when the vehicle list changes.
- **Placement:** the duplex keeps its bay by the gate, inside the lot. Smaller homes park just east of the compound, nose to the street. The generator moves out of the way (`OutsideOpts.eastClear`). The camera frames the lot plus the parking (`BuiltRoom.frame`).
- **Structures**, cut away like the house so the car stays visible:
  - **Carport:** steel posts and beams, with a red long-span roof in strips.
  - **Standard garage:** plastered block walls (full back and west, low east), a lintel with the roller-door drum, and a bulb.
  - **Luxury double garage:** a painted, two-bay version with a tiled pad, a centre pier, a gold trim and an LED strip.
- **Cars:** most expensive first, up to the capacity inside. Without a garage, one car stands on a pad outside. One more car parks **on the street** in front (High tier only). The models come from `place3d/engine/cars.ts`, and tokunbo or used cars reuse the saloon, GLE and G-Class bodies with their own paint (`CAR_MODELS` in `room.ts`).
- **Perf:** everything merges into the home's few per-layer meshes through `HomeBuilder`, so cars add triangles but no draw calls. The Low tier draws fewer roof strips and no street car.

## H2: selling cars and dealer price tiers

Migration `20261012000400_sell_receipts.sql`, test `sell_receipts_test.sql`.

### Selling a car
- **Phone → Cars → My cars** and the home's garage sheet (**Your cars**) have **Sell** on every owned vehicle. The
  confirm dialog shows the list price, the buy-back % and the payout.
- `car_sell(item)` pays **cars.resale_pct** of the base (list) price (default **60 %**, i.e. 40 % depreciation, rounded
  down to ₦1,000) **into the bank**; ledger "Sold car: <name>". Refused on the road or while busy (`bl_assert_free`),
  for a car you don't own (`not_owned`) and when `cars.sell_enabled` is off. The garage stays; the 3D home drops the car.
- The market no longer buys cars through the Bag (`item_sell` refuses vehicles with `use_car_sell`), so there is one price.
- Buying at a budget lot and selling back always loses money (0.88 × list in, 0.60 × list out).

### Dealer tiers (Admin → Content → Car dealers)
`car_dealers`: location_id, tier (`budget` | `mid` | `premium`), multiplier (0.5–2), label, blurb, sort, active.
The server prices every vehicle with `bl_dealer_price(item, location)` = base × multiplier, rounded to ₦10,000
(₦1,000 under ₦1M); `shop_list`, `shop_buy` and the place cards (`place_interior`) all use it. The Cars app shows
a tier badge per dealer, the dealer's blurb, "₦X below/above list" and the price at the other dealers that stock the car.

| Dealer | Tier | Multiplier | Stock |
|---|---|---|---|
| Sapele Rd Tokunbo Lot | budget ("Tokunbo lot") | 0.88 | used only: bicycle, Boxer, Kia Rio, tokunbo saloon, Camry "Muscle", Lexus RX 350 |
| Ighodalo Car Deals | mid ("Car dealer") | 1.00 | the used cars plus new Camry and C300 |
| SDD Motors | premium ("Official showroom") | 1.20 | everything, and the **only** seller of the G-Wagon, GLE 63, Urus, Cybertruck, Escalade and new Hilux |

Stock is the items' `sold_at` (Content → Items). The migration only changed rows still holding the seeded value.
The Tokunbo Lot's 3D "Luxury corner" still shows luxury cars as display pieces; they have no buy card there.

Why these numbers (searched 2026-10-11): Nigerian listings show the same model far cheaper at roadside tokunbo lots
than as brand-new from official dealers (Nairametrics' January 2026 tokunbo roundup lists a 2007–09 Camry at
₦8.5–10M; 2026 guides put a brand-new Camry at ₦25–30M+ and official dealers above that). Within the same car, a lot vs
a franchise showroom differs by roughly 10–30 % (papers, warranty, plates, margins), hence 0.88 / 1.00 / 1.20.
Sources: https://nairametrics.com/2026/01/11/see-10-tokunbo-cars-you-can-buy-in-nigeria-for-n10-million-or-less/ ·
https://nigerianqueries.com/prices-of-toyota-camry-cars-in-nigeria/ · https://awajis.com/tokunbo-cars-nigeria/
(low-authority listing sites; treat as a guide). The multipliers and base prices are admin-editable.

Receipts: every car, garage and house move from ₦500,000 gives a receipt (docs/RECEIPTS.md).
