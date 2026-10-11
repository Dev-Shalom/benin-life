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
- **Copies:** some pieces can be owned several times (up to `max_qty`, e.g. 6 plastic chairs). The keys
  are `own_<id>`, `own_<id>-2`, and so on.
- **Moving house** resets positions. Starter pieces go back to their default slots, and everything else
  waits in storage.
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
