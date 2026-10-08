# Lagos Life reference screenshots (sent by the user, 2026-10-05)

These are style references only. Don't copy their branding or assets.

| File | Screen | What to take from it |
|---|---|---|
| 01-signup.jpg | Sign up | Light sky-blue gradient background and one white rounded card. Pill tab switch (Create account / Log in). Soft grey filled inputs with a helper text line under each. An "I'm 18+ and agree…" checkbox row. One big green pill CTA. A small reassurance line under it. "← Back to the city" link top-left. Logo and tagline above the card. |
| 02-login.jpg | Log in | Same card. Username-or-email field, password with an eye toggle, "Forgot password?" link, green CTA, "Welcome back" line. Very clean, lots of whitespace. |
| 03-creator-man.jpg | Character creator | **3D low-poly character on a turntable ("Drag to spin")**. Top bar: back, step title "Look" with a 5-step progress bar, shuffle button, green "Next". Bottom sheet with the Sim name field, Body (Woman/Man segmented control), and chip rows for Hairstyle, Outfit and Fabric (Plain/Ankara/Adire/Aso-oke). A sticky "Continue" button. |
| 04-creator-colours.jpg | Creator, scrolled | Round swatch rows for skin tone (7), hair colour, outfit colour and bottoms colour. The selected swatch has a blue ring. |
| 05-creator-woman.jpg | Creator, woman | Female hairstyles (Braids, Afro, Bun, Ponytail, Long, Locs, Low cut, Gele, Classic) and outfits (Casual, Office, Owambe, Site work). |

User's direction: see docs/FEEDBACK_PHASE1.md. More screenshots are coming; the user will add them to this folder through GitHub.

## New home references (uploaded 2026-10-08)

| File | Screen | What to take from it |
|---|---|---|
| `1791390706223.jpg` | Bright premium home | Open-plan cutaway with distinct rooms; believable tile and wall finishes; planted perimeter; pool and loungers; driveway, gates and parked cars; calm daylight and soft contact shadows. The floating HUD is clean and does not obscure the home. |
| `Screenshot_2026-10-08-13-34-39-325_com.twitter.android.jpg` | Purple luxury home | Room-specific props and furniture (pool table, office, kitchen, bath, music room); readable paths between rooms; water edge, garden and vehicle display. Premium assets should be gated by the player's home tier, not added to every starter home. |
| `Screenshot_2026-10-08-13-34-41-616_com.twitter.android.jpg` | Night home | Same home reads clearly at night through warm wall lights and restrained violet accents. Preserve dark detail and navigation contrast; avoid making the whole scene depend on neon. |

These are visual targets, not assets to copy. Keep Benin Life's existing character identity and readable low-poly presentation. The practical target is richer materials, room-specific furnishing, landscaped plots and deliberate day/night lighting while retaining the current single-canvas, low-end-phone rendering path. The screenshots are home references; they do not provide a street/building-footprint dataset for the Benin map.

**First implementation (2026-10-08):** the premium GRA duplex plot now has a compact pool deck, two loungers, planted edges, a lit open carport and parking for one owned vehicle. The vehicle is selected from the player's inventory, so the property does not show a car the player has not bought. This is intentionally limited to the duplex tier; starter homes stay appropriate to their price/origin. Runtime/mobile review is still outstanding.

**Graphics follow-up (2026-10-08):** the shared home/place solid material now uses per-surface roughness with the existing procedural atlas, so lighting reads more physically across LAPO rooms, NEPO homes and place interiors. City buildings, roads/ground, roofs, trees, water and traffic use tuned standard materials. LAPO gains visible bulb wiring and a compound generator; NEPO windows gain full-length curtains. This is a broad renderer/detail improvement, not a complete art replacement; the scenes still need visual review and low-end phone profiling. Keep the OSM credit while the OSM-derived downtown data remains in the game.

**Live screenshot review (2026-10-08):** the user showed a NEPO profile in a Uselu self-contain. The renderer had inferred home finish from housing type alone, so this NEPO home inherited LAPO louvres/plaster/bare-bulb styling. Pass the profile origin into `HomeView`; NEPO rooms should use painted walls, tile finish, curtains and warm downlights even at the self-contain tier, while the housing tier continues to gate pools and other luxury exterior assets.

## Full walkthrough (IMG_2358–IMG_2395, uploaded by the user)
Everything is **3D**: low-poly three.js-style characters, an isometric 3D home, and a 3D city map. The UI is light and clean: white floating cards, soft shadows, green primary buttons, emoji icons, rounded pills.

