# Benin Life: handoff for the next Claude session

Read this file first, then `docs/BRIEF.md`, `docs/ARCHITECTURE.md`, `docs/DB_CORE.md` and `docs/MAP_GEO.md`. Status is as of 2026-10-05.

## The project
**Benin Life** is a free browser life-sim for **Benin City, Nigeria**. It is modelled on the viral "Lagos Life" game (a Sims-like game on an illustrated city map). The user (GitHub: Dev-Shalom) wants to release it to everyone in Benin.

**Gameplay:**
- Players tap places on an illustrated Benin map, and each place opens a panel.
- Sims-style needs, a day/night clock, and travel by walking, keke, ECTS bus, drop or car, with real Benin traffic (the Ramat Park go-slow).

**Systems:**
- Jobs, with **career ladders from intern up to CTO-level** in every official track.
- Hustles (agbero, Yahoo boys with an EFCC raid risk).
- Markets, a finance system (bank, PoS, esusu, loans), farming, hospitals, a Babalawo, police, jail and bail.
- PvP robbery, with CCTV and police catch chances.
- Chat and DMs.

**Admin and payments:**
- An **admin panel** where the user tunes every percentage and number live.
- Paystack top-ups for virtual naira. This is a placeholder for now and must be easy to swap.
- An in-game **airport** for later linking to other cities' games.

**Tone:**
- All copy is in **Naija Pidgin**, not Bini/Edo.
- Light street humour, never too dark.
- Fictional gang names only. Show respect to the Oba and the palace.

**Stack:**
- React 19 + TS + Vite 8, zustand, react-router v7.
- Supabase (Postgres, RLS, RPCs, realtime). The free tier keeps costs low.
- **SVG-only art.** Use the `svg-creator` skill workflow: render, look, fix.
- Supabase auth with email and password, no OTP.

## How the user wants you to work (important)
- **Run one subagent at a time, in hierarchy order.** Never run several agents in parallel: the user's PC has only 8 GB of RAM, and parallel agents burned through the usage limit.
- **Verify before committing.** For each agent's output:
  - Read its report.
  - Re-run the tests yourself (`bash scripts/sql-test.sh …`, `npm run build`).
  - Look at the renders and screenshots.
  - Then commit just that agent's files.
- **Demo at the end of every phase.** When a phase is done, give the user a playable demo, wait while they go through everything, and only then start the next phase.
- **Landing page and UI polish:** use the **`emil-design-eng`** (Emil Kowalski) skill and the **`design-taste-frontend`** skill.
- The user writes casually by voice. Confirm decisions back in short, plain language.
- Commit messages end with the session's attribution lines.

## Done so far (all committed)
| Commit | What |
|---|---|
| Phase 0 | Scaffold, `docs/BRIEF.md` (the approved brief), `docs/ARCHITECTURE.md` (the binding contract: tables, RPCs, 37 locations, formulas, file ownership, art contracts), `src/lib/types.ts`, the SQL test harness `scripts/sql-test.sh` (runs migrations and a test inside BEGIN…ROLLBACK against the local container `supabase_db_benin-life`) |
| P1 shell | Landing, Auth, Setup, CreateSim (avatar creator), Game screen (HUD, needs bars, location sheet, travel picker, status banners for travel/busy/jail/hospital/robbed), UI kit `src/ui/*`, zustand state, realtime config, clock, Pidgin strings, ActivitiesPanel |
| P1 DB | `supabase/migrations/20261004000100_core.sql` + `…200_core_seed.sql`: 9 core tables, RLS, 9 RPCs, 37 locations, 68 config rows, 22 activities. All 17 groups in `supabase/tests/core_test.sql` pass. Notes in `docs/DB_CORE.md` |
| P1 avatar | `src/art/avatar/*`: layered SVG with 8 skin tones, 14 hairstyles and 23 Benin outfits; `AvatarGallery.tsx` dev page |
| P1 map | `src/art/map/*`: illustrated Benin map with day and night, pins, travel overlay and pan/zoom; generation takes about 120 ms |
| P1 scenes A | `src/art/scenes/` (11 scenes, day and night): market, hospital, campus, palace, museum, club, bank, police, motorpark, street, pos |
| P1 scenes B | `src/art/scenes/` (10 scenes, day and night): farm, home_face_me, home_flat, home_duplex, airport, shrine, workshop, buka, salon, cyber. `office` is Phase 2. Render any scene with `node scripts/render-scenes.mjs <outDir> [scene…]` |
| Cloud tooling | Skills committed in `.claude/skills/` (svg-creator, emil-design-eng, design-taste-frontend). SQL tests run without Docker: start a local Postgres, load `scripts/supabase-stub.sql` once, then `BL_PSQL="psql -h /tmp -p 54322 -U postgres -d postgres" bash scripts/sql-test.sh …` |

