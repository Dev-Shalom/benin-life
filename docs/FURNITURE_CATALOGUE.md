# Furniture catalogue (B1 Buy mode + arrange)

103 pieces in six rooms (Parlour, Bedroom, Kitchen, Bathroom, Outside, Decor), in three tiers:
**LAPO** (31, trench basics), **Mid** (43) and **Nepo** (29, luxury). The rows live in `furniture`
(migration `20261012000200_buy_catalogue.sql`). Prices, tiers, bonuses and the rest are editable in
Admin → Content → Furniture.

## How it works
- **Buy** (dock → Buy → Furniture): room tabs, LAPO/Mid/Nepo filter, tap Buy then Pay. `furniture_buy`
  takes cash first, then bank, and the piece is delivered to the inventory. At home the game goes
  straight into placing it.
- **Arrange** (Buy → Arrange, or after a purchase): tap a piece in the room, or pick it from My items.
  It moves live; the diamond D-pad nudges it 0.25 m along the walls, rotate turns it 90°, Store sends it
  back to the inventory, and Done saves it with `furniture_place`. A red piece and a warning mean the spot
  is not allowed, and Done refuses it.
- **Rules** (client `src/art/home3d/arrange.ts`, server `bl_furniture_check`, both using the same
  numbers from `home_layouts`):
  - Inside pieces must stay in the house; generators, tanks and solar panels go in the compound;
    chairs and plants may go in either.
  - Curtains, ACs, art and clocks must touch the back (north) or left (west) wall.
  - Solid pieces may not overlap fixtures, partitions, a door's clear zone or each other.
- **Selling (H2):** Buy → Arrange → My items has **Sell** on every piece you bought, placed or in storage. A
  confirm dialog shows the payout: **furniture.resale_pct** of the catalogue price (default 45 %, rounded down to
  ₦100), paid in cash by `furniture_sell(key)`; ledger "Sold furniture: <name>". The copy disappears (the last copy
  takes the sold key, so keys stay `own_x`, `own_x-2`, ...). The free piece that came with the house (copy 1 of a
  starter row) can't be sold ("came with the house"; a bought extra copy can), and built-ins (`fixed`) are part of the
  house, not your furniture. Not while busy. Switch: `furniture.sell_enabled`. Furniture of ₦500,000 or more gives a
  receipt (docs/RECEIPTS.md).
- **3D thumbnails (H2):** the Buy cards, My items and the sell dialog show the real model, rendered by ONE shared
  offscreen WebGL renderer (`src/art/thumbs/render.ts`, loaded lazily) only for cards that scroll into view, a few
  per tick, cached in memory and sessionStorage (`bl.thumb.v1.*`). The renderer is disposed after 15 s idle. The emoji
  stays in Lite mode, on data-saver/2G, without WebGL or if the context fails (`src/art/thumbs/Thumb.tsx`).
- **Copies:** some pieces can be owned several times (up to `max_qty`, e.g. 6 plastic chairs). The keys
  are `own_<id>`, `own_<id>-2`, and so on.
- **Moving house** (H1, `house_move`): every piece that stood in the old home is placed again in the new one: its
  default slot when valid, else the nearest free spot to where it stood (relative position), else My items. Pieces
  already in My items take a free default slot of the new home when valid. The toast says how many wait in My items.
- **Home sizes (H1):** hostel 5.2×4.4, face-me 4.2×3.8, self-contain 6.0×4.8 (unchanged), mini-flat 9.6×7.2 (bedroom,
  kitchen, bathroom, parlour, dining), GRA duplex 14.4×10 (master bedroom, fitted kitchen + island, bathroom with
  tub, laundry + staircase, furnished guest bedroom, dining, big parlour). Bigger homes come with built-in pieces
  (`fixed: true` in `model.ts`: kitchen units, ACs, ceiling fan, chandelier, dining set, guest room) that block
  placement like fixtures. `home_layouts` is regenerated from `model.ts` by the H1 migration.
- **Need bonuses** come only from placed pieces:
  - `rest_pct` scales sleep energy, as before (beds from 90 % to 140 %).
  - `bonus` adds need effects to a home activity, using the strongest value per need, so bonuses never
    stack. Examples: a split AC gives sleep +8 energy and −4 stress, a fridge gives cooking +2 belle, a
    water heater gives bath +8 clean, and a 75" TV gives TV +8 fun.

## Price sources (checked October 2026; shop prices change often, so treat these as a guide)
- Vitafoam 6x6, 8": about ₦100–110k; 6x6x10 spring about ₦190k. Source: nigerianqueries.com Vitafoam / 6x6
  price lists (2026). The olivefoam.ng 2026 guide gives ₦80–220k for mainstream mattresses.
- Sumec Firman 2.8KVA manual: ₦370k; 1.8KVA: ₦240k; 9KVA: ₦1.15M. Source: zit.ng.
- Haier Thermocool 200L chest freezer: ₦451k; 219L inverter: ₦587k. Source: zit.ng.
- Scanfrost cookers: ₦48–75k for basic models, ₦840k for the 5-burner SFC9502SS. Sources: nigerianqueries
  (April 2026) and zit.ng.
- Hisense 1.5HP split AC: ₦363–430k; split ACs overall: ₦180–850k. Source: zit.ng 2026 guide.
- Hisense 75" QLED: ₦1.22–1.32M; 32" LED: ₦169–225k. Sources: zit.ng and naijatechguide 2026 TV prices.
- 7-seater sofas: ₦341k (Chesterfield), ₦1.5M (Lagos "royal" set), ₦5.39M (Turkish luxury, Zit). The
  Italian set is set at ₦6.5M. Sources: zit.ng and jiji.ng.
- 3.5KVA solar/inverter system: about ₦3.2M. Source: naijatechguide. GeePee 1000L tank: ₦33.5–38.5k.
  Source: nigerianqueries (2026).
- Nexus 65L bar fridge and Nexus fridges: ₦70k to ₦685k; water dispensers: ₦48–200k. Source: zit.ng.
- Kerosene: about ₦2,970 per litre (NBS, May 2026), which is why the wick stove is cheap but the fuel is
  not.
- **Estimates** (market-stall prices, no single listing): plastic chairs, stools, mats, buckets, clothes
  rack, curtains, pots, Tiger gen, Benin bronze replicas, the 20KVA soundproof gen, chandelier, car shade.

To change the catalogue, edit the rows in Admin, or add a new migration that upserts by id. A new
`kind` also needs a `KINDS` entry in `src/art/home3d/model.ts` and a model in
`src/art/home3d/engine/furniture.ts`. Its w/d/solid/placement in SQL must match `KINDS`.
