# Free roam (walk and drive the whole city in 3D)

Opt-in third-person roaming in the real 3D streets of Benin City. Nothing changes for players who never use it. Phase 1 walked the King's Square box. **Phase 2** (this document) opens the **whole city map**: streamed chunks, collision everywhere, your own car, hailing a keke, a search for the GPS line, the closed airport.

Look: the same calm, clean, flat-shaded low-poly as the 3D map and the drive scene, at human scale. Procedural geometry only, theme tokens for the UI (Light and Dark), no real brands.

## Where things live
| Piece | Files |
|---|---|
| City bounds, speeds, streaming defaults | `src/art/roam3d/area.ts` |
| World data from the SAME layout as the 3D city map: buildings (heights and palettes by district), OSM footprints, landmarks, trees, lamps, GRA compound walls, stalls, kiosks, doors / arches / the shut gate, edge fence, walking grids | `roam3d/world.ts` |
| Chunk index (what lies in which 120 m square) | `roam3d/chunks.ts` |
| Collision (pure TS) | `roam3d/collide.ts` (circles for people), `carphys.ts` (the car), `player.ts`, `traffic.ts`, `peds.ts`, `gps.ts` |
| Streaming + meshes | `roam3d/engine/stream.ts` (scheduler, instanced trees / shadows / lamp pools), `street.ts` (chunk builder generator, far backdrop), `soup.ts` (typed-array triangle soup, chunk clip) |
| Scene (react-three-fiber, lazy) | `roam3d/engine/RoamScene.tsx`, `carview.ts` (your car), `cars.ts` (traffic models) |
| HUD, controls, mini-map, search / hail sheet | `roam3d/RoamView.tsx`, `RoamMap.tsx`, `RoamSheet.tsx`, `roam3d.css` |
| Game integration | `screens/game/RoamHost.tsx`, buttons in `screens/Game.tsx`, `state/ui.ts`, `api/roam.ts`, `roam3d/access.ts` |
| Server | `supabase/migrations/20261118000100_roam.sql` (phase 1), `20261119000100_roam2.sql` (phase 2); tests `supabase/tests/roam_test.sql`, `roam2_test.sql` |
| Collision stress test | `node scripts/roam-collide-check.mjs [--quick] [--only=1,2,3,4,5] [--seed=N]` |
| Dev page (no login) | `/dev/roam?start=oba_market&hour=21&theme=dark&gfx=low&fps=1&car=kia_rio_used&drive=1&cam2=inside&rain=1&sheet=keke&dest=police_hq&x=500&y=545&h=1.5&yaw=&pitch=&dist=&debug=1` |

Dev API in the browser console (`window.__roam`): `stats()`, `stream()` (chunks, build times, JS tick time, `renderer.info` memory), `teleport`, `cam`, `settle`, `advance(sec)`, `setInput`, `auto({mode:'walk'|'drive'})` (a scripted walker / driver that follows routes to random places forever), `car.*`.

## Entry and exit
- **Step outside** (home chip row) and **Walk the city** (map view row): on any active place (the whole city is open, setting `roam.area.all`). Calls `roam_start`, the street opens at the place's door. With `roam.area.all` off the old King's Square box applies and **Go to King's Square to walk** returns.
- **Go in** at a door: `roam_enter(place)`. On success the game refreshes, free roam closes and the place opens exactly as today. **Leave** returns to the map.
- **Hail keke** and the car button work only inside the street. **Quick travel** from the map stays available everywhere.

## Controls and UI (kept out of the way)
Touch: joystick bottom-left, drag anywhere else to orbit, Walk / Run (Brake while driving), the contextual action (Go in / Talk), the **car button** (Get my car / Get in / Get out), top-right: Leave, view, **search** (destination for the GPS line anywhere in the city), **Hail keke** (appears when you stand on a pavement beside a road). Keyboard: WASD or arrows, Shift run, Space brake, E / Enter action, G car, V view, M map, R run toggle.
Driving: stick up = go, down = brake then reverse, left / right = steer; the Brake button is the hand brake. Chase view, or **Driver view** with the drive scene's dashboard (steering wheel that turns, speed, fuel gauge, warning lights, wipers in the rain).

