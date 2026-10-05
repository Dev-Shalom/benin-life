# Prompt to paste into a new Claude session (cloud or local)

This file is kept current after every step. The live status is in `docs/HANDOFF.md`, under the "STATUS LOG" section at the bottom.

**Current state (updated by the cloud session after every step):** Phase R in progress in a cloud session. Done: R1, R2, R3a, R3b, R4. Running: R5 (3D Benin city map). Next: R6 demo. Decisions: keep Phase 1 SVG place scenes as panel headers; 3D for everyone, the 2D map only as a fallback on extremely weak connections.
If the cloud session is still working when you start locally, run `git pull` first and don't redo a step marked [running] unless it has been idle for hours.

```
You're continuing the "Benin Life" game project: https://github.com/Dev-Shalom/benin-life
All the latest work is on branch claude/kind-bell-e9reb8. Run: git fetch origin && git checkout claude/kind-bell-e9reb8 && git pull

Before doing anything, read:
1. docs/HANDOFF.md fully. Read the STATUS LOG at the bottom first, because it says exactly where the last session stopped.
2. docs/REDESIGN_PLAN.md (the current phase: the redesign to 3D and a Lagos Life-style UI, agents R1 → R6).
3. docs/FEEDBACK_PHASE1.md (my feedback) and docs/references/lagos-life/NOTES.md (reference screenshots).
4. docs/BRIEF.md, docs/ARCHITECTURE.md, docs/DB_CORE.md, docs/MAP_GEO.md and docs/ORIGIN.md as needed.

Rules:
- Use only ONE subagent at a time, in the order in REDESIGN_PLAN.md. Never run them in parallel (my PC has 8 GB of RAM).
- After each agent, check its work yourself (SQL tests, npm run build, look at screenshots or renders), then commit and push. Add a line to the STATUS LOG in HANDOFF.md after every step.
- When a phase is finished, give me a playable demo and wait for my OK before starting the next phase.
- For UI work, use the skills in .claude/skills/ (design-taste-frontend, emil-design-eng, and svg-creator for art).
- I talk casually by voice. Confirm decisions back to me in short, plain language.

Continue from the first item in the STATUS LOG that isn't marked done. Tell me in 3 lines where things stand before you start.
```
