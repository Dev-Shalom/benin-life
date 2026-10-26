# House upgrades (R8)

Fynta: "It would be good to have the option to expand or upgrade your existing house rather than having to purchase a completely new property."
Players can now extend and improve the home they live in. Migration `20261018000500_house_upgrades.sql`, test `supabase/tests/house_upgrades_test.sql`, geometry check `scripts/home-upgrade-check.mjs`.

## How homes work (and the ownership rule)
Every home in the game is **rented** (weekly rent). So "owner" means *your own current home*:
- Only the home you live in. Not the UNIBEN hostel (never upgradable), not a home you are visiting, not while you owe rent, not from jail.
- The tenant pays for the works **plus a landlord consent fee** (`house.upgrade_landlord_fee_pct`, default 10% of the upgrade price, on top, not refunded).
- There is no house-selling flow in the game. The "sale" is **moving out**: `house_move` gives back `house.upgrade_resale_pct` (default 50%) of what you paid for upgrades into the bank (a build still in progress is refunded in full). The old home is released for good, so the upgrades go with it. `house_upgrade_state().sale_value` shows the figure; `bl_house_upgrades_value(uid)` is the hook for R9 player-to-player house sales.

## The catalogue (admin table `house_upgrades`, Admin -> Content -> House upgrades)
Columns: `name, emoji, category, description, preview` (what you will see in 3D), `tiers` (home types: face_me, self_contain, mini_flat, duplex), `price`, `tier_prices` (per home type override), `build_minutes` (0 = instant), `requires` (an upgrade id that must be finished first), `effect` jsonb, `sort`, `active`.

Defaults (all admin-editable; seeds use `on conflict do nothing`, so admin edits survive re-runs):

| Upgrade | Home types | Price | Build | Effect |
|---|---|---|---|---|
| Extra bedroom | face-me, self-contain, mini-flat | 1.8M / 2.6M / 3.8M | 120 min | new room in 3D; sleep stress -2, nap -1 |
| Guest wing | duplex | 9M | 240 | big new wing in 3D |
| Boys' quarters | duplex | 5.5M | 150 | yard building; sofa stress -3, rest -2 |
| Carport / Standard garage / Luxury double garage | all / self-contain+ / duplex | 1.5M / 5M / 12M | 60 / 150 / 240 | adds a garage where there is none |
| Extra car space (x2, chained) | all | 3M, 4.5M | 120, 150 | garage capacity +1 each (max 4 bays) |
| Generator house | all | 450k-650k | 45 | sleep energy +2, nap +1, TV fun +2 |
| Solar and inverter | self-contain+ | 2.2M-5.5M | 120 | sleep energy +3, nap +2, TV fun +3, sofa +1 |
| Borehole and tank | all | 900k-1.1M | 90 | bath hygiene +6, toilet +2 |
| Compound wall, then Gate + CCTV | all | 500k-800k, 2.2M | 60, 90 | compound wall / gate drawn; sleep stress -1, -3 |
| Fresh paint, POP ceiling and tiles, Premium finish | all (premium: self-contain+) | 150k-8M | 30 / 90 / 150 | finish level 1-3: wall and floor materials change |
| Upgrade to next tier in place | face-me, self-contain, mini-flat | 3.5M / 8M / 22M renovation fee | 240 / 360 / 720 | see below |

There was no "NEPA took light" mechanic and no burglary at home (pickpocketing never happens in private homes), so generator and solar give a comfort bonus, and security is cosmetic plus calmer sleep. Bonuses add to home activities inside `do_activity` (patched), capped per need by `house.upgrade_bonus_cap` (12).

`effect` keys: `bonus` {activity: {need: n}}, `finish` 1-3, `security` 1-2, `garage_type`, `garage_space`, `requires_garage`, `requires_no_garage`, `to_home` (start_home id), `geom` (3D floor plan, set by code: do not edit).

## Building (builders working)
`house_upgrade_buy(id)` pays (bank first, then cash; ledger `house_upgrade`, label "House upgrade: <name>") and inserts a `player_house_upgrades` row with `ready_at = now + minutes`. **No cron**: the row is settled lazily on the next read (`house_upgrade_state`, `house_upgrade_home`, `do_activity`, the admin grant). Settling runs the side effects (garage, car space, tier change); bonuses and looks are read live from finished rows only. `house_upgrade_state().just_finished` lists finished-and-not-yet-announced upgrades once: the client shows the toast "Builders don finish: X is ready!". The client reads once at sign-in and again just after the next build is due (`src/state/upgrades.ts`).

Settings (Settings -> Rent): `house.upgrades_enabled`, `house.upgrade_resale_pct` (50), `house.upgrade_landlord_fee_pct` (10), `house.upgrade_max_builds` (1: one build at a time), `house.upgrade_time_pct` (100: scales every build time; 0 = instant, handy for testing), `house.upgrade_bonus_cap` (12).