| File | Screen | Notes |
|---|---|---|
| IMG_2358, 2374 | In-game home | Isometric 3D apartment with furniture and the Sim walking. **Top bar:** one white floating pill with day+time, mood ("Very Happy"), players-online count, mute, and money with a green "+" (top up). **Left:** quest/wish chips ("Eat at Amala Shitta +3✨", "Daily gem hunt") and a "Clean screen" toggle. **Bottom-left:** round avatar portrait plus 6 tiny need bars. **Bottom dock:** Home · Buy · Map · Phone (with a badge). A keyboard-shortcut button sits bottom-right. A system toast appears top-centre. |
| IMG_2364–2365 | Creator: Look | Fabric chips, colour swatches, and a 3D turntable. |
| IMG_2366–2367 | Creator: Personality | Pick 2 traits from emoji cards: Hustler, Foodie, Owambe Spirit, Gym Rat, Smooth Talker, Lazy Bone, Clean Pikin, Night Crawler, Tech Bro/Sis, Musical. Each one changes skill growth or need decay. |
| IMG_2368–2369 | Creator: Dream | A lifetime goal: Oga at the Top (top of any career), Lekki Landlord (net worth ₦1M), Afrobeats Star (Music lvl 10), Everybody's Padi (4 best friends), Yaba Unicorn (startup funded). |
| IMG_2370–2371 | Creator: Birth lottery | A big icon reveal of "LAPO Baby! Self-made hits different." Perk rows: ₦60k LAPO loan with weekly repayment, Hustle skill starts at 2, skills learned 25% faster, start in Mushin/Yaba. "Decided once for your account." **No percentages shown.** |
| IMG_2372–2373 | Creator: Home | Choose where to live. Cards show a district, a description, a tag (Student life / Hard start / Balanced / Big spender), a starting cash amount, and weekly rent (rent is paid every Saturday). Options the origin can't afford are greyed out ("With LAPO money? 😂 Work your way here"). |
| IMG_2375–2376 | Buy mode | 3D home in edit mode. Catalogue tabs: Design/Sleep/Kitchen/Bath/Comfort/Fun/Skills/Light. Furniture cards show grid size, star quality and a ₦ price; prices run from a ₦450 plastic chair to a ₦585k split AC. |
| IMG_2377–2378 | Sim sheet: Profile | Tabs are Profile/Needs/Goals/Skills/People/Career/Settings. Header shows the portrait, name, mood and active feeling. Profile has a 3D turntable, the look editor, and an "Invite people to your house" link. |
| IMG_2379–2380 | Needs | 6 bars (Hunger, Energy, Fun, Social, Hygiene, **Bladder**) with %. **Feelings** (moodlets) are listed with a +score, e.g. "Owner of the Night +55", "Slept Like an Oba +15". Traits are listed at the bottom. |
| IMG_2381 | Skills | Cooking, Charisma, Fitness, Coding, Music, Hustle, Dance, Comedy, Photography. Each runs level 1–10 with segmented bars. |
| IMG_2382–2383 | Goals | A lifetime dream card with progress, an origin card ("LAPO Baby — Loan paid off. Self-made 💪"), Wishes (small quests worth ✨ points, rerollable), and **Perks** bought with ✨ (Iron Belle, Steel Bladder, Power Napper, Good Lawyer: jail 25% shorter, and so on). |
| IMG_2384 | People | Relationships list with role and relationship level (Acquaintance/Stranger) and a bar. |
| IMG_2385 | Career | Track and level ("Tech · Level 1 · Intern"), ₦ per shift, shift hours, a performance bar, the next promotion and what it needs, and a work-days strip (M–F). |
| IMG_2386 | Settings | Sound, music, "Free will" toggle, install-as-app (PWA) card, notifications, recovery email, Log out / Main menu / New life. |
| IMG_2392 | City map | 3D low-poly city with districts. Place labels are white pills with emoji. Filter chips: Serious go-slow · Billboards · Neighbours · Sea · Gov. "Coming soon" yellow pills for Airport and Refinery. Billboards show real ads (a monetisation idea). |
| IMG_2393–2394 | Phone | A phone mock-up overlay with a lock-screen clock and an app grid: Jobs, Messages, Meetumo (dating), Salary Index, PopOut Tickets, Games, Nollywood, Bet Tips, Contacts, Ride, Chowdeck (food), Bank, Boutique, Forbes (rich list), Houses, Cars, Invite, Health, Invest, LagosBet, Family, Hustle, Lagos Gov, Police, My Ads, Settings. **The phone is the hub for most systems.** |
| IMG_2395 | Keyboard shortcuts | M map, H home, B buy, P phone, S needs/skills, T things to do, 1–9 spots, E people, arrows/R/Enter/Del in buy mode, Esc, ?. |

