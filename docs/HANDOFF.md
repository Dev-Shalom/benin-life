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

## In progress or not yet done (Phase 1 wrap-up), in this order
1. ~~**Scenes B**~~ **DONE** (`src/art/scenes/_sharedB.tsx`, farm, home_face_me, home_flat, home_duplex, airport, shrine, workshop, plus buka/salon/cyber/office if they're in its scope).
   - When this handoff was written, an agent was still working on these on the user's PC. Files may be partial or uncommitted.
   - Check which files exist, render each one day and night, finish any that are missing, and run `npm run build`.
   - The original agent briefs aren't in the repo. The scope comes from ARCHITECTURE §7 and `src/art/Scene.tsx`.
2. ~~**Map geography fix.**~~ **DONE** (migration `20261005000100_map_geo.sql`, `supabase/tests/map_geo_test.sql`, render with `node scripts/render-map.mjs <outDir>`). The user asked for the map to match the real Benin City. The research is done and saved in **`docs/MAP_GEO.md`**: verified facts, road bearings, and a full corrected position table.
   - Write a new migration that updates `locations.x/y` to those values. Don't edit the applied core migration.
   - Update ARCHITECTURE §5.
   - Rework `src/art/map/mapGeo.ts` and the related files:
     - Road directions (Siluko goes **NW**, the Lagos Rd goes **N** to Uselu, Ugbowo and Oluku).
     - The palace compound goes **W** of King's Square.
     - District areas and exit signs.
   - Re-render and check.
3. ~~**Starting class roll, LAPO baby vs Nepo baby (user request).**~~ **DONE** (migration `20261005000200_origin.sql`, `supabase/tests/origin_test.sql`, `src/screens/OriginReveal.tsx`, HUD badge + Papa chip; notes in `docs/ORIGIN.md`). Profile panel badge waits for P2-SOCIAL's ProfilePanel.
   - **What the terms mean:** "Nepo baby" is born into wealth and connections. "LAPO baby" comes from a poor background and hustles alone; the name references LAPO Microfinance.
   - **The roll:** at `create_profile` the server rolls a class at random. The chance is admin-tunable with the config key `origin.nepo_pct`, default about 10. Everyone else is a LAPO baby. Keep it data-driven so more tiers can be added later.
   - **What each class sets (all admin-tunable config):** start cash, start bank, home location and housing, starting items (for example, a nepo baby gets a car and a laptop), a career head-start level, and an optional daily allowance from "Papa".
     - LAPO babies get easier micro-loan access, which is a Phase 2 hook.
     - Nepo babies get much more money and better homes, for example a GRA duplex.
   - **Code changes:**
     - Add `profiles.origin` and expose it in GameState and `types.ts`.
     - Add SQL tests.
     - Add a fun animated **reveal screen** after character creation ("Omo! You be Nepo baby…" / "LAPO baby — na hustle go carry you…").
     - Show the class on the profile and HUD.
4. ~~**Shorter sleep and activities, with a progress ring (user request).**~~ **DONE** (migration `20261005000300_time_tuning.sql`: rate 0.75 and `profiles.busy_started_at`; `src/ui/ProgressRing.tsx` in the busy banner; `supabase/tests/time_test.sql`).
   - A full sleep currently takes about 40 real minutes (`time.real_seconds_per_game_minute` = 5). The user wants **about 5–8 real minutes**. Set it to about 0.75 so a 480-game-minute sleep takes about 6 min, and keep it admin-tunable.
   - The busy banner must show a **slow-filling circular progress ring** that completes when the activity ends, like Lagos Life, instead of only a countdown.
5. ~~**Game-day counter.**~~ **DONE** (config `clock.epoch` = 2026-10-05T00:00:00Z, read by `bl_game_clock` and `src/lib/clock.ts`). The HUD shows "Day 3323" because the clock counts from 2026-01-01. Add a config epoch (launch date) so the count starts near day 1.
6. ~~**Landing page polish**~~ **DONE** using the `emil-design-eng` and `design-taste-frontend` skills. A good landing page already exists in `src/screens/Landing.tsx`.
7. ~~**Paystack placeholder.**~~ **DONE** (`src/lib/payments.ts` provider interface + `LIVE_CHECKOUT` flag, placeholder `WalletPanel` that P2-PAY takes over). Add a provider-agnostic `src/lib/payments.ts`, `VITE_PAYSTACK_PUBLIC_KEY` in `.env.example`, and a wallet "Top up" button that says it's coming soon. The user will test real payments with you later and will provide the **test** public key only.
8. **Phase 1 demo:**
   - Run the full app against local Supabase: `npx supabase start -x studio,imgproxy,vector,logflare,supavisor,storage-api,postgres-meta,edge-runtime,mailpit`, `npx supabase db reset`, `.env.local` from `supabase status`, then `npx vite`.
   - Click through sign-up, avatar creation, the origin reveal, travel, activities, a robbery and night mode, and fix bugs.
   - **Check the toast position:** an early screenshot showed the welcome toast overlapping the HUD username.
   - Hand the user the demo. Optionally deploy a preview (Vercel/Netlify plus a free Supabase project) so they can try it on a phone.

## Phase 2 (after the user approves the Phase 1 demo), one agent at a time
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
Run a full browser test, balance the numbers, write a deploy guide (Supabase cloud plus static hosting), and push to `https://github.com/Dev-Shalom/benin-life`. Then give the user the final demo.

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
