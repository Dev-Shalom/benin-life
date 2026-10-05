# 3D home, HUD, Sim sheet and phone (R4)

## Where things live
| Piece | Files |
|---|---|
| Game screen (home view or map, HUD, sheets) | `src/screens/Game.tsx` |
| HUD: top pill, left rail, needs card, dock, keyboard button | `src/screens/game/Hud.tsx` |
| Furniture sheet (tap furniture -> home activities) | `src/screens/game/HomeSheet.tsx` |
| Sim sheet (7 tabs) and the Edit look sheet | `src/screens/game/SimSheet.tsx` |
| Phone | `src/screens/game/Phone.tsx` |
| Keyboard shortcuts, shortcuts sheet, Buy teaser | `src/screens/game/Extras.tsx` |
| 3D home data (layouts, furniture kinds, groups) | `src/art/home3d/model.ts` (no three.js) |
| Walking paths (grid + A*) | `src/art/home3d/nav.ts` (no three.js) |
| Lazy wrapper, snapshot while suspended, no-WebGL fallback | `src/art/home3d/HomeView.tsx` |
| Canvas, camera, Sim controller | `src/art/home3d/engine/HomeScene.tsx` |
| Room shell / furniture geometry / poses / day-night | `engine/room.ts`, `engine/furniture.ts`, `engine/poses.ts`, `engine/light.ts`, `engine/build.ts` |
| Dev page | `/dev/home?l=flat&h=21.5&busy=bed` (dev server only) |
| Preferences (mute, sound, music, lite map, clean screen) | `src/lib/prefs.ts` (localStorage, try/catch) |
| Map view: 3D city / lite 2D map (R5) | `src/art/city3d/*`, `docs/CITY3D.md` |
| Mood from needs, low-need tips | `src/lib/mood.ts` |
| Cached activities + creator catalog | `src/state/catalog.ts` |

## Layout
- **Top:** one white pill. Weekday + game day + time (sun/moon), mood (emoji + label, tap -> Needs), players online (`players_online()` every 60 s; hidden if the call fails), mute (stored in prefs; there is no audio yet), cash with a green "+" (Wallet). Bank lives in the Wallet, the phone's Bank app and the Sim sheet. Under 480 px the mood and "online" labels hide; under 350 px the online count hides.
- **Left rail** (under the pill): up to 2 wish chips from the lowest needs below 45 ("Eat something", "Use the toilet"...; tap -> the matching furniture at home, else the location sheet), Dad's allowance chip (Nepo), new-player protection, and "Clean screen". Under 600 px the chips use a compact size so the rail does not cover the house.
- **Clean screen** hides the pill, chips, needs card and dock. Status banners stay. The button turns into "Show HUD".
- **Bottom:** status banners (travel, busy ring, jail, hospital) and the place chip, then the needs card (cached `AvatarPortrait`, origin badge, 6 tiny bars; tap -> Sim sheet Needs) and the **dock: Home · Buy · Map · Phone** (unread alerts badge on Phone). Desktop puts needs, dock and the keyboard button on one row.
- **Toasts** sit top-centre under the pill (`--hud-bottom` is measured by `TopPill`).
- **Views:** at home (`location_id === home_location_id`, not travelling) the 3D home shows unless the player opened the map; everywhere else the map: the **3D city** (R5, `CityView`, see `docs/CITY3D.md`), with the 2D map only as the lite fallback. Only one of the two canvases is ever mounted. Arriving home switches back to the home view.
  - Home: at home -> home view; away -> map + the home location sheet (travel picker).
  - Buy: "Buy mode, coming soon" sheet (Phase 2 catalogue preview).
  - Map: the map; the location sheet works as before.
  - Phone: the phone overlay.

## Keyboard shortcuts (desktop)
M map · H home · B buy · P phone · S Sim sheet (Needs) · T things to do here · E people here · Esc close · ? this list. Ignored while typing or with Ctrl/Alt/Cmd. No animations on keyboard actions.

## 3D home
- **One canvas**, orthographic isometric camera from the south-east, `frameloop="demand"`, DPR capped at 1.5. It redraws every frame only while the Sim walks or the player drags; otherwise 24 fps for the idle sway (12 fps asleep). Paused while a sheet covers it, not drawn when hidden/off-screen.
- **Only one WebGL canvas on screen:** when the Sim sheet's Profile tab (turntable) or the Edit look sheet opens, `HomeView` takes a still frame (`snapshot()`), unmounts the home canvas and shows the image until the overlay closes.
- **Drag** rotates the view ±43°, pinch/wheel zooms 0.85-1.9×. A drag never counts as a tap.
- **Day/night** from the game clock (`engine/light.ts`): hemisphere + sun/moon, warm indoor point light at night, window glass and lamp shades change colour, sky gradient behind the canvas.
- **Cost:** the room is merged into 4 meshes (solid, glow, glass, screens) with vertex colours: ~3.2k-5.5k triangles, 4 draw calls. The character adds ~32-40 draw calls and 8k-16k triangles (hair and outfit decide). Measured in the game (R4 check, SwiftShader): hostel 36 calls / 14.3k tris, self-contain 43 / 19.2k, duplex 44 / 21.0k; a full frame renders in 0.2-0.8 ms (`__home.bench`, dev only).
- **No WebGL / context lost:** the home's SVG scene (`src/art/scenes/home_*.tsx`) with a "Things to do at home" button.

