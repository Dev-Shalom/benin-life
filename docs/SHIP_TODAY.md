# Ship-today requests (user, 2026-10-06) — do these in order, one agent at a time

Status markers: [todo] / [running] / [done]. Keep this file + HANDOFF STATUS LOG + CLOUD_PROMPT current.

## 0. Starter homes by origin — [done] (see HANDOFF STATUS LOG). Partial work committed as `5c237bc Starter homes WIP snapshot`; if a session dies, resume from it (don't start over).
Then push branch → main (it also carries the "full amount under ₦100,000" migration 000900; order 000400 before 000900).

## S1. Quick polish batch — [done]
1. **Names** (some things are shared by Lagos and Benin — use what Benin people actually use):
   - Phone betting app **EdoBet → "BetNaija"**.
   - **KekeGo → a "Ride" app**: book what you ride — keke, ECTS bus/danfo-style bus, okada (if allowed), drop/cab, own car — with prices/times (reuses the travel quote), like a ride-hailing app.
   - **ChopNow → "Chowdeck"** (real app used in Benin too).
2. **Anti-farming**: set `bank.transfer_min_account_real_minutes` default to **1440** (24 h) via migration (only if still at the old default).
3. **Beta badge** on landing + HUD (small), and **Terms of Service + Privacy Policy pages** (`/terms`, `/privacy`, English, NDPR-aware, 18+, virtual money has no cash value, no withdrawals, data we store, how to delete account, contact email dev.shalom1@gmail.com); link from sign-up checkbox, landing footer, Settings.
4. **Update notice**: detect a new deploy (poll `/version.json` written at build time, or compare build hash every few minutes / on focus) → show a small **phone-style dialog** "There's a new update" + **Refresh** button; refresh keeps everything (state is on the server; keep local prefs).
5. **Live counts (realtime presence)**: "online" count in the HUD increases instantly when someone comes online and decreases when they leave (Supabase Realtime Presence channel, cheap); **people at a place** count updates live too (per-location presence or the existing players_here + realtime). Admin Overview "online now" uses the same source.
6. **Smooth day/night**: no snapping at 6 AM/6 PM. Lighting (map city + home + sky + street lights + windows) eases continuously: dusk darkens gradually (~17:30 → 19:30) and dawn brightens gradually (~05:30 → 07:00), following real Benin time.
7. **Sound**: light ambient in-game music/city ambience (loops, small files or WebAudio-generated, lazy-loaded, respects the mute toggle and Settings sound/music switches, off until first user tap per browser rules) + **click SFX** on buttons/taps + small cues (money in, action done, notification). Keep total audio small (< ~300 KB, or synthesized).

**S1 notes (agent, 2026-10-06, verified by lead: build, 12 suites, screenshots; on main):** all 7 items built. Migration `20261006001000_ship_polish.sql` (transfer wait 30 → 1440 only if still 30; Chowdeck in config labels + `food_order` / `bl_ledger_label` messages, re-created from their live definitions). Ride app = `phone/RideApp.tsx` (no okada: the travel system has none). Terms/Privacy at `/terms`, `/privacy`. Update notice via `dist/version.json` (docs/DEPLOY.md). Presence channel `online` (`src/state/presence.ts`). Smooth light `src/lib/daylight.ts` (dev: `window.__blHour`). Sound `src/lib/sound.ts`, synthesized (0 KB); music now defaults ON at low volume. Details: docs/HUD_HOME.md "S1 polish".

## S2. Welcome-back screen — [done]
When a player opens the game after being away (new session / long absence), show a "welcome back" screen like Lagos Life:
- their **3D house** with the **Sim inside**, camera **slowly orbiting 360°** around the house;
- the Sim's **face** (portrait) + name, **current money**;
- buttons: **Continue** (enter game), **New life** (start over: new Sim — confirm twice; server RPC that archives/resets the profile safely, keeps the account; admin-tunable whether allowed), **Log out** below.
- Lightweight: reuse the home scene, one canvas, frameloop only while orbiting.

