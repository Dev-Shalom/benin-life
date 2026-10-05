# "Real life, but virtual" — user direction (2026-10-05, night)

The user wants the game to follow real daily life in Benin City. Waiting on new reference screenshots
(the user says they uploaded them; not in the repo yet — check `docs/references/` after `git pull`).

## 1. Clock = real Benin time
- The game clock must match the **actual time in Benin City (WAT, UTC+1)**: 7:30 AM in real life = 7:30 AM in the game.
  Today the clock runs 12× faster (1 game day = 2 real hours); that changes to 1×.
- Day/night, rush hours (07–10, 16–20), market days, club nights, banking hours (08–16), Saturday rent and
  "per game day" limits (shifts, Dad's allowance, transfers) all follow the real calendar.
- **Open question for the user:** activities and sleep stay SHORT in real minutes (user asked for no long waits earlier),
  or become real-length? Default proposal: keep durations short and admin-tunable (`time.real_seconds_per_game_minute`),
  while the clock itself is real time. Needs decay re-tuned to real hours (admin-tunable).
- Implementation: config `clock.mode` = 'real' | 'accelerated' (default 'real'), `clock.timezone` = 'Africa/Lagos';
  `bl_game_clock` + `src/lib/clock.ts` read it; day number = days since launch; tests for both modes.

## 2. People at every place (NPCs + real players), capped
- When a place is selected/opened, show **people there**: real players present + **default NPC people** so places feel alive
  (busy market in the morning, students at UNIBEN on weekdays, club crowd at night, empty streets at 3 AM).
- NPC count per place is data-driven by place type × real time of day × day of week (config/table), e.g. `place_crowd_profiles`.
- **Cap what's rendered** to avoid lag on low-end phones: e.g. max ~8–12 visible characters per scene/sheet
  (config `crowd.max_visible`), real players first, then NPCs; show "+N more here" for the rest. Use cached portraits
  (one WebGL renderer) — never one live 3D canvas per person.
- NPCs have names, outfits (avatar presets), a short Pidgin/English line, maybe a role (trader, keke rider, student).
- In the 3D city: small crowd markers/instanced figures at busy places, density by time.

## 3. Places / mapping
- Take note of real places (see `docs/LANDMARKS.md`) and how the map renders them; follow the user's references once they arrive.

## What the references show (see NOTES.md "Live places walkthrough")
- Real-time clock confirmed; activities stay short (5–20 real seconds) → answer to the open question: **keep durations short**.
- Every place = a **3D interior** you're inside, with **zones** and **action cards** per zone (duration, price/Free/Earns ₦, effect chips, Risky tag),
  an action **queue** with cancel, a rotating **mood line**, inline **"Say something out loud"** chat, share/map/home buttons,
  **NPCs with name pills** + **real players with blue @name pills + green dot**, **People N** with a render cap, a streaming "Loading…" pill.
- Map place sheet: description, share link, activity chips, **"On today"** live events with tickets, **travel mode cards** + Go button.
- Live events / banners (investor coming in 2 days, LIVE match), daily hunt, gigs that pay with tax.

## Build plan (Phase L "Live places", after V1-8; one agent at a time)
| # | Step | Scope |
|---|---|---|
| L1 | Real Benin time | clock.mode real (WAT), all day/night/rush/banking/rent/daily caps on the real calendar; short action durations kept; needs decay retuned per real hour (admin). |
| L2 | Place interiors + zones | 3D interior per place type (market, buka, club/lounge, bank, hospital, campus, motor park, PoS, police, palace/museum respectful, tech hub, stadium, shrine, street); data-driven `place_zones` + `zone_actions` (activities, jobs, shop items mapped to zones); action cards UI with queue + cancel; mood lines per place × time. Phase-1 SVG scenes stay as the fallback / Lite mode header. |
| L3 | Crowds | NPC roster (names, presets, lines) spawned by place type × real hour × weekday; real players present; render cap (config `crowd.max_visible`, default ~10), players first; name pills (white NPC / blue @player + green dot); "People N" list; chat bubbles over heads; streaming load pill. |
| L4 | Map sheet + events | place sheet with description, share link, activity chips, "On today" (Samuel Ogbemudia Stadium matches, Friday/Saturday concerts, market days), travel mode cards + Go; top banners for live/upcoming events. |
| L5 | Real landmarks | from docs/LANDMARKS.md. |

## Status
- V1-8 done (v1 ready). References read. Order: L1 → L2 → L3 → L4 → L5.
