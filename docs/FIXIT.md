# "Fix it" update

Twelve fixes from real player feedback, done easiest first, one commit each. Migrations are `20261110000100` and up, tests are in
`supabase/tests/fixit_test.sql` (one group per item with server logic). Player-facing words are in quotes.

## 1. Candidate registration pop-up repeated
- **Cause:** the "Candidate registration is open" banner (`ElectionBanner` in `src/screens/game/PollingStrip.tsx`) showed on every load for the whole 48 h registration window, even to people who had already declared.
- **Now:** it shows at most once per election cycle per player per browser (`src/lib/seenPrompts.ts`, key `bl.seen.<user>.reg.<cycle>`), never to someone who already declared, and has **"Don't show again this election"**. The Benin Votes badge and the Elections tab still show registration. Voting-day banner is unchanged (it always shows).

## 2. Club money shout-out covered the screen
- **Cause:** the spray / bottles takeover (`.hx`) was a fixed full-screen layer (z 80) with a blurred backdrop and one giant button, so it swallowed every tap for 3.5 to 9 s.
- **Now:** a compact card under the HUD (max 40% of the height). Everything in it has `pointer-events: none` except a 40 px **close (X)** button, so the game stays playable. Holds are shorter: spray tiers 2.2 / 2.5 / 2.8 / 3.2 / 3.6 / 4.2 / 5.0 s (was 3.5 to 9 s), shutdown 4 s (was 6), VIP arrival 2.4 s (was 3). The money-pick notes layer already ignored taps.
- Files: `src/styles/hype.css` (Fix it 2 block), `src/screens/game/Hype.tsx`, `src/state/hype.ts`.

## 3. Spray / bottle notifications were annoying
- New per-player setting **Settings -> Club spray alerts** (table `club_alert_prefs`, RPCs `club_alert_prefs_get` / `club_alert_prefs_set`, migration `20261110000100_club_alert_prefs.sql`):
  - "Shout-outs in my club": the card in the club you stand in. **On** by default. Your own spray always shows.
  - "Big sprays in other clubs": the app-wide strip. **Off** by default.
  - "Phone pings for club hype": a push. **Off** by default. `bl_push_on_hype` is patched (guarded replace) to need this switch **and** the existing `push.enabled`, `push.cat_events`, the player's Game events category, a saved device and the usual rate limits.
- Client: `src/state/clubAlerts.ts`, `src/state/hype.ts` (filters), `ClubAlertsSettings` in `src/screens/game/NotificationsSettings.tsx`.

## 4. Can't sleep on the bed in the second room
- **Cause (found by driving the real app):** the server never cared where a bed stands (every bed kind, also one in an extension room, passes `bl_furniture_for` and `do_activity('sleep')`, now covered by test group 4). The client was the problem: a queued home task only remembered the furniture *group*, so the Sim always walked to the **first** piece that hosts the activity (the main-room bed), and when the sleep started the pose code picked that first piece again and walked there. Tapping the bed in the extension / second bedroom looked like nothing worked.
- **Now:** the task keeps the tapped piece (`piece` in `src/state/tasks.ts`, `HomeSheet`), the Sim walks to that exact bed and stays on it for the pose. From "Things to do" (no tap) the nearest piece that hosts the activity is used. Files: `HomeScene.tsx`, `TaskRunner.ts`, `tasks.ts`, `HomeSheet.tsx`.
- Note: the three biggest beds (6 ft, king, luxury king) are refused in some spots of a small extension room because they would block its doorway; that is the existing placement rule (the message says "You are blocking the door"), move the bed along the wall.

## 5. Gang Boss handed over by mistake
- Migration `20261110000200_gang_boss_handback.sql`, tests group 5. New tables `crew_boss_log` (the audit trail of every Boss move, no client access) and `crew_boss_requests`.
- **New Boss:** "Hand it back" any time (`crew_boss_handback`), only while the last Boss move was a handover to them.
- **Previous Boss:** "Ask for it back" within `crew.boss_request_hours` (24, admin Settings) of the handover (`crew_boss_request`); the Boss taps "Give it back" or "No" (`crew_boss_respond`). One request at a time, it dies with the 24 hours.
- A normal "Make Boss" (`crew_transfer`) is now logged by a guarded patch. Gang app -> Overview shows the **Boss rank** card only when one of these applies (`crew_boss_state`).
- **Admin:** the Grant toolbox's Gang section now has **Make Boss** (`admin_crew_set_boss`: audited in `admin_audit` as `grant_crew_boss` and `crew_boss_log`, the old Boss becomes Lieutenant, both players get an alert). Before, admin could only set Lieutenant / Member / Prospect.

## 6. Unpaid land levy blocked buying and could not be paid
- **Cause:** the server was right (one open deal at a time, `invest_land_levy(deal, pay)` pays or walks away, a deal past `invest.land_deal_minutes` is released by the next buy). The client only kept the levy deal in the sheet that opened it: close the sheet and the deal stayed open with no way to see or pay it, and every new purchase said "You still have a land deal open".
- **Now:** Invest -> High risk shows an **Open land deal** card at the top of Land (from `invest_overview().pending_deal`) with plots, the levy, the total, **Pay levy** and **Walk away**, and a note that new land is blocked until one is picked. A cold deal is not shown and is released on the next buy. No server change; test group 6 covers show / block / walk / pay / expiry.
