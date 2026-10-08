# Prompt to paste into a new Claude session (cloud or local)

This file is kept current after every step. The detailed live status is the STATUS LOG at the bottom of `docs/HANDOFF.md`.

## Where the project is (2026-10-06, local session)
- **Current snapshot (2026-10-08; overrides the historical notes below):** branch `codex/visual-quality` includes screenshot-origin fix `cd14e5b` atop the pushed graphics follow-up `bfe89fa` on `origin/main`. The closed-place fix is already in `origin/main` at `cbe6fe8` (travel to closed places is refused server-side, map sheet explains opening time, and players inside are returned home when a place closes). Vercel deploys `main`; verify the deployment in Vercel before claiming the live site has updated.
- **Visual/map pass in progress:** the initial GRA duplex yard and downtown OSM footprint work is pushed as `5f151bb`. Follow-up `bfe89fa` upgrades shared home/place surfaces to roughness-aware PBR, tunes city materials, adds LAPO bulb wiring and a compound generator, and adds NEPO window curtains. Screenshot fix `cd14e5b` passes profile origin into the home renderer, so NEPO self-contains use NEPO finishes. The 5,281-building OSM snapshot covers downtown only; the wider map remains curated/procedural. `npm run build` passes. The user's screenshot has been reviewed, but wider scene coverage and low-end phone performance are not yet checked. Broad scene-by-scene art polish remains. See `docs/FEEL_PLAN.md`, `docs/MAP_GEO.md`, `docs/CITY3D.md`, `docs/maps/README.md`, and `docs/HUD_HOME.md`.
- **Paused / next systems:** P3 full-screen hype aura is unfinished on `origin/wip/p3-hype-aura` (SQL migration/test snapshot only; no finished client takeover on main) and should stay paused unless the user resumes it. E1 economy/storyline remains todo. Paystack `payments.enabled` remains off until the user completes a live test.
- **Push/deploy:** these graphics commits were pushed to `main` with the user's authorization. Vercel's actual deployment state still needs a live deployment check; do not claim the published app is updated based only on matching Git SHAs.

### Historical snapshot (2026-10-06; superseded by current snapshot above)
- **Live on main / https://benin-life.vercel.app:**
  - v1: the 3D game, creator, jobs, shops, rent, bank, chat and admin.
  - **L1 real Benin time:** WAT clock; every action takes seconds (sleep ≤15 s scaled by tiredness, shift 18 s, travel ≤20 s, hospital 30 s, jail 45 s); live progress bars; "Action timing" in admin.
  - **Money format:** K/M/B/T/Q, plus admin Give/Take money with shorthand ("5B"), preview and confirmation.
- **On the work branch only, NOT yet on main:**
  - The money short form now starts at ₦100,000 (user rule: under ₦100,000 shows in full). Migration 20261006000900.
  - **Hold it off main until "Starter homes" lands.** Its migration is 20261006000400, and the hosted DB must receive the migrations in number order.
- **Running:** **Starter homes by origin.**
  - LAPO: drum + bucket, one stool, small stove, mat.
  - Nepo: moderate furniture.
  - Actions match the furniture; the walk is skipped on short actions.
  - Migration 20261006000400_starter_furniture (applied locally). If the session died, check `git status` for its uncommitted files, verify, commit, then push the branch to main.