### Layouts per housing (`homeLayoutFor(housing_id, scene)`)
| housing_id | Layout | What's in it |
|---|---|---|
| `hostel_uniben` | `hostel` | 2 bunks, lockers, 2 desks + chairs, radio, hot plate, fan; bucket bathroom, shared toilet and drum in the corridor yard |
| `face_me_ekenwan`, `face_me_aduwawa` | `face_me` | double bed, wardrobe, rug, table + radio, plastic chair, kerosene stove, fan; shared bathroom, toilet, generator, drum and clothesline in the fenced compound |
| `self_contain_uselu` | `self_contain` | bed, wardrobe, sofa, TV, centre table, fan, kitchenette + gas; own bathroom (WC, shower, sink); generator outside |
| `mini_flat_mission` | `flat` | bedroom (bed, wardrobe, AC), kitchen (counter, cooker, fridge, gas), bathroom, parlour (sofa, armchair, TV, rug, dining set, lamp); generator |
| `duplex_gra` | `duplex` | master bedroom (king bed, AC, lamp), open kitchen + island + fridge, bathroom with tub, L-sofa, big TV, dining for 4, plants, lamps; generator |
Unknown housing ids fall back by prefix, then by the location scene.

### Furniture -> activities
`ACTIVITY_GROUP` maps home activities to a group: `sleep`/`nap` -> bed, `cook_home` -> kitchen, `bathe` -> bath, `use_toilet` -> toilet, `watch_tv`/`listen_radio` -> media. Anything else is `seat`. Tapping a piece opens its group's activities (a seat also lists media; the wardrobe opens "Change your look"). When a home activity is running (`profile.busy_label` = the activity name), the Sim walks to the group's piece (`actorFor`: a piece with `actorFor: [group]` wins, e.g. the sofa or chair for TV/radio) and holds the group's pose: lie (bed), sit (sofa, chair, toilet), cook, scrub. When it ends the Sim stands up beside it. Idle Sims wander every 16-34 s.

### Add a piece of furniture
1. Add the kind to `FurnitureKind` and `KINDS` in `model.ts`: footprint `w`/`d`, `solid`, optional `group`, `spot` (where the Sim stands, local `[x, z, facing]`, +z is the front) and `seat` (sit: hips `[x, y, z, yaw]`; lie: feet `[x, y, z, yaw]`, head towards -z).
2. Build it in `buildPiece` (`engine/furniture.ts`) from `b.box()` / `b.cyl()` (bottom-centre placement, local frame). Use `{ layer: 'glow' }` for lamp shades, `'glass'` for windows/mirrors, `'screen'` for screens.
3. Place it in a layout's `furniture` (`x`, `z`, `rot` in quarter turns, optional `y` and `color`).
4. Check `/dev/home?l=<layout>` and the nav test idea in the R4 report (every actor spot reachable from the door).

### Add a home layout
Add a `HomeLayout` to `LAYOUTS` (house `w`/`d`, `lot` incl. yard, floor/patch colours, partitions with doorway gaps, low front-wall `doors`, back-wall `windows`, idle `home` spot, furniture) and map its `housing_id` in `HOUSING_LAYOUT`.

## Sim sheet
Tabs Profile / Needs / Goals / Skills / People / Career / Settings (`useUi().openSim(tab)`; `setOverlay('settings')` still works and opens Settings).
- Profile: live turntable, @name, Edit look (creator `LookPanel` without the name field, saves with `update_avatar`), home + weekly rent, dream, traits.
- Needs: the 6 needs with %, Health and Stress, "Feelings arrive soon", traits.
- Goals: dream card (progress starts in Phase 2), origin card, wishes and perks previews.
- Skills / People / Career: previews of the Phase 2 systems.
- Settings: sound effects, music, **Lite map for weak network** (`prefs.liteMap`; `CityView` reads it together with `isSlowNetwork()`), notifications placeholder, account email, admin button, log out, 18+ note.

## Phone
Lock screen (game time, weekday, latest unread alert) -> tap or swipe up -> app grid. Built apps: **KekeGo** (Ride: places by distance -> map + the location sheet's travel picker), **Wallet** (Wallet panel), **Alerts** (events list; marks read), **Bronze Bank** (balances), **Settings** (Sim sheet). Jobs, Messages, Contacts, ChopNow (food), Houses, Cars, Health, Invest, EdoBet, Family, Hustle, Edo Gov and Police open a "Coming soon" screen. The home bar goes back to the grid; Esc or "Close" closes the phone.

### Add a phone app
Add an entry to `APPS` in `Phone.tsx` (`id`, fictional `name`, emoji, tile gradient, `pitch` for the coming-soon screen). To build it, render its screen in the `app && (...)` switch or make `launch()` open a panel/sheet. Never use a real brand name.

## Bladder (server)
Migration `supabase/migrations/20261005000500_bladder.sql`, tests `supabase/tests/bladder_test.sql`.
- `profiles.bladder` (default 100). Decays `needs.bladder_per_hour` (5) per game hour × trait `effects.decay.bladder`. While it sits at 0, hygiene drops an extra `needs.bladder_empty_hygiene_per_hour` (4). Decay stays path-independent; `get_my_state` stays read-only.
- `bl_decay_row`, `bl_apply_needs`, `bl_adjust_needs` redefined (same signatures) to include bladder.
- Activities: `use_toilet` (home, free, 5 min), `ease_yourself` (buka/club/cyber/campus/hospital, ₦50), `public_toilet` (market/motorpark/street, ₦50, hygiene -2), plus `watch_tv` (flat/duplex) and `listen_radio` (face-me/hostel) for the furniture. Drinks lower the bladder (chapman, club night, football, pepper soup).
- `players_online()` -> `{count, minutes}` (authenticated only) for the HUD pill.
