# Places: interiors, zones, action cards, landmarks (L2)

"Places must be entered, not just announced" (user, binding). At any place that is not your home (and not
on the road), the game shows that place's **3D interior** with the Sim inside, instead of the map. You leave
with **Map** or **Home** (dock or the card's buttons). The map is still there: open it from the dock, and its
"You're at" chip / the place sheet have **Go inside** to step back in.

## What the player sees
- **The room**: a low-poly interior built from the place's zones (bar, dance floor, DJ booth, VIP section,
  stalls, pitch, pool, showroom...), lit from real Benin time (`src/lib/daylight.ts`; indoor kits keep their
  lamps on, clubs go dark with party colours; a closed place has its lights down). Tap the floor to walk
  (M1 pathing), drag to turn ±43°, pinch / wheel to zoom.
- **People**: real players at the place (S1 Realtime Presence) as blue **@name** pills with a green dot,
  then the named background people of the hour (L3, white pills), drawn up to `crowd.max_visible` (players first,
  the rest as "+N more here"). The card's **People N** counts everyone and opens the People list (L3 crowds below).
- **The place card** (bottom): emoji, name · district, a rotating **mood line** (place type × part of day;
  "Closed now · Opens 9 PM" while closed), **Say something out loud…** (location chat, `chat_send`; behind
  a chat button on phones), Share / Map / Home, **zone chips**, and the picked zone's **action cards**.
- **Action cards**: icon, duration in seconds (same formula as the server, `activitySeconds`), price / **Free**
  / **Earns ₦…** (jobs), effect chips (+Fun, −Stress...), a **Risky** tag, and why it's locked
  ("Opens 9 PM", "Night only", "Not enough cash", "Only in your own home"). Cars need a second tap
  ("Tap again · ₦2.5M").
- **Walk, then start (M2)**: every card goes through the action queue (`src/state/tasks.ts`,
  `src/screens/game/TaskRunner.ts`): the Sim walks to the zone's spot, and only on arrival the RPC runs
  (`do_activity`, `work_shift`, `shop_buy`), so the server timer and the live bars start then. The left
  task pill reads "Walking to the bar…", then the countdown; queue chips with ↑ / × as at home. A floor
  tap during a task walk drops that task. While the action runs the Sim holds the zone's pose (sit at a
  table / in the stands / cinema seat, lie on a bed, swim in the pool, dance on the floor).