## Phase 1 status: COMPLETE, waiting for the user's OK (as of 2026-10-05)
All Phase 1 work is committed on branch `claude/kind-bell-e9reb8` (not yet merged to `main`).

| Item | Where |
|---|---|
| Scenes B (10 scenes incl. new `cyber`) | `src/art/scenes/*`, render with `node scripts/render-scenes.mjs <outDir> [scene…]` |
| Map matches real Benin geography | migration `20261005000100_map_geo.sql`, `supabase/tests/map_geo_test.sql`, `src/art/map/*`, render with `node scripts/render-map.mjs <outDir>`. Two pins nudged from MAP_GEO.md (ring_road_pos 540,452; police_hq 510,604) to avoid overlaps |
| LAPO baby / Nepo baby roll | migration `20261005000200_origin.sql` (`origin_tiers`, `origin.*` config, `claim_allowance()`, origin block in `get_my_state`), `supabase/tests/origin_test.sql`, `src/screens/OriginReveal.tsx`, HUD badge + Papa chip. Notes: `docs/ORIGIN.md`. Profile-panel badge waits for P2-SOCIAL |
| 6-min sleep + progress ring + Day 1 epoch | migration `20261005000300_time_tuning.sql` (`time.real_seconds_per_game_minute` 0.75, `profiles.busy_started_at`, `clock.epoch` 2026-10-05), `supabase/tests/time_test.sql`, `src/ui/ProgressRing.tsx` |
| Landing page polish | `src/screens/Landing.tsx`, `LandingArt.tsx`, `Brand.tsx` (palace silhouette with bronze bird, bus/keke go-slow), landing CSS in `src/styles/screens.css`. LAPO/Nepo numbers on the landing page are hard-coded copies of the `origin.*` defaults |
| Paystack placeholder | `src/lib/payments.ts` (provider interface, `LIVE_CHECKOUT=false`), placeholder `src/panels/WalletPanel.tsx` (P2-PAY takes it over), `.env.example` keys |
| Phase 1 demo click-through | 13 steps passed against real local Supabase. Fixes: toasts sit under the measured HUD (`--hud-bottom`), no duplicate toast on street robbery, danger glow / "Danger zone" label threshold 1.4 (only Upper Sakponba + Third East), "Belle" label |

**Run all SQL tests** (after `npx supabase db reset`): `bash scripts/sql-test.sh -- supabase/tests/core_test.sql supabase/tests/map_geo_test.sql supabase/tests/origin_test.sql supabase/tests/time_test.sql`. Without Docker see the Cloud tooling row above.

**One-command demo:** `scripts/demo.ps1` (Windows) or `bash scripts/demo.sh` (Mac/Linux) starts Supabase, resets the DB, writes `.env.local` and opens the game.

### User feedback on the Phase 1 demo: see docs/FEEDBACK_PHASE1.md (read it before any UI or copy work)

### Open questions for the user (asked 2026-10-05; answers are in FEEDBACK_PHASE1.md)
1. Jail and hospital use the same `time.real_seconds_per_game_minute` as sleep, so they got ~6.7x shorter. Give crime its own rate key in Phase 2?
2. Landing page is dark "dusk" theme only. Light theme wanted?
3. The map compresses distances to the centre, so outer S/W is mostly bush. OK?
4. Nepo start: ₦50k cash + ₦500k bank + ₦5k/game-day Papa allowance; car ₦2.5M and laptop ₦250k are placeholder prices. OK?

### Small polish noted by the demo verifier (not done, low priority)
- With a sheet open, toasts overlap the sheet's scene header (and on desktop run ~60px into the right-hand sheet).
- "Do am" buttons stay enabled while busy (server refuses with a Pidgin error).
- Sign-in shows two greetings in a row; on /create the welcome toast covers the title briefly.
- Fully zoomed-out map shows empty bands above/below.
- Kingdom Lounge's pin hit circle overlaps Bronze Bank's label at default zoom.
- On load `get_my_state` is called 3x and `game_config` 2x (harmless).