## Streaming design
- The city (1000 x 1000 m map, 81 chunks of 120 m, `roam.chunk.m`) is built **at most a few milliseconds a frame**: `buildChunkGen` is a generator that yields every few buildings / road segments / one attribute copy; the scheduler (`stream.ts`) runs it for 3 ms a frame on Low and 4 ms on High (+2 ms above 12 m/s, 14 ms while the first chunks load). Next chunk = nearest to the player with a bias of up to 55 m for where you are heading.
- **Detail radius** `roam.chunk.load_m` (200 m on High, 150 m on Low = 75 %): chunks whose nearest edge is inside it are built; they are disposed 40 m beyond it (geometry only, materials, the sign atlas and the instanced meshes are shared). Fog is 60-340 m (High) / 45-270 m (Low) so nothing pops in view.
- **Backdrop**: beyond the detail radius up to 1.75x of it, each chunk is ONE merged mesh of plain box buildings, road ribbons and ground (one draw call, built in a couple of milliseconds). A chunk shows its backdrop until its detailed mesh is in.
- One chunk is built with the Phase 1 code (windows, doors, awnings, shop fronts, signs, lamps, props, landmark models) but visits only the items listed in it (`chunks.ts`) and keeps only the triangles whose centre lies in the chunk (`Soup.clip`), so a building on a border is split cleanly: no seams, no duplicates. The soup writes into growable typed arrays with flat normals computed on the way (no per-frame garbage, no `computeVertexNormals`).
- **Trees, tree shadows and lamp pools** are three shared instanced meshes refilled when a chunk comes or goes; the camera fades trees between you and the lens (`eachTreeNear`).
- Before the first frame the 3x3 chunks round the player are built behind the "Stepping out" screen.
- **Collision is not chunked.** The whole city's static colliders (about 2,300 polygons, 10,200 edges, 1,600 posts and trunks: a few hundred KB) live in one spatial hash built once with the world (about 1.5 s on a desktop, behind the loading screen), so the set around the player is always complete before the player can reach it, at any speed. Only meshes stream.

### Districts and look
Heights, palettes and crowds follow the city's districts (`drive3d/district.ts`): the centre grows to 4-5 floors, GRA is low white villas under terracotta / green / slate roofs behind compound walls with a gate gap and yard trees, UNIBEN / UBTH campus is long low cream blocks under green roofs, markets and crowded quarters stay small and rusty, the outskirts are huts. Markets: up to 44 stalls (Oba Market) with sellers and umbrellas, signed entrance arches. Motor parks: a yellow entrance arch and **danfo minibuses** (deep body, black waist band, glazed cabin, roof rack) on the pad. Every place has an entrance: a door with awning and sign on a building (or a small shop put up beside the road), an arch (museum, markets, motor parks, campus, shrine, farm, stadium) or a kiosk (PoS stands, street spots). Every other building gets a door; some on the main roads are small shop fronts with made-up names; lamps every ~21 m with warm pools at night.
**Benin Airport** is present but closed: a shut steel gate between posts, a red and white barrier, its name and an **"Under construction"** board. Walking up to it shows "Go in"; the server refuses (`inactive`: "Benin Airport is under construction. Check back soon.").
Crowd: walkers recycle round the player (never in front of the camera close up) with a density per district (market 1.0 ... GRA 0.18, outskirts 0.07); sellers and idlers move to free stalls / doors near you.

