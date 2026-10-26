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
  takes the sold key, so keys stay `own_x`, `own_x-2`, ...). H4: pieces that came with the house (starter pieces and a
  home's built-ins) can be sold too, at a lower rate (see "Came with the house" below). Architecture (`fixed`) is part
  of the house, never your furniture. Not while busy. Switch: `furniture.sell_enabled`. Furniture of ₦500,000 or more
  gives a receipt (docs/RECEIPTS.md).
- **3D thumbnails (H2):** the Buy cards, My items and the sell dialog show the real model, rendered by ONE shared
  offscreen WebGL renderer (`src/art/thumbs/render.ts`, loaded lazily) only for cards that scroll into view, a few
  per tick, cached in memory and sessionStorage (`bl.thumb.v1.*`). The renderer is disposed after 15 s idle. The emoji
  stays in Lite mode, on data-saver/2G, without WebGL or if the context fails (`src/art/thumbs/Thumb.tsx`).
- **Copies:** some pieces can be owned several times (up to `max_qty`, e.g. 6 plastic chairs). The keys
  are `own_<id>`, `own_<id>-2`, and so on.
- **Moving house** (H1, `house_move`): every piece that stood in the old home is placed again in the new one: its
  default slot when valid, else the nearest free spot to where it stood (relative position), else My items. Pieces
  already in My items take a free default slot of the new home when valid. The toast says how many wait in My items.
- **Home sizes (H1, made bigger on 2026-11-02, see `docs/HUD_HOME.md` "bigger homes"):** hostel 6.2×5.0, face-me 6.8×5.6, self-contain 9.0×6.8,
  mini-flat 13×9.4 (bedroom, kitchen, bathroom, parlour, dining), GRA duplex 19×13.4 (master bedroom, fitted kitchen + island,
  bathroom with tub, laundry + staircase, study, furnished guest bedroom, dining, big parlour). Bigger homes come with furniture (H4: yours,
  see below) and a little architecture (`fixed: true`: the fitted kitchen counter, the island, the staircase) that
  blocks placement like fixtures. `home_layouts` is regenerated from `model.ts` (H1, then H4 for `included`, then the bigger-homes migration).
- **Need bonuses** come only from placed pieces:
  - `rest_pct` scales sleep energy, as before (beds from 90 % to 140 %).
  - `bonus` adds need effects to a home activity, using the strongest value per need, so bonuses never
    stack. Examples: a split AC gives sleep +8 energy and −4 stress, a fridge gives cooking +2 belle, a
    water heater gives bath +8 clean, and a 75" TV gives TV +8 fun.

## Came with the house (H4, migration `20261012001400_house_items_movable.sql`)
Everything movable that comes with a home is the player's own furniture: select it in Arrange, nudge it with the D-pad,
rotate it, Store it in My items, Sell it. My items and the sell dialog say **"Came with the house"**.

**What became furniture** (`included: '<catalogue id>'` in `model.ts`, server copy `home_layouts.included`):

| Home | Pieces (catalogue id) |
|---|---|
| Mini-flat | kitchen cabinet (`kitchen_cabinet`), bedroom split AC (`ac_split`), ceiling fan (`fan_ceiling`), 4-seater dining set (`dining_4`), Firman generator (`gen_firman`) |
| GRA duplex | water heater, kitchen cabinet, washing machine, 2 split ACs, crystal chandelier, ceiling fan, 6-seater dining set, guest bed (`bed_double`), guest bedside table, guest 3-door wardrobe, Firman generator, 2 compound palms (`plant_palm`) |
| Hostel, face-me, self-contain | nothing: their toilets, bucket baths, drums, clotheslines and generators are shared compound things |
| Starter pieces (by origin) | the starter set from `starter_furniture` (foam mat, stool ... / bed, sofa, TV ...) |

**What stays part of the house** (`fixed` or `FIXED_KINDS`): walls, partitions, doors, windows, toilets, sinks, showers,
the bathtub, the fitted kitchen counter (`kitchen`), the kitchen island, the staircase, and the shared compound things
of the small homes. They still block placement and can't be selected, moved or sold (`fixed_furniture`).
Every included kind was already in the catalogue, so no new rows or prices were needed.

**How it is granted.** `bl_house_items_grant(uid, move_in)` gives a home's pieces ONCE per (player, home)
(`player_house_grants`), as real copies (`player_furniture.source = 'came_with_house'`, `house_qty` +1) standing at the
spots the house had them (else the nearest free spot, else My items). It runs when you choose your first home, in
`house_move` (before your old furniture is placed around them), for every existing player in the migration, and as a
safety net on any furniture action. You can never move back into a home you left (H1), so a home's pieces come once.
Selling a piece never brings it back. `house_qty` counts the copies that came with a house; they are always the highest
copy numbers (`own_x-<qty-house_qty+1>` .. `own_x-<qty>`), and buying or selling renumbers keys to keep it so.

**Selling them.** A came-with-the-house copy pays `furniture.included_resale_pct` (default **25 %**) of its catalogue
price, a bought copy pays `furniture.resale_pct` (45 %) as before. Came-with-the-house sales also share an allowance: the
total they can ever pay is the sum of
- the starter pieces' value at 25 % (once per life; a new life starts with new money), plus
- for every home: at most `furniture.included_move_cap_pct` (default **75 %**) of its move-in fee (the fee paid when
  moving; for the first home, its listed fee = 4 weeks of rent).

When the allowance is used up, `furniture_sell` refuses with `house_resale_used` (the dialog says so and the piece can
still be kept or stored). `furniture_sell_quote(key)` gives the dialog the real amount first. The ledger row of a
came-with-house sale has `meta.included = true`.

**Profit math per tier** (4 weeks move-in, 25 %, cap 75 %; test `supabase/tests/house_items_test.sql` group 5):

| Home | Move-in fee | Pieces at 25 % | Most a move can add | Net per move |
|---|---|---|---|---|
| UNIBEN hostel | ₦4,000 | ₦0 | ₦0 | −₦4,000 |
| Face-me (Aduwawa / Ekenwan) | ₦4,800 / ₦6,000 | ₦0 | ₦0 | −₦4,800 / −₦6,000 |
| Self-contain | ₦16,000 | ₦0 | ₦0 | −₦16,000 |
| Mini-flat | ₦32,000 | ₦356,200 | ₦24,000 | −₦8,000 |
| GRA duplex | ₦100,000 | ₦1,497,300 | ₦75,000 | −₦25,000 |

So move → sell → move always loses at least a quarter of the fee (plus the weekly rent), whatever the admin sets the
rents to, as long as the cap stays under 100 %. Without the cap, 25 % of the duplex's pieces (₦1.5M) would be 15× its
move-in fee, which is why the cap is needed. Because the allowance is one pool, a Nepo who never sells their starter
set can use that part on the home's pieces instead; the total stays the same.

**Need bonuses** follow the pieces: `bl_furniture_for` counts owned copies minus stored ones, so a sold piece (qty − 1)
or a stored one stops giving its bonus (e.g. sell the duplex water heater and the bath bonus drops from +8 to the
washer's +4; store the washer and it is gone).

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
