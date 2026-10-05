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
- [running] V1-4 Shops + rent
