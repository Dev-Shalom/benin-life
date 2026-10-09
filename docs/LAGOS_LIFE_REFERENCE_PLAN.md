# Benin Life — Lagos Life reference audit and development roadmap

**Purpose:** turn the supplied screenshots into a practical, sequenced plan for making Benin Life a polished, replayable, mobile-first Benin City life simulator. The goal is to learn from the references' clear presentation and breadth while building original Benin Life art, systems and stories. Do not copy Lagos Life branding, assets, names or screen layouts pixel-for-pixel.

## Reference review and scope

I reviewed the full reference folder on GitHub `main` at `4067a6f`: **127 files total — 126 images and `NOTES.md`**. The current local checkout contains the previous 62 images; the GitHub update adds 64 newer mobile screenshots. I inspected the full set in labeled visual sheets and read the existing notes. The commit comparison from local `d4e2276` to GitHub `4067a6f` contains only those 64 image files under `docs/references/lagos-life/`; the code baseline is otherwise the same.

The references cover:

1. **Account and character setup:** account creation and login, the turntable character preview, body/look choices, fabric and colour choices, traits, dream, origin reveal and home selection (`01-signup.jpg`–`05-creator-woman.jpg`, `IMG_2364.png`–`IMG_2373.png`).
2. **The home and main HUD:** the top status pill, needs, short goals, clean-screen action, dock, 3D home, furniture catalogue and Sim tabs (`IMG_2358.png`, `IMG_2374.png`–`IMG_2386.png`).
3. **The city and live places:** map, place sheets, interiors, NPCs, other players, chat, activities, events and travel (`IMG_2392.png`–`IMG_2421.png`).
4. **Premium and night homes:** landscaped compound, pool, driveway and parked vehicles; room-specific interiors; warm lighting and restrained night accents (`1791390706223.jpg` and the two Twitter screenshots).
5. **The newer 64-screen mobile walkthrough:** boutique/wardrobe and outfit previews; rich and company rankings; house invitations; family and relationship screens; hustle job board, hiring and ratings; bus-company registration, routes and fares; betting; government/election screens; local shops and ratings; company registration; court claims; social feed; help guide; home HUD, room chat and home/place views.

These screens show intended product breadth; several also show empty states, closed shops, unfinished service screens and systems whose rules are not visible in a screenshot. A screenshot proves the design direction, not that the pictured service is balanced, safe or worth building.

## Recommendation

Benin Life already has the main foundation the references are asking for: a five-step creator, LAPO/NEPO origins, a 3D home and city, walkable place interiors, NPCs, jobs, bank, transport, weekly Stories, police reports and bail, events, location chat, friends, voice messages and private house visits. The current social update also synchronizes the host's home layout, furniture placements and player movement.

The largest gaps are **a complete home buy/build loop, persistent life-goal progress, more polished scene consistency, and deeper connected activities**. They matter more than adding every icon from the reference phone. Benin Life should feel richer because its places, homes, careers, social events and stories form one coherent Benin life—not because the phone has the same number of apps.

## What the references do well

- **A readable visual hierarchy:** one clear primary action, rounded cards, concise headings, readable status and a calm light interface around the game view.
- **A character preview that makes choices concrete:** the Sim remains visible while the player changes clothes, colours and identity.
- **A home that feels like a place:** open cutaway rooms, furniture with space to walk, room-specific props, yard planting, lighting and vehicles.
- **A consistent loop from screen to action:** browse, inspect, choose, confirm, then see the result in the world or the player's profile.
- **A useful phone hub:** players can find work, services, contacts, transport and city activities without leaving the game.
- **A social city:** named people, locations, messages, events, local shops and player activities make the map feel populated.

## What to improve in Benin Life

