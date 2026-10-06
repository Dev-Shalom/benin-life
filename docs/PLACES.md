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
  then background people per zone (L3-lite), drawn up to `crowd.max_visible` (players first). The card's
  **People N** counts everyone (players + background people + you).
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

## Not done here (next steps)
- L3: real NPC roster (names/outfits/lines from a table by place type × hour × weekday), chat bubbles over
  heads, a "People N" list sheet with NPCs, full avatar rigs for nearby people (now: low-poly instanced
  figures), animation LOD.
- L4: map place sheet with "On today" events (match days, concerts), travel cards + Go, live banners.
- Interiors are client-side only (where you stand is never sent to the server), like the home.
- Homes of other players show a simple interior whose actions say "Only in your own home".