- **Done today (on main):** starter homes by origin, money full under ₦100k, **S1 quick polish** (BetNaija, Ride, Chowdeck, 24 h transfer wait, Beta, Terms/Privacy, update dialog, live counts, smooth day/night, sound), **S2 welcome-back screen** (orbiting house, Continue/New life/Log out; migration 20261006001100).
- **Frozen today (user):** the welcome-back screen. A redo to match Lagos Life (inline confirm, no archive) is under "LATER" in SHIP_TODAY.md. Do not touch it until the user says so.
- **Also done (on main):** M1 Sim movement & life (tap-to-walk, walk cycle, idle life).
- **Also done (on main):** S3 map upgrade.
- **Also done (on main):** M2: faster walk, walk then start, left task pill, queue, straight legs.
- **Also done (on main):** L2 place interiors + 17 real landmarks (clubs, car dealers, mall, Kada, Mama Ebo, hotels, zoo, stadium, Emotan). See docs/PLACES.md.
- **Also done (on main):** F1: only 360 Signature open (admin Active switch + hours), and the real-feel look everywhere (docs/FEEL_PLAN.md).
- **Also done (on main):** L3 crowds (named NPCs with roles, busy by real hour, People list, speech bubbles).
- **Also done (on main):** P1 polish (walking NPCs, softer light, people everywhere, luxury cars + bike/motorcycle, queue circles).
- **Also done (on main):** P2 club hype (MC Lightning announcements, Doremi, amapiano, per-place soundtracks).
- **Also done (on main):** L4 events (On today, tickets, travel + Go, banners).
- **Done (on main):** PAY: Paystack top-ups (docs/PAYMENTS.md), Ranks leaderboards, VIP arrivals. The user must turn on payments.enabled after a test payment. P3 is paused on branch wip/p3-hype-aura. Next: E1 economy and storyline. Later: gangs (docs/GANGS_PLAN.md). Previously running: L2 place interiors (docs/REAL_LIFE_PLAN.md Phase L, SHIP_TODAY L2+, docs/LANDMARKS.md). If the session died, check `git status` for its files, verify, commit.
- **SHIP-TODAY LIST (user, 2026-10-06): `docs/SHIP_TODAY.md` — follow it in order:** starter homes → S1 quick polish (BetNaija, Ride app, Chowdeck, 24 h transfer wait, Beta badge, Terms/Privacy, update-available dialog, live online/place counts, smooth day/night, sound + click SFX) → S2 welcome-back screen (orbiting house, Continue/New life/Log out) → M1 movement → S3 map upgrade → L2+ (real landmarks incl. car dealers + top clubs).
- **Next, in order (older list, now inside SHIP_TODAY):**
  0. **M1 Sim movement & life:** tap-to-walk on the floor, smooth walk cycle, breathing/idle life (docs/REAL_LIFE_PLAN.md).
  1. **L2:** enter places. A 3D interior with zones and action cards, using the REAL Benin places by their real names (docs/LANDMARKS.md, user decided) plus the real housing ladder (face-me-I-face-you → self-contain → mini-flat → Ikpokpan Rd apartment → Aideyan Rd duplex → Estate Gate mansion).
  2. **L3:** crowds. NPCs plus real players with name pills, capped.
  3. **L4:** map place sheet plus "On today" events.
  4. Then the post-v1 list: PvP robbery/police, loans/esusu, farming, Babalawo, more careers/hustles, buy mode, Paystack (test key from the user), DMs, airport, skills/perks, and the Terms/Privacy pages.
- **User rules (binding):**
  - Every action is short, with live progress.
  - Money shows in full under ₦100,000, short form from ₦100,000 up.
  - Real place names.
  - LAPO starts with trench basics.
  - 18+.
  - Keep the default numbers; the user tunes them in admin.
  - One agent at a time.
- **User to do:** claim admin at https://benin-life.vercel.app/admin (see docs/ADMIN.md), then tune the numbers.

## WARNING for the local PC (2026-10-06)
At 13:32 the PC pushed an old starter-homes version ("Latest Changes from map stylings", 212604e) and merged it into main with conflict markers in 10 files, which broke the build. The cloud restored the verified version (b5a9b1d). **Before working locally, always run `git fetch && git reset --hard origin/claude/kind-bell-e9reb8` (after saving anything you need), or `git pull`, and never commit files that contain `<<<<<<<`.** Never edit an applied migration such as 20261006000400.

