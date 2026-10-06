# Gangs, robbery and security: an "open world" plan, GTA-like (user, 2026-10-06). LATER, not tonight

The user's direction: players can create a gang, and gangs can rob and steal. The world should feel alive: you might be minding your own business and get "Your house is being robbed!" and have to react. Real players and NPCs share the world.

## Core loop
1. **Crews/gangs.**
   - Create one with a name, tag, colours and a boss. Invite members, with ranks: boss, deputy, member.
   - The gang has a bank (shared stash), a reputation and "heat".
   - A gang HQ is a place you rent and then enter (L2 interior).
2. **Crimes**, each a seconds-long action with odds:
   - **PvE:** pickpocket NPCs, rob a PoS kiosk, hijack a car, sell "hot" goods at Oba Market.
   - **PvP:** burgle a player's house (only while they are away or asleep).
3. **Defence.**
   - Buy security: gateman, dog, burglar-proof bars, CCTV, alarm, a "vigilante" subscription. Each lowers the odds of success and raises the chance a robber is caught.
   - **Live alert:** "Your house is being robbed! 60 s." You can rush home (travel), call police (pay), or call your gang for backup.
4. **Police and heat.**
   - Each crime adds heat (a wanted level of 1–5 stars, decaying over real time).
   - Police NPCs at checkpoints can stop you. Jail already exists (45 s); bail and a lawyer come later.
5. **Turf.**
   - Gangs claim places (motor parks, markets) for a small passive cut.
   - Turf wars run on weekly scheduled windows, not 24/7, to avoid griefing.

## Fairness and anti-grief (must have)
- **Newbie protection:** no PvP against accounts under 72 h old or below a level. LAPO starters are protected first.
- **Caps:** a cap on how much can be stolen per victim per day (e.g. 10–20% of cash on hand, never bank savings). Cooldowns per robber and per victim.
- **Opt-in:** an "Outlaw" toggle. PvP crime only works between players who opted in, but anyone can be robbed by NPC thieves (PvE events).
- Server-side odds and logs. Admin can tune every number and pause crime globally.
- 18+ and game-only money (already in the Terms).

## Live-world events (cheap first version)
- **Random server events** via a scheduled function:
  - NPC thieves hit a home (defence decides the outcome)
  - an area goes "go-slow" or gets a police checkpoint
  - a club night with a guest DJ
- **Push/toast alerts** through Realtime, plus a phone "Alerts" feed (exists).

## Build order (later)
G1 gangs and gang bank → G2 home security items plus NPC burglary events and alerts → G3 PvP burglary (opt-in, caps) → G4 heat, police, checkpoints → G5 turf.
