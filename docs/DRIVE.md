# Drive scene (3D travel with road events)

When a player travels by car, keke, ECTS Bus or drop, the game shows a 3D drive along the real Benin roads instead of a plain jump. On foot there is no drive. Style: calm, clean low-poly, muted real colours, soft light, readable on a phone.

The trip itself is server-owned (`travel_start` / `travel_arrive`, `profiles.travel_*`). The drive is a view on top of it, plus server-rolled **road events**. Since drive 2 the trip length also comes from the real route distance (see "Real trip time") and the scene draws exactly that trip: the car's place on the route is `elapsed / total` from the server's start and arrival timestamps.

## What the player sees
- **The real route**: the road graph the city map uses (`src/art/city3d/route.ts`: mapGeo ROADS plus the Ring Road, Dijkstra) is turned into a drivable track by `src/art/drive3d/track.ts`. The route is simplified to straight stretches; every real bend of 22 degrees or more becomes a junction the car turns at, **left or right as on the map**, slowing into the corner, with the car and camera swinging round (front wheels steer, the body rolls). A run along the Ring Road becomes the **King's Square roundabout** the car goes round counter-clockwise (drive on the right) with the National Museum drum on the island. Road names on the sign boards and in the route chip change as the car enters each road; a sign before a junction shows the road you are about to turn onto, or "Roundabout" and the road you leave by. Names used: Ring Road, Ugbowo-Lagos Road, Mission Road, Akpakpava Road, Benin-Auchi Road, Benin-Agbor Road, Sakponba Road, Sapele Road, Airport Road, Siluko Road, Ekenwan Road, 3rd East Circular and the side roads (`ROAD_NAME` in `model.ts`). "Lagos" appears only in the real road name.
- **Dressing that matches the district**: each 60 m chunk of street takes its look from the map's own zones (`src/art/drive3d/district.ts`, same rules as the city layout): city centre (tall pale blocks, awnings, parked cars), residential, crowded quarters (low rust-roofed blocks, umbrellas), GRA (white villas behind walls and hedges, red and green roofs, lawns), UNIBEN / UBTH campus (long low cream blocks, green roofs, lawns, many trees), markets (stalls with colourful canopies, crates and umbrellas along the pavement near Oba Market, Ekiosa and the other markets) and outskirts (sparse huts, palms). The ground tints with the district.
- **Mini-map**: a small map under the route chip (top-left) drawing the route from the map data (roads in the background, the driven part solid) with a moving dot for the car and pins for start and end. Tap it to open it bigger (with the place names), tap again to close. It sits over buildings, never the road.
- **Vehicle**: the player's own car (`usePrimaryCar`, mapped from the item id to a sedan, SUV, pickup, motorcycle or bicycle with a muted colour), or a keke, the ECTS Bus or a taxi for the other travel modes.
- **Driving feel**: smooth acceleration and braking (the speed follows a profile: slower into corners, stops for road events and the arrival), the nose dips under braking, the body rolls into turns, a slight suspension bob, wheels that turn with the steering and spin with the speed, a camera that widens a little and faint speed streaks at the screen edges as it gets faster (off with reduced motion). A few times a trip a slow vehicle (often a bus) is ahead in your lane: you close in, sit behind it and it pulls away.
- **ECTS Bus** (travel label "ECTS Bus"): a proper low-poly city bus, yellow body with a red band round it, "ECTS" lettering on both sides, a front destination board showing where it is going, windows and sliding doors. It is also the bus in NPC traffic and the buses on the city map (yellow with the red band). Riding it: the bus makes **one or two bus stops** on the way (a shelter with an ECTS sign and a yellow-and-red roof; the bus pulls in, the doors open, people get on and off, then it drives on). The stop time (5.5 s each) is part of the trip time, so the bus still arrives on the server's second. Trips under about 32 s have no stop.
- **Cameras** (one button, remembered per device): **Chase** (behind, on the route), **Side** (three-quarter from the median), **Driver** (first person with dashboard and a steering wheel that turns; handlebar for keke, okada and bicycle). On the bus the third view is **Seat**: the aisle seat of the first row, looking down the aisle and out of the windscreen (seats, poles, driver, passengers, open windows).
- **Other players**: cars with small name tags (max 8) from a light Supabase Realtime presence channel `drive:<road>` joined only while the scene is open. One tiny payload (name, vehicle) is tracked once on join: no database writes, no per-frame traffic. Skipped in poll mode, on a weak device (4 on Low graphics) and when the admin turns it off.
- **Layout**: top-left route chip (from, to, road, time left, progress bar) with the mini-map under it; top-right camera, horn and map; bottom: an event card only when something happens, the outcome line, the arrival card, and two small links (Turn back, Skip). Safe areas are respected and nothing covers the road. All UI uses the tokens in `src/styles/tokens.css`, so Light and Dark both work.
- **Horn**: a short two-tone Web Audio beep (respects mute and sound effects).
- **Skip**: closes the scene for this trip; the trip carries on and ends on time exactly as before (the old plain travel UI). **Map** does the same and opens the map. **Turn back** (tap twice) calls `drive_turn_back()`: the trip ends where it started, the fare is not refunded.
- **Arrival**: the destination as it looks on the normal 3D city map (`src/art/drive3d/engine/place.ts`). Places with a landmark on the map (National Museum, Oba's Palace, Oba Market and the other markets, UNIBEN, UBTH, Bronze Tech Hub, Police HQ, the stadium, Baba's Shrine, the motor parks, Ikpoba bridge, the farm huts) are drawn by the very same builder the city uses (`buildLandmarks` in `city3d/engine/build.ts`, asked for just that place's pieces). Every other place is the building the city map stands there: the nearest building of the city layout (same size, walls, roof shape and colours) with its neighbours and trees, an awning in the place's colour and the place name on an entrance sign. Markets also get the stalls the map shows around the sheds. The car stops at the kerb in front, the **Go in** card shows, and a push-in on the entrance follows. Only if a place had no model at all would the old gate (name board, guard hut, boom barrier) be used (`buildGate` is kept for that).
- **Setting**: Sim sheet > Settings > "3D drive when I travel" (`prefs.driveScene`, default on). Off = the old instant travel, and no road events (the client never asks for one).

## Real trip time (server-authoritative)
Migration `20261116000100_drive_realtime.sql`; test `supabase/tests/drive2_test.sql`.

`bl_travel_quote` (patched live, guarded replace with `pg_temp.drv2_patch`) now returns for every mode

`real_seconds = clamp(base + seconds_per_km * km * mode_factor, min, max)`

where `km` is the route distance (`bl_distance_km`). Short hops are short (about 25 to 40 s), cross-town trips are long (up to 150 s). Walk, keke, ECTS Bus, drop, car, motorcycle and bicycle keep their own pace through the factor. `travel_start` stores `travel_arrives_at = start + real_seconds`, and the 3D drive reads those two timestamps, so the scene ends exactly when the server says (events that add or save seconds move the arrival and the scene follows). The master switch `drive.travel.real_time_enabled` off gives the old short timings again (game minutes, `action.travel_max_seconds`); while it is on the old cap does **not** clip the trip, `drive.travel.max_seconds` is the one cap. The bus label is "ECTS Bus" (it was "ECTS Green Bus").

Defaults: base 15 s, 7.5 s per km, shortest 25 s, longest 150 s, factors walk 3, keke 1.3, bus 1.6, drop 1.1, car 1, motorcycle 0.85, bicycle 1.8. (Across town is about 12 km: a car takes about 105 s, the bus hits the 150 s cap.)

How the scene uses it (`track.ts`): the track length is chosen from the trip seconds (about 11 to 15 m of scene per second of trip, by mode), a speed profile is computed (corners, bus stops, slow-downs) and its time table is stretched to the trip's seconds. The car's wanted place is `track.sOfT(progress * total)`; a small controller keeps the car on it (it can speed up a little to catch up and never reverses). Road events stop the car on a straight stretch (the card waits until one comes, at most 14 s).

## Road events (server-authoritative)
Migration `20261114000100_drive.sql`; test `supabase/tests/drive_test.sql`.

| Event | Choices | Outcomes |
|---|---|---|
| Area boys ambush | Pay them / Drive off / Call police (switchable) | Pay: lose the demand (a share of your cash, floored and capped). Drive off: escape chance, else they take more, a repair bill and a little health. Call police: they may arrive in time (nothing lost), else part of the demand and lost time. Stress changes. |
| Police checkpoint | Show papers / Settle / Argue | Papers pass chance, else the fine. Settle: a flat amount, always accepted. Argue: waved on, else a double fine and lost time. |
| Go-slow | Wait / Take a shortcut | Wait: extra seconds, a little less fun. Shortcut: works (arrive sooner) or fails (more time, a repair cost, stress). |
| Beggar / hawker | Give / Buy pure water / Ignore | Give: cash out, fun up, stress down. Water: small cost, hunger and fun up. Ignore: a pang of stress. |

No gore. Outcomes use cash, health, stress, fun, hunger and the arrival time. Cash lost is always capped by the cash in hand.

RPCs (all `security definer`, volatile because they call `bl_me()`; no grants to anon):
- `drive_event_roll()`: called by the app about every 8 s while driving. It applies every limit, rolls the event (or none) and stores the pending card in `drive_state`. A waiting card is returned again after a reload.
- `drive_event_choose(p_choice)`: rolls the outcome, applies money (`bl_add_money`, ledger reasons `drive_ambush`, `drive_police`, `drive_goslow`, `drive_beggar`, `drive_repair`), needs (`bl_adjust_needs`) and moves `travel_arrives_at`. Only the choices on the card are accepted. A card answered after the trip clock ran out is still valid (the app holds the auto-arrive while a card is open, `useDrive.hold`); a delay then counts from now.
- `drive_turn_back()`: cancels a trip that has not arrived.
- `drive_state` (RLS on, no policies, no grants): `events_today`, `last_event_at`, `last_roll_at`, trip counters and the pending card. No foreign key to `profiles`, no trigger, nothing per player in the migration.

### Rate limits
Per Benin day cap (`drive.max_per_day`), per trip cap (`drive.max_per_trip`), cooldown between events (`drive.cooldown_s`), shortest gap between checks (`drive.roll_gap_s`), quiet start and end of the trip (`drive.min_progress_pct`, `drive.max_progress_pct`), total delay per trip (`drive.max_delay_s`), unanswered cards expire (`drive.pending_ttl_s`). A player under `drive.min_cash` is never stopped for money, only by a go-slow.

## Admin tunables
All in Admin > Settings, category **Drive scene & road events** (`game_config`, category `drive`, every row has a label, description and range; the master switch and event chance are also in the quick list).

- Trip time: `drive.travel.real_time_enabled` (off = the old short trips), `drive.travel.base_seconds`, `drive.travel.seconds_per_km`, `drive.travel.min_seconds`, `drive.travel.max_seconds`, and one factor per mode `drive.travel.f_walk|f_keke|f_bus|f_drop|f_car|f_motorcycle|f_bicycle`.
- Switches: `drive.enabled` (off = old instant travel for everybody), `drive.events_enabled`, `drive.presence_on`, `drive.turn_back_on`, and one per event: `drive.ambush_on`, `drive.police_on`, `drive.goslow_on`, `drive.beggar_on`, `drive.ambush.police_on` (the Call police button).
- Frequency: `drive.event_pct`, `drive.max_per_day`, `drive.max_per_trip`, `drive.cooldown_s`, `drive.roll_gap_s`, `drive.min_progress_pct`, `drive.max_progress_pct`, `drive.pending_ttl_s`, `drive.min_cash`, `drive.max_delay_s`.
- Mix: `drive.w_ambush`, `drive.w_police`, `drive.w_goslow`, `drive.w_beggar` (weights; 0 = never).
- Area boys: `drive.ambush.pay_pct|pay_min|pay_max|escape_pct|fail_mult|damage_cost|fail_health|police_pct|police_fail_pct|police_delay_s|stress`.
- Police: `drive.police.papers_ok_pct|fine|settle|argue_pct|argue_fine_mult|argue_delay_s|stress`.
- Go-slow: `drive.goslow.wait_s|wait_fun|shortcut_pct|shortcut_save_s|shortcut_fail_s|shortcut_fail_cost|stress`.
- Beggar: `drive.beggar.give|give_fun|give_stress|water_cost|water_hunger|water_fun|ignore_stress`.

## Where things live
| Piece | File |
|---|---|
| Host: decides whether to show the scene, builds the track for a trip, keeps the scene for the arrival shot, skip / turn back / map | `src/screens/game/DriveHost.tsx` (mounted in `Game.tsx`) |
| UI layer + event flow + speed streaks | `src/art/drive3d/DriveView.tsx`, `drive3d.css` |
| Mini-map | `src/art/drive3d/MiniMap.tsx` |
| Route to track (turns, roundabout, bus stops, slow-downs, speed profile, time table; no three.js) | `src/art/drive3d/track.ts` (road graph shared with the map: `src/art/city3d/route.ts`) |
| Road names, vehicle mapping, helpers (no three.js) | `src/art/drive3d/model.ts` |
| Which district a map point is in (no three.js) | `src/art/drive3d/district.ts` |
| 3D scene (lazy chunk): pose on the track, camera, controller, traffic | `src/art/drive3d/engine/DriveScene.tsx` |
| Streets (chunk generator), junctions, roundabout | `engine/world.ts` |
| Vehicles (ECTS Bus, wheels kit), event props, signs, cockpit, batching | `engine/vehicles.ts`, `props.ts`, `batch.ts` |
| ECTS Bus doors, destination board, inside of the bus, bus stops | `engine/bus.ts` |
| The destination as the city map shows it | `engine/place.ts` (uses `buildLandmarks` in `src/art/city3d/engine/build.ts` and the city layout) |
| Other players (presence), horn | `useOthers.ts`, `horn.ts` |
| RPC wrappers, auto-arrive hold | `src/api/drive.ts`, `src/state/drive.ts` (`StatusBanners.tsx` honours the hold) |
| Player setting | `prefs.driveScene` (`src/lib/prefs.ts`, `SimSheet.tsx`) |
| Dev page (dev server only) | `/dev/drive?from=ekenwan_room&to=oba_market&total=90&p=0.4&s=<track m>&mode=car|bus|keke|drop&cam=chase|side|inside&h=14&event=ambush|police|goslow|beggar&arrived=1&others=1&gfx=low&theme=dark&veh=camry_new` (`window.__drive.dev({s, pin, hold, top})` for screenshots) |

## Performance
- No assets: every shape is procedural. A street is generated in 60 m chunks around the car into about 24 instanced meshes (re-filled every 60 m, nothing per frame); static parts (junction asphalt, the roundabout and its ring of buildings) are merged; vehicles are single merged geometries with vertex colours, NPC traffic is one instanced mesh per kind, the player's wheels are one instanced mesh.
- Measured on SwiftShader at 390x844: **about 45 draw calls and 16k to 24k triangles** on a street (Low graphics 45 calls and 16k triangles), up to about 85 calls for the few seconds a junction shows two streets at once.
- **Graphics Low** (`useTier`): about 60 % of the buildings and trees, 9 NPC cars instead of 16, no stars, no antialiasing, DPR capped at 1.1, a shorter fog, at most 4 other players. High: DPR up to 1.6.
- No shadows (a soft blob under each car), no per-frame React state (the frame loop reads refs, the overlay re-renders four times a second), the canvas stops in a hidden tab. The destination model is built a moment after the first frame, so the trip starts at once.
- If WebGL is missing or the context is lost the scene turns itself off for the session and travel goes on as before.

## Checks
- `bash scripts/sql-test.sh -- supabase/tests/drive_test.sql`: settings, switches, every limit (progress window, gap, trip cap, cooldown, daily cap and the next-day reset, pending resume and expiry), every outcome of every event with chances forced to 0 or 100 and time pinned with `bl.test_offset_seconds`, cash never below zero, the delay cap, savings never landing in the past, a late answer, low cash, turn back, grants and RLS.
- `bash scripts/sql-test.sh -- supabase/tests/drive2_test.sql`: the trip time settings, the "ECTS Bus" label (and no "Green" left), real_seconds = base + per km x km x factor for every mode, far longer than near, walk > bus > keke > drop > car, the min and max clamps, the master switch back to the old short trips, the old `action.travel_max_seconds` not clipping a real-time trip, `travel_start` storing exactly the quoted length, the closed airport. `core_test.sql` and `time_test.sql` switch real trip time off where they check the old game-minutes pace.
- Visual checks: `/dev/drive` (see above) and `/dev/city?f=market&sel=oba_market&bare=1&z=7` to compare an arrival with the city map.