## Your own car
- **Rules as the drive scene**: car, SUV, pickup, motorcycle or bicycle you own (`vehicleFor`, the primary vehicle `bl_driving_item`), same models (`vehicleKit`: body, steering and spinning wheels, brake lights), same cockpit and dashboard components, headlight cones and tail lights at night, wipers and rain streaks from the server's daily rain schedule (`bl_drive_weather`), condition and fuel chips.
- **Get my car**: it appears at the nearest free kerb 8 to 45 m away (parallel to the road, clear of colliders, never at a junction, never within 8 m of any person or traffic car, fades in over 0.7 s); a blue beam marks it. **Get in** at the driver door (left side, within 3 m) calls `roam_set_mode('car')` (the server checks ownership, condition above 0, fuel above 0); **Get out** puts you beside the driver door (or the other side / the rear) and records where the car stands (`roam_set_mode('walk', x, y, a)`). Pulling up at a place by car leaves the car at its kerb for the next walk. It is also found where you left it.
- **Park anywhere legal**: the car must be nearly stopped and within about a metre of the carriageway edge or off the road (`parkLegal`); "You cannot leave it in the middle of the road".
- **Physics** (`carphys.ts`): kinematic bicycle model (steering angle tightens with speed, tops out at 20 m/s on a sedan, 6.5 m/s on a bicycle, slower off the road, less grip in rain), body roll into the turn, nose dip under braking, wheels spin with the real distance. Fixed 60 Hz steps.
- **Collision**: the body is a set of circles (big ones down the middle, rows of small ones along nose and tail, corner discs) moved in **sub-steps of at most 5 cm**, pushed out of walls, poles, trunks, parked cars (statics) and traffic (boxes). A step that cannot be resolved returns to the last valid pose. Impacts above 1.6 m/s count as **light**, above 6.5 m/s as **hard** (0.8 s cooldown); the car loses speed, bounces a little, the camera shakes. No tunnelling: the stress test checks every step.
- **Pedestrians are a soft collider**: they step aside early (before a moving car is within 4 m + 1.1 s of travel, up to 3.6 m/s), and the car is blocked 0.7 m before touching one (no damage, no contact). NPC cars brake for your car (three circles) like for a person, keep a gap in which they could stop dead, and **never fade in within 8 m of a person or your car** (they wait unseen at the end of their stretch, braking smoothly, or are held at the start). This also fixes the Phase 1 rough edge where a car fading in could shove a standing player.
- **Fuel and damage**: the gauge falls with the distance driven (client estimate: litres per km of the vehicle x `roam.drive.fuel_scale`), and every ~4 s `roam_drive_report` sends the metres, the light / hard hits, the position. The server clamps and applies (below) and answers with the real tank and condition. **0 fuel**: the car rolls to a stop and the **Out of fuel** card offers **Push the car to the kerb** (free), **Call a mechanic** (`drive.dry.*` settings: cash, litres, a short wait before the car starts again) or **Hitch a keke** (parks the car and opens the hail sheet at the normal fare). **Condition 0**: the car will not start ("Repair it at the Mechanic Village, or hail a keke").

## Hail a keke
On any pavement beside a road the **Hail keke** button appears (setting `roam.keke.enabled`). It opens the place list (distance from you, sorted, with search); picking one calls `roam_hail_keke(dest)`, a guarded wrapper round the existing `travel_start(dest, 'keke')`: normal fare, normal trip clock and keke rules (keke only between keke-friendly places), the existing 3D ride, then free roam opens again at the destination door (`roamPending`). The airport and other closed places are refused by travel. Not from inside your car.

## GPS search
The magnifier button lists every place in the city (name, kind, distance), searchable; picking one draws the green line and the beam. On foot the line follows pavements and crossings (A* on a 1 m grid of the colliders); in the car the line is wider. The mini-map opens to the whole city; tap a pin for the same line.

## Collision design (people)
- Statics: polygons as edge segments with outward normals and **thickness** (a thin compound wall or gate is never treated as "deep inside" from its far side; this also fixed a phase 1 tunnelling case at tiny OSM slabs), posts and trunks as circles, in a dense hash (CSR arrays, no allocation per query).
- The player is a circle (r 0.32 m); `move()` uses sub-steps of at most 0.4 x radius and pushes out of overlaps; motion along a wall survives (slides); a squeezed step returns to the last valid spot.
- Camera collision: a height-aware ray from the body (walking), pulled in by buildings in the chase cam.