| Area | Benin Life today | Gap and planned response |
|---|---|---|
| **Visual identity** | A consistent low-poly 3D home, city and place renderer; roughness-aware materials, day/night lighting, origin-aware home finishes, graphics tiers and a Lite map. | Review every main scene at phone scale. Add more room-specific props, believable material variation, compound details and controlled shadows. Keep the recognizable Benin Life character style; improve craft and lighting before increasing polygon count. |
| **Homes** | Multiple housing tiers, origin-based starter furniture, furniture ownership, walking/pathfinding, private visits, host-only movement/rotation of owned movable pieces and synchronized placements. | The full buy mode is still a coming-soon preview. Build a real catalogue-to-placement flow, persistence and room navigation. Structural fixtures and some non-owned items remain fixed. Make a host's saved home the canonical version visitors load. |
| **Creator and style** | The creator already has Look → Personality → Dream → Birth lottery → Home, plus avatar editing and traits. | The references show a larger wardrobe with context outfits, owned/premium garments and immediate try-on. Build an in-game wardrobe and saved outfit slots rather than rebuilding the creator. Make Benin-inspired fabrics, workwear and occasion clothing original and respectful. |
| **Goals and stories** | Weekly WAT story choices and an origin/dream-based first-session guide exist. The guide is browser-local; dream progress is shown as unimplemented. | Persist milestones and one-time rewards server-side. Link a short story arc across weeks, with choices that reflect origin, dream and current stage. Show only truthful progress. |
| **Jobs and money** | Jobs, shifts, pay, bank, rent, cars and buying are implemented in a first slice. | Career depth, economy balance and player businesses remain incomplete. Finish one reliable money loop before adding company ownership, bus fleets or a broad marketplace. |
| **Social play** | Location chat, friend DMs, voice notes, house visits, live shared rooms and location events exist. | Add repeat reasons to meet: small co-op event goals, party activities and persistent NPC ties only when their state and rewards can be saved and moderated. Prefer a curated city noticeboard before an unmoderated social feed. |
| **Phone and services** | The phone intentionally lists working apps: Jobs, Messages, Stories, Bank, Ranks, Ride, Chowdeck, Houses, Cars, Police, Wallet, Alerts and Settings. | The screenshots contain many more apps. Add them only when the service works end-to-end; a smaller, dependable phone is clearer than many dead ends. |
| **Map and places** | The city map has Benin districts and landmarks, procedural infill, a downtown OSM footprint, walkable interiors, crowds and events. | Continue scene review and map coverage carefully. The current footprint is not a complete exact map of Benin. Use verified local locations and keep OSM attribution; don't trade phone performance for map density. |
| **Mobile usability** | Responsive game controls, clean-screen mode and low/auto graphics paths exist. | Recheck all menus and gameplay at narrow phones, tablets and desktop. The newer screenshots are tall mobile captures; several small actions, menus and dense lists need comfortable spacing and clear text at actual device scale. |

## Product principles

1. **Benin-first, original world.** Use recognizable Benin City neighbourhoods, building types, transport, work and public places. Use public cultural details carefully. Don't lift Lagos names, branding, artwork or sacred imagery.
2. **Every feature needs a playable loop.** A phone icon is not a feature. Each service needs an entry point, useful action, server result, feedback, error/empty state and reason to return.
3. **Make progression visible and fair.** Keep prices and rewards within a tested economy. Avoid fake progress, pay-to-win gates, random punishment and grind without a meaningful payoff.
4. **Design for phones first.** Preserve the 3D view, place controls where thumbs can reach them, respect safe areas and provide a clear Lite/fallback path.
5. **The server owns shared truth.** Money, purchases, milestones, furniture ownership, visits, cases and rewards must be validated server-side. Realtime is for timely presentation, not authority.
6. **Quality is not raw detail.** Use deliberate composition, readable walk paths, believable light/material response and local props. Keep the current stylized 3D identity and profile actual phones before increasing detail.

## Recommended roadmap

### Phase 0 — Repair and prove live house visits

**Status: RUNNING.** The code for invitations, admission, shared home rendering, movement broadcasts and house chat exists in the release, but it has not passed a two-account live play-through. The player reports that an accepted guest is not visibly inside the host's home, the two players do not see each other's movement, and house chat is not working. Treat those as real defects until reproduced and fixed; do not call Phase 0 complete based on the code or migration alone.

