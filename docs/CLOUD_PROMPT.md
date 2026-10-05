# Prompt to paste into a new Claude session (cloud or local)

This file is kept current after every step. The detailed live status is the STATUS LOG at the bottom of `docs/HANDOFF.md`.

## Where the project is (2026-10-05, ~21:00 UTC)
- **Goal right now:** finish **v1** (a launchable game). Plan: `docs/V1_PLAN.md`. The user keeps ALL default numbers and will tune them in the admin dashboard before announcing.
- **Done and live (pushed to main):**
  - Phase 1 (2D art, map geography, LAPO/Nepo roll, 6-min sleep, landing).
  - Phase R redesign R1–R6: light Lagos Life-style UI, English copy (Pidgin only in street moments, Nepo says "Dad"), 3D characters, 5-step creator, 3D home, HUD + dock (Home · Buy · Map · Phone), phone apps, Sim sheet, Bladder, 3D Benin City map (2D map only as weak-network fallback).
  - V1-3 jobs that pay · V1-4 shops + Bag + ChopNow + weekly rent · V1-5 bank/PoS/transfers · V1-6 chat per place · V1-7 admin page (`/admin`).
- **Done:** V1-8 launch check — **v1 is ready** (`docs/DEPLOY.md`). Now: Phase L.
- **Watch:** the GitHub Action that pushes migrations to the hosted DB was slow/queued for the chat (20261005001000) and admin (20261005001100) migrations; one run was cancelled. It now runs on `main` only. Check the Actions tab: if "Supabase preview DB" isn't green on the latest `main` commit, re-run it (Actions → Supabase preview DB → Run workflow). Until it's green, chat/admin on the live site can error.
- **User to do after V1-8:** claim admin at https://benin-life.vercel.app/admin with dev.shalom1@gmail.com or code.devshalom@gmail.com (then clear `admin.bootstrap_emails` in Settings → Admin; fallback SQL: `update profiles set is_admin = true where username = '<name>';`), tune numbers, then announce.
- **New user direction (top priority after V1-8):** `docs/REAL_LIFE_PLAN.md` Phase L (L1 real Benin time → L2 place interiors + zones + action cards → L3 crowds with render cap → L4 map sheet + live events → L5 landmarks). References: `docs/references/lagos-life/NOTES.md` "Live places walkthrough".
- **Next after v1, in order:** 1) real Benin landmarks (`docs/LANDMARKS.md`; ask real brand names vs nods), 2) PvP robbery + police/jail/bail, 3) loans/esusu (LAPO hook), 4) farming, 5) Babalawo, 6) more careers + hustles (agbero, Yahoo/EFCC), 7) buy mode/furniture, 8) Paystack top-ups (test key only from the user), 9) DMs, 10) airport, 11) skills/feelings/wishes/perks, 12) Terms/Privacy pages.

## How it is deployed
- **Preview / live site:** https://benin-life.vercel.app — Vercel deploys **`main`**. `.env.production` points at Supabase project `twwttirvesbwjvzjmenp`.
- **Database:** the GitHub Action "Supabase preview DB" runs `supabase db push` on every push that touches `supabase/migrations/**` (repo secrets `SUPABASE_ACCESS_TOKEN`, `SUPABASE_DB_PASSWORD` are set). Migrations must be idempotent and safe on a non-empty DB. Never edit an applied migration — add a new one.
- **Branches:** work happens on `claude/kind-bell-e9reb8`. Only VERIFIED steps are pushed to `main` too (`git push origin HEAD:main`, fast-forward). Work-in-progress snapshots go to the work branch only.
- **Local run:** Docker Desktop on, then `powershell -ExecutionPolicy Bypass -File scripts\demo.ps1` (Windows) or `bash scripts/demo.sh` (Mac/Linux). It applies new migrations with `supabase migration up` (keeps accounts) and opens http://localhost:5173.
- **Tests:** `bash scripts/sql-test.sh -- supabase/tests/core_test.sql supabase/tests/map_geo_test.sql supabase/tests/origin_test.sql supabase/tests/time_test.sql supabase/tests/creator_test.sql supabase/tests/bladder_test.sql supabase/tests/careers_test.sql supabase/tests/shops_test.sql supabase/tests/bank_test.sql supabase/tests/chat_test.sql supabase/tests/admin_test.sql` (rolled back), plus `npm run build`. Never run `npx supabase db reset` on a DB with accounts you want to keep.
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