### Stress test (`scripts/roam-collide-check.mjs`, whole city, seed 424242)
1. **Static**: 1,750,000 random moves (walk, run, 9, 14, 30, 60 m/s, hitch frames to 0.25 s, aimed at walls and corners) from random spots all over the city: smallest clearance 0.319 m (radius 0.32), inside a collider 0, outside the city 0; sliding along walls keeps 100 % of free speed, no backward jitter.
2. **Cars and people**: 260 cars, 27 pedestrians, 240 s, scripted players working among the cars: 0 player / car overlaps, 0 car / car overlaps, 0 pedestrians inside colliders, fastest push 4.9 m/s (no shoves).
3. **Doors and GPS**: all 40 places' standing spots are clear and reachable (a final pass moves a spot to the nearest reachable free cell when later colliders sealed a pocket); 1,560 routes between all pairs, none unreachable, none through a collider.
4. **Driving**: 260 drives (sedan, SUV, pickup, motorcycle, bicycle) over the whole city, 468,000 fixed steps, 16,800 m, up to 17.5 m/s, aimed at walls and poles, with and without traffic, 4 standing pedestrians ahead on a quarter of the runs: 342 light and 168 hard hits; after EVERY step an independent exact test of the oriented box: **never inside a collider** (worst brush 4 cm at a corner), never outside the city, **no step jumps (0 tunnelling)**, never deep inside a traffic car, never within the soft margin of a pedestrian.
5. **Spawning**: 40 lane starts with a person standing there for 25 s: 398,000 fade-in checks, 0 cars appeared within 8 m (47,000 held-back car steps).