- **Tabs**: a card of kind `panel` (bank counter, PoS, "All ShopRite items", jobs you don't have) opens the
  place sheet on that tab. People N opens the sheet (people list, all tabs, chat).

## Soft launch: the `active` flag (F1, migration `20261006001400_soft_launch.sql`, tests `supabase/tests/soft_launch_test.sql`)
- `locations.active boolean not null default true`. A hidden place (active = false):
  - has **no map pin** (2D or 3D) and is **not in the Ride list or the map search/filters**: `useGame.loadLocations` keeps
    only active places in `locations` (your own home always stays); `locationsById` still has every place, for names;
  - **can't be travelled to**: `bl_travel_quote` (so `travel_quote` and `travel_start`) refuses with hint `inactive`
    ("Rome Night Club is closed for now. Check back soon."). Your own home is always reachable;
  - **can't be acted in**: `bl_place_open` is false and `bl_assert_place_open` raises hint `inactive` first, so `do_activity`
    and `shop_buy` refuse; `work_shift` checks `bl_assert_place_active`. `place_interior` returns `active: false`,
    `open: false`, `opens: "Closed for now"`, and every card is locked "Closed for now"; the place card says
    "🔒 Closed for now · check back soon".
  - A player already inside is **not stuck**: travel only checks the destination, so Map / Home / Ride all work.
- **Seeded once** (config `places.soft_launch_seeded`): Club De Medici, Rome Night Club, Cube Nightlife, Versus Lounge and
  the made-up Owambe Republic are hidden; **360 Signature** stays open, 9 PM – 5 AM. The pre-L2 made-up clubs
  **Bronze Lounge** and **Kingdom Lounge (GRA)** were left as they were (active, 9 PM – 5 AM); hide them in admin if wanted.
  A re-run of the migration never touches `active` again.
- **Admin → Content → Places**: an **Active** switch on every row (saves at once, toast "… is now hidden"), the
  same switch in the row form, and **Opens at / Closes at** as time inputs (half hours work: 21:30 is stored as 21.5;
  blank both = always open; one without the other, or the same time twice, is refused in the form; the DB check
  `locations_hours_chk` backs it up). Audited by `admin_row_upsert` as before.
- `node scripts/place-check.mjs` still checks hidden places (they can be switched back on) and asserts 360 Signature is active.

## Server (migration `supabase/migrations/20261006001300_places.sql`, tests `supabase/tests/places_test.sql`)
### Tables (all RLS on; clients may only `select`; writes through admin RPCs)
| Table | Columns | Notes |
|---|---|---|
| `place_zones` | `id` pk ('club.bar', 'mama_ebo.counter'), `scene` (place type) **or** `location_id` (one place), `zone_key`, `label`, `icon`, `prop`, `x`, `z`, `w`, `d` (metres), `rot` (quarter turns: 0 faces the camera, 1 right, 2 back, 3 left), `note` (strip under the cards), `sort`, `active` | A place gets its type's zones; a place zone with the same `zone_key` **replaces** the type's zone (inactive = hides it). Trigger: the scene must exist on the map. |
| `zone_actions` | `id` pk ('club.bar.lounge_chill'), `zone_id`, `kind` (`activity` \| `job` \| `shop` \| `panel`), `ref`, `label`, `icon`, `sort`, `active` | Trigger: `ref` must exist (activity, item, career track, or tab `shop/jobs/bank/pos/activities/chat/inventory`). |
| `place_moods` | `id` pk, `scene` or `location_id`, `part` (`any`, `morning` 5–12, `afternoon` 12–17, `evening` 17–21, `night` 21–5), `icon`, `line`, `sort`, `active` | Place lines first, then the type's. |
| `locations` + | `open_hour`, `close_hour` (null = always open; `close_hour` may be below `open_hour` = past midnight) | Clubs 21 → 5, Kada 10 → 24, the mall 9 → 22, the zoo 8 → 18. |
| `activities` + | `location_ids` (only at these places; empty = every place of its scenes), `risky` (a street robbery roll at that place, `bl_roll_street_robbery`), `rush` jsonb (`{"from":12,"to":15,"pct":40,"line":"..."}` = may sell out then; nothing is charged), `icon` | Mama Ebo's pepper rice: `location_ids {mama_ebo}`, rush 12–15 at 40 %. |

### RPCs / functions
| Name | What |
|---|---|
| `place_interior(p_location text default null)` | Everything for the interior and the card in one read: location, `here`, `home`, `open`, `opens` ("Opens 9 PM"), `hours`, `night`, `part`, `moods`, `zones[]` each with `actions[]` (activities offered at that type/place with cost, effects, seconds fields, risky, rush, `locked`; shop items **sold at this place** with price/category/owned; job tracks that work here with title + pay for you; tabs the place has). Authenticated only. |
| `do_activity` (re-created from its live definition) | + `location_ids`, opening hours (`hint 'closed'`), rush sell-out (`hint 'sold_out'`, before any charge), Risky robbery roll (returned as `robbed`). Grants unchanged. |
| `shop_buy` (re-created) | + opening hours; **cars** (category `vehicle`): one at a time, never the same car twice (`already_owned`), paid **bank first, then cash** (`cars.bank_first`), ledger `car_purchase`. Any vehicle in the Bag already unlocks the "Your car" travel mode (`bl_travel_quote`, unchanged). |
| `bl_place_open(locations)`, `bl_assert_place_open`, `bl_hour_label(numeric)`, `bl_day_part()` | Internal helpers (revoked from clients). |
| `bl_admin_table_spec` / `bl_admin_check_value` (re-created) | Whitelist `place_zones`, `zone_actions`, `place_moods`, the new activity columns and the place hours; new column type `num_null`. |

### Config (category `places`)
`places.hours_enabled` (true), `places.mood_seconds` (7), `places.npc_per_zone` (2), `crowd.max_visible` (10),
`cars.bank_first` (true). See docs/ADMIN.md.

## Client
| Piece | Files |
|---|---|
| Interior data (no three.js): kits per place type, prop metadata (solid? where the Sim stands, pose), room sizing, zone spots, walk grid, busy curves + crowd planner | `src/art/place3d/model.ts` |
| Geometry: shell + one prop per zone, merged into 4 meshes | `src/art/place3d/engine/props.ts` (uses the home's `HomeBuilder`) |
| Canvas, camera, Sim walker + poses, instanced crowd, name pills, sign, taps | `src/art/place3d/engine/PlaceScene.tsx` (lazy chunk) |
| Lazy wrapper, still frame while suspended, SVG fallback (no WebGL / lost context) | `src/art/place3d/PlaceView.tsx` |
| Card, cards, data hooks (`usePlaceInterior`, `usePlayersAt`) | `src/screens/game/PlaceCard.tsx`, styles `.place-card*`, `.pc-*`, `.place3d*` in `src/styles/game.css` |
| Wiring (when to show the interior, queue, crowd plan, insets) | `src/screens/Game.tsx` |
| Task queue: `kind` (`activity` \| `shift` \| `buy`), `zone`, `walkTo`, `qty` | `src/state/tasks.ts`, `src/screens/game/TaskRunner.ts` (`useTaskRunner(state, homeLive, placeLive)` → `placeTask`) |
| API types | `src/api/places.ts` |
| SVG fallback headers for the new types | `src/art/scenes/{mall,cinema,hotel,zoo,stadium,monument,car_dealer}.tsx` (+ `_sharedL2.tsx`) |
| Check (every zone spot reachable from the entrance, no overlapping zones, crowd cap) | `node scripts/place-check.mjs` (reads the local DB) |

### Kits (by place type)
Indoor halls (back + left walls full height, cut-away front/right, entrance gap, windows, wall lamps):
buka/restaurant, club/lounge (party lights, dark), bank hall, hospital, campus lecture hall, police station,
museum, tech hub (office), cyber, shrine, salon, workshop, airport, car showroom, hotel lobby/pool, cinema,
mall/supermarket aisles. Outdoor yards (ground island, low fence, trees, sign on posts): market stalls,
motor park, street, PoS stand, zoo, stadium, Emotan plaza (monument), farm, palace (respectful).

### Props
`stall`, `food_stall`, `crates`, `restroom`, `counter`, `checkout`, `bank_counter`, `tables`, `vip`, `tv_screen`,
`bar`, `dance_floor`, `dj_booth`, `atm`, `seats`, `shelves`, `aisles`, `beds`, `bed_lux`, `desk`, `lecture`,
`desks`, `trees`, `bus`, `keke`, `grill`, `kiosk`, `bench`, `board`, `gate`, `courtyard`, `display`,
`pedestals`, `stage`, `altar`, `salon_chairs`, `furnace`, `crops`, `shed`, `cinema_door`, `planters`,
`cinema_hall`, `arcade`, `pool`, `cage`, `pen`, `stands`, `pitch`, `statue`, `cars`, `lane`. Unknown props draw a
small crate. Walk-on props (dance floor, pitch, tables, seats, pool...) don't block walking; the Sim uses
them from the middle; solid props are used from their front (`rot`).

### Cost (SwiftShader, measured with `window.__place.stats()` / `bench()`)
| Place | Draw calls | Triangles | ms/frame |
|---|---|---|---|
| Home (reference, docs/HUD_HOME.md) | 42 (face-me) – 50 (duplex) | 11.5k – 14.5k | 0.2–0.4 |
| Oba Market (phone, LAPO) | 47 | 12.8k | 0.3 |
| UNIBEN campus (phone) | 49 | 14.5k | 0.3 |
| Bronze Bank (phone / desk) | 46 / 53 | 11.1k / 12.4k | 0.2 / 0.8 |
| Cube Nightlife, closed (phone) | 45 | 12.7k | 0.2 |
| Versus Lounge at night, 2 players + crowd (phone / desk) | 48 / 55 | 14.0k / 15.3k | – |
| Samuel Ogbemudia Stadium (phone) | 47 | 14.8k | – |
| SDD Motors / Protea / Kada / Benin City Mall (desk, NEPO) | 55–56 | 13.6k – 15.7k | 0.4–0.5 |

The room + every prop = 4 calls, the crowd = 3 calls (instanced torso / legs / head) whatever its size, the
sign = 1; the rest is the player's Sim (~35–45 calls, outfit-dependent) and the invisible tap boxes. Frames:
every frame only while walking / blending / turning the camera; 24 fps idle (dancers, breathing), 12 fps
reduced motion; nothing when hidden; paused under a full sheet. three.js + r3f load lazily (`PlaceScene`
chunk); the Game chunk only gets the card and the model.

## How to add a place
1. Add a `locations` row (id, name, district, scene, blurb, risk..., x/y from docs/MAP_GEO.md /
   docs/LANDMARKS.md, keep pins ≥ 34 map units apart: `supabase/tests/map_geo_test.sql`), `actions` for the
   sheet tabs (`activities`, `shop`, `jobs`...), and `open_hour`/`close_hour` if it has hours.
2. If its type is new: add the scene to `SceneType` (`src/lib/types.ts`), `SCENE_EMOJI` (`city3d/model.ts`),
   `PIN_STYLE` + a glyph (`map/pinIcons.tsx`), a kit in `place3d/model.ts` `KITS`, an SVG header in
   `src/art/scenes/<scene>.tsx`, and type zones (next step).
3. Zones: rows in `place_zones` for the type (or for this one place), with props from the list above.
   Run `node scripts/place-check.mjs`.
4. Cards: rows in `zone_actions` (activities must list the scene; shop items must list the place in `sold_at`).
5. Mood lines in `place_moods`. Optional: `PIN_META` short label + tier in `src/art/map/mapGeo.ts`.
All of 3–5 can be done live from **Admin → Content → Place zones / Zone actions / Mood lines**; a new place
type or a new prop needs code.

## Admin
Content → **Place zones** (x/z inline; "Add"), **Zone actions**, **Mood lines**; **Activities** gained
Icon, Only at these places, Risky, Rush hour sell-out; **Places** gained Opens at / Closes at. Settings →
category "places" (keys above). All writes audited as before.

## L3 crowds (migration `20261006001500_crowds.sql`, tests `supabase/tests/crowds_test.sql`)
"Places should feel alive": named Benin people at every place, the same for every player, busy and quiet by real
Benin rhythm.

### Server
| Piece | What |
|---|---|
| `npc_roster` | 121 seeded people: `name`, `role`, `motion` (idle, dance, hype, dj, trade, serve, guard, sit, cheer, work, phone), `avatar` (a partial AvatarConfigV2; `preset` = outfit preset, optional `top.c`), `lines` (English, one per row), `pidgin` (one per row, only used at market / street / motor park / PoS), `scenes` (place types) and/or `location_ids` (only these places; wins), `zone_key` (where they stand: dj, dance, bar, counter, foodstuff...), `headliner` (always there while the place has people), `sort`, `active`. Benin names (Osaro, Eki, Nosa, Uyi, Efosa, Osas, Ivie, Imade, Omoruyi, Ehis...). 360 Signature has **MC Lightning** (hype man), **DJ Ekpen**, **Big Osaze** (bouncer) and Ivie (waitress) on top of the club-wide bouncer, bartender, big spenders and 9 dancers; the hidden clubs share **DJ Uyi**. Every non-home place type has people (traders and a mama put at markets, agberos and keke riders at parks, students and a lecturer at UNIBEN, nurses, bankers, police, a barber, car salesmen, bronze casters at Igun Street...). |
| `crowd_profiles` | place type × hour band (`from_hour` inclusive, `to_hour` exclusive, Benin time) × `days` (all / weekday / weekend) → `npcs` (how many people are there). Most specific wins: weekday/weekend before all, then the shortest band, then `sort`. Every type has an all-day base row, so every hour of every day is covered. Seeded: markets 60 at 7–12 and empty at night, UNIBEN 40 on weekday daytime and 8 at weekends, clubs 24–28 at night and 40–45 on weekend nights, streets 1 at 0–5 AM, the stadium 120 on weekend afternoons, banks weekdays only... |
| `place_people(p_location, p_hour default null, p_weekday default null)` | Who is present: `{location, hour, weekday, open, total, npcs[{id, name, role, motion, zone, headliner, avatar, line, lines}]}`. Deterministic per place × date × hour (md5 seed), so every player sees the same people; headliners first, then the seeded order; list capped by `crowd.npc_list_max` (30), `total` = the profile number. Closed / hidden places and homes = nobody. `p_hour` is the dev visual-hour override (any authenticated player may ask for another hour; harmless). Authenticated only. Helpers `bl_crowd_count`, `bl_lines` revoked from clients. |
| Admin | `bl_admin_table_spec` re-created from its live (F1) definition + `npc_roster` and `crowd_profiles`: **Content → People (NPCs)** and **Crowd profiles** (people count inline), audited by `admin_row_upsert`. Check constraints refuse an unknown motion, a bad day kind and a band with from ≥ to. |

### Client
| Piece | Files |
|---|---|
| `placePeople()` + types | `src/api/places.ts` |
| `usePlacePeople` (per place × hour, re-reads on the hour; dev `?hour=` / `__blHour` override goes to the server), `usePlayersAt` now carries avatars | `src/screens/game/PlaceCard.tsx` |
| `planCrowd`: players first, then the named people at their zone (`zone_key`, else dancers on the dance floor, the DJ / hype man at the booth, the rest round-robin); `npcAvatar(raw)` = full look. While loading nobody is drawn; if the call fails the old unnamed people come back | `src/art/place3d/model.ts` |
| **Crowd rigs**: the real avatar built at ~25 % segment detail (`withDetail` in `engine/geo.ts`; the Sim, portraits and the creator are untouched, `MODEL_VERSION` unchanged), tiny face parts and skin under clothes dropped, braids/locs swapped for a look-alike, then baked into **one skinned mesh with vertex colours** (rigid skinning on the same 16 bones): ~1.1k triangles and 1 draw call per person | `src/art/avatar3d/engine/crowd.ts` |
| Motions on top of the M1 idle life: dance, hype (arm pumping, jumps on the beat), DJ (hands on the decks, head nod, hand to the headphones), trader beckoning, serving tray, guard arms folded, work (bent), phone, cheer, sit | `src/art/place3d/engine/crowdPose.ts` |
| Who gets a rig: real players, then headliners, then whoever is nearest the camera, up to `crowd.rigs_high` (4) at Graphics High / `crowd.rigs_low` (2) at Low; built one every ~45 ms (a pump that a crowd re-plan never cancels). The rest stay the 3-call instanced figures (rigged people are compacted out of the instance list). **Animation LOD**: the 2 nearest rigs pose every frame, the next 2 every 2nd, the rest every 3rd; instanced figures every 2nd frame. | `src/art/place3d/engine/PlaceScene.tsx` |
| Pills + bubbles: white NPC pills (tap = their line, ~4 s), blue @player pills with the green dot; headliners get pill priority. Tap a person in 3D (invisible instanced boxes, 0 draw calls) or in the People list → a speech bubble over the head. A new location chat line floats over the speaker for ~5 s (your own over your Sim). Now and then (`crowd.chatter_seconds`, 22 s average) someone says a line; never while paused or hidden. "+N more here" chip over the room. | `PlaceScene.tsx`, styles `.place3d__bubble`, `.place3d__more`, `.people-*` in `src/styles/game.css` |
| **People N** opens the People list: you and the real players (cached portraits), then the people around with role and their line (portraits too, lazily); tap one = bubble in the room; "+N more people here"; "Place details & chat" opens the old place sheet. | `PeopleSheet` in `src/screens/game/PlaceCard.tsx` |

### Cost (SwiftShader, `__place.stats()`, Graphics High; before = F1 numbers)
| Scene | Before (calls / tris) | After (calls / tris) |
|---|---|---|
| 360 Signature at 11 PM, phone | 50 / 21.2k | 54 / 25.6k (4 rigs, 4.9k) |
| 360 Signature at 11 PM, desktop | 57 / 22.5k | 61 / 26.9k (4 rigs) |
| Oba Market at 9 AM, phone | 49 / 22.3k | 53 / 26.7k (4 rigs) |
CPU submit (`bench()`) 0.4–1.3 ms. The same rooms with `__blRigs = 0` (dev) are back at the F1 numbers. Six rigs would be
~+7k triangles; `crowd.rigs_high` = 4 keeps the busiest rooms at ~25–27k (slightly over the ~25k guide on the
heaviest rooms; set it to 3 to be strictly under).

### Dev
`window.__blRigs = n` overrides the rig count; `__place.stats()` gains `rigs` and `rigTriangles`.

## P1 polish (migration `20261006001600_polish.sql`, tests `supabase/tests/polish_test.sql`)
### People walk around (`src/art/place3d/engine/wander.ts`, wired in `PlaceScene.tsx`)
- One **agent** per drawn person (NPCs and real players' figures), all on the place's one M1 nav grid, moved by the
  same `stepWalker` as the Sim (spring-eased speed, turn on the spot, eased final facing; NPC cruise ~1 m/s, dancers
  0.55, the waiter 1.25). Pause (role motion) → walk → pause, with staggered, seeded timers (first walks 2–10 s after
  you walk in), so the room moves but never looks chaotic.
- **By role** (`wanderKind` in `model.ts`, from `motion` + seat + role): `roam` (idle / phone people) visit spots in
  their own zone or one of the 4 nearest; `dance` shuffles ≤ 1.4 m inside the floor; `stay` (bouncer, trader,
  cashier, worker, fans) steps out 0.5–1.3 m and comes back to their spot; `waiter` (role Waiter / Waitress)
  goes bar ↔ tables / VIP; `fixed` = the **DJ behind the booth** (the booth is now a shallow desk at the front of its
  zone with a riser behind it) and the hype man next to them; `seat` stays seated.
- **Separation:** a walker waits for someone close in front (0.6 m; the lower index has right of way) or for the
  Sim (0.8 m), and picks a new spot after ~2.4 s. NPCs are never in the grid, so real players are never blocked.
  At most 2 path plans per frame (A* spread over frames). Agents keep their state across crowd re-plans (by id).
- **Rigs** walk with the real walk cycle (`poseGait`, phase by distance so feet don't slide, blended with the role
  motion by gait weight); **instanced figures** glide with a bob and a leg "stride" (legs scaled in depth) and a
  slight lean. Animation LOD unchanged (2 nearest rigs every frame, next 2 every 2nd, rest every 3rd; instances every
  2nd); positions update every frame. 30 fps while people walk at Graphics High (24 on Low, 12 reduced motion);
  **reduced motion = nobody wanders**. Tap boxes, blobs, pills and bubbles follow the walkers.
### People in every place
- +63 roster people (184 active): every active place type now has 5+ of its own (car dealers 8, airport 7, cyber 6,
  farm 5, palace 6, police 6, shrine 6, workshop 6, zoo 7, PoS 6, salon 6, museum 6, monument 7...).
- Crowd profiles: the all-day base rows that were 0 or 1 now have staff on duty (bank / car dealer / museum / salon /
  workshop / zoo / farm / office / PoS / shrine 2, cinema / mall / palace / cyber / monument 3, police / hotel /
  airport 4), plus a few evening bands; seeded once (`places.p1_people_seeded`). Markets and bukas stay empty in the
  dead of night on purpose. Closed / hidden places still have nobody.
### Luxury cars at every dealer (`src/art/place3d/engine/cars.ts`)
- Procedural low-poly models (extruded side profiles with a chamfer + greenhouse + wheels + glow lamps; no assets):
  **Mercedes-AMG GLE 63 Coupe** (white; Panamericana vertical-slat grille, coupe roofline, quad pipes),
  **Mercedes-AMG G 63 "G-Wagon"** (matte grey; boxy, upright glass, round lamps, fender indicators, spare wheel on the
  back door), **Lamborghini Urus** (yellow, black roof; wedge nose, hexagon arches / grille / pipes, Y lamps),
  **Tesla Cybertruck** (brushed steel wedge, trapezoid arches, light bars), **Cadillac Escalade** (black, chrome
  grille, vertical lamps), **Mercedes-Benz C300** (blue, star grille), **Toyota Camry** (red), a **Bajaj Boxer**
  motorcycle and a **bicycle**.
- New props: `lux_cars` (the showroom: Urus, G 63, Cybertruck, GLE on spotlit pads with tag stands) and `car_lot`
  (Escalade, C300, new Camry, a tokunbo saloon, the Boxer and the bicycle). The type's showroom / lot zones were
  widened to 9 m (only if still at the seeded size). The Tokunbo Lot's hidden showroom became its **Luxury corner**.
- Items (category `vehicle`, sold at Ighodalo Car Deals, SDD Motors and the Tokunbo Lot only; admin-editable):
  G-Wagon ₦350M, GLE 63 ₦180M, Urus ₦450M, Cybertruck ₦250M, Escalade ₦250M, C300 ₦95M, new Camry ₦75M (the tokunbo
  "Muscle" stays ₦6.5M), Bajaj Boxer ₦1.6M, bicycle ₦180k. Same purchase flow (one of each, second tap, bank first).
- **Own-vehicle travel:** any of them unlocks "Your own …" (mode `car`). With no car, a bicycle gives "Your bicycle"
  (12 km/h, free, no traffic) and a Boxer "Your motorcycle" (35 km/h, ₦40/km, a third of the traffic); config
  `travel.bicycle.*` / `travel.motorcycle.*`. `bl_travel_quote` re-created from its live definition (grants kept);
  options carry `vehicle`. Risk = the own-vehicle (`car`) multiplier, the same the arrival roll uses.
### Cost (SwiftShader, `__place.stats()`, Graphics High)
| Scene | Before (calls / tris) | After (calls / tris) |
|---|---|---|
| 360 Signature 11 PM, phone | 54 / 25.8k | 53–56 / 24.5–27.9k (3–6 rigs) |
| 360 Signature 11 PM, desktop | 61 / 26.9k | 63 / 29.2k (6 rigs), 0.96 ms |
| Mama Ebo, phone | 57 / 22.1k | 57 / 22.3k |
| SDD Motors (7 cars + 2 bikes), phone / desktop | 47 / 19.2k | 54 / 35.1k · 60–63 / 39k, 0.6–0.9 ms |
| Bronze Bank / Museum / Igun Street 8 PM, phone (people now) | 46–48 / 15–16k | 49–51 / 19–24k |
| LAPO home | 45 / 16.1k | 45 / 16.1k |
| 360 Signature 11 PM, phone, Graphics **Low** | – | 51 / 21.4k (2 rigs, no pools / fog), 0.9 ms |
| Oba Market 9 AM, phone (walking crowd) | 53 / 26.7k | 55 / 29.4k (6 rigs), 0.5 ms |
The cars add ~12k triangles to the dealer room (still 1 merged mesh, +0 calls); the user lifted the triangle guide.
Walking costs CPU only (a few short A* plans per second, at most 2 per frame). `bench()` stays 0.3–1.5 ms.

## P2 hype (migration `20261006001700_hype.sql`, tests `supabase/tests/hype_test.sql`)
Big spenders in a club get hyped by the MC, live, and the biggest spends go out app-wide. Server-authoritative:
clients can only read.
### Server
- **`place_announcements`** (id, location_id, user_id, username, kind, amount, qty, text, ticker, global, created_at).
  RLS on, `select` for authenticated, no insert / update / delete grants. In `supabase_realtime` (added only when the
  publication exists and the table isn't in it yet). Old rows are cleaned now and then (`hype.retention_hours`).
- **`hype_templates`** (id, kind, line, ticker, sort, active): the MC's lines in Naija hype style, two per kind,
  admin-editable in **Content → Hype lines**. Placeholders `{name}` `{place}` `{count}` `{bottles}` `{amount}`.
- **`bl_hype_announce(user, place, kind, amount, qty, force)`** (server only, not executable by clients) is the
  only writer. It is called from the re-created **`do_activity`** (VIP table → `vip`, spray money → `spray`, hype man
  shout-out → `shoutout`, Shut down the club → `shutdown`) and **`shop_buy`** (club bottle → `bottles`, counted over
  `hype.bottle_window_s` from the ledger, so "E don pop 3 bottles" counts up). Only in places whose scene is `club`.
  Both functions return the row as `hype` (null when none).
- **Rate limits:** one announcement per player per `hype.cooldown_s` (the spend itself always goes through; Shut down
  the club always announces in the club); spends ≥ `hype.global_min` set `global` + a `ticker` line, at most one per
  `hype.global_cooldown_s` app-wide.
- **Shut down the club** (`shut_down_club`, DJ zone card, 🔥): costs `hype.shutdown_cost` (₦2M; a trigger on
  `game_config` keeps the card price in sync), + `hype.shutdown_cred` street cred, and buys a round for every other
  player in the club (+`hype.round_fun` fun, +`hype.round_social` social). With the default threshold it always goes
  app-wide (unless another ticker ran in the last 90 s).
### Client
- `src/state/hype.ts`: one Realtime channel on the club you're inside (`location_id=eq.<club>`) and one app-wide
  (`global=eq.true`). The last 30 min of the club's lines load on entry (chat).
- Club row → **banner** at the top of the place view (`src/screens/game/Hype.tsx`, rise + fade in 320 ms, out 180 ms,
  tap to close, queue of 3, 7 s each), a **bubble over the hype man** (MC Lightning at 360 Signature; the DJ when no
  hype man is drawn), the same line in the **club chat** as a hype row, the **Doremi stinger** + the crowd's "ayyy",
  and ~3 s of reactions: the hype man points and jumps, the DJ and dancers throw their hands up, the simple figures
  jump higher, the lights swell a touch.
- Global row → a slim **ticker** under the HUD for 6 s with a soft two-note cue, for everyone not in that club.
- **On the beat:** `readBeat()` (src/lib/sound.ts) drives the dancers' steps / arm swings / bob, the hype man and DJ
  nods, the instanced figures' bounce and a soft light swell on each beat (+12 % light gain at the beat, decaying; no
  strobe). Reduced motion: smaller moves, no jumps, no light pulse. Audio off: a silent clock at 113 BPM.
### Check
`bash scripts/sql-test.sh -- supabase/tests/hype_test.sql` (announce + text, no client writes, cooldown, global flag
and cooldown, Shut down the club, bottles count up, non-club spends silent, publication + admin spec).

## Not done here (next steps)
- L3 leftovers: rigs don't rebuild when the graphics tier changes mid-visit (they do on the next visit); no streaming
  "Loading…" pill. (P1 did the wandering and put the DJ behind the booth.)
- P1 optional, not done: the player's own car parked outside their home / on the street.
- L4: map place sheet with "On today" events (match days, concerts), travel cards + Go, live banners.
- Interiors are client-side only (where you stand is never sent to the server), like the home.
- Homes of other players show a simple interior whose actions say "Only in your own home".