## Upgrade to the next tier, in place
Face-me -> self-contain -> mini-flat -> duplex at the **same address** (same private home location and map spot).
- Price = the upgrade's renovation fee + (target rent - current rent) x `house.move_in_weeks` + landlord fee. Pays now; the builders then work (240/360/720 min). While it builds, no other works can be bought.
- On finish (`bl_house_apply_tier`): `start_home`, `housing_id` and `weekly_rent` become the target's; the old tier is released (can't go back); the home scene follows the tier; **furniture is placed again** with the same rules as moving (default slot, else nearest free spot, else My items); **the garage is kept** (its row is re-keyed to the new home); the new tier's built-ins are granted once; other upgrades carry over (an extension that has no floor plan for the new tier stays as a bonus and still counts in the sale value).

## 3D
Pure data in `src/art/home3d/upgrades.ts`: `applyUpgrades(baseLayout, done, building)` returns the layout with finished upgrades built in and scaffolding for builds in progress.
- Extension rooms (sizes after the 2026-11-02 bigger homes: face-me 6.8 x 3.2, self-contain 7.2 x 3.2, mini-flat 8 x 3.4, duplex guest wing 10 x 3.8) attach to the south wall (`HomeLayout.rooms`: rect + doorway). The lot grows to hold them. Furniture is untouched; the room is just more floor, furnished through the usual Buy / Arrange flow. Wall pieces (curtains, ACs, wall art) only hang on the north or west wall, so a south room with x0 = 0 has the west wall for them.
- Yard buildings (`HomeLayout.structs`): boys' quarters, generator house, solar rack, borehole tank. They block walking and solid furniture.
- Finish level changes floor and wall materials and colours (level 2+ gets the tiled "rich" look and POP cornice; level 3 marble-look floors and gold skirting). Security draws the compound wall, then gate pillars, a sliding gate and a CCTV mast.
- A garage upgrade shows the garage through the existing parking code. Builds show scaffolding: round the new room, building spot or parking pad; a tier upgrade scaffolds the front of the house.
- `nav.ts` (`roomWalls`, `wallSegments`, `buildGrid`) and `arrange.ts` (`LayoutRef`, `homeBlocks`, `placementIssue`, `findFreeSpot` accept an upgraded layout) keep walking and arranging working.
- Server mirror: `bl_home_ext(uid)` reads the rooms and buildings from finished upgrades (`effect.geom[layout]`); `bl_furniture_check` is patched (guarded replace) so a piece can stand in an extension room, the doorway stays clear, the shared wall and yard buildings block solid pieces. The same numbers live in the TS `GEOM` table and in the migration (re-seeded on every run so code and server never drift): `node scripts/home-upgrade-check.mjs --sql` prints them, `--geom` finds free yard spots, no flag verifies (no clashes with fixtures, doors clear, every new room and building reachable from the front door, plain layout unchanged).
- Guests see the host's upgrades (`house_upgrade_home(owner)` uses the same visit rule as `garage_home`).
- Dev page: `/dev/home?l=face_me&o=lapo&up=ext_bedroom,paint_fresh&build=gen_house`.

## UI
- Phone -> Houses -> "Upgrade your home": the builders card (scaffold icon, progress bar, time left), "Your home has", then cards by category with price, time, effect chips and preview text. Tap a card to open it, then "Start building".
- A builders pill on your home screen while something is being built (tap opens Houses).
- Toast when done. Help article "Upgrade your home" and a "What's new" tour step (`houses`).

## Admin
- Content -> House upgrades (all columns above).
- Players -> detail -> House upgrades: what is built or building, and **Grant** (free, instant, audited as `house_upgrade_grant`, player gets an event). A grant must fit the player's home type but skips requirements and costs.

## Defaults the owner should know
- Tenant pays the works plus a 10% landlord fee; 50% of the works price comes back when you move out (unfinished builds in full). Fees are never refunded.
- One build at a time. Build times are real minutes and listed above; Settings -> Rent -> "Upgrades: build time %" scales them (0 instant).
- Hostel rooms can never be upgraded.
- Prices are my estimates for Benin City, in line with the garage prices; tune them in Content -> House upgrades. Tier upgrades are deliberately expensive (3.5M, 8M, 22M renovation fee) because the rent difference alone is tiny.
- Wall-hung furniture only fits on the north or west wall, so it works in the new room only where that wall exists.
- Hostel / other homes: "Upgrade to a duplex" scaffolds the front of the house, not the new rooms, because the plan only changes when it finishes.

## Tests
`supabase/tests/house_upgrades_test.sql`: catalogue and list, who may upgrade (hostel, visiting, rent owed, wrong home type, switch off), requirements, paying (bank first, landlord fee, ledger), build timer with time travel (`bl.test_offset_seconds`: builders working, half way, lazy settle, toast list once), effects (room furnishable, doorway blocks, bonuses reach `do_activity`, capped, garage + car space), in-place tier upgrade (furniture and garage kept, rent, scene, released old tier), sale value and moving out (refund, ledger), admin grant + audit, grants and RLS.
