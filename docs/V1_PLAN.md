# V1 launch plan (approved by the user, 2026-10-05)

The user wants a **launchable v1** first: a game that already works and where players can do real things
every day. Other features ship one by one after launch.

## In v1, in order (one agent at a time, verify, commit, push to both branches)
| # | Step | Scope |
|---|---|---|
| V1-1 | R5 3D city map | finish + verify (running) |
| V1-2 | R6 full test | click-through of everything so far, fix bugs |
| V1-3 | Jobs that pay | data-driven career tracks/levels (ARCHITECTURE §9b) for a launch subset: PoS operator, market trader, keke rider, UNIBEN student, UBTH nurse/health, tech intern at `bronze_tech_hub` (+ scene `office`). Shifts at the job's location, pay per shift, XP, promotion through the first few levels, performance from needs. Phone "Jobs" app + Sim sheet Career tab. All numbers admin-tunable. |
| V1-4 | Spend money | NPC shops at markets/buka (food + basic items, inventory, use/eat), items table seeds. Turn on weekly rent (`rent.enabled`) once jobs exist; landlord warning/eviction kept light. |
| V1-5 | Bank | deposit / withdraw at Bronze Bank (and PoS with a fee); bank money can't be robbed. Phone "Bank" app. |
| V1-6 | Chat | per-location chat, low bandwidth (paged, rate-limited, profanity filter, block/report). |
| V1-7 | Admin page | `/admin` for `is_admin`: edit every `game_config` value grouped by category (sliders/inputs), edit start_homes/traits/dreams/careers/items prices, origin %, force next origin, player list (grant money, ban), audit log. Changes live via realtime. |
| V1-8 | Launch check | full test on the preview (https://benin-life.vercel.app), balance pass, deploy notes, then hand the user v1 and wait for OK. |

## After v1 (one by one)
**First after v1: real Benin landmarks** (docs/LANDMARKS.md — ShopRite/Benin City Mall, Kada Plaza, Mama Ebo, Ogba Zoo, stadium, Emotan Statue, hotels, GRA lounges, fun parks).
PvP robbery/gangs and full caught-crime investigation, loans + esusu (LAPO hook), farming at Iguobazuwa, Babalawo charms, more careers + hustles (agbero, Yahoo/EFCC), buy mode + furniture, airport/private flights, skills/feelings/wishes/perks. Police robbery reports, bail, and a fictional story-only jail branch are in the E1 local first slice; real crime/arrest mechanics are still future work. Location chat works; one-to-one DMs remain later work. Paystack is implemented but top-ups remain off until the user completes a live test.

## Preview
- Site: https://benin-life.vercel.app (Vercel deploys `main`; `.env.production` points at Supabase project `twwttirvesbwjvzjmenp`).
- DB: GitHub Action "Supabase preview DB" runs `supabase db push` on every push touching `supabase/migrations/**` (secrets SUPABASE_ACCESS_TOKEN, SUPABASE_DB_PASSWORD are set). Never write a migration that would break on a non-empty DB.
- Only push VERIFIED work to `main`; WIP snapshots go to `claude/kind-bell-e9reb8` only.
