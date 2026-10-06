# Ship-today requests (user, 2026-10-06) — do these in order, one agent at a time

Status markers: [todo] / [running] / [done]. Keep this file + HANDOFF STATUS LOG + CLOUD_PROMPT current.

## 0. Starter homes by origin — [running] (see HANDOFF STATUS LOG)
Then push branch → main (it also carries the "full amount under ₦100,000" migration 000900; order 000400 before 000900).

## S1. Quick polish batch — [todo]
1. **Names** (some things are shared by Lagos and Benin — use what Benin people actually use):
   - Phone betting app **EdoBet → "BetNinja"**.
   - **KekeGo → a "Ride" app**: book what you ride — keke, ECTS bus/danfo-style bus, okada (if allowed), drop/cab, own car — with prices/times (reuses the travel quote), like a ride-hailing app.
   - **ChopNow → "Chowdeck"** (real app used in Benin too).
2. **Anti-farming**: set `bank.transfer_min_account_real_minutes` default to **1440** (24 h) via migration (only if still at the old default).
3. **Beta badge** on landing + HUD (small), and **Terms of Service + Privacy Policy pages** (`/terms`, `/privacy`, English, NDPR-aware, 18+, virtual money has no cash value, no withdrawals, data we store, how to delete account, contact email dev.shalom1@gmail.com); link from sign-up checkbox, landing footer, Settings.
4. **Update notice**: detect a new deploy (poll `/version.json` written at build time, or compare build hash every few minutes / on focus) → show a small **phone-style dialog** "There's a new update" + **Refresh** button; refresh keeps everything (state is on the server; keep local prefs).
5. **Live counts (realtime presence)**: "online" count in the HUD increases instantly when someone comes online and decreases when they leave (Supabase Realtime Presence channel, cheap); **people at a place** count updates live too (per-location presence or the existing players_here + realtime). Admin Overview "online now" uses the same source.
6. **Smooth day/night**: no snapping at 6 AM/6 PM. Lighting (map city + home + sky + street lights + windows) eases continuously: dusk darkens gradually (~17:30 → 19:30) and dawn brightens gradually (~05:30 → 07:00), following real Benin time.
7. **Sound**: light ambient in-game music/city ambience (loops, small files or WebAudio-generated, lazy-loaded, respects the mute toggle and Settings sound/music switches, off until first user tap per browser rules) + **click SFX** on buttons/taps + small cues (money in, action done, notification). Keep total audio small (< ~300 KB, or synthesized).

## S2. Welcome-back screen — [todo]
When a player opens the game after being away (new session / long absence), show a "welcome back" screen like Lagos Life:
- their **3D house** with the **Sim inside**, camera **slowly orbiting 360°** around the house;
- the Sim's **face** (portrait) + name, **current money**;
- buttons: **Continue** (enter game), **New life** (start over: new Sim — confirm twice; server RPC that archives/resets the profile safely, keeps the account; admin-tunable whether allowed), **Log out** below.
- Lightweight: reuse the home scene, one canvas, frameloop only while orbiting.

## M1. Sim movement & life — [todo]  (spec in docs/REAL_LIFE_PLAN.md)
Tap the floor to walk there (home + places) with pathing, smooth walk cycle, alive idle (breathing, weight shift, look-around), natural idle after tasks.

## S3. Map upgrade — [todo]
The user finds the map "looking weird". Improve the 3D city's look: clearer roads and road names, better building variety/colours by district, nicer terrain/greenery, readable labels that don't crowd, nicer camera default, landmark models more recognisable, smooth day/night (S1.6). Keep perf budget (draw calls/triangles) from docs/CITY3D.md.

## L2+. Places, crowds, events, landmarks — [todo]
As in docs/REAL_LIFE_PLAN.md. Landmarks (docs/LANDMARKS.md): keep the REAL names the user chose (ShopRite/Benin City Mall, Kada Plaza, Mama Ebo, Protea, Golden Tulip, Ogba Zoo, Ogbe/Samuel Ogbemudia Stadium, Emotan Statue, real clubs) and **mix in local made-up names** so it isn't built only on real brands. Add:
- **Car dealers** (buy cars): real Benin options along Sapele Rd — e.g. Ighodalo Car Deals (Km 5 Sapele Rd), SDD Motors (174 Sapele Rd), Otos Autos (near Santana Market), Dominion Automobile; official Toyota (Mandilas, 45 Benin–Agbor Rd). Pick 1–2 real + a made-up "Tokunbo lot".
- **Top clubs with hype men & big spenders**: 360 Signature (GRA, 1st Ugbor Rd), Club De Medici (23 Benoni off Airport Rd, GRA), Rome Night Club ("biggest in Benin"), Club Vibes (DJ + hype man), Cube Nightlife, Versus Lounge, Havana. Club actions: table/bottle service (VIP prices), "spray money", hype man shout-out (costly, + street cred), dance.

## Sources (car dealers, clubs)
https://ranked.ng/car-dealerships/benin-city · https://www.facebook.com/p/Ighodalo-Car-Deals-100063548294416/ · https://nigerianinformer.com/official-accredited-toyota-dealers-in-nigeria-addresses/ · https://ranked.ng/nightclubs/benin-city · https://blog.naijabased.fun/night-club-in-benin-city · https://www.tripadvisor.com/Attractions-g298361-Activities-c20-t99-Benin_City_Edo_State.html
