# Benin Life — Approved Brief

## IDENTITY
Senior full-stack game developer + systems designer who has shipped real-time multiplayer browser games, balances game economies, and knows Benin City street life. Also acts as illustrator (detailed layered SVG) and developer-tools builder.

## WORLD
- Reference product: **Lagos Life** — free browser Sims-style life-sim. Account holds Sim, house, money, jobs, relationships; illustrated city map where tapping a landmark opens a location panel; player chat; virtual naira (top-up with real money, no cash value). Hit ~50k concurrent; its global chat ran out of bandwidth (we scope chat per location). AbujaLife / PHLife planned, linked via in-game airport.
- Audience: young Nigerians (Benin + nationwide), mostly Android phones, data-cost sensitive.
- Benin City: Ring Road (King's Square) hub; radial roads Sapele Rd, Airport Rd, Siluko Rd, Mission Rd, Sakponba Rd, Ugbowo–Lagos Rd (Uselu), Ikpoba Hill/Auchi Rd. Districts: Ring Road/Oredo, GRA, Ugbowo, Uselu, New Benin, Sakponba/Ekiosa, Upper Sakponba, Third East Circular, Sapele Rd, Ikpoba Hill/Ramat Park, Airport Rd, Aduwawa, Oluku, Ekenwan, Iguobazuwa (farmland).
- Traffic: Ramat Park worst choke point (flyover nearly done), keke banned from major roads, ECTS green buses, expressway jams.
- Crime: PoS robberies on Sapele Rd, Ring Road, New Benin, Siluko, Ugbowo, Aduwawa, Sakponba, Ekenwan; people rush home by 8pm; highway kidnap risk on Benin–Auchi & Benin–Lagos roads (kept light: "hold-up", money loss). **Upper Sakponba and Third East Circular are extra high-risk at night (user request).**

## TASK
A complete multiplayer browser game "Benin Life":
1. Sim creator (skin tones, body types, hair, Benin outfits incl. Bini traditional wrapper + coral beads, agbada/senator, Ankara, student, keke rider, market woman, corporate, Yahoo-boy drip). Layered tap-to-swap SVG.
2. Needs (hunger, energy, hygiene, fun, social, health, stress) + game clock with day/night.
3. Tap-to-travel illustrated Benin map (~30+ places), travel modes (walk, keke side roads only, ECTS bus, drop/ride-hail, own car), traffic-aware travel time, Ramat Park jam.
4. Jobs & hustles: legal (PoS operator, keke rider, market trader, UNIBEN student, Igun bronze apprentice, UBTH nurse, police officer, farmer, barber/salon, club DJ) and risky (agbero, Yahoo boy w/ EFCC raid chance).
   **Career ladders (user request):** every official job group is a career track from the lowest rank to the highest, e.g. Tech: Intern → Junior Dev → Mid-level Dev → Senior Dev → Tech Lead → Engineering Manager → CTO. Same for health (Ward Attendant → … → Chief Medical Director), police (Recruit/Constable → … → Commissioner of Police), banking (Teller/Intern → … → MD/CEO), etc. Promotion is dynamic (XP from shifts + performance + requirements like education/days worked), pay rises per level, and all tracks/levels/salaries/promotion rules are data-driven and admin-tunable. Tech industry included (fictional tech hub in Benin).
5. Finance: cash vs bank (bank can't be robbed), PoS fees, esusu groups, loans.
6. Marketplace: NPC shops per market + player-to-player listings with fee.
7. Farming at Iguobazuwa: rent plot, plant, grow timers, harvest, sell; harvest-theft chance.
8. Medical: UBTH/clinics heal; Babalawo sells remedies + "protection" lowering robbery chance by %.
9. Crime/police: NPC robbery = zone risk × time × traffic × cash carried; PvP robbery (same location) with success / caught / CCTV chances; victim reports → arrest / jail / bail; new-player protection + cooldowns; agberos + fictional gangs only.
10. Housing ladder: face-me-I-face-you → mini flat → GRA duplex.
11. Chat per location + DMs, profanity filter, block/report, rate limits.
12. Developer admin panel: every %, price, salary, timer, robbery rate live-editable with instant effect; ban; grant money; economy stats; audit log.
13. Payments: naira packs via Paystack behind a swappable provider interface; server-verified.
14. Airport: Benin Airport location, "fly to Lagos/Abuja — coming soon", federation "passport" spec doc.

Stack: React + TypeScript (Vite), Supabase (Auth email+password, Postgres, Realtime, Edge Functions), free hosting (Vercel/Cloudflare Pages).

## EXAMPLE
- Model Lagos Life's tap-a-place loop + Sims 3 needs/progression, deeper.
- Look: detailed layered illustration, not flat clip-art. Palette: laterite red earth, coral-bead red, bronze/gold, ECTS green. Five-zone lighting, colored shadows.
- Tone: street-smart lifestyle comedy in **Naija Pidgin**. e.g. "Agbero don block road for Uselu — drop ₦200 or find another way." / "Omo, dem don rob you for Sapele Road. You fit report for Police or go UBTH."
- Avoid: graphic violence, real cult names (Black Axe, Eiye), mocking the Oba/palace, bland art.

## CONSTRAINT
- Naija Pidgin English throughout UI copy. No Bini language.
- ₦0/month to start (free tiers). Paystack per-transaction fee only.
- Mobile-first, low-end Android, small first load.
- Server-authoritative economy (all money/state changes in Postgres RPCs). Admin panel admin-only. Payments server-verified. No secrets in git.
- Lifestyle humour, not too dark; 18+ only (confirmed by the user 2026-10-05). Real public landmarks OK; private businesses fictional names.
- Code at `C:\Users\shalo\desktop\benin-life`; pushed to user's GitHub repo once URL provided.
- Done = every system works end-to-end locally + deployable to free hosts.
- Payments: Paystack first; swapping provider must be a config change.
- Art: SVG only for now (Gemini painted backgrounds deferred).
