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
- `zoom` = visible size of the short screen side in world units (5–80 since S3; was 110). First open: **cover** (phones: about the 2D map's cover zoom; desktop: 0.78 × 100/aspect), aimed between the player and King's Square (target = player × 0.62) so the first view shows more city; later opens in the same session return to the last view.
- S3: the target can't leave the city: `bnd(zoom) = clamp(47 − 0.4·zoom, 14, 45)` world units from King's Square, so zoomed out the city always fills the screen.
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
- Target: < ~60 draw calls and < ~150k triangles. Measured (SwiftShader, `__city.stats()`, after S3): **16–18 draw calls by day, 21 at night, up to ~23 with filters/travel; ~107k triangles by day, ~115k at night** (instanced meshes are not frustum-culled, so this is the whole city). Before S3: 16–18 / 21 calls, ~99k / ~108k triangles.
- ~1,125 buildings (walls + flat roofs in one instanced mesh, hip and gable roofs in one each), ~1,765 trees/palms (canopy, trunks, fronds), ~203 vehicles (one instanced mesh), ~300 lamps. Ground, roads, river and landmarks are merged meshes with vertex colours.
- `frameloop="demand"`: every frame only while the camera moves; ~15 fps otherwise for traffic and pulses; nothing while paused, hidden, off-screen; no animation with reduced motion. DPR capped at 1.5. `powerPreference: 'low-power'`.
- Chunks (gzip): CityScene JS **22.5 kB** (20.4 kB before S3) + CSS 2.0 kB; the 2D map moved to its own lazy chunk (20.2 kB), so the Game chunk dropped from 42.7 to 20.6 kB. The index chunk grew 0.03 kB.
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

## S3 map polish (2026-10-06)
The user said the map "looks weird". What was wrong and what changed:

| Problem (before) | Fix |
|---|---|
| The city sat on a bright orange laterite "stain" fading into saturated green; empty sand at close zoom looked like desert | New ground palette (`groundColor` in `engine/build.ts`): calm bush green → dry grass → sandy paving → pale concrete in the core, plus low-frequency value noise (`vnoise`) so big areas are not flat. Every building now stands on a **yard** (lawn in the GRA, paving in the core, packed earth elsewhere), drawn in the merged ground mesh (2 triangles each, no extra draw call). |
| Zoomed out, the map was a visible square slab in a different green; you could pan/zoom off into empty bush; radial roads and the river stopped dead at the edge | The ground grid fades into the skirt colour (no seam); open roads and the Ikpoba run on 600 map units past the edge; `ZOOM_MAX` 110 → 80 and the zoom-dependent pan bound `bnd(zoom)`. |
| Roads didn't read as roads: no names, thin marks, brown "plank" side streets | Dark asphalt, pale kerbs on every paved road, **white edge lines** + centre dashes (yellow on expressways/Ring Rd, white on main roads), broken where roads meet so junctions stay clean (`nearOther` sample grid); grey paved side streets with kerbs; Ramat Park island gets a kerb. |
| Only faded grey caps such as "SAPELE RD" floating in fields | **Road names along the roads** (HTML overlay, kind `road`): white text with a dark halo, rotated to the road's screen angle and kept upright. Names and positions come from `ROADS[].labels` in `mapGeo.ts` (MAP_GEO names) plus a candidate every ~150 map units and two on the Ring Rd; greedy placement after places, collision as a chain of small boxes along the rotated label, the same name never within 240 px, shown at zoom ≤ 50. The road-named district labels were removed. |
| District names nearly invisible (thin, 42% grey) | Darker text with a light halo by day, light text with a dark halo at night; shown at zoom 18–70. |
| Random roof confetti, every district alike | One palette per district style (`WALLS`/`ROOFS` in `layout.ts`): core = pale concrete under grey zinc and rust; residential = warm walls, terracotta/brown roofs, the odd blue; cramped = rusty zinc; GRA = white villas, terracotta/green/slate roofs on lawns. |
| Houses poking into the palace compound | Building placement tests the footprint corners against the special zones, not just the centre. |
| Palace a dark blob, bird too small | Lighter rust-red roofs; the bronze bird is 1.8× bigger on a short mast. |
| Pills clipped at the screen edge; "You are here" pill covered the player's own pin | A pill that would be cut off becomes a dot (must-show ones slide back inside). The current place's label is anchored on top of the (bigger) 3D pin, and its tag's space is reserved. Tier-2 names show up to zoom 44 (was 34) when there is room. |
| Players-per-place counts never reached the map | `Game.tsx` passes `crowd` from S1 Realtime Presence (`usePresenceStore().at`, other players only): blue count badge on pills and the 🏘️ Neighbours filter now work. |
| Danger glow a harsh red blob at night | Softer opacity (0.42 + pulse 0.2). |

Perf (SwiftShader, 390×844, dev page): day 18 calls / 98.7k → 106.8k triangles; night 21 calls / 107.6k → 115.3k; `bench(10)` ~186–200 ms per frame both before and after (software rendering, noise ±10%). No new draw calls; nothing new is allocated in the render loop beyond the small box lists the label placement already used (road labels reuse one scratch box; `roadSeen` is a module map cleared each frame). Layout still ~60–75 ms once per session.
