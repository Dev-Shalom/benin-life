# Shops, the Bag, ChopNow and rent (V1-4)

Files: `supabase/migrations/20261005000800_shops.sql`, `supabase/tests/shops_test.sql`, wrappers in `src/api/shops.ts`,
types in `src/lib/types.ts` (`// V1-4`), shared item UI `src/panels/shop/ShopUI.tsx`, the Shop tab `src/panels/ShopPanel.tsx`
(action id `shop`), the Bag `src/panels/InventoryPanel.tsx` (global panel `inventory`), phone apps
`src/screens/game/phone/FoodApp.tsx` (ChopNow) and `HousesApp.tsx` (Houses), the dock's Buy sheet (`Extras.tsx`), the
"Eat something" wish chip (`Hud.tsx`), the Sim sheet Profile tab (home + Bag cards) and the laptop link in the career
requirements (`CareerUI.tsx`).

Test (migrations applied): `bash scripts/sql-test.sh -- supabase/tests/shops_test.sql`

## How it plays
1. **Shop tab.** Markets, bukas, motor parks, PoS stands, the Wi-Fi joint, the Tech Hub, the hospitals' pharmacy counter,
   the salon and Igun Street have a **Shop** tab when you stand there. Item cards show the emoji, price, need chips,
   how many you already own, a quantity stepper and **Buy**. Cash only.