- Trace the guest from accepting the invite (knocking), through the host's named notification and host admission, into the host's home session. Keep admission server-checked: the host must be home, and guests must not enter a closed or private home by travel/map access.
- Make the host and every admitted guest render the same owner home layout, room, furniture and saved placements. Both sides must see the other player's avatar in-world.
- Synchronize movement as continuous, interpolated movement, not a disappearance/reappearance or a one-time position snapshot. Reconnect should restore current room membership and the correct home state.
- Make house text and voice chat reach every admitted participant in that home room. Preserve the approved mic/send composer and playback-speed control.
- Keep guests read-only for furniture editing, while allowing the intended home activities. Provide an obvious **Leave house** action that returns the guest to their own home and saved layout. The host can end their own session; define and handle what happens to guests if the host leaves or disconnects.
- Support multiple admitted guests for parties without leaking one home's presence, chat or furniture to another home.
- Use two separate player accounts on separate browsers/devices to reproduce each failure and verify invite → knock → admit → see each other → move → chat → leave, plus permissions and reconnect. Record device, viewport and network conditions.

**Cloud check (2026-10-09):** a two-account local Playwright run passed: friend, invite, knock, admit, both in the same room with each other in `useHouseRoom` members, house chat, Leave house. Added: a host leaving home ends the visit and sends guests home with an alert (migration 20261009000200). The live production check with two real phones is still owed by the user.

**Done when:** two or more players complete the full visit and consistently see the same home, each other's live avatars, and the same house chat; leaving restores each guest's own home; guests cannot edit the host's property; closed homes remain inaccessible.

**Work log (2026-10-09):** local implementation now recognizes the admitted-guest state in the home view, separates player arrival positions deterministically, publishes each player's latest position when Realtime presence joins, and adds a one-tap server-backed Leave house action. A new leave-house migration and social SQL coverage are in the working copy. `npm run build` passes; `npm run lint` exits successfully with existing warnings; rollback-only social/chat SQL suites and `git diff --check` pass. Live two-account verification is still blocked because the browser control reports that a saved user permission setting blocks access. Keep this patch on `codex/visual-quality`; do not push to `main` or claim deployment until the two-account flow is verified. Phase 0 remains open.

### Phase 1 — Visual quality and mobile consistency

**Size: M. Dependency: Phase 0 baseline captures.** Work from highest-traffic surfaces outward: home, HUD/phone, map, one market, one workplace, one night venue, then the remaining scene types.

- Make a screenshot set for the same viewports in Benin Life and the references: narrow phone, larger phone, tablet and desktop.
- Tune home framing, wall cutaways, walk routes, object scale, floor/wall material variation, contact shadows and lighting. Give each home tier appropriate props and exterior treatment; do not paste pools/luxury assets into starter homes.
- Make the home scene support multiple distinctive, rigged 3D player avatars at once. Show visitors visibly walking and performing permitted home actions (for example sitting, resting or using an activity), with animation and position shared consistently to everyone in the room.
- Give scenes a visual signature: market shade and clutter; workshop/cyber equipment; warm buka light; restrained club colour; daylight/day/night readable windows. Keep text, player labels and controls above the environment.
- Audit text wrapping, sheet overlap, safe-area padding, scene loading and reduced-motion behavior. Keep the Clean screen option.
- Profile representative low-end Android and iOS devices. Keep existing graphics tiers and the 2D Lite path. Establish capture-based comparisons so future art changes don't quietly regress readability or frame time.

**Done when:** every primary route is legible on the smallest supported phone; screenshots have consistent framing and light; no major scene causes crashes, unusable frame rate or controls obscured by the HUD.

### Phase 2 — Complete the home builder

**Size: L. Dependency: the existing furniture catalog, saved placements, home pathfinding and visitor sync.** This is the strongest direct follow-up to the new home references and a natural Benin Life differentiator.

