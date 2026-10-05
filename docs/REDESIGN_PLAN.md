# Phase R: redesign before Phase 2 (approved by the user on 2026-10-05)

The user approved all three:
1. **The whole game goes 3D:** characters, the home, and the city map.
2. **Copy Lagos Life's deeper life systems, with Benin flavour:** traits, dream, skills, feelings, wishes, perks and buy mode.
3. **Do this redesign before Phase 2,** with a playable demo at the end.

## Inputs
| Doc | What it holds |
|---|---|
| `docs/references/lagos-life/*` + `NOTES.md` | The reference screenshots with notes on each screen |
| `docs/FEEDBACK_PHASE1.md` | The user's Phase 1 feedback: moderate Pidgin, an English landing page, "Dad" not "Papa", presets, face shapes, admin controls everything, and the 2nd account forced to Nepo |
| `docs/MAP_GEO.md` | Real Benin geography, which still applies |

We take Lagos Life's style and structure only. **Don't copy its names, logos or assets.** Every brand in the phone and the city is a fictional Benin version.

## Rules for every agent
- **One agent at a time.** The lead verifies each one (build, tests, screenshots), commits and pushes, then starts the next.
- **UI work:** use `.claude/skills/design-taste-frontend` and `.claude/skills/emil-design-eng`.
- **Copy:**
  - English by default. Pidgin only for street moments (agberos, robbery, market banter, the LAPO voice) and kept natural.
  - The landing, auth and settings pages are in English.
  - Nepo babies say "Dad", not "Papa".
- **Admin control:** every gameplay number lives in `game_config` or data tables, so the admin panel (Phase 2) can edit all of it.
- **Low-end Android first:**
  - Lazy-load 3D.
  - Keep draw calls low and use shared materials/instancing.
  - Cap the device pixel ratio at about 1.5.
  - Use a single WebGL canvas per screen.
  - **HUD, chat and lists use cached portrait images, not live canvases.**
- **This PC has about 8 GB of RAM:** render or screenshot one thing at a time, and kill any headless browser you start.

## Agents, in order
| # | Agent | Scope |
|---|---|---|
| R1 | **Look and copy** | Light design system (tokens, UI kit restyle: white floating cards, soft shadows, green primary, pills, emoji icons, clean sans font). **Landing page** (English, complements the game, no LAPO/Nepo numbers). **Login and sign-up** (Lagos Life-style card, plus a "Back" link, 18+ checkbox, password eye, forgot password). **Copy pass**: moderate the Pidgin across `src/lib/pidgin.ts` and the screens; Nepo says "Dad". The current game screen only needs restyling to the new tokens here; the HUD layout changes in R4. |
| R2 | **3D engine and characters** | Add three.js + @react-three/fiber (+ drei), lazy-loaded. Build a low-poly 3D character system: woman/man, body types, **face shapes** (round, oval, square, long, heart), hairstyles incl. gele/braids/locs/low cut/afro, 8 skin tones, outfits with fabrics (Plain, Ankara, Adire, Aso-oke, Bini coral beads), accessories (shades, cap, wristwatch, chain, phone in hand). **Outfit presets** with clear labels (Bini Traditional Wear, Yahoo Boy (no pink; shades + cap + watch + chain), Corporate, UNIBEN Student, Market Woman, Keke Rider, Owambe, Nurse, Police, Streetwear…); each item stays editable after picking a preset. Idle animation. **Drag-to-spin turntable.** A cached portrait renderer for the HUD and lists. Prefer CC0 rigged low-poly base meshes (e.g. Quaternius/Kenney) if they give better quality, and record their licences in `docs/ASSETS.md`; otherwise build them procedurally. New `AvatarConfig` v2 with a migration from v1. |
| R3a | **Creator data (DB)** | Data-driven `traits` (2 per Sim), `dreams`, start-home options (weekly rent, each origin's start cash, availability per origin) and profile columns. Rework the origin roll. Add **admin/dev overrides**: "force next new account's origin" (config) and set origin per account (admin RPC). **Set it so the user's next new account is Nepo.** Rent is due weekly. SQL tests. |
| R3b | **Creator flow (UI)** | 5 steps on the 3D turntable: Look → Personality (pick 2) → Dream → Birth lottery reveal (perks listed, no percentages, "Dad" for Nepo) → Choose where to live (Benin homes: UNIBEN hostel Ugbowo, face-me-I-face-you Aduwawa/Ekenwan, self-contain Uselu, mini-flat GRA; options the origin can't afford are greyed out with a joke). |
| R4 | **3D home, HUD and phone** | Isometric 3D "dollhouse" of the player's home with furniture and the Sim walking. New HUD: top white pill (day+time, mood, online count, mute, ₦ + top-up), wish chips + "Clean screen" on the left, portrait + need bars bottom-left, **bottom dock Home · Buy · Map · Phone**. **Sim sheet** with Profile / Needs (adds **Bladder**) / Goals / Skills / People / Career / Settings tabs (stub the tabs whose systems arrive in Phase 2). **Phone** overlay with a lock-screen clock and an app grid of fictional Benin apps (Jobs, Messages, Bank, Contacts, Ride (keke/drop), Food (Chowdeck-style), Houses, Cars, Health, Invest, Bet, Family, Hustle, Edo Gov, Police, Settings…); apps not built yet show "Coming soon". Keyboard shortcuts on desktop. |
| R5 | **3D Benin city map** | Low-poly 3D city laid out from `docs/MAP_GEO.md`: Ring Road with the museum, the palace west of King's Square, the road bearings, the Ikpoba River, the Ramat Park go-slow, districts. Place labels as white emoji pills. Filter chips (Go-slow, Neighbours, Danger zones, Gov…). "Coming soon" pills (Airport link). Travel overlay. Day/night. |
| R6 | **Demo** | The lead runs a full click-through against local Supabase, fixes issues, then gives the user the demo and waits for their OK. |

**After R:** Phase 2 as in HANDOFF.md, with most systems shipping as phone apps and Sim-sheet tabs:
- Skills, feelings, wishes and perks come with P2-ECON.
- Buy mode and the furniture catalogue come with P2-ECON housing.
- The admin panel must cover every config value and data table, including origin tiers, traits, dreams, homes, furniture prices and timings.