## Server (positions are cosmetic; money, fuel and damage are not)
`roam_sessions` (user_id key, no profiles column, no FK, no trigger, RLS on, no grants). Phase 1 RPCs: `roam_start`, `roam_enter`, `roam_leave` (see the migration header). Phase 2 (`20261119000100_roam2.sql`, live functions patched by guarded single replace through `pg_temp.roam2_patch`):
- **Area**: `bl_roam_in_area` is "any place" when `roam.area.all` is on (inactive places are still refused by `roam_enter`: `inactive`, travel's own words; your own home is allowed). Off = the old box.
- `roam_set_mode(mode, vehicle, x, y, a)`: `walk` records where the vehicle was left (clamped to the map); `car` checks `roam.drive.enabled`, ownership (inventory, category vehicle), condition (`wont_start`), fuel (`no_fuel`) and a mechanic still working (`busy`), counts against the rate window.
- `roam_enter` anti-teleport uses the mode: walking pace (`roam.max_speed_mps`) or `roam.drive.max_speed_mps` in the car, and in the car the session must have **reported at least `roam.drive.min_report_pct` % of the distance** through fuel checkpoints ("You have not driven that far yet"). Arriving by car applies the same hooks as travel (`bl_vip_arrival`, `bl_roll_street_robbery` with mode `car`, its own multiplier `crime.mode_mult_car`), no fare, and leaves the car at the place.
- `roam_drive_report({dist_m, light, hard, x, y, a})`: only way fuel burns and damage lands. Rate limits: at most one per `roam.drive.report_gap_s`, `roam.drive.max_reports_min` a minute. Distance: a JSON number, clamped to max drive speed x elapsed + `roam.drive.slack_m`. Fuel burn: distance x `roam.drive.fuel_scale` x litres per km of the class (`drive.fuel.lpk_*`) x wear. Hits: counts, at most `roam.drive.max_hits_report` and elapsed / `roam.drive.min_s_per_hit` + 1; damage = light x `damage_light` + hard x `damage_hard` (x `drive.rain.damage_mult` in rain), clamped per report (`max_damage_report`) and per rolling minute (`max_damage_min`); condition floors at 0, the tank at 0; the answer carries `empty` / `wont_start`.
- `roam_dry_choose('push' | 'mechanic')`: out of fuel, with the drive scene's costs and waits (`drive.dry.*`).
- `roam_hail_keke(dest)`, `roam_car_info()`.
Tests: `roam_test.sql` (phase 1, run with `roam.area.all` off) and `roam2_test.sql` (settings, whole city, closed airport, mode and ownership, driving anti-teleport, fuel validation and clamps, damage clamps, rate limits, robbery with mode car and no fare, out of fuel, keke, structure and grants). Time is pinned with `bl.test_offset_seconds`; street robbery is switched off or forced where money is asserted.

## Tunables (Admin -> Settings -> Free roam, category `roam`)
Phase 1: `roam.enabled`, `roam.area.enabled`, `roam.area.x0/y0/x1/y1` (the box, used when `roam.area.all` is off), `roam.max_speed_mps` 6.5, `roam.door_slack_m` 15, `roam.min_enter_s` 1.5, `roam.session_ttl_s` 7200, `roam.rate.window_s` 60, `roam.rate.max_calls` 20.
Phase 2: `roam.area.all` (whole city), `roam.drive.enabled`, `roam.drive.max_speed_mps` 24, `roam.drive.fuel_scale` 8 (a street kilometre burns that many real kilometres of fuel: a 45 L sedan lasts about 50 km), `roam.drive.report_gap_s` 3, `roam.drive.max_reports_min` 24, `roam.drive.slack_m` 40, `roam.drive.max_hits_report` 6, `roam.drive.min_s_per_hit` 1.2, `roam.drive.damage_light` 1.2, `roam.drive.damage_hard` 4.5, `roam.drive.max_damage_report` 15, `roam.drive.max_damage_min` 30, `roam.drive.min_report_pct` 60, `roam.car.ready_s` 4, `roam.keke.enabled`, `roam.chunk.m` 120 (80-200) and `roam.chunk.load_m` 200 (100-400), the two streaming hints the client reads. Plus the Drive settings it reuses (`drive.fuel.*`, `drive.damage.*`, `drive.dry.*`, `drive.rain.*`, `drive.weather.*`).

## Performance (390 x 844 and 240 x 420 software rendering, desktop CPU; `?fps=1` shows it live)
Measured while a scripted walker / driver crosses the city (`__roam.auto`), and with a 360-hop trip across the whole city:
| | draw calls | triangles on screen | JS per frame (avg / worst slice) | chunk build (CPU) |
|---|---|---|---|---|
| Graphics High, walking | 63-71 | 95-153k | 2.5 ms | 3-45 ms a chunk, slices <= 2.6 ms (5.5 ms for a landmark chunk) |
| Graphics High, driving | 72-80 | 90-134k | 3.5-4 ms | |
| Graphics Low, walking | 41-45 | 48-53k | 1.2 ms | |
| Graphics Low, driving | 58-62 | 52-100k | 1.7 ms | |
Low: detail radius 150 m, fog 45-270 m, 8 + 4 + 1 people instead of 16 + 8 + 3, DPR 1.1, no antialiasing, no window frames or bars. The draw calls are the visible chunks (4-5 meshes each, frustum culled), the backdrop meshes, 8 instanced meshes (traffic, trees, shadows, pools), 14-ish single-call crowd rigs and your car. No per-frame allocation in the physics loop; traffic far from the player skips the people checks.
**Memory**: over a 2-lap trip across the whole city (165 chunks built, 149 disposed) `renderer.info.memory.geometries` stayed in a 74-114 band, textures flat after the crowd rigs were in (25-28), JS heap 114-146 MB after GC: nothing leaks. JS heap while driving 140-170 MB. Real Android frame time was not measured (software rendering here): the hitch budget is what to watch (chunk slices of 1-3 ms desktop, a landmark slice 5 ms).

## Limits / left for later
No walking inside buildings, no injuries or ragdolls, no real-time other players in the street, NPC "Talk" is a greeting line, opening hours are not checked by `roam_enter` (the place screen shows closed, as with travel). Fuel burn on the client between checkpoints is an estimate; the server's answer wins. The car is kinematic (no drifting, no body damage on the model, the camera shakes and the condition falls). The server cannot see that a car really drove the route (positions are cosmetic): it caps what a checkpoint may claim and requires the reported distance before pulling up at a place. The far backdrop has no trees. The night sky is a flat dark blue. Dev-only collider overlay: `?debug=1`.
