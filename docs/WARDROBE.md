# Wardrobe: Benin Boutique (W1)

The in-life wardrobe (LAGOS_LIFE_REFERENCE_PLAN Phase 4). Players browse clothes by brand, try them on a 3D turntable, buy them, and save a look per "Wear for" slot. The 3D Sim changes outfits by context. **Everything is cosmetic:** clothes never change needs, skills, jobs or any other gameplay number. The creator (identity setup) and "Edit look" are unchanged.

| Where | What |
|---|---|
| `supabase/migrations/20261010000100_wardrobe.sql` | Tables, seed, RPCs, config, admin whitelist |
| `supabase/tests/wardrobe_test.sql` | SQL tests (rolled back) |
| `src/lib/outfit.ts` | Pure outfit logic: `itemPatch`, `lookPatch`, `applyPatch`, `defaultLook`, `outfitFor`, `outfitContext` |
| `src/state/wardrobe.ts` | Store (`wardrobe_state`), RPC wrappers, `useShownAvatar` hook |
| `src/screens/game/Boutique.tsx` + `.css` | The boutique screen (lazy chunk, one live canvas) |

## Data
- **`wardrobe_brands`**: `id, name, tagline, colour` (accent hex), `is_house, sponsor, active, sort`. Admin: Content → Wardrobe brands.
- **`wardrobe_items`**: `id, name, brand_id, category` (top / bottom / outfit / shoes / bag / hat_hair), `gender` (null = both), `patch` (jsonb), `colours` (text[] of hex), `price` (0 = free), `tag` (basic / designer / owambe), `default_slots` (text[], a hint only), `icon, description, active, sort`. Admin: Content → Wardrobe items (price inline).
- **`player_wardrobe`**: `(user_id, item_id)` primary key, `colour` (first colour bought), `price_paid`, `bought_at`. Buying an item unlocks all its colours.
- **`player_outfits`**: `(user_id, slot)` primary key, `items` ([{item, colour}]), `patch` (the merged avatar patch).
  - No row: the slot shows the **everyday** look ("Keep my everyday look").
  - Row with `patch` null: the slot's **default rule** ("Use the default").
  - Row with a patch: a saved look.
- RLS: players can only `select` their own `player_*` rows; the catalog tables are readable. All writes go through the RPCs (no insert/update/delete grants).

### The patch
A partial avatar config (docs/AVATAR3D.md): `{"top":{"s":"hoodie","f":"plain"}}`, `{"shoes":{"s":"sneakers"}}`, `{"hat":"cap"}`, `{"accessories":["backpack"]}`, or several for an outfit. The colour the player picks fills `top.c` (top, outfit), `bottom.c` (bottom; outfit too unless the patch sets one), `shoes.c`, or `accent` (bags, hats). Garments merge key by key; `accessories` replaces only the bag accessories (`bag`, `backpack`). Patches merge in the order outfit, top, bottom, shoes, bag, hat_hair. Server (`bl_wardrobe_item_patch`, `bl_wardrobe_apply`) and client (`itemPatch`, `applyPatch`) do the same thing.

Only use style ids the renderer draws (`AVATAR_OPTIONS` in `src/art/avatar3d/catalog.ts`); unknown ids fall back silently (`normalizeAvatar`). Gendered styles (agbada, kaftan, gown, maxi, boubou, skirt, heels, gele, head tie, fila, coral cap) need the item's `gender` set.

## RPCs
| RPC | Does |
|---|---|
| `wardrobe_state()` | `{enabled, brands_enabled, cash, bank, gender, brands[], items[] (with owned, owned_colour), outfits{slot: {items, patch}}}`. Items: active ones plus any the caller owns, for the caller's gender. |
| `wardrobe_buy(p_item, p_colour)` | Bank first, then cash (`bl_add_money`, ledger reason **"Boutique: &lt;item&gt;"**, meta item/colour/price). Refuses: switched off, unknown/inactive, wrong gender, bad colour, already owned, not enough money. Works while busy (it is like an online order). |
| `wardrobe_set_outfit(p_slot, p_items)` | `p_items` = `[{item, colour}]`, at most one per category (an outfit excludes top and bottom). Paid items must be owned; free items are always allowed. `[]` = the everyday look as it is. `null` = use the default (not for everyday). **The everyday slot is also merged into `profiles.avatar`,** so portraits, chat, ranks and other players see it. |
| `wardrobe_clear_slot(p_slot)` | Deletes the slot row: the slot keeps the everyday look. |

Slots: `everyday, home, sleep, date, party, work, gym`.

