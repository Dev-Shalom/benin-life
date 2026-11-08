# Free roam, phase 1 (walk the streets round King's Square)

Opt-in third-person walking in the real 3D streets. Nothing changes for players who never use it. Phase 1 covers one area: Ring Road, King's Square and the streets round it (map box x 395..610, y 392..645, 11 places: National Museum, Oba Market, Ring Rd PoS, Oba's Palace, Igun Street, Mama Osas Buka, Police HQ, Bronze Bank, Sapele Rd PoS, Ekiosa Market, Mission Rd Flats).

## Where things live
| Piece | Files |
|---|---|
| Area, speeds, player radius | `src/art/roam3d/area.ts` |
| World data (from the SAME layout as the 3D city map): buildings, OSM footprints, landmarks, trees, lamps, stalls, kiosks, doors, edge fence, walking grids | `roam3d/world.ts` |
| Collision (pure TS) | `roam3d/collide.ts`, `player.ts`, `traffic.ts`, `peds.ts`, `gps.ts` |
| Scene (react-three-fiber, lazy) | `roam3d/engine/RoamScene.tsx`, `street.ts` (merged meshes), `soup.ts`, `cars.ts` |
| HUD, controls, mini-map | `roam3d/RoamView.tsx`, `RoamMap.tsx`, `roam3d.css` |
| Game integration | `screens/game/RoamHost.tsx`, buttons in `screens/Game.tsx`, `state/ui.ts`, `api/roam.ts`, `roam3d/access.ts` |
| Server | `supabase/migrations/20261118000100_roam.sql`, test `supabase/tests/roam_test.sql` |
| Collision stress test | `node scripts/roam-collide-check.mjs [--quick]` |
| Dev page (no login) | `/dev/roam?start=oba_market&hour=21&theme=dark&gfx=low&fp=1&dest=police_hq&open=1&debug=1&fps=1` (also `x y h yaw pitch dist`) |

## Entry and exit
- **Step outside** (home chip row): if the home place is inside the area, calls `roam_start` and opens the street at its door; otherwise the button reads **Go to King's Square to walk**: opens the normal travel picker for the museum, and when the trip ends there free roam opens by itself (`roamPending`, expires after 20 min).
- **Walk the city** (map view row) when the place you are at is inside the area. Coming out of a place puts you at its door.
- **Go in** at a door: `roam_enter(place)`; on success the game refreshes, free roam closes and the place opens exactly as today (same sheet / scene). **Leave** returns to the normal map.
- All buttons hide when `roam.enabled` or `roam.area.enabled` is off, or the place is outside the box.

## Controls
Touch: joystick bottom-left, drag anywhere else to orbit, **Walk/Run** and the contextual action (Go in / Talk) bottom-right, view button (third / first person) top-right, tap the mini-map to open it and tap a pin to get a GPS line. Keyboard: WASD or arrows, Shift run, R run toggle, E / Enter action, V view, M map. Camera: over-the-shoulder with wall collision (pulls in, hides the body when close), or first person (remembered per device).

## How the world is built
Map units are metres (x east, y south, same as the city map). Roads (kerb strips, edge lines, centre lines, no markings inside junctions), houses and OSM footprints with plinth, windows (only on walls facing open ground), a door on every building, awnings and sign boards on place doors; arches for the museum and markets, kiosks for PoS stands, landmark models drawn by the city's own `buildLandmarks`; stalls with sellers at the markets; extra lamps and parked cars; a fence and road-works barriers on the area edge; a low-detail backdrop (+150 m, one wall quad per edge) under fog. Day/night from the game clock through `cityLight`; night adds lit windows, lamp pools and a small light that walks with the player.

