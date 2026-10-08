# E1 — Benin Life stories, choices and civic systems

Status: first playable slice pushed to `main` in `247d1b4` on 2026-10-08; GitHub's Supabase migration workflow succeeded; `npm run build` passes; local Docker migrations and rollback-only RPC checks pass for story loading/choice persistence, robbery report filing, case listing and bank-first bail. Vercel deployment is not yet independently confirmed. Interactive client checks, replay/ownership rejection checks, more story content and the broader E1 economy remain unfinished.

## Design rules

- Benin Life takes place in **Benin City, Edo State, Nigeria**. Do not confuse it with the Republic of Benin.
- Local details should sound like Benin City: neighbourhood check-ins, buka and market life, transport, generator/power interruptions, rain and drainage, community events, football, school/work routines, and Edo cultural heritage.
- Stories are short and choice-led. A player can help, spend a little, ask someone, or opt out. Avoid making every story a penalty or a grind.
- Treat cultural and royal traditions with respect. The Igue Festival is not a generic party backdrop: use public-facing music, food, art and community scenes, and do not make sacred palace rites interactive without knowledgeable local review.
- Law enforcement and legal claims must be grounded in a current official source. Mark invented checkpoint/case events as fictional game scenes, keep them separate from real law, and never claim the game is legal guidance.
- Keep outcomes server-authoritative, one choice per story week, no repeated reward farming, and all amounts/timers configurable. Money is game-only.
- Stories should be positive and age-appropriate. The previously specified hookup content remains 18+, tasteful and non-explicit.

## First slice

1. **Weekly story rotation:** one story is selected from an admin-editable catalogue for the WAT week. The server stores the player's choice and result and rejects a second choice that week.
2. **Story interactions:** choices can adjust bounded needs and street cred. A fictional reckless choice may trigger a brief jail timer, demonstrating the existing status/jail UI. It is not a simulation of a particular real offence or sentence.
3. **Police phone:** a player files a report only against a real robbery alert belonging to that account, at Police HQ or while held in the fictional cell. Case rows are private to the player. Bail draws from bank first, then cash.
4. **Cars app:** lists the existing dealer stock and directs the player to the selected dealer; purchases still go through the existing server purchase RPC (one of each, bank first, then cash).
5. **People:** tap a named NPC in the room or in the People list to open a small conversation with reply choices. Free-form messages to real players remain in the per-location Chat tab.

## Remaining E1 work

- Expand stories into a reviewed weekly catalogue with dates, optional requirements, multi-step progress, and admin editing; add public-holiday and seasonal schedules only from verified sources.
- Complete the economy pass and deep career ladders (school/degree gates, apprenticeship/housemanship, promotion paths and balance) without making early play pay-to-progress.
- Build an actual evidence/investigation flow for robbery reports; the first slice only records the report and case number. A real crime/wanted system is not implemented yet; don't imply a player can be jailed for crimes beyond the fictional story choice.
- Add richer NPC conversation trees and persistent relationships after this small scripted interaction.
- Recheck vehicle catalog, dealer access, travel unlocks, and cash/bank accounting in the live preview after the migration is deployed.

## Local context research (checked 2026-10-08)

- Edo State's official culture article describes Benin/Edo bronze work, festivals, traditional dance and coral-bead regalia, and identifies Igue as an annual Benin City festival. Use it as high-level context, not as a substitute for consultation on sacred details: [The Beauty of Arts and Culture in Edo](https://edostate.gov.ng/the-beauty-of-arts-and-culture-in-edo/).
- Edo State's 2025 bulletin announced monthly environmental sanitation for the last Saturday, 7–10 a.m.; a later official notice records a cancellation and reschedule. Therefore, sanitation dates can change: keep them as configurable story events and do not present a permanent schedule: [Edo Bulletin, April 2025](https://edostate.gov.ng/wp-content/uploads/2025/04/Edo-Bulletin-April-2nd-Vol-2-Edition-2025-.pdf), [government reschedule notice](https://edostate.gov.ng/government-special-announcement-6/).
- The official Edo State Traffic Management Agency describes traffic management/enforcement as its remit: [EDSTMA](https://edstma.edostate.gov.ng/).
- A 2021 Edo Government notice described a rider-permit system and said motorcycles remained prohibited in the Benin City metropolis at that time. This is dated information; current routes and exceptions were not confirmed in current official material during this research. Do not hard-code an okada ban based on that old notice: [Edo rider permits, 2021](https://edostate.gov.ng/edo-govt-to-commence-issuance-of-riders-permit-to-tricycle-motorcycle-operators/).
- The State's official materials refer to a 2023 Sanitation and Pollution Management Law, but this pass did not verify its full current text. Avoid encoding precise fines, arrest powers, sanitation hours or criminal procedure until a current gazetted law is reviewed.

## Push gate

Before this phase reaches `main`: verify Story duplicate-choice rejection, Police report eligibility and cross-player privacy, bail funding order, NPC taps at phone and larger screens, and phone purchase paths. The local Docker migration chain and rollback-only RPC checks passed; they do not verify the hosted database. Then update this plan, `docs/SHIP_TODAY.md`, `docs/HANDOFF.md`, and `docs/CLOUD_PROMPT.md` with the exact pushed commit. Vercel deployment is a separate check.