- Turn Buy mode into a real catalogue grouped by room/use: design, sleep, kitchen, bath, comfort, fun, skills and lighting. Show price, ownership, grid footprint, quality and the activity it supports.
- Add preview → rotate → place → confirm/cancel, plus move, return-to-inventory and undo. Snap to a simple grid, show collisions and keep doors, toilet access and walking lanes clear.
- Persist placement, rotation, room/slot and item ownership. Validate price, bounds, collisions and host permissions on the server. Recover safely from interrupted saves.
- Keep each layout within its floor plan. Provide simple controls first; add free placement only after snapping/pathfinding works reliably on touch.
- For visits, stream the host's saved state to admitted guests and keep visitors read-only. Show a clear “host is editing” state if needed; never let a guest's local preview overwrite the owner's layout.
- Gate room sizes and premium exterior pieces by owned/rented home tier. Provide affordable starter furniture so progression doesn't require real-money purchases.

**Done when:** a player can buy or use an owned item, place/move/rotate/remove it, save/reload, walk around it, and see that exact state during a visit. Guests can interact with furniture actions but cannot mutate the layout.

### Phase 3 — Make the life goal and story genuinely persistent

**Size: M/L. Dependency: existing dream, career, skill, social and story data.**

- Add server-tracked milestones for each chosen dream. Use actions the game already supports—shifts, savings, skill levels, friendships or business—rather than invented counters.
- Display milestone progress in Goals and award modest, one-time rewards. Reject duplicate claims server-side and never show fake `0%` progress as if it were live tracking.
- Expand weekly Stories into a short linked chapter arc. Record prior choices, allow helpful/practical/social/opt-out answers, and vary dialogue or eligible choices by origin, dream and life stage.
- Add one repeatable wish/daily objective only after server reset rules and anti-farming checks are agreed. Prefer a small optional objective over a login streak that punishes missed days.
- Ground local weather, holidays, public services and legal references in current authoritative sources before presenting them as real. Mark fictional events clearly.

**Done when:** a new account can choose a dream, see valid progress from actual play, complete a chapter, claim one reward once and return the following week to a consequence that reflects the earlier choice.

### Phase 4 — Wardrobe and personal style

**Size: M. Dependency: existing avatar renderer and ownership/Shop transaction path.**

- Create a wardrobe screen with the Sim visible while browsing; support outfit slots such as everyday, home/sleep, work, date/occasion, party and fitness.
- Start with a small, high-quality set of outfits and colour/fabric variants. Show owned, equipped and for-sale states; save outfit choices and preview them before purchase.
- Use original Benin Life designs and locally relevant fabrics/silhouettes. Keep purchases cosmetic; never make an outfit affect job eligibility or player power.
- Keep the existing creator for identity setup. Wardrobe is an in-life extension, not a second creator flow.

**Done when:** outfits can be previewed, equipped, saved and restored across sessions on a phone, with correct avatar rendering in the home, city, profiles and chat.

### Phase 5 — Deepen careers before launching businesses

**Size: L. Dependency: balanced income/expenses, inventory and server-side transaction tests.**

- First improve a small career subset with clear entry requirements, shift quality, skill-based promotion and work schedules. Make sure each job pays fairly against rent, food, transport and home items.
- Then add **one** player-run business loop (recommended first: a local service/shop or a small transport operator). Include registration cost, a few upgrade choices, operating expenses, service hours, customer demand and an understandable earnings ledger.
- Add local marketplace discovery only for live, purchasable services with accurate availability, prices and ratings. Keep reviews reportable and blockable; prevent fake rating/reward farming.
- Add escrow or dispute handling only with explicit server rules, timeout behavior and abuse controls. Don't imply real-world delivery or cash-out unless those services actually exist.
- Expand to buses/routes, more industries and business rankings after the first business loop is stable.

**Done when:** one business can be started, operated, improved and closed with correct balances, visible costs/revenue, no duplicate payouts and understandable failure states.

### Phase 6 — Grow the city community safely

**Size: M. Dependency: stable realtime, moderation, privacy and event persistence.**

- Add a small co-op goal at a real Benin place—such as preparing for a match day, market day or neighbourhood cleanup—with shared progress and a modest cosmetic/community reward.
- Add persistent NPC relationship stages only when dialogue, player choice and reward state are server-backed. Start with a few memorable Benin characters instead of a huge static roster.
- Consider a curated in-game bulletin for events and player-owned services before a broad social feed. If a feed is introduced, ship reporting, blocking, rate limits, visibility controls and clear deletion/moderation rules with it.
- Keep private home membership and direct messages private. Do not put voice recordings, house status or precise player activity into public feeds without an explicit player action.