## Collision design
- Statics: building / landmark / stall / car polygons as edge segments with outward normals, trunks, lamps and arch posts as circles, in a dense spatial hash (CSR arrays, no allocation per query). Area edge = rectangular bounds.
- Dynamics: pedestrians (circles) and cars (oriented boxes) set each step.
- The player is a circle (r 0.32 m). Fixed 60 Hz steps (max 6 per frame). `move()` splits any displacement into sub-steps of at most 0.4 x radius, so nothing can tunnel at any speed, then pushes the circle out of overlaps (deepest first, up to 10 iterations). Motion along a wall survives, so it slides; corners resolve radially; if a step cannot be resolved (squeezed) it returns to the last valid spot. A circle that starts valid never ends inside anything.
- Cars follow the city's lanes and speeds (x0.8) but keep their own travelled distance: they brake for the car ahead, for the player and for pedestrians, and never move into a spot overlapping a person. A moving car that does touch you shoves you gently sideways (capped), no injury in phase 1.
- Camera collision: a ray from the body, height aware (low obstacles do not pull the camera in).
- GPS: A* (`sim/nav.ts`) on a 0.5 m grid built from the colliders; carriageways are closed except at crossings (about every 45 m and at junctions) so the line follows pavements; falls back to the open grid.

### Stress test result (`scripts/roam-collide-check.mjs`)
1,750,000 random moves (walk, run, 9, 14, 30 and 60 m/s, hitch frames up to 0.25 s, moves aimed at walls and corners) against the real colliders: smallest clearance 0.319 m (radius 0.32), inside a collider 0 times, outside the area 0 times; sliding along walls keeps at least 91 % of free speed with no backward jitter; 240 s of traffic (100 cars) and 27 pedestrians with scripted players running at cars: 0 overlaps player/car, 0 car/car, 0 pedestrians inside colliders; 110 GPS routes between all places, all reachable and walkable.

## Server (positions are cosmetic)
`roam_sessions` (user_id key, no profiles column, no FK, no trigger, RLS on, no grants). RPCs (security definer, volatile): `roam_start(place)` (must be at that place, not travelling / busy / jailed, place inside the area), `roam_enter(place)` (needs a session younger than `roam.session_ttl_s` started at the place you are at; the walk from the session place needs at least `(distance - door_slack) / max_speed` seconds since the last anchor and never less than `min_enter_s`; refusals `far`, `outside`, `rate` come back as `{ok:false, message}` so they still count against the rate limit; success moves `location_id` like arriving, plus `bl_vip_arrival`), `roam_leave()`. Rate limit: `roam.rate.max_calls` per `roam.rate.window_s`.

## Tunables (Admin -> Settings -> Free roam, category `roam`)
`roam.enabled` (master), `roam.area.enabled`, `roam.area.x0/y0/x1/y1`, `roam.max_speed_mps` 6.5, `roam.door_slack_m` 15, `roam.min_enter_s` 1.5, `roam.session_ttl_s` 7200, `roam.rate.window_s` 60, `roam.rate.max_calls` 20. Client-side speeds (walk 2.0, run 4.9 m/s) are in `area.ts`. The 3D street is built for the default box; change the box only together with the client.

## Performance (390x844, SwiftShader, `?fps=1`)
Static street 105k triangles but in 25 frustum-culled chunks: **about 20-27 draw calls and 62-90k triangles on screen** (Graphics High); chunking cut the first measurement from 126k. Merged vertex-coloured meshes, instanced trees (30 tris each), cars (one instanced mesh per kind), one blob-shadow instanced mesh, one sign atlas. People are 1-draw-call crowd rigs (player 0.65 detail, NPCs 0.3, built one at a time in the background; Low: 5 walkers + 4 sellers + 1 idler instead of 10 + 8 + 3, DPR 1.1, no antialias). No per-frame allocation in the physics loop. Real Android frame time not measured (software rendering here).

## Limits / left for later
Phase 1 only: no walking inside buildings, no injuries or ragdolls, no real-time other players in the street, no weather, NPC "Talk" is a greeting line. Few windows because most OSM footprints are small and packed. Opening hours are not checked by `roam_enter` (the place screen shows closed, as with travel). Homes are not in the area today, so Step outside normally offers the King's Square trip. Dev-only collider overlay: `?debug=1`.