## NEXT: Phase R redesign (approved 2026-10-05). See docs/REDESIGN_PLAN.md. Do it BEFORE Phase 2.
The whole game goes 3D, with a Lagos Life-style light UI, the creator flow, a phone, and the deeper life systems.

## Phase 2 (after the Phase R demo is approved), one agent at a time
1. **Economy and careers.** Jobs and the career ladders in ARCHITECTURE §9b, including the new `bronze_tech_hub` location (scene `office`, position in MAP_GEO.md), plus market/shop and housing.
2. **Money.** Bank, PoS fees, esusu, loans (with the LAPO hook), farming at Iguobazuwa, hospital, and the Babalawo (charms that reduce robbery chance).
3. **Crime.** PvP robbery with CCTV and police catch chance, police, jail and bail, Yahoo and EFCC raids, and agberos.
   - If it replaces `bl_roll_street_robbery`, it must also replace `bl_street_robbery_chance` so the UI's risk warnings stay correct.
4. **Chat and DMs.** Design for low bandwidth: Lagos Life's chat struggled at about 50k players online.
5. **Admin panel** (`src/admin/AdminApp.tsx`, already routed at /admin for `is_admin`):
   - **Very simple and good-looking.** Edit every `game_config` value with sliders and inputs grouped by category.
   - Edit career levels, origin tiers and probabilities, and robbery percentages.
   - The changes go live through realtime.
6. **Payments and airport.** Paystack, built so the provider can be swapped; the airport for linking to other cities; and the office art.

## Phase 3
Draft the Terms of Service and Privacy Policy pages (approved by the user; the sign-up checkbox links to them). Run a full browser test, balance the numbers, write a deploy guide (Supabase cloud plus static hosting), and push to `https://github.com/Dev-Shalom/benin-life`. Then give the user the final demo.

## Decisions the user already approved
- Use Paystack first, behind an abstraction so it can be changed.
- Use agberos, Yahoo boys and a Babalawo, but keep it light and not too dark.
- Players can rob players, with a catch chance through police or CCTV.
- Email and password login, no OTP.
- SVG art only; the Gemini image key is optional and parked.
- Keep "POLICE IS YOUR FRIEND" on the police scene, because the user finds it funny.
- These balance numbers are approved (and admin-tunable):
  - New-player protection: 2 real hours.
  - Street robbery: 6% base, 35% cap.
  - Fares are rounded up to the nearest ₦10.
- Night danger zones are **Upper Sakponba** and **Third East Circular** (night multiplier 3.0).
- The map opens at "cover" zoom on phones (fills the screen).

## Gotchas
- **On the user's Windows PC:**
  - Claude Code runs inside the VS Code terminal, so don't close VS Code.
  - Docker Desktop is at `%LOCALAPPDATA%\Programs\DockerDesktop\Docker Desktop.exe`.
  - `~/.wslconfig` caps WSL at 3 GB.
- **In a cloud session:** you can't run the user's local Docker. Use the cloud environment's own tooling, or ask the user to run commands locally.
- `get_my_state` must stay read-only. The realtime profile subscription refreshes on profile writes, so any write there causes an infinite refresh loop.
- Scene SVG ids must be prefixed with the scene name. The avatar uses unique per-instance ids. Several of either can be in the DOM at once.
- `.env.local` is gitignored. The local Supabase keys are the public demo keys.

