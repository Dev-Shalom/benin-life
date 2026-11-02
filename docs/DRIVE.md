# Drive scene (3D travel with road events)

When a player travels by car, keke, ECTS bus or drop, the game shows a short 3D drive along the real Benin roads instead of a plain jump. On foot there is no drive. Style: calm, clean low-poly, muted real colours, soft light, readable on a phone.

The trip itself is unchanged and server-owned (`travel_start` / `travel_arrive`, `profiles.travel_*`). The drive is a view on top of it, plus server-rolled **road events**.

## What the player sees
- **Scene**: a dual carriageway with a median, shop-houses, compound walls, trees and palms, street lamps, electric poles with cables, umbrellas, parked cars, road signs with real road names, NPC traffic (cars, keke, okada, buses). Day and night follow the game clock (lit windows, lamps, headlight beams, stars at night).
- **Vehicle**: the player's own car (`usePrimaryCar`, mapped from the item id to a sedan, SUV, pickup, motorcycle or bicycle with a muted colour), or a keke, an ECTS bus or a taxi for the other travel modes.
- **Real roads**: the roads of the trip come from the same map data as the 3D city (`src/art/drive3d/model.ts` `routeRoads`: Dijkstra route over `mapGeo` ROADS plus the Ring Road, each stretch named). Sign boards and the route chip show them in order, e.g. Ekenwan Road, Ring Road, Airport Road. Names used: Ring Road, Ugbowo-Lagos Road, Mission Road, Akpakpava Road, Benin-Auchi Road, Benin-Agbor Road, Sakponba Road, Sapele Road, Airport Road, Siluko Road, Ekenwan Road, 3rd East Circular and a few side roads. "Lagos" appears only in the real road name.
- **Cameras** (one button, remembered per device): **Chase** (behind the car), **Side** (three-quarter from the median, other players' cars overtake in front of the lens), **Driver** (first person with dashboard and a steering wheel that turns; handlebar for keke, okada and bicycle).
- **Other players**: cars with small name tags (max 8) from a light Supabase Realtime presence channel `drive:<road>` joined only while the scene is open. One tiny payload (name, vehicle) is tracked once on join: no database writes, no per-frame traffic. Skipped in poll mode, on a weak device (4 on Low graphics) and when the admin turns it off.
- **Layout**: top-left route chip (from, to, road, time left, progress bar); top-right camera, horn and map; bottom: an event card only when something happens, the outcome line, the arrival card, and two small links (Turn back, Skip). Safe areas are respected and nothing covers the road. All UI uses the tokens in `src/styles/tokens.css`, so Light and Dark both work.
- **Horn**: a short two-tone Web Audio beep (respects mute and sound effects).
- **Skip**: closes the scene for this trip; the trip carries on and ends on time exactly as before (the old plain travel UI). **Map** does the same and opens the map. **Turn back** (tap twice) calls `drive_turn_back()`: the trip ends where it started, the fare is not refunded.
- **Arrival**: a gate shot at the destination (accent colour from the place type, name board, guard hut, boom barrier) with a **Go in** button; the barrier lifts, the car rolls through, the place opens.
- **Setting**: Sim sheet > Settings > "3D drive when I travel" (`prefs.driveScene`, default on). Off = the old instant travel, and no road events (the client never asks for one).

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
| Host: decides whether to show the scene, keeps it for the gate shot, skip / turn back / map | `src/screens/game/DriveHost.tsx` (mounted in `Game.tsx`) |
| UI layer + event flow | `src/art/drive3d/DriveView.tsx`, `drive3d.css` |
| Roads, vehicle mapping, helpers (no three.js) | `src/art/drive3d/model.ts` |
| 3D scene (lazy chunk) | `src/art/drive3d/engine/DriveScene.tsx` |
| Street, vehicles, event props, gate, signs, cockpit, batching | `engine/world.ts`, `vehicles.ts`, `props.ts`, `batch.ts` |
| Other players (presence), horn | `useOthers.ts`, `horn.ts` |
| RPC wrappers, auto-arrive hold | `src/api/drive.ts`, `src/state/drive.ts` (`StatusBanners.tsx` honours the hold) |
| Player setting | `prefs.driveScene` (`src/lib/prefs.ts`, `SimSheet.tsx`) |
| Dev page (dev server only) | `/dev/drive?cam=chase|side|inside&h=14&event=ambush|police|goslow|beggar&arrived=1&others=1&gfx=low&theme=dark&mode=car&veh=camry_new` |

## Performance
- No assets: every shape is procedural. The street is built once as ~20 instanced meshes and repeats every 60 m (endless, scrolled). Static ground, kerbs, cables, gate and cockpit parts are merged into a few draw calls; vehicles are single merged geometries with vertex colours, NPC traffic is one instanced mesh per kind.
- Measured on SwiftShader at 390x844: **36 to 54 draw calls, 12k to 21k triangles** (Chase, Side, Driver, events, gate; Low graphics about 42 calls and 12k triangles).
- **Graphics Low** (`useTier`): about 60 % of the buildings and trees, 9 NPC cars instead of 16, no stars, no antialiasing, DPR capped at 1.1, a shorter fog, at most 4 other players. High: DPR up to 1.6.
- No shadows (a soft blob under each car), no per-frame React state (the frame loop reads refs), the canvas stops in a hidden tab, the overlay re-renders four times a second.
- If WebGL is missing or the context is lost the scene turns itself off for the session and travel goes on as before.

## Checks
- `bash scripts/sql-test.sh -- supabase/tests/drive_test.sql`: settings, switches, every limit (progress window, gap, trip cap, cooldown, daily cap and the next-day reset, pending resume and expiry), every outcome of every event with chances forced to 0 or 100 and time pinned with `bl.test_offset_seconds`, cash never below zero, the delay cap, savings never landing in the past, a late answer, low cash, turn back, grants and RLS.
