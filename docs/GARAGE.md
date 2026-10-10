# G1: garage and parked car

User request (binding): "If they buy a car, they should have the option: do you want to build a garage now? You cannot have a car and not see your car at your house. Building the garage has a price, an actual real-life price of building a garage. Everything in this game is related to real life."

Files: `supabase/migrations/20261010000400_garage.sql`, `supabase/tests/garage_test.sql`, `src/api/garage.ts`, `src/state/garage.ts`, `src/screens/game/GarageSheet.tsx`, parking in `src/art/home3d/engine/room.ts` (`buildParking`), camera framing in `HomeScene.tsx` (`room.frame`), admin entry in `src/admin/Content.tsx`.

## Player flow

- **After buying a car** (the dealer place, Phone → Cars, or a shop panel; any `shop_buy` that returns `car: true`), the **"Where will you park your new car?"** sheet opens. It lists every active garage type with its price and capacity. Types the home can't take are shown but disabled, with the reason ("Needs a self-contain or bigger", "Needs a duplex"). **Not now (park outside)** closes it. Bicycles and the Bajaj Boxer don't trigger the offer.
- **At home**, the Things to do sheet has a **Build a garage** row that opens the same sheet. It shows the current garage and the upgrade options. Guests don't get this row.
- **Building** is instant, with a toast. Live progress was left out because garage building is not a home activity and the busy/timer pattern is tied to `do_activity`.
- **Paying:** bank first, then cash, through `bl_add_money`. The ledger reason is `garage` with meta `{garage, name}`, and the statement label is **"Garage: <name>"**.
- **Upgrading or changing type** replaces the old garage at the **full new price**. There is no refund or trade-in. Building the type you already have is refused (`already_built`).
- **Moving home:** the garage belongs to the home it was built at (`housing_id` + `home_location_id` saved on the row). In a different home it reads as "no garage", and the player builds again. If they move back, the old one counts again, because the row is still there until they build elsewhere.

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