## STATUS LOG (newest at the bottom; updated after every step)
- [done] Phase 0 and Phase 1, plus the Phase 1 demo fixes (see the tables above).
- [done] The user's Phase 1 feedback is recorded in docs/FEEDBACK_PHASE1.md, and the Lagos Life references are in docs/references/lagos-life/.
- [done] 2026-10-05: the user approved Phase R (everything goes 3D, a Lagos Life-style UI, deeper systems). The plan is in docs/REDESIGN_PLAN.md.
- [done] R1 Look and copy: committed 2026-10-05 and verified (build plus screenshots). The user CONFIRMED 18+ (replace any remaining 16+). The user approved drafting Terms of Service and Privacy Policy pages in Phase 3. Left for R3a: the server strings still say "Papa" (claim_allowance, origin taglines) plus Pidgin seed blurbs.
- [done] 2026-10-05 (cloud): user confirmed the R plan order R2 finish -> R3a -> R3b -> R4 -> R5 -> R6. Decisions: keep the 22 Phase 1 SVG location scenes as the header art in each place's panel; 3D city/home for everyone, with the Phase 1 2D map used ONLY as a fallback on extremely weak/low-data connections (detect e.g. navigator.connection effectiveType 'slow-2g'/'2g' or saveData, plus a manual toggle in Settings).
- [done] R2 finish (cloud): portraits hardened (visible-only rendering, LRU cap, context-loss recovery, retries, v1 migration safety net), Yahoo black+gold, stronger face shapes, three/r3f vendor chunks, docs/ASSETS.md + docs/AVATAR3D.md, dev route /dev/create. Original note: your local commit 827ee69 has the avatar3d engine, presets, fabrics, face shapes, turntable and the CreateSim switch; still to verify/fix: cached HUD portraits (grid tiles rendered blank in a headless check), no pink in Yahoo preset, phone performance, docs/ASSETS.md.
- [done] R3a creator data (DB): migration 20261005000400_creator.sql (traits, dreams, start_homes, create_profile_v2, choose_start_home, origin.force_next='nepo' one-shot, admin_set_origin + admin_audit, rent built but rent.enabled=false, Dad copy, moderated seed copy), creator_test.sql, docs/CREATOR.md. Demo scripts now use `supabase migration up` (keeps the user's accounts).
- [done] R3b 5-step creator UI (src/screens/CreateSim.tsx + src/screens/creator/*, one 3D canvas, resume to Home step, username-taken path). Notes: server username-taken error has no hint (client matches text); test accounts left in the local DB; origin.force_next restored to 'nepo'.
- [done] User decision: keep the R3a seed values for now (home rents/start cash, rent off until Phase 2 jobs, GRA Landlord ₦5M, mini-flat on Mission Rd). The user will tune everything in the admin console, so Phase 2 admin must cover start_homes, traits, dreams and every config key.
- [done] R4 3D home (5 layouts), new HUD + dock, Sim sheet (7 tabs), phone (18 fictional apps), Bladder need (migration 20261005000500_bladder.sql + bladder_test.sql). Verified on 3 accounts at 390 and 1280. Notes: sky snaps (no fade) at dawn/dusk; T and E open the same sheet; clock vs activity speed are separate config keys.
- [done] User asked to merge: main fast-forwarded to the work branch (5e3db8a). From now on push each verified step to both claude/kind-bell-e9reb8 and main (Vercel deploys main).
- [done] User approved the V1 launch plan: docs/V1_PLAN.md (R5 → R6 → jobs → shops+rent → bank → chat → admin → launch check). Phase 2 items not in V1 ship one by one after launch.
- [done] R5 3D Benin city map (V1-1): src/art/city3d/*, docs/CITY3D.md. ~17 draw calls, ~100k tris, 20 kB gz chunk; 2D map is a lazy fallback (Data Saver/2g/Lite pref/no WebGL). Open: Neighbours chip needs per-place player counts (Phase 2 social); wish chips cover part of the map on phones (look at in R6); real low-end phone check needed.
- [done] R6 full test (V1-2): 17 fixes (map rail folds, top pill clock, UI reset on re-login, travel marker mode, English server strings via 20261005000600_r6_fixes.sql, brand names, GRA/Sapele Road names, /dev routes dev-only). Suggestions parked: cancel/wake-up for activities, rent '(starts soon)' copy, housing-specific activities, danger filter camera, logout → landing.
- [done] V1-3 Jobs that pay: migration 20261005000700_careers.sql (6 tracks, bronze_tech_hub + office scene, work_shift/work_finish pay at end, auto-promotion, 3 shifts/game day), careers_test.sql, JobsPanel, phone Jobs app, Career tab, docs/CAREERS.md. Open to user: laptop gate for LAPO interns until shops sell it (V1-4), pay table, firing later, job-switch cooldown.
- [done] V1-4 Shops + rent: migration 20261005000800_shops.sql (18 items, laptop ₦45k, shop_list/buy/use/sell, ChopNow +40%, pay_rent, rent ON with no back-charge trigger, 60% sleep energy while owing), shops_test.sql, ShopPanel, Bag, ChopNow + Houses apps, docs/SHOPS.md. Open to user: laptop price, rent penalty/eviction later, paracetamol, sell free laptop, ChopNow delay.
- [done] User decision (2026-10-05 evening): finish v1 tonight; keep ALL default values (laptop price, rent penalty, pay table, no firing, instant job switch, instant ChopNow, etc.). The user will tune everything in the admin dashboard before announcing.
- [done] User asked for real top-tier Benin landmarks; researched and saved in docs/LANDMARKS.md (first step after v1; brand-name decision pending).
- [done] V1-5 Bank: migration 20261005000900_bank.sql (deposit/withdraw at Bronze Bank 08–16, PoS 1.5% min ₦100, transfers ₦50 fee, limits, history), bank_test.sql, BankPanel, PosPanel, phone Bank app, night 'Bank your cash' tip, docs/BANK.md.
- [done] V1-6 Chat: migration 20261005001000_chat.sql (per-location chat with RLS = current place, realtime, profanity filter, rate limits, report/auto-hide, block, 48 h retention, admin hide, chat_muted_until), chat_test.sql, ChatPanel, unread chip, phone Messages shortcut (DMs later), blocked list, docs/CHAT.md.
- [done] V1-7 Admin page: migration 20261005001100_admin.sql (config list/set/revert with audit, whitelisted table upserts, players: grant/ban/mute/admin/origin, stats, audit, chat reports, admin_claim with admin.bootstrap_emails; admin.* config hidden from players), admin_test.sql, src/admin/* (Overview, Settings, Content, Players, Chat, Audit), docs/ADMIN.md. User must claim admin on the live site soon after deploy, then clear the owner list.
- [done] V1-8 Launch check: no blockers; top-level ErrorBoundary + stale-chunk reload, PWA manifest/icons, OG tags, docs/DEPLOY.md. Exploit checks pass. Balance suggestions (not applied): starter rent ×3–5, slower early promotion, anti-alt-farming transfer settings, student pay ₦1,500. **v1 is ready.**
- [done] L1 real Benin time plus short actions everywhere with live progress (2026-10-06): migrations 000100 (already live) and 000200_real_time_fixes, src/lib/live.ts, plus admin action-timing keys. Defaults: jail 45 s, hospital 30 s, shift 18 s, travel 20 s, decay 2.5. Parked: the Sim walks to the bed for most of a short sleep (L2 polish).
- [done] **Money format (user request, 2026-10-06).** Shipped: src/lib/format.ts (naira exact for any size incl. digit strings/bigint; nairaShort K/M/B/T/Q, full under ₦10,000, truncates so ₦999,999 → ₦999K; parseNaira; isShortened), HUD cash pill (tap the amount = full figure for 4 s, + opens the wallet), titles with full amounts wherever short form shows, admin Give/Take money with shorthand + preview + quick adds + confirm ≥ ₦1B, migration 20261006000300_money_format.sql (bl_naira any size + "-₦", bl_naira_short, config admin.grant_max = ₦1Q replaces the hard ₦1T cap, ₦9Q balance ceiling, transfer/PoS config max raised), admin_test.sql extended. Original spec: Use real-world short scales everywhere, on both the player and admin side:
  - Scale: ₦950 · ₦12.5K · ₦1.2M · ₦3.4B · ₦1.1T · ₦2Q (quadrillion). Full amounts keep comma grouping (₦1,250,000,000,000). Hover or tap shows the full amount.
  - **Where:** src/lib/format.ts (`naira` / `nairaShort`), plus the HUD money pill, bank, shops, jobs, phone apps and the admin pages. Money is stored as bigint, which holds up to about ₦9.2 quintillion; JS is exact to about 9e15.
  - **Admin "Grant money"** (admin_grant_money already exists): the amount input accepts shorthand ("500K", "2.5M", "5B", "1T"), shows a live formatted preview, offers quick buttons (+1M, +1B, +1T), and asks for confirmation on huge amounts. Check that no config cap or validation blocks trillion amounts. Add SQL tests for large grants and a UI screenshot.
- [done] **Starter homes by origin (user, 2026-10-06).** Migration 20261006000400_starter_furniture.sql (furniture, starter_furniture, player_furniture; LAPO drum+bucket/stool/kerosene stove/foam mat 90% rest; Nepo bed/sofa/TV/fridge/gas cooker; furniture-gated actions; walk skipped on short actions; admin editable), furniture_test.sql. Pushed to main with 000900. The PC attempt was lost (never pushed); rebuilt in the cloud session as migration 20261006000400_starter_furniture.sql. If your local DB already recorded 000400 from the lost attempt, re-apply the new file by hand with psql.
  - **LAPO babies** start with trench basics only:
    - a water drum and a bucket (for bathing)
    - ONE small stool (no sofa)
    - a small stove (kerosene or a single gas burner) for cooking
    - a mat or thin foam mattress
    - nothing out of the ordinary for someone starting from the trenches
  - **Nepo babies** start with moderate, decent furniture: a proper bed, a sofa, a TV, a fridge and a gas cooker. Nice, but not mansion-level.
  - Starting furniture is data-driven per origin and per start home, and editable in admin.
  - Make the 3D home rendering (R4) and the actions that depend on furniture match. For example, LAPO bathing uses the bucket, and cooking uses the stove.
- [todo] **SHIP_TODAY list (user, 2026-10-06): docs/SHIP_TODAY.md** — S1 quick polish → S2 welcome-back → M1 → S3 map → L2+. Brand decision: KEEP the real names the user chose, mix in local made-up names; add car dealers + top clubs.
- [todo] **M1 Sim movement & life (user, 2026-10-06):** tap the floor to walk there (home + every place interior), smooth real walk cycle with pathing around furniture, alive idle (breathing, weight shift, look-around), natural idle after tasks; Sims-3 feel but lightweight. Spec in docs/REAL_LIFE_PLAN.md. Next after starter homes.
- [todo] **Real housing (user):** a housing ladder using real Benin areas and types:
  - face-me-I-face-you, self-contain and mini-flat in real neighbourhoods
  - an Ikpokpan Rd apartment
  - an Aideyan Rd duplex
  - an Estate Gate mansion (GRA)
  - Rent and buy prices are admin-editable.
- [todo] **Real landmarks with their REAL names (user decided, see docs/LANDMARKS.md):** big clubs and lounges (Versus, Havana, Cube, Club De Medici, Vibes), hotels (Protea, Golden Tulip), Benin City Mall/ShopRite, Kada Plaza, Mama Ebo, Ogba Zoo, Samuel Ogbemudia Stadium, Emotan Statue, and so on. Build them together with the L2 interiors, so the places you enter are the real ones.
- Order after L1: money format → starter homes by origin → L2 interiors (real landmarks + housing included) → L3 crowds → L4 events.
- [done] **S1 quick polish (2026-10-06).** BetNaija (coming soon), Ride app (keke/ECTS/drop/own car; no okada in the travel system), Chowdeck; migration 20261006001000_ship_polish (new-account transfer wait 1440 min); Beta badge; /terms + /privacy; update-available dialog via dist/version.json; live online/place counts (Realtime presence); smooth day/night (src/lib/daylight.ts); synthesized sound + click SFX (music on by default, low). Follow-ups: transfer-wait message says minutes, should say hours.
- [done] **S2 welcome-back screen (2026-10-06).** Orbiting 3D home with the Sim, portrait, money, Continue / New life (confirm twice, type the Sim name) / Log out. Migration 20261006001100_life_restart (profile_archive, life_restart(), life.* config, chat/audit FKs moved to auth.users so they survive a restart, admin + mute carry over, transfer-wait message in hours). life_test.sql. A restart resets account age (24 h transfer wait applies again, anti-farming). Throwaway test account s2throwaway@test.local exists locally only.
- [done] **M1 Sim movement & life (2026-10-06).** Tap the floor to walk (A* on 0.2 m cells + smoothing, tap marker, ignores drag/pinch), a walk cycle driven by distance so feet don't slide, turns on the spot, idle breathing/weight shift/look-around/fidgets, mood posture, 0.42 s blends after tasks, busy hint. Client-side only (no migration). Reusable src/art/sim/{nav,locomotion}.ts for L2. Idle 24 fps, asleep or reduced motion 12 fps. Welcome screen untouched (frozen by user).
- [done] **S3 map upgrade (2026-10-06).** New ground colours with no orange stain, the map edge blends out, roads and the river carry past the edge, pan and zoom are clamped. Asphalt roads with kerbs, lane marks and road names along the road. Readable district names, roof colours by district, houses kept off landmarks, a bigger bronze bird. Edge-safe pills, a better default camera, live presence counts on the map. Draw calls unchanged; about 107k triangles (budget 150k). Client only.
- [done] **M2 movement and task feel (2026-10-06).** Walk speed 1.9 m/s (`sim.walk_speed`, `sim.robe_speed_mult` 0.7, `sim.tired_slowdown` 0.18). The Sim walks to the spot and `do_activity` is called on arrival. Compact task pill on the left plus an action queue (`action.queue_max` 5; ×, move up). `activity_stop()` stops a running task and keeps partial gains, with no refund. Leg bug root cause: `restPose()` never reset the knees; fixed, with scripts/pose-check.mjs. Migration 20261006001200_sim_feel, sim_feel_test.sql.
- [done] **L2 place interiors + real landmarks (2026-10-06).** Every place has a 3D interior with zones, action cards, mood lines, location chat, People N and player pills. Tasks go through the M2 queue (walk to the zone, start on arrival). Migration 20261006001300_places: place_zones, zone_actions, place_moods, opening hours (clubs 9 PM–5 AM), Risky/rush activities, place_interior() RPC, cars sold at dealers. 17 landmarks (15 real + Owambe Republic + Tokunbo Lot), about 40 activities (VIP table, spray money, hype man, cinema, zoo, pool, match day, pepper rice sell-out). The migration was checked on a fresh DB. Next: L3 crowds (NPC roster, bubbles), L4 "On today" events.
- [done] **F1 (2026-10-06).** Soft launch: `locations.active`, and only 360 Signature is open among the new clubs; the others are hidden once via `places.soft_launch_seeded`. Admin Places has an Active switch and Opens/Closes time inputs, and hidden places are blocked on the server (travel, activity, buy, shift). Real feel: src/art/feel/* (procedural texture atlas, baked AO, light rigs per place, Benin clutter, an outside world with fog, fan/flicker/club sweep, vignette and grain, per-place sound, Graphics Auto/Low/High). Within budget (at most 57 draw calls, about 23k triangles). Migration 20261006001400_soft_launch.
- [done] **L3 crowds (2026-10-06).** npc_roster (121 NPCs: MC Lightning, DJ Ekpen, Big Osaze at 360 Signature), crowd_profiles by type × hour × weekday, and place_people() picked the same way for every player. Nearest people use real avatar rigs (4 on High, 2 on Low) with role motions; the rest are instanced. White/blue name pills, People list, NPC and chat speech bubbles. Admin Content: People (NPCs) and Crowd profiles. Migration 20261006001500_crowds. The busiest rooms are about 26k triangles (set `crowd.rigs_high` to 3 to stay under 25k).
- [done] **P1 polish (2026-10-06).** NPCs wander (wander.ts; the DJ stands behind the booth). Lighting toned down 40–60%. 63 more NPCs, so every place type has people. Procedural cars at all dealers: Urus ₦450M, G 63 ₦350M, Cybertruck and Escalade ₦250M, GLE 63 ₦180M, C300 ₦95M, Camry ₦75M, Bajaj ₦1.6M, bicycle ₦180k; the bicycle and motorcycle have their own travel modes. Queue circles (2 + "+N"; `action.queue_max` 7; a "Next…" placeholder between tasks). Migration 20261006001600_polish.
- [done] **P2 club hype + party vibe (2026-10-06):** place_announcements over Realtime, written only on the server by bl_hype_announce from do_activity/shop_buy; hype_templates editable in admin; "Shut down the club" ₦2M; app-wide ticker at ₦500k or more; Doremi stinger; original amapiano groove (src/lib/music.ts) synced to lights and dancers; per-place soundtracks. Migration 20261006001700_hype. (big-spender announcements to everyone in the club plus an app-wide ticker, Doremi stinger, original amapiano groove synced with the lights, live soundtracks for other places). See SHIP_TODAY P2.
- [done] **L4 events (2026-10-06).** place_events (weekly in WAT plus one-off) and event_tickets; events_on_today() and event_buy_ticket(); event-only cards (`requires_event`). New map place sheet: open/closed, people, Share link, On today, travel cards with Go. Rotating event banner (hype takes priority), LIVE/🎟️ pin badges, admin Content → Events. Seeded: Bendel match on Sunday 4 PM, Amapiano Night Fri/Sat, Kada premiere Fri, Protea pool party Sat, Oba Market day Sat, owambe Sun. Migration 20261006001800_events.
- [paused] **P3 hype with aura:** the agent hit the weekly limit; unfinished work is on branch `wip/p3-hype-aura`.
- [done] **PAY (2026-10-07).** topup_packs and payments; payment_init plus the service-role-only bl_payment_credit (idempotent, checks the amount); Edge Functions paystack-verify and paystack-webhook (HMAC), deployed by .github/workflows/supabase-functions.yml (copies the GitHub secret PAYSTACK_SECRET_KEY into Supabase). The client reads Vercel env PAYSTACK_PUBLIC_KEY (envPrefix PAYSTACK_PUBLIC_). Admin Payments page and Top-up packs. Ranks phone app (Rich and VIP podiums), top-3 VIP arrival announcements. `payments.enabled` is false until the user tests. Note: the local DB has P3's 001900 applied, so hype_test fails locally only.
- [todo] **E1:** economy and storyline (see SHIP_TODAY E1).
- [done] **Closed places (2026-10-07).** You can't travel to a place outside its hours (server), the map sheet shows "closed, opens at…", and players inside when it closes are sent home with an alert. Migration 20261007000200_closed_places.
- [running] **VQ visual quality + OSM map fidelity (2026-10-08).** The initial OSM core + GRA duplex pass is pushed as `5f151bb`; the shared PBR/home detail follow-up is `bfe89fa`; screenshot-origin fix is `cd14e5b`. The latter passes profile origin into the home renderer, so NEPO self-contains use NEPO finishes rather than LAPO defaults. `npm run build` passes. The user's live screenshot was reviewed; low-end mobile performance and broader scene-by-scene visual review remain unverified. City footprints cover downtown only. Details: `docs/SHIP_TODAY.md` VQ, `docs/FEEL_PLAN.md`, `docs/MAP_GEO.md`, `docs/CITY3D.md`, `docs/HUD_HOME.md`.
- [paused] **P3 hype aura (2026-10-08 status check).** Still only a database/test snapshot on `origin/wip/p3-hype-aura`; no finished client takeover on `main`. Keep paused per the user's prior instruction to hold the hype test.
- [running, pushed to main] **E1 storyline + social/police slice (2026-10-08, commit `247d1b4`).** Migration `20261008000100_story_police.sql` adds WAT-week story choices, bounded effects, one fictional short-hold branch, private robbery reports/cases and bank-first bail. The GitHub Supabase migration workflow succeeded. Phone Cars app uses existing dealership stock and `shop_buy`; Stories and Police apps connect to the RPCs. Place NPC taps open a scripted conversation; real-player location chat already existed. Local Docker migrations and rollback-only RPC checks passed for story load/choice, report/case listing and bank-first bail; `npm run build` passes. Local migration review fixed a missing `relax_sofa` activity seed in `20261006001300_places.sql` and malformed storyline JSON. Still needed: replay/ownership rejection and Cars/NPC client checks. Vercel deployment has not been independently confirmed. Full E1 economy, real crime/investigation mechanics, DMs and deeper story catalogue remain unfinished. Plan and researched context: `docs/STORY_PLAN.md`.
- [running, local WIP 2026-10-08] **Benin Life first-session journey + retention plan.** Added `src/screens/game/JourneyGuide.tsx` after new-profile move-in, using saved LAPO/NEPO origin and dream, with a four-card responsive intro and final map handoff. Completion is browser-local. Hid non-working Contacts, Health, Invest, BetNaija, Family, Hustle and Edo Gov phone apps. Adjusted synthesized home music toward a calm upbeat groove (96 BPM day / 76 BPM night, quiet shaker and lighter bass). `docs/STORY_PLAN.md` now records five retention pillars, local setting guardrails and pending server-side milestones, linked weekly chapters, NPC relationships, co-op goals and one-time rewards; `docs/SHIP_TODAY.md` and `docs/CLOUD_PROMPT.md` track this work. `npm run build` passes. Interactive mobile/desktop checks remain. Not pushed; do not report as live.