**Done when:** a group can find an event, participate together, see shared progress and leave without spam, private data leakage or unrewarded actions.

### Phase 7 — Civic systems and optional services

**Size: M/L. Dependency: safety/legal review and a stable core economy.**

- Extend the current Police case file into a private, evidence-based fictional investigation. Add clear stages and outcomes; don't claim a real report is filed with a real agency.
- Use fictional neighbourhood or city-service votes (for example, which public event or park improvement players prefer) instead of simulating current real elections or real politicians.
- Keep Court as a fictional dispute-resolution mechanic, not legal advice. Require evidence, protect both players' privacy, prevent repeat harassment and make moderator escalation clear.
- **Do not copy the real-odds betting app.** If a sports activity is ever desired, prefer no-stake predictions, trivia or team support with cosmetic/community rewards. Keep payments and wagering out of that loop unless separately reviewed for law, age, safety and responsible-play controls.
- Add optional family links (for example sibling, cousin, aunt/uncle or niece/nephew) and opt-in relationship requests only after consent, privacy, age safeguards, reporting/blocking and retention are defined. A request must be accepted by the other player and easy to decline or end. Keep relationship and family information private by default. Partner preferences may be player-selected; do not make access to the game conditional on identity or relationship status.

## Performance, accessibility and multiplayer guardrails

- Keep the single-visible-canvas approach, on-demand/paused rendering where appropriate, merged room geometry and instanced repeated city objects. Three.js documents instancing as a way to reduce draw calls; its optimization guidance also covers merged geometry. Keep the existing scene budgets and profile before adding assets. [Three.js InstancedMesh](https://threejs.org/docs/pages/InstancedMesh.html), [Optimize Lots of Objects](https://threejs.org/manual/pages/optimize-lots-of-objects.html).
- Cap device pixel ratio for heavy scenes and keep a tested Low/Auto tier. Three.js notes that rendering at full device resolution can be too slow for heavy applications. [Three.js Responsive Design](https://threejs.org/manual/pages/responsive.html).
- Keep Presence for membership/online state, not every position update. Supabase warns that Presence is not designed for high-frequency updates; use bounded, throttled Broadcast snapshots for movement and interpolate locally. Keep channels private and authorize joins/publish/read through RLS. [Supabase Presence](https://supabase.com/docs/guides/realtime/presence), [Realtime Authorization](https://supabase.com/docs/guides/realtime/authorization).
- Use **24 × 24 CSS pixels** as the WCAG 2.2 AA minimum target/spacing baseline and aim for **44 × 44 CSS pixels** on frequently used touch actions where layout allows. Test icon-only buttons with labels and screen readers. [WCAG 2.2 Target Size (Minimum)](https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum), [Target Size (Enhanced)](https://www.w3.org/WAI/WCAG22/Understanding/target-size-enhanced).
- Release gate for each major phase: phone, tablet and desktop captures; keyboard/touch checks; low-tier device profiling; 4G/reconnect check; database authorization and duplicate-write tests; production migration and Vercel version check.

## First recommended work order

1. Repair the reported house visit, shared avatar movement and room chat failures in Phase 0; then verify with two accounts.
2. Complete Phase 1's multi-avatar home and mobile visual review at phone/tablet/desktop sizes.
3. Build the full furniture catalogue and buy/place/move loop. This turns the home references into persistent gameplay and strengthens visits.
4. Complete truthful dream milestones and a connected weekly story arc shaped by each player's origin and chosen life path.
5. Add wardrobe, then one business system; let player feedback determine which additional apps earn a place on the phone.

The current production game is live. This plan is a roadmap, not a claim that the future phases or every reference screen are implemented. The user has now approved proceeding, starting with Phase 0. Update this document and `docs/HANDOFF.md`, `docs/CLOUD_PROMPT.md`, and `docs/SHIP_TODAY.md` as work changes status. Do not describe a feature as fixed/live until implementation, verification, push and deployment have each been confirmed.
