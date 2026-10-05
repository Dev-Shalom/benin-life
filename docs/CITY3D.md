# 3D Benin City map (R5)

The dock's **Map** view shows a low-poly 3D Benin City. The Phase 1 2D map is kept only as the **lite fallback** (see "Fallback rules" below).

## Where things live
| Piece | Files |
|---|---|
| Map view: picks 3D or lite 2D, Lite badge, still frame while suspended | `src/art/city3d/CityView.tsx` (in the Game chunk; no three.js) |
| Public API | `src/art/city3d/index.ts` (`CityView`, `FILTERS`, `COMING_SOON`, `matchesFilter`, `placeEmoji`) |
| Data: map↔world, place emoji, filters, coming-soon pills, exit signs, district names | `src/art/city3d/model.ts` (no three.js) |
| Road-following travel routes (graph + Dijkstra over the map roads) | `src/art/city3d/route.ts` |
| Procedural layout in map space (roads, side streets, buildings, trees, cars, lamps) | `src/art/city3d/engine/layout.ts` |
| three.js meshes (ground, roads, river, landmarks, instancing) | `src/art/city3d/engine/build.ts` |
| Canvas, camera, gestures, labels overlay, filters, travel overlay | `src/art/city3d/engine/CityScene.tsx` (lazy chunk) |
| Day/night | `src/art/city3d/engine/light.ts` (built on the home's `homeLight`) |
| Overlay styles (pills, chips, controls) | `src/art/city3d/city3d.css` (loads with the lazy chunk); `.city-view` and `.lite-badge` live in `src/styles/game.css` |
| Dev page | `/dev/city` (dev server only, see below) |

## Layout data source
Everything is laid out from the **same map-space data as the 2D map**: `src/art/map/mapGeo.ts` (`ROADS`, `RING`, `RIVER`, `BRIDGE`, `PALACE`, `CAMPUS`, `UBTH`, `AIRPORT`, `RUNWAY`, `TERMINAL`, `POLICE`, `MARKETS`, `CORES`, `GRA_ZONE`, `FARMLAND`, `GROVE`, `RAMAT`, `DISTRICT_TINTS`), which follows `docs/MAP_GEO.md`. Place positions come from the `locations` table (x/y in 0–1000, north up).
- World units: `x = (mapX − 500) × 0.1` (east), `z = (mapY − 500) × 0.1` (south), `y` up. King's Square is the origin. The camera looks north, so **north is up on screen**, same as the 2D map.
- The layout is deterministic (seeded PRNG) and built once per session (~55–75 ms on a laptop, SwiftShader).
- Density (`CORES`) decides how many buildings line each road and how much infill there is. District style: `core` (Oredo, 2–4 storeys, flat roofs), `gra` (big white houses, hip roofs, many trees), `cramped` (Upper Sakponba, Aduwawa, Ekenwan, outer Siluko: small rust-zinc blocks), `campus` (UNIBEN faculty rows, green roofs), `market` (coloured tarps around each market), `res` (everything else).

## What is in the city
- Laterite ground that turns to bush at the edges, lawns in the GRA/campus/UBTH, green banks along the river, crop fields on the NW farmland (Iguobazuwa side).
- **Ring Road** around **King's Square** with the round **National Museum** drum in the middle (lawn, paths, trees, flags).
- **Oba's Palace** WEST of King's Square, outside the ring: laterite-red compound walls, the hall and wings with steep pyramid roofs, a ceremonial gate facing the square, and a **bronze bird** on the tallest roof.
- Radial roads at the real bearings (Lagos/Ugbowo N to Uselu, UBTH, UNIBEN and Oluku; Mission NNE; Akpakpava NE over the **Ikpoba bridge** to Ramat Park; Auchi ENE; Agbor E; Sakponba SE; Sapele SSE; Airport SW; Ekenwan WSW; Siluko NW → Upper Siluko), the three East Circulars, fishbone side streets.
- The **Ikpoba River** N–S east of the centre with gallery forest; the bridge deck on Akpakpava Rd.
- **Ramat Park** roundabout with a monument and the **go-slow**: bumper-to-bumper queues on Akpakpava, Auchi and Agbor roads that creep stop-go.
- Landmarks: Oba Market + the other markets (zinc sheds + tarps), UNIBEN gate + Senate block + stadium, UBTH tall block with red crosses, Benin Airport (runway SW, terminal, tower, parked plane), Police Command HQ (blue/white, Nigerian flag), motor parks (pads, shelters, parked danfos), Baba Osagie's thatched shrine in the grove, farm huts.
- Free traffic on the big roads, street lamps on the ring and main roads, instanced trees and palms.

## Labels (HTML overlay)
- Every place is a white emoji pill (`placeEmoji`, short names from `PIN_META`). The overlay is positioned from the camera inside the render loop (no React re-render per frame).
- **Greedy placement** in screen space, in priority order: travel marker, selected, current, travel destination, filter matches, big landmarks (`LANDMARKS`), other tier-1 places, coming-soon pills, tier-2 places, exit signs, district names. A pill that would overlap becomes a small emoji **dot**; if the dot overlaps too it hides. Tier-2 places show as dots when zoomed out (short side > 34 world units). Areas under the HUD pill + chips, the bottom HUD and the zoom buttons are reserved (no labels).
- Current place: green pill with a "You are here" tag + a green 3D pin and pulsing ring. Selected: dark pill + white ground ring. Travel: "Heading here" tag on the destination, a road-following route (white, the done part green), a keke marker with an "On the way" tag moving with `travel.progress`.
- Tonight's danger zones get a red outline and ⚠️. Player counts (`crowd`) show as a blue badge when the game passes them (it does not yet; see open questions).
- Tap a pill or dot → `onSelect(id)` → the existing `LocationSheet`. Tapping the 3D city picks the nearest place (34 px on screen, or 22 map units on the ground). A drag never counts as a tap.

## Camera
- Perspective (fov 34°), fixed yaw (north up). Pitch eases from 46° (close) to 60° (far).
- Drag pans (the ground point stays under the finger), with a short inertia; pinch and wheel zoom about the fingers/cursor; +/− buttons; **Find me** flies to the player (or the travel marker).
- `zoom` = visible size of the short screen side in world units (5–110). First open: **cover** (phones: about the 2D map's cover zoom, centred on the player); later opens in the same session return to the last view.
- Selecting a place flies it into the part of the screen the sheet leaves free (phones: above the bottom sheet; desktop: left of the 460 px side sheet). A new trip frames the whole route.
- HUD insets (`insetTop`/`insetBottom`) shift the projection so the target sits in the middle of the visible band.

## Filters
| Chip | Matches | 3D effect |
|---|---|---|
| 🔴 Go-slow | `congestion ≥ 1.5` (Ramat Park 2.2, Uselu, PoS lines) | red pulsing overlay on the roads near them (radius grows with congestion) |
| 🏘️ Neighbours | `crowd[id] > 0` | blue rings; without `crowd` data the caption says "Live player counts per place · Coming soon" |
| ⚠️ Danger zones | `isNightRisky` (risk × night× ≥ 1.4: only Upper Sakponba and Third East) | red glow (always on at night, pulsing; the chip also shows it by day) |
| 🧺 Markets | scene `market` | orange rings |
| 🏛️ Gov & services | scenes `police`, `hospital`, `bank` | green rings |
Chips toggle (several at once). Matching pills get a coloured outline and the rest fade. A one-line caption explains the last chip. `isNightRisky` now lives in `mapGeo.ts` and is shared by the 2D map, the 3D city and the risk labels.

**Coming soon** (yellow pills, tap → toast): "Airport link" at Benin Airport (fly to Lagos/Abuja). Add more in `COMING_SOON` (`model.ts`). The Bronze Tech Hub pill was replaced in V1-3 by the real place (`bronze_tech_hub`, 🚀 pill, tier 1) and a landmark model in `buildLandmarks()` (glass block, laterite wing, solar roof, gold medallion; plot `TECH_HUB` in `mapGeo.ts` kept clear of generated buildings).

## Day/night
From the game clock (`hour` float). `cityLight(hour)`: hemisphere + sun colours and strength, sky/fog colour, landmark windows (glass blue by day, warm at night), water, lamp bulbs. At night (`dark > 0.45`): lit window bands on ~55% of buildings (85% of tall ones), warm light pools under the street lamps, the danger glow. Dusk/dawn tint the sky orange.

## Fallback rules (`CityView`)
The 3D city is the default for everyone. The lite 2D `BeninMap` (lazy chunk) is used only when:
1. `navigator.connection.saveData` is on, or `effectiveType` is `slow-2g`/`2g` (`isSlowNetwork()` in `src/lib/prefs.ts`);
2. the player turned on **Lite map for weak network** (Sim sheet → Settings, `prefs.liteMap`);
3. WebGL is not available (`webglAvailable()`);
4. the WebGL context was lost while the map was on screen (or the 3D chunk failed to load).

A small badge sits under the HUD pill: "🪶 Lite map" + **Switch to 3D** (network: keeps 3D for this session; preference: turns `liteMap` off; lost: retries). With no WebGL it says "3D isn't supported on this device".

**One canvas:** the Game screen mounts either the home view or the map, never both. When the Sim sheet's Profile tab (turntable) or the Edit look sheet opens, `CityView` takes a still frame, unmounts the canvas and shows the image until the overlay closes (same as the home). Under full-screen overlays (phone, Sim sheet, Buy, panels) the canvas stays mounted but stops drawing (`paused`). It keeps drawing under the location sheet, which only covers part of it.

## Performance budget
- Target: < ~60 draw calls and < ~150k triangles. Measured (SwiftShader, `__city.stats()`): **16–18 draw calls by day, 21 at night, up to ~23 with filters/travel; ~106k triangles by day, ~115k at night** (instanced meshes are not frustum-culled, so this is the whole city).
- 1,151 buildings (walls + flat roofs in one instanced mesh, hip and gable roofs in one each), ~1,765 trees/palms (canopy, trunks, fronds), ~203 vehicles (one instanced mesh), ~300 lamps. Ground, roads, river and landmarks are merged meshes with vertex colours.
- `frameloop="demand"`: every frame only while the camera moves; ~15 fps otherwise for traffic and pulses; nothing while paused, hidden, off-screen; no animation with reduced motion. DPR capped at 1.5. `powerPreference: 'low-power'`.
- Chunks (gzip): CityScene JS **20.2 kB** + CSS 1.9 kB; the 2D map moved to its own lazy chunk (20.2 kB), so the Game chunk dropped from 42.7 to 20.6 kB. The index chunk grew 0.03 kB.
- Frame time: SwiftShader (software rendering in the container) takes ~170–190 ms for a full frame at 390×844, which is not meaningful for real phones; check on a real low-end Android. `__city.bench(n)` (dev) times n frames with a GPU sync.

## Dev page
`/dev/city?f=<preset>&h=<hour>&z=<zoom>&cur=<place>&sel=<place>&travel=<from>,<to>,<progress>&filters=goslow,danger&bare`
- Presets: `city`, `centre`, `palace`, `museum`, `river`, `ramat`, `airport`, `uniben`, `ubth`, `police`, `market`, `north`, `gra`; or `x`, `y`, `z` in map space. `bare` hides the chips and HUD insets (close-ups).
- Locations come from `src/art/city3d/dev/fixture.ts` (a snapshot of the seeded table; regenerate it if positions change). The route is tree-shaken out of production builds.
- Dev globals: `__city` (stats, bench, flyTo, screenOf, snapshot), `__cityView` (camera state), `__cityGl`.

## How to add…
- **A place:** add the row to `locations` (migration); give it a short name and tier in `PIN_META` (`mapGeo.ts`) and, if its scene's emoji does not fit, an entry in `ID_EMOJI` (`model.ts`). Regenerate `dev/fixture.ts`. Labels, filters and routes pick it up automatically.
- **A landmark model:** add a block in `buildLandmarks()` (`engine/build.ts`). Use `at2(mapX, mapY, yaw)` to set the frame, then `b.box(w, h, d, x, y, z, colour)` / `b.cyl(rTop, rBot, h, x, y, z, colour, { seg, ry })` in world units (bottom-centre placement). `{ layer: 'glow' }` parts light up at night. Keep the zone clear of generated buildings by adding it to `special()` in `engine/layout.ts` (or a polygon in `mapGeo.ts`).
- **A road:** add it to `ROADS` in `mapGeo.ts` (the 2D map draws it too); buildings, lamps, traffic and routes follow.
- **A filter:** add it to `CityFilter`, `FILTERS`, `FILTER_COLOR` and `matchesFilter` (`model.ts`) and a caption in `CityScene`.