## Live places walkthrough (IMG_2398–IMG_2421, uploaded 2026-10-05 night)
**The clock is real time** (device 22:07 = in-game "Mon 5 · 10:07 PM"). Activities are still SHORT in real seconds (5–17 s cards).

| File | Screen | What to take from it |
|---|---|---|
| 2398–2399 | New Afrika Shrine (club interior) | Opening a place puts you INSIDE a 3D low-poly interior (stage, speakers, dance floor, tables, signage, wall art). NPCs stand around with white name pills (Femi, Tobi). Bottom place card: emoji + place name · district, a rotating live "mood line" ("The horns section is on fire", "The drummer hasn't stopped for an hour"), share / map / home buttons, a chat input "Say something out loud…" with send, and **zone chips** (Dance floor, Band stage, Tables, Fela wall, People 7). Tapping a zone shows **action cards**: emoji, duration (14 s), price (₦3,000) or Free, effect chips (+Fun +Social). A "VIP prices for your table (×10)" strip. |
| 2400–2401 | i-Fitness gym | Zones Weights / Treadmills / Yoga studio / Smoothie bar / Showers; cards "Lift Weights 11 s ₦4,000 +Fitness −Energy", "Session with a Coach ₦10,000 +Social +Fitness". NPCs use the equipment. |
| 2402–2403, 2414 | CcHub (tech hub) | Zones Hot desks / Event stage / Coffee bar / Beanbag corner / People 6. Cards: "Hack on Side Project 17 s Free +Fun +Coding", "Free Wi-Fi & Chill", **"Freelance Gig — Queued · Earns ₦"**, "Hack an ATM — Risky". Left rail shows the **running/queued action with a ring and "tap to cancel"**. A dark **event banner** at the top: "A foreign investor is coming · ₦10m · in 2 days". With more players present, **real players appear as blue "@username" pills with a green online dot** above their 3D character; the chat input becomes "Say something to the 6 players here…". |
| 2404 | Phone | App grid continues (Chowdeck, Bank, Boutique, Forbes, Houses, Cars, Invite, Health, Invest, LagosBet, Family, Staff, Hustle, Lagos Gist, Lagos Gov, Police, My Ads, Settings). Toast: "Landing page shipped… +₦6,800 from Freelance Gig (₦1,700 tax)" — gigs pay with tax. |
| 2405–2410 | Sim sheet | Goals (lifetime dream progress, origin card "LAPO Baby — Loan paid off", Wishes with ✨ and reroll), Perks (Iron Belle, Steel Bladder, Early Bird, Never Dull, Sweet Mouth, Hustle Juice, Connected, Fast Learner, Clean Freak, Social Butterfly, Power Napper, Good Lawyer…), Skills levels 1–10 (Cooking, Charisma, Fitness, Coding, Music, Hustle, Dance, Comedy…). |
| 2411–2413 | Top up wallet | Packs: ₦50k game money for ₦1,000 (Jollof pack), ₦300k for ₦5,000 (Owambe), ₦700k for ₦10,000 (Big boy · best value), ₦1.6m for ₦20,000 (Odogwu); Naira / USD toggle; "card, bank transfer or USSD". |
| 2415–2417 | Map → stadium sheet | Place sheet over the blurred 3D map: description ("A local match every afternoon… concerts on Friday and Saturday nights"), "Share a link to …", **activity chips** (Regular Ticket, VIP Ticket, Executive Box, Lead the Chant, Concert tickets, Stadium Tour, Buy a Jersey, Suya & Malt at the Gate, Five-a-side…), **"On today"** card with a LIVE match (score, minute, Regular ₦20k / VIP ₦200k / Box ₦2.5m), then **travel mode cards** (Trek Free, Keke ₦1,500, Danfo ₦1,500, Okada ₦2,000, Cab ₦4,500, premium ride) and a big "Go · ₦…" button. |
| 2418 | Stadium interior at night | 3D stadium with pitch, stands full of NPC fans, floodlights, scoreboard "55' Kano Pillars 0–0 Inter"; a LIVE banner with "What's on & tickets". Zones Popular Stand / VIP Stand / Executive Box / The pitch / Tickets & fan shop. |
| 2419–2421 | Balogun Market at night | Market stalls interior; many real players (@names); "Loading Lagos… 51%" progress pill while the place streams in; **"People 3313"** — the count is huge but only a handful of characters are rendered (cap). Zones Foodstuff stall / Alhaji's fabrics / Wholesale depot / Loading bay / Iya Agbo; cards "Buy Foodstuff — Choose ›", "Gala & LaCasera 5 s ₦1,500 +Hunger +Fun", "Pickpocket a Trader 5 s Risky". |