## Config (Settings → Wardrobe)
- `wardrobe.enabled` (default true): off = no Boutique tile, buy/save refused, every Sim shows its everyday look.
- `wardrobe.brands_enabled` (default true): off = no brand pills; items are shown by category only.

## Auto-switch by context (client)
`useShownAvatar` (src/state/wardrobe.ts) → `outfitContext` → `outfitFor(profile.avatar, outfits, slot)`:
1. Busy with Sleep / Take a nap → **sleep**
2. Busy with "Working: …" (a shift) → **work**
3. Busy with a jog / gym / workout / training activity (e.g. Jog round the track) → **gym**
4. At your own home (not visiting) → **home**
5. Inside a club, or at a place with a live owambe / party / club night / concert event → **party**
6. Otherwise → **everyday**

Unset slots fall back to everyday. Default rules: sleep = cotton pyjamas (tee + joggers, slippers, no hat except a head tie, outdoor extras off); home = everyday clothes with slippers, bag/shades/phone off; gym = vest or tee, shorts, trainers; work / date / party = everyday.

Used by the 3D home (`HomeView`), place interiors (`PlaceView`) and the house room presence (guests see your home or sleep outfit). Portraits, chat and lists keep the everyday look (`profile.avatar`). The date slot has no automatic trigger yet (no date activity exists); it is saved for when one does.

## The screen
Phone tile **Boutique** (and Sim sheet → Profile → **Wardrobe**). Full-screen, lazy-loaded, one `AvatarStage` (the home/place canvas is suspended while it is open, like Edit look).
- Turntable preview on a soft gradient ("Drag to spin"), "Your look today" / "&lt;slot&gt; look" chip.
- Brand pills, balance (bank + cash), brand tagline.
- "Wear for" slot row and a note card per slot with **Keep my everyday look** / **Use the default**.
- Category tabs for the brand (Shirts & tops, Sets & outfits, Bottoms, Shoes, Bags, Caps & hats: only those it has).
- Item cards: icon on a tint of the selected colour, brand name, price / Free / Yours, colour count and dots, badges Wearing / Owned / Designer / Owambe.
- Tap = try on instantly (tap again to take off). The bottom bar shows the colour swatches of the last tapped piece and the action: **Buy · ₦…** (confirm modal), **Buy the X first**, or **Wear for &lt;slot&gt;**.

## Seed (47 items, 6 brands)
- **Benin Basics** (house): free tee, singlet, jeans, joggers, slippers, canvas sneakers, "No hat"; polo ₦12k, office shirt ₦18k, shirt and tie ₦30k, trousers ₦20k, wrapper ₦8k, pencil skirt ₦18k, pyjamas ₦9k, leather shoes ₦28k, backpack ₦14k, handbag ₦25k, head tie ₦6k, bucket hat ₦7k.
- **Benin Owambe** (house): ankara shirt ₦22k, senator kaftan ₦65k, lace agbada ₦450k, aso-oke buba and wrapper with gele ₦380k, ankara gown ₦55k, lace boubou ₦240k, leather sandals ₦12k, party heels ₦35k, coral bead cap ₦250k.
- **Ring Road Atelier** (house, designer): date-night suit ₦1.8M, evening gown ₦1.5M, royal aso-oke agbada ₦9M, ivory lace maxi ₦7.5M, designer handbag ₦4.5M.
- **Go Crazy**: tee ₦35,000, hoodie ₦85,000, joggers ₦60,000, cap ₦25,000. **Placeholder prices (could not be verified online): set real prices in admin.**
- **Nike**: tee ₦55,000, hoodie ₦150,000, joggers ₦120,000, cap ₦45,000, sneakers ₦220,000. **Estimated Nigerian retail: set real prices in admin.**
- **Adidas**: tee ₦50,000, tracksuit ₦200,000, sneakers ₦180,000, cap ₦40,000, sports kit ₦95,000. **Estimated Nigerian retail: set real prices in admin.**

Never label anything "cheap"; the affordable range is the house brand Benin Basics.

### Real brand names
Real brand names (Go Crazy, Nike, Adidas) are used by the owner's choice, for future sponsorships. **Get permission from each brand before marketing the game with them**, and add logos only when a brand supplies them. Today brands are text names plus an accent colour only; no logos or logo images. Mark a brand `sponsor` in admin once a deal exists.

## Not done / later
- Card art is an emoji on a colour tint, not a rendered garment thumbnail (rendering ~50 portraits would cost a lot on low-end phones).
- "Edit look" (Sim sheet) still lets players change clothes freely, as before W1.
- No wigs: hairstyles stay part of identity (creator / Edit look).