## How it is deployed
- **Preview / live site:** https://benin-life.vercel.app — Vercel deploys **`main`**. `.env.production` points at Supabase project `twwttirvesbwjvzjmenp`.
- **Database:** the GitHub Action "Supabase preview DB" runs `supabase db push` on every push that touches `supabase/migrations/**` (repo secrets `SUPABASE_ACCESS_TOKEN`, `SUPABASE_DB_PASSWORD` are set). Migrations must be idempotent and safe on a non-empty DB. Never edit an applied migration — add a new one.
- **Branches:** work happens on `claude/kind-bell-e9reb8`. Only VERIFIED steps are pushed to `main` too (`git push origin HEAD:main`, fast-forward). Work-in-progress snapshots go to the work branch only.
- **Local run:** Docker Desktop on, then `powershell -ExecutionPolicy Bypass -File scripts\demo.ps1` (Windows) or `bash scripts/demo.sh` (Mac/Linux). It applies new migrations with `supabase migration up` (keeps accounts) and opens http://localhost:5173.
- **Tests:** `bash scripts/sql-test.sh -- supabase/tests/core_test.sql supabase/tests/map_geo_test.sql supabase/tests/origin_test.sql supabase/tests/time_test.sql supabase/tests/creator_test.sql supabase/tests/bladder_test.sql supabase/tests/careers_test.sql supabase/tests/shops_test.sql supabase/tests/bank_test.sql supabase/tests/chat_test.sql supabase/tests/admin_test.sql` (rolled back; run each suite in its own call — they share state if run together; also furniture_test.sql and life_test.sql), plus `npm run build`. Never run `npx supabase db reset` on a DB with accounts you want to keep.
- **Config that must stay set:** `origin.force_next` = "nepo" (one-shot: the user's next new account is Nepo), `origin.nepo_pct` = 10, `time.real_seconds_per_game_minute` = 0.75, `clock.epoch` = "2026-10-05T00:00:00Z", `rent.enabled` = true, `admin.bootstrap_emails` = the user's two emails (until they claim admin).

## Docs map
`HANDOFF.md` (status log, rules, decisions) · `V1_PLAN.md` · `REDESIGN_PLAN.md` · `FEEDBACK_PHASE1.md` · `ARCHITECTURE.md` (binding contract) · `DB_CORE.md` · `ORIGIN.md` · `CREATOR.md` · `AVATAR3D.md` · `HUD_HOME.md` · `CITY3D.md` · `CAREERS.md` · `SHOPS.md` · `BANK.md` · `CHAT.md` · `ADMIN.md` · `LANDMARKS.md` · `DEPLOY.md` (V1-8) · `MAP_GEO.md` · `ASSETS.md` · `references/lagos-life/NOTES.md`.

## The prompt
```
You're continuing the "Benin Life" game project: https://github.com/Dev-Shalom/benin-life
The latest work is on branch claude/kind-bell-e9reb8 (main = last verified step, deployed to https://benin-life.vercel.app).
Run: git fetch origin && git checkout claude/kind-bell-e9reb8 && git pull

Before doing anything, read docs/CLOUD_PROMPT.md (this file), then the STATUS LOG at the bottom of docs/HANDOFF.md, then docs/V1_PLAN.md. Read the other docs listed in the "Docs map" as needed for the step you're on.

Rules:
- Use only ONE subagent at a time, in the order of docs/V1_PLAN.md. Never run them in parallel (my PC has 8 GB of RAM).
- After each agent, check its work yourself (SQL tests, npm run build, screenshots), then commit, push to claude/kind-bell-e9reb8, and push verified steps to main too. Add a line to the STATUS LOG in docs/HANDOFF.md and update the "Where the project is" section of docs/CLOUD_PROMPT.md after every step.
- Keep the default numbers; I'll tune them in the admin dashboard.
- UI work: use the skills in .claude/skills/ (design-taste-frontend, emil-design-eng, svg-creator for art).
- I talk casually by voice. Confirm decisions back to me in short, plain language.

Continue from the first STATUS LOG item that isn't marked done. If an item says [running] and there are uncommitted files for it, finish and verify that work instead of starting over. Tell me in 3 lines where things stand before you start.
```
