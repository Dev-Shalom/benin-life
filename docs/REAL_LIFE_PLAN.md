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

## Status
- Not started; V1-8 launch check is running first. Next session: read the new references, confirm the open question, then
  build in this order: real-time clock → crowds (NPC + players, capped) → landmarks.