**S2 notes (agent, 2026-10-06, for the lead to verify):** built. Screen `src/screens/WelcomeBack.tsx` (lazy) behind `PlayGate` in `App.tsx`; when-to-show logic `src/lib/welcome.ts` (sessionStorage once per tab + localStorage last seen per user, `life.welcome_after_minutes` default 30). Home orbit = new `HomeScene` props `orbit` / `dollhouse` / `interactive` / `insetLeft` (low walls all round, 52 s per turn, still under reduced motion, draws only while orbiting and visible). New life = two dialogs (what is lost, then type the Sim's name) -> RPC `life_restart()` in `20261006001100_life_restart.sql`: archives to `profile_archive` (jsonb snapshot), deletes the profile (ledger/events/inventory/furniture cascade), keeps the account; chat/report/block/audit FKs moved to `auth.users` so they survive; admin rights + running chat mute carry over; config `life.restart_enabled` (true), `life.restart_cooldown_hours` (0), `life.welcome_enabled`, `life.welcome_after_minutes`; audited `life_restart`. Same migration: transfer wait message in hours from 120 min ("New accounts can send money 24 hours after joining. About 23 h 50 min to go."). Tests `supabase/tests/life_test.sql` (13 suites pass). Details: docs/HUD_HOME.md "S2 welcome back", docs/ADMIN.md.

## M1. Sim movement & life — [done]  (spec in docs/REAL_LIFE_PLAN.md)
Tap the floor to walk there (home + places) with pathing, smooth walk cycle, alive idle (breathing, weight shift, look-around), natural idle after tasks.

**M1 notes (agent, 2026-10-06, for the lead to verify):** built, client-side only (no RPC, no migration, SQL suites 13/13 pass, config untouched). Shared modules for L2: `src/art/sim/nav.ts` (grid, binary-heap A*, string pulling, corner rounding, nearest-reachable fallback) and `src/art/sim/locomotion.ts` (spring-eased speed, corner/stop slow-down, turn-in-place, final facing); `src/art/home3d/nav.ts` now only turns a HomeLayout into obstacles. Rig: `poseLife` (4 s breathing, weight shifts, look-arounds, 5 fidgets, tired slump / happy bounce from `simPosture`) and `poseGait` (distance-driven phase, no foot sliding) + pose buffers in `avatar3d/engine/anim.ts`; old `poseIdle`/`poseWalk` untouched (portrait cache unchanged). HomeScene: floor tap (8 px / 550 ms / one finger; drag, pinch, wheel never walk), green fading ring, furniture tap = sheet + pre-walk (≤ 7 s), action start keeps the `home.walk_max_share_pct` rule (+ hurry up to 1.4×), 0.42 s blends for sit/lie/stand/task end, busy = glass hint "<activity> first, then you can walk". Frame rate: full while moving/blending, 24 fps idle, 12 fps asleep/reduced motion, none hidden; under a sheet it only finishes a walk. Welcome screen file not touched (frozen): no taps there, idle life plays (neutral mood). Cost unchanged: face-me LAPO 42 calls / 11.5k tris, duplex Nepo 50 / 14.5k (same as before); idle ≈19 renders/s before and after (SwiftShader phone), walking ≈17-18/s (SwiftShader-bound), render 0.2-0.4 ms/frame before and after. Check: `node scripts/nav-check.mjs`. Dev: `window.__blSlowMo = 0.1` slows walks/blends for frame checks. Not done: blinks (eyes are merged into the head mesh; 1-2 px at home zoom), NPC animation LOD (no NPCs yet, L3). Details: docs/HUD_HOME.md "M1 movement", docs/AVATAR3D.md "M1 rig animation".

## S3. Map upgrade — [done]
The user finds the map "looking weird". Improve the 3D city's look: clearer roads and road names, better building variety/colours by district, nicer terrain/greenery, readable labels that don't crowd, nicer camera default, landmark models more recognisable, smooth day/night (S1.6). Keep perf budget (draw calls/triangles) from docs/CITY3D.md.

**S3 notes (agent, 2026-10-06, not committed):** diagnosis + fixes in docs/CITY3D.md "S3 map polish". Ground no longer an orange stain (sand/concrete/grass palette + noise + a yard under every building), no square slab edge (seamless skirt, roads and river run on past the edge, max zoom 80 and a zoom-dependent pan bound), real-looking roads (kerbs, white edge lines, centre dashes broken at junctions, paved side streets), **road names along the roads** (Ugbowo–Lagos, Mission, Akpakpava, Benin–Auchi, Benin–Agbor, Sakponba, Sapele, Airport, Siluko/Upper Siluko, Ekenwan, 3rd East Circular, Ring Rd), readable district names, district palettes (GRA white villas on lawns, core concrete/zinc, cramped rusty zinc), palace kept clear of houses + bigger bronze bird, labels no longer clipped at screen edges, "You are here" sits above the pin, desktop opens closer, live player counts (S1 presence) on the pills and the Neighbours filter. Perf: same draw calls (18 day / 21 night), triangles 99k → 107k day, 108k → 115k night (budget 150k). No migration. Files: `src/art/city3d/engine/{build,layout,CityScene}.ts(x)`, `src/art/city3d/{model.ts,city3d.css}`, `src/screens/Game.tsx`.

## M2. Movement & task feel (user, 2026-10-06) — [done]  (comes before L2)
1. **Faster walk, with a set speed.** The Sim walks too slowly. Raise the default speed and make it admin-tunable (`sim.walk_speed`, plus the robe/wrapper multiplier and the tired slowdown).
2. **Walk first, then the task starts.** When a task is tapped, the Sim does not teleport. They walk all the way to the spot, and only on arrival does the task (and its countdown) start. The server timer starts when they arrive: call the action RPC on arrival. Cancelling a walk cancels the task.
3. **Task progress pill moves to the left side, smaller.** No longer bottom-middle, so the centre stays clear. Shrink it and put it on the left, with the needs and quick buttons (where the "Eat something / Get some sleep" chips are).
4. **Action queue.** Tap several tasks; they line up and run one after another. The Sim walks to the next spot when the current task ends. The player can see the queue, remove items and reorder them if cheap. Max queue length is admin-tunable (`action.queue_max`, default 5).
5. **Bug: bent legs after sitting.** After watching Nollywood on the TV (or any sit), standing up leaves the legs bent. The legs must be straight when standing or walking again.

**M2 notes (agent, 2026-10-06, not committed):** details in docs/HUD_HOME.md "M2 movement & task feel". (1) Walk 1.15 → **1.9 m/s** (robes 0.72 → 1.33), stride + cadence scale with speed, admin keys `sim.walk_speed` / `sim.robe_speed_mult` / `sim.tired_slowdown`. (2) Every task walks first (M1 pathing) and `do_activity` is called **on arrival**; the 15 % / 1.4× / placed-there rules are gone; × or a floor tap drops the walking task; errors toast and the queue goes on; no-furniture tasks start at once. (3) Progress pill moved to the **left column** (icon, name, thin live bar, seconds, ×; shift pay counter kept); bottom busy banner removed. (4) **Queue** (zustand, max `action.queue_max` = 5, full toast, × and ↑ per chip, cleared on logout / leaving / travel / jail / hospital / server busy). New `activity_stop()` RPC for the × on a running task (keeps the share earned so far, no refund). (5) Bent legs: `restPose()` never straightened the knees, so a sit's 1.45 rad knee bend leaked into standing; fixed + `scripts/pose-check.mjs` + dev `__legCheck`. Migration `20261006001200_sim_feel.sql`, tests `sim_feel_test.sql`.

## L2+. Places, crowds, events, landmarks — [L2 + L3 done; L4 events next] (first L2 agent hit a usage limit before changing anything)
As in docs/REAL_LIFE_PLAN.md. Landmarks (docs/LANDMARKS.md): keep the REAL names the user chose (ShopRite/Benin City Mall, Kada Plaza, Mama Ebo, Protea, Golden Tulip, Ogba Zoo, Ogbe/Samuel Ogbemudia Stadium, Emotan Statue, real clubs) and **mix in local made-up names** so it isn't built only on real brands. Add:
- **Car dealers** (buy cars): real Benin options along Sapele Rd — e.g. Ighodalo Car Deals (Km 5 Sapele Rd), SDD Motors (174 Sapele Rd), Otos Autos (near Santana Market), Dominion Automobile; official Toyota (Mandilas, 45 Benin–Agbor Rd). Pick 1–2 real + a made-up "Tokunbo lot".
- **Top clubs with hype men & big spenders**: 360 Signature (GRA, 1st Ugbor Rd), Club De Medici (23 Benoni off Airport Rd, GRA), Rome Night Club ("biggest in Benin"), Club Vibes (DJ + hype man), Cube Nightlife, Versus Lounge, Havana. Club actions: table/bottle service (VIP prices), "spray money", hype man shout-out (costly, + street cred), dance.

**L3 crowds (agent notes, 2026-10-06; status marker left for the lead):** named NPC roster (121 Benin people, roles, looks,
English lines + Pidgin at markets/streets/parks/PoS) in `npc_roster`; how many by place type × hour band × weekday/weekend in
`crowd_profiles`; `place_people()` picks the same people for every player per place × hour. Nearest 4 people (2 on Low) use
the real avatar baked into a 1-call skinned mesh with role motions (MC Lightning hyping and DJ Ekpen at 360 Signature,
dancers, traders, bouncers); the rest stay instanced; animation LOD. White NPC pills, blue @player pills, People N list,
NPC + chat speech bubbles, "+N more here". Admin → Content → People (NPCs) / Crowd profiles; config `crowd.npc_list_max`,
`crowd.rigs_high`, `crowd.rigs_low`, `crowd.chatter_seconds`. Migration `20261006001500_crowds.sql`, tests
`crowds_test.sql`. Details + cost: docs/PLACES.md "L3 crowds".

## F1. Club soft launch + real feel (user, 2026-10-06 evening): [done]
- **Soft launch:** only **360 Signature** is open at first. The other clubs (and any place) can be hidden or shown with an admin switch (`locations.active`); hidden places have no map pin and can't be travelled to. Each place's opening and closing hours are editable in admin → Places.
- **Real feel** for every interior and the home: see docs/FEEL_PLAN.md.
- L3 crowds is paused (it was stopped before it changed anything). Gangs/robbery is planned in docs/GANGS_PLAN.md for later.

**F1 notes (agent, 2026-10-06, not committed; status marker left for the lead):**
- **Soft launch:** `locations.active` (migration `20261006001400_soft_launch.sql`, tests `soft_launch_test.sql`, 16/16 suites pass). Hidden places have no pin, aren't in Ride/search, can't be travelled to (`bl_travel_quote`, hint `inactive`), and refuse `do_activity` / `shop_buy` / `work_shift`; players inside can still leave or go home. Seeded once (`places.soft_launch_seeded`): Club De Medici, Rome, Cube, Versus and Owambe Republic hidden; 360 Signature open 9 PM – 5 AM. Pre-L2 made-up Bronze Lounge and Kingdom Lounge left active (switch them off in admin if wanted). Admin → Content → Places: Active switch per row + Opens at / Closes at time inputs with validation, audited.
- **Real feel:** shared `src/art/feel/` (texture atlas, baked AO, rigs per place type, clutter kits, outside world, fan / flicker / club sweep / steam, vignette + grain, per-place sound, Graphics Auto/Low/High in Settings). Home and 360 Signature first, then every kit through the shared shell. Details, perf table and what's left: docs/FEEL_PLAN.md "What F1 built". Screenshots: scratchpad `f1/` (before-*, after-*, montage-before-after.png).

## P1. Polish batch (user, 2026-10-06 night): [running], then L4, push tonight
1. **People move around:** NPCs don't stand frozen. Everyone walks between their spots and zones naturally, using M1 locomotion and pathing, then idles and does their role motion.
2. **Subtler lighting:** the light pools, beams and LED glow feel too strong. Use a soft, subtle ambient across all places (and the home).
3. **People everywhere:** every place type has characters, not only the main ones.
4. **Car stands:** car models with real shapes, a **Mercedes GLE AMG, G-Wagon (G-Class), Lamborghini Urus and Tesla Cybertruck**, on display at every car dealer and buyable there.
5. **Queue UI:** the running task pill, plus small **circles to its right** with the icon of each queued task. Show the running task plus at most 2 circles; when the running task ends, the next one shifts in. `action.queue_max` default is now **7**.
6. **No hard budget:** the user says look matters more than staying under the triangle guide; keep it smooth on phones (Auto/Low tier).

## LATER (user, 2026-10-06): welcome-back redo. Do NOT touch today; S2 stays as shipped.
The user wants the welcome screen to look like Lagos Life (`docs/references/lagos-life/welcome-back-1.jpg`, `welcome-back-2-newlife.jpg`):
- Game logo and title at the top, with a tagline (e.g. "Live your Benin story.").
- A big 3D house filling the middle, slowly orbiting 360°.
- A compact bottom card:
  - a row with portrait, name, then "Tuesday 6 Oct · ₦989m"
  - a green **Continue** button
  - a **New life** button
  - footer: "Signed in as @name" on the left, a blue **Log out** link on the right
- **New life confirm is inline** inside the card. It is not a modal and there is no typing the name. Text: "Start a brand-new life? <name>'s life (₦…, house, things and progress) will be replaced for good." Buttons: **Keep my life** / **Start over**.
- **No archive:** on Start over, discard everything and start fresh as a new player. Drop `profile_archive` snapshots (stop writing them; the table can stay or be emptied in a later migration).

**L2 notes (agent, 2026-10-06, not committed; status marker left for the lead):** places are entered: anywhere that is not home (and not on the road) shows the place's **3D interior** with a place card (mood line, Say something, Share/Map/Home, zone chips, action cards with seconds / price / Free / Earns ₦ / effect chips / Risky / lock reason). Every card goes through the M2 queue: walk to the zone (M1 pathing), the RPC runs on arrival; the left task pill and queue work inside. Data-driven: `place_zones`, `zone_actions`, `place_moods` (admin-editable, Content tabs), seeded for **every** location type; opening hours per place (clubs 9 PM – 5 AM, "Opens 9 PM" by day, enforced by `do_activity` + `shop_buy`). **17 new places** (12 real + Owambe Republic + Tokunbo Lot made-up, see docs/LANDMARKS.md "Seeded in L2"), 7 new place types with SVG headers, ~40 new activities (VIP table ₦150k, spray money ₦50k Risky, hype man shout-out ₦100k +5 street cred, dance, cinema, zoo, pool, luxury suite sleep, match day, Emotan photo/history, Mama Ebo pepper rice that sells out at lunch...), Kada chicken / popcorn / ShopRite items / club drinks, **cars at the dealers** (Tokunbo Corolla ₦2.5M, Kia Rio, Camry, Lexus RX, new Hilux; bank first then cash; any car unlocks "Your car" rides, which already existed). L3-lite: real players as blue @name pills + background people (instanced, cap `crowd.max_visible` 10). Perf: 45–56 draw calls / 11–16k triangles per interior (home 42–50 / 11.5–14.5k), lazy chunk. Migration `20261006001300_places.sql`, tests `places_test.sql` (15/15 suites pass), checks `node scripts/place-check.mjs`. Details: docs/PLACES.md.

## Sources (car dealers, clubs)
https://ranked.ng/car-dealerships/benin-city · https://www.facebook.com/p/Ighodalo-Car-Deals-100063548294416/ · https://nigerianinformer.com/official-accredited-toyota-dealers-in-nigeria-addresses/ · https://ranked.ng/nightclubs/benin-city · https://blog.naijabased.fun/night-club-in-benin-city · https://www.tripadvisor.com/Attractions-g298361-Activities-c20-t99-Benin_City_Edo_State.html
