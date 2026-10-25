# Cooking and markets (step C)

Players buy real ingredients, cook at home on the stove, and eat, share or feed the kids. Built on what was already
there: the `items` table, `shop_list` / `shop_buy`, `item_use`, the Cooking skill, the Catering course, kids feeding.
No parallel systems.

Migration: `supabase/migrations/20261030000100_cooking.sql`. Test: `supabase/tests/cooking_test.sql`.
Client: `src/api/cooking.ts`, `src/screens/game/phone/KitchenTab.tsx`, `PricesTab.tsx`, `CookingApp.css`, tabs in `FoodApp.tsx`.
Nothing touches `profiles` (no column, trigger or foreign key).

## How it plays
1. **Ingredients** are normal items (category `ingredient`) in small portions: a derica, a cup, a tuber, a bunch, a sachet.
   26 of them: rice, beans, garri, yam, plantain, palm oil (1 cup), vegetable oil, tomatoes, pepper, onions, crayfish, dry fish,
   chicken, assorted meat, egg, instant noodles, egusi, bitter leaf, scent leaf, ugu, palm fruit, beletete, potash, starch, pap,
   seasoning cubes. Base prices follow 2026 Nigeria (rice about N900 a derica = a N85k bag, beans N1,350, garri N400).
   No VAT. They cannot be sold back, traded or eaten raw.
2. **Two places.** The base price is the item price (Content -> Items).
   - **Oba Market** (6 AM to 8 PM): the base price, moved by a fixed amount each Benin day inside a band (default 8 %).
     Seeded by date + item + place, so everybody sees the same price all day. Never dearer than the supermarket.
   - **Edo Fresh Supermarket**: always open, base + 30 %, never changes.
   Buying is the normal Shop tab (`shop_buy`). The Shop tab at both places has a "Today's prices" button and shows
   "up / down vs yesterday" on Oba prices.
3. **Prices tab** (Phone, Chowdeck): `grocery_prices()` returns today, yesterday, change in percent and the supermarket
   price for all 26, plus both places' opening state. Filters: all, dropped, rose.
4. **Kitchen tab** (Phone, Chowdeck; also "Open the kitchen" when you tap the stove at home): recipes, what you hold, pot size
   (1 to 3 batches), Cook. The server checks everything (`cook_start`).
5. **Cooking rules.** You must be at your own home (not visiting), have a stove or cooker (switchable), be free (not busy),
   have the Cooking level (and the certificate if the recipe needs one), and hold all the ingredients (x pot size). The server
   takes the ingredients, puts the portions in the Bag as `dish_<recipe>` and keeps you busy for the cook time.
   A bigger pot makes more portions from more ingredients and takes longer (+50 % per extra batch). A bag holds at most 40
   portions of one dish.
6. **Eating** is the normal Eat button (`item_use`): hunger, energy, mood (fun) per portion, set by the recipe.
7. **Sharing**: `cook_share` sends portions to your partner (a couple) for free, 20 a Benin day, and tells them.
8. **Kids**: from Nursery up, feeding a child uses one cooked portion from the parent's bag instead of lunch money (and fills
   them 25 % more). It counts as spending on the child at its ingredient cost, so the grown-up gift cap still sees it.
   Newborns and babies still need formula or cereal.
9. **Skill and XP**: Cooking skill (existing). XP per cook is the recipe's XP, the same for any pot size. Fair rules:
   a daily cap (default 100 base XP a Benin day), dishes 2 or more levels below you give only 40 %, and the normal XP multiplier
   and Foodie trait apply after the cap. Skills off = no XP and no level gates.
10. **Catering certificate** (School app): unlocks Black soup (level 6) and cooks every dish 25 % faster.

## The dishes (default numbers per portion)
| Dish | Level | Batch | Min | Hunger | Energy | Mood | XP |
|---|---|---|---|---|---|---|---|
| Indomie and egg | 1 | 2 | 8 | 32 | 2 | 3 | 10 |
| Akara and pap | 1 | 4 | 25 | 38 | 4 | 4 | 10 |
| Beans and dodo | 2 | 4 | 40 | 50 | 5 | 6 | 14 |
| Yam porridge (asaro) | 2 | 5 | 45 | 55 | 6 | 6 | 14 |
| Jollof rice and chicken | 3 | 8 | 60 | 52 | 4 | 9 | 18 |
| Owo soup with starch | 4 | 8 | 55 | 55 | 4 | 7 | 22 |
| Banga soup with starch or eba | 4 | 8 | 60 | 58 | 4 | 8 | 22 |
| Egusi soup with pounded yam | 5 | 8 | 75 | 65 | 5 | 10 | 28 |
| Black soup (omoebe), Catering | 6 | 8 | 80 | 70 | 6 | 12 | 34 |

Home cooking costs about N19 to N30 of ingredients per hunger point at Oba prices, against about N36 to N40 for the ready-made
packs. The test checks that every recipe stays between N10 and N35 a point.

## Server pieces
- Tables (RLS on, no client grants): `cook_recipes`, `cook_ingredients` (amount 0 = not used), `cook_daily` (XP, cooks and
  shared portions per user and day). A trigger on the recipe tables keeps the dish item in step (name, effects, value).
- Player RPCs (authenticated only): `grocery_prices()`, `cook_overview()`, `cook_start(recipe, pots)`, `cook_share(item, qty)`.
  The read-only ones are plain reads (PostgREST runs them in a read-only transaction; the test covers that).
- Private helpers `bl_cook_*`: `bl_cook_price` (the one place the price is computed), `bl_cook_yesterday`, `bl_cook_award`,
  `bl_cook_kid_dish`, and more.
- Guarded patches: `bl_shop_price` (ingredients go to `bl_cook_price`), `shop_list` (adds `yesterday`), `bl_kids_can` and
  `kids_care` (cooked meal as kids' food), `bl_admin_table_spec` (editors).

## Admin
- Settings -> **Cooking and markets**: 16 keys (switch, price band, supermarket markup, biggest pot, extra time per batch,
  longest cook, bag limit, stove needed, daily XP cap, easy-dish levels and percent, Catering certificate id and speed-up,
  share cap, kid meals on, kid meal boost). Each has a label, a description and a min and max.
- Content -> **Recipes** and **Recipe ingredients**; ingredient names and base prices: Content -> **Items** (category `ingredient`).
  Add a recipe and its ingredients and players can cook it at once. Switch a dish off with On.

## Help and tour
Help article `cooking`, tour step `cooking` (Chowdeck icon, "What's new"). Deep links: `go=food`, `go=food:kitchen`, `go=food:prices`.

## Not done / ideas
- No cooking quality (every portion of a dish is the same) and no selling of food to players.
- The stove type does not change speed or XP.
- Other markets (Uselu, Ekiosa...) do not sell ingredients yet: add the place id to an item's `sold_at` and it follows the market rule.