2. **The Bag.** Dock **Buy** → **Bag** (or the Sim sheet's Profile → Bag → Open, or the "Eat something" chip).
   Food and drinks: **Eat** / **Drink** (instant, one at a time). Toothpaste, paracetamol, airtime and data: **Use**.
   Soap is used up automatically on your next bath at home. The laptop, the car and souvenirs are kept.
   At a market every sellable item shows **Sell ₦X** (its resale price).
3. **ChopNow** (phone). Every food and drink at shop price + 40 % (at least ₦200), rounded up to ₦10. Paid by transfer
   from the bank first, the rest in cash. Arrives at once (the rider is fast) and lands in the Bag. Works while busy or
   on the road; not in a police cell or a hospital bed.
4. **Houses** (phone). Your home, weekly rent, the next rent day (weekday, game day and time, plus the real time left),
   rent owed with **Pay now**. The phone tile shows a red "!" while you owe rent.

## Items (seeded; admin-editable rows)
| | id | Name | Cat. | ₦ | Effects | Sell | Sold at |
|---|---|---|---|---|---|---|---|
| 💧 | pure_water | Pure water sachet | drink | 50 | energy +1, stress −2, bladder −8 | – | 6 markets, 4 motor parks, 2 bukas |
| 🥤 | bottled_water | Bottled water | drink | 250 | energy +2, stress −3, bladder −10 | – | 6 markets, Uselu/Ramat parks, UBTH, Mercy, Tech Hub, Wi-Fi joint |
| 🍹 | zobo | Chilled zobo | drink | 300 | fun +3, stress −3, bladder −8 | – | 5 markets, 2 bukas |
| 🍺 | malt_drink | Malt drink | drink | 500 | energy +6, fun +3, bladder −10 | – | 6 markets, 2 bukas, 4 motor parks |
| 🥐 | roll_and_soda | Sausage roll + soda | food | 600 | hunger +14, fun +4, bladder −8 | – | 4 motor parks, 3 PoS stands, Oba + Uselu markets |
| 🍩 | puff_puff | Puff-puff (5 balls) | food | 300 | hunger +12, fun +3 | – | 6 markets, 4 motor parks, Back Gate |
| 🥣 | garri_groundnut | Garri + groundnut | food | 300 | hunger +20, bladder −6 | – | 6 markets, Back Gate |
| 🍌 | boli_groundnut | Boli + groundnut | food | 400 | hunger +18, fun +2 | – | 4 markets, 4 motor parks |
| 🍜 | noodles_pack | Noodles pack | food | 400 | hunger +18 | – | 6 markets, Back Gate, Wi-Fi joint |
| 🍢 | suya_stick | Suya stick | food | 500 | hunger +15, fun +5 | – | 4 motor parks, 2 bukas, New Benin + Oregbeni |
| 🍞 | bread_egg | Bread + fried egg | food | 700 | hunger +25, energy +2 | – | 6 markets, Uselu/Ramat parks, Back Gate |
| 🍲 | owo_pack | Owo soup + starch pack | food | 1,800 | hunger +50, fun +5, social +2 | – | 2 bukas, Oba + Ekiosa markets |
| 🍛 | jollof_pack | Jollof rice + chicken pack | food | 2,000 | hunger +50, fun +8 | – | 2 bukas, New Benin, Uselu, Santana |
| 🧼 | soap | Bar of soap | hygiene | 300 | boost: next home bath +20 hygiene, +2 fun | 30 % | 6 markets, salon |
| 🪥 | toothpaste | Toothpaste + brush | hygiene | 400 | hygiene +10, social +3 | – | 6 markets, salon |
| 💊 | pain_relief | Paracetamol strip | health | 300 | health +4, stress −6 | – | UBTH, Mercy, Oba/New Benin/Uselu markets |
| 📶 | airtime | Airtime top-up (₦500) | phone | 500 | social +12, fun +2 | – | 3 PoS stands, 3 markets, Uselu park, Wi-Fi joint |
| 📱 | data_bundle | Data bundle (1.5GB) | phone | 1,000 | fun +15, social +5 | – | 3 PoS stands, Wi-Fi joint, Tech Hub |
| 💻 | laptop | Fairly-used Laptop | gadget | **45,000** | keep (Tech Junior Dev+ requirement) | 40 % | Tech Hub, Wi-Fi joint |
| 🗿 | bronze_mini_head | Mini bronze head | souvenir | 8,000 | keep | 60 % | Igun Street |
| 🚗 | tokunbo_car | Tokunbo Saloon | vehicle | 2,500,000 | keep (car travel mode) | no | not sold yet (Cars app later) |

Places that gained the `shop` action: Mama Osas Buka, Back Gate Joint, the 4 motor parks, the 3 PoS stands, the Wi-Fi
joint, Bronze Tech Hub, UBTH and Mercy Clinic (the 6 markets, Igun Street and the salon already had it). The test checks
that every `sold_at` place has the tab and every tab sells something.

### Effects format (`items.effects`)
- Need keys (`hunger, energy, hygiene, fun, social, health, stress, bladder`) → a **use** item; `item_use` consumes one
  and applies them with `bl_adjust_needs`.
- `{"boost": {"<activity id>": {needs}}}` → a **boost** item: `do_activity` uses up one of each matching item in the Bag
  and adds the deltas to that activity (soap + `bathe`). `item_use` refuses it (hint `use_with_activity`).
- `{}` → a **keep** item (laptop, car, souvenir). `item_use` refuses it (hint `not_usable`).

### Laptop price reasoning
A LAPO Tech Intern earns ₦3,500 a shift at 100 % (about ₦3,000 at a normal 85 %), at most 3 shifts per game day
(2 real hours), so ~₦9,000-10,500 a game day. Food costs ~₦3,000-4,500 a game day and the cheapest rent ~₦200 a day, so
an intern saves ~₦5,500 a game day: **₦45,000 ≈ 8 game days ≈ 16 real hours**. Someone on Trade/PoS/Transport is promoted
after 4 shifts (₦4,500-6,500) and saves ~₦8,000+ a game day: ~6 game days ≈ 12 real hours. Both are inside the 12-20 hour
target. Nepo babies already own one (resale ₦18,000).

## RPCs (authenticated only)
| RPC | Returns |
|---|---|
| `shop_list(p_location default null)` | `{location:{id,name,scene}, here, sell_here, cash, items:[{id,name,category,price,description,effects,icon,kind,sellable,resale_price,owned,affordable}]}` (read-only; defaults to where you are) |
| `shop_buy(p_item, p_qty default 1)` | `{message, item, qty, owned, spent, cash}`; cash only, ledger reason `shop` (meta item/qty/location) |
| `item_use(p_item)` | `{message, item, effects, left}` — instant |
| `item_sell(p_item, p_qty default 1)` | `{message, item, qty, earned, left}`; only where the scene is in `shop.sell_scenes`; ledger `shop_sell` |
| `food_menu()` | `{markup_pct, min_fee, cash, bank, items:[{…, shop_price, price, owned}]}` (read-only) |
| `food_order(p_item, p_qty default 1)` | `{message, item, qty, owned, paid, paid_bank, paid_cash}`; ledger `food_delivery` |
| `pay_rent()` | `{message, paid, paid_bank, paid_cash, owed}`; bank first, then cash; partial payments count; ledger `rent` (meta `settle`) |
| `get_my_state().inventory` | `[{id,name,category,icon,qty,price,description,effects,kind,sellable,resale_price}]` (read-only, qty > 0) |
| `get_my_state().rent.owed_sleep_pct` | the sleep penalty percent, for the Houses app |

`shop_buy`, `item_use` and `item_sell` call `bl_me()` + `bl_assert_free` (not while busy, travelling, jailed or in hospital).
`food_order` and `pay_rent` call `bl_me()` only (phone transfers work while busy); `food_order` refuses in a cell or a
hospital bed. `do_activity` is redefined (same signature, same rules) for boosts and the rent penalty, and returns
`used` and `rent_penalty` too.

**Errors** (P0001, English, with hints): `no_item` ("That item doesn't exist." / "You don't have X in your Bag."),
`not_sold_here` ("X is not sold here. Try Oba Market, …"), `not_enough_cash` ("Not enough cash. X costs ₦Y and you have
₦Z on you."), `bad_qty`, `cant_sell_here`, `not_sellable`, `not_on_menu`, `use_with_activity`, `not_usable`,
`no_rent_owed`, plus the usual `busy` / `traveling` / `jailed` / `hospitalized`.

Helpers (`bl_need_keys`, `bl_item_kind`, `bl_need_effects`, `bl_effects_add`, `bl_resale_price`, `bl_delivery_price`,
`bl_csv_has`, `bl_can_sell_at`, `bl_give_item`, `bl_item`, `bl_check_qty`, `bl_inventory_info`,
`bl_rent_switch_trigger`) are revoked from public/anon/authenticated.

## Rent (now ON)
- `rent.enabled` was flipped to **true** by this migration, once: the update only runs while the value is still the
  seeded `false` **and** `updated_by is null` (no admin has set it). An admin who later turns it off keeps it off.
- **No back-charge.** `bl_charge_rent` only rolled the due date forward lazily (inside gameplay calls), so a Sim who had
  not played since rent day would have been charged up to 4 weeks the moment rent came on. A new trigger
  `game_config_rent_switch` runs whenever `rent.enabled` goes false → true and moves every overdue `rent_due_at` to the
  next rent day. This also protects later admin toggles. Tested (a 3-weeks-overdue Sim pays nothing on the switch).
- Charging itself is unchanged (R3a, `docs/CREATOR.md`): every Saturday 00:00 game time, lazily in `bl_me()`, bank first
  then cash, shortfall → `rent_owed` + a "Landlord don knock!" `rent_owed` event (shown as a red toast), at most 4 weeks.
- **Consequence while owing (light, fair, config-driven):** sleeping or napping at home gives only
  `rent.owed_sleep_energy_pct` (60) % of the energy, and the activity message carries the landlord's knock
  ("Where my rent? You owe ₦1,100!"). Pay it any time from the phone's Houses app (`pay_rent`, partial payments
  allowed). No eviction in v1.

## Config (category `shop` / `rent`, all admin-tunable)
`shop.max_qty_per_buy` 10 · `shop.delivery_markup_pct` 40 · `shop.delivery_min_fee` 200 · `shop.sell_scenes` "market" ·
`rent.owed_sleep_energy_pct` 60 · `rent.owed_sleep_activities` "sleep,nap" · `rent.enabled` true (since V1-4).
No per-district price multipliers in v1: edit `items.price` instead.

## Phase 2 hooks
- Buy mode / furniture (dock Buy sheet keeps the preview), Cars app (the starter car is not sellable until then),
  moving house (Houses app has the teaser card), eviction (read `rent_owed`), hospital vs paracetamol balance (P2-FIN).
- Admin page (V1-7): edit `items` rows (price, effects, sold_at, sellable, resale_pct) and the `shop.*` / `rent.*` config.
