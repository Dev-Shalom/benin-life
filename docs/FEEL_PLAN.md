# Real-feel plan: places and home should feel like real life, not Roblox (user, 2026-10-06)

The user wants every place you can walk into, home included, to feel like a real Benin club, buka or room. It must stay lightweight enough for low-end phones. This is the critical brainstorm; the step **F1** below builds it.

## Why it looks like Roblox today
1. **Flat colours.** Every surface is one flat colour with no texture, wear or grain.
2. **Flat lighting.** The light is even everywhere: no dark corners, no light pools, no contact shadows.
3. **Too clean.** Everything is perfectly clean and evenly spaced: no clutter, stains, cables or posters.
4. **Toy colours.** Saturated primary colours, the same palette in every place.
5. **Floating diorama.** The room floats on a round plate in a blue void, with no outside world, no windows to look through and no depth.
6. **Static.** Nothing moves except people: no fan, no flicker, no club lights.

## What makes a scene feel real, and the cheap way to do each (no big downloads, mobile-safe)
| Real-life cue | Cheap technique | Cost |
|---|---|---|
| Dark corners and contact shadows | Bake ambient occlusion into **vertex colours** when the room is built (darker near wall/floor seams, under furniture and in corners). Fake round blob shadows under people and furniture. | 0 per frame |
| Surface texture (tiles and grout, wood grain, worn concrete, peeling paint, rusty zinc, carpet, plaster cracks, stains) | **Procedural canvas textures**, generated once in code into one shared ~512 px atlas. No image downloads. Use the same textures in every place, tinted per place. | One-off ~20 ms |
| Mood lighting per place | A **palette and light rig per place type**: club = dark with coloured light pools and emissive LED strips; buka = warm tungsten bulb; bank/hospital = cool fluorescent; market = sun shafts and coloured tarp shade; home LAPO = one yellow bulb and a lantern; Nepo = warm POP downlights. Fake light pools are additive transparent discs and cones, not real shadows. Tone mapping (ACES) and gentle fog for depth. | Low |
| Lived-in clutter, Benin details | Small instanced **clutter kits**: plastic chairs, crates of Star/Gulder/Coke, Gala and Bournvita, a calendar with the Oba, a church/party poster, a wall fan, a prepaid NEPA meter, an extension box, a generator outside, a water dispenser, a kettle, a Ghana-must-go bag, flip-flops at the door, curtains. Placed with seeded randomness so each place is unique. | Low (instanced) |
| A world outside | Replace the floating plate with **ground that continues outside** (street, gutter, neighbouring walls), fading into fog. **Windows** show an outside gradient that follows the time of day (src/lib/daylight.ts). | Low |
| Light colour transitions | The background sky gradient and room light ease with the time of day (S1 smooth day/night). Club light colours cycle slowly. | Low |
| Small motion | A rotating ceiling fan, a flickering fluorescent tube, slowly sweeping club lights (a shader uniform), steam over pots, a few dust motes. All cheap and on demand. | Low |
| Camera feel | A slightly lower, cinematic default angle; a soft vignette and very light film grain as a **CSS overlay** (free on the GPU). | 0 |
| Sound | Per-place ambience from the existing synth: club bass, buka chatter and pots, bank hum, market haggling, generator. | 0 |

## Quality tiers (stay light)
- **Auto-detect** from devicePixelRatio, renderer and frame-time sampling: **Low** gets no fog, no light pools, half the clutter and DPR capped at 1.25. **High** gets everything.
- There is a Settings toggle ("Graphics: Auto / Low / High"), and Lite mode keeps the SVG.
- **Budget:** at most ~70 draw calls and ~25k triangles per interior; one texture atlas; no per-frame allocations.

## Apply everywhere
- **Home:**
  - LAPO face-me-I-face-you: cement floor with stains, peeling paint, louvre windows, an exposed bulb, buckets.
  - Nepo duplex: polished tiles, POP ceiling with downlights, a rug, art.
- **Every place kit:** club, buka, market, bank, hospital, campus, motor park, PoS, police, palace, tech hub, stadium, shrine, street, showroom, hotel, cinema, supermarket.

## Steps
- **F1:** soft launch of the clubs (only 360 Signature open; the others hidden and switchable in admin), plus opening hours editable in admin, plus the real-feel pass (textures, baked AO, light rigs, clutter, outside world, motion, tiers). Do the home and the club first, then all the other kits.

## What F1 built (agent, 2026-10-06; status marker left for the lead)
All of it lives in `src/art/feel/` and is shared by the home (`src/art/home3d/engine/room.ts`, `HomeScene.tsx`) and every
place kit (`src/art/place3d/engine/props.ts`, `PlaceScene.tsx`). It still merges into the same few meshes as before.

| Piece | How | Files |
|---|---|---|
| **Texture atlas** | One procedural canvas (1024 px High / 512 px Low, 4×4 tiles, seeded, seamless), drawn once per session: plain grain, tiles + grout, wood planks, worn concrete with stains and pits, plaster with cracks and peeling, rusty corrugated zinc, carpet, fabric weave, leather, brushed metal, tarp, cement blocks, laterite, asphalt, painted wall, grass. Every part carries `feelUv` (world metres, box-projected by face normal) and `feelTile`; a patched Lambert shader repeats the tile with `fract` + `textureGrad` (no mip seams) and multiplies the vertex colour, so kits keep their palettes ("tinted per place"). The tile comes from `opt.mat`, the builder's current `mat`, or is guessed from the colour (wood / metal / zinc / fabric constants), so old furniture code got textures untouched. | `atlas.ts`, `materials.ts`, `home3d/engine/build.ts` |
| **Baked AO + blob shadows** | Big boxes are subdivided (~0.5–0.65 m); every solid box registers as an occluder; `HomeBuilder.finish()` darkens vertex colours once: contact at the floor, wall/floor seams, corners, and the floor under beds/tables/counters. The Sim already had a blob; the crowd got instanced soft blobs (1 call). | `build.ts`, `PlaceScene.tsx` |
| **Light rig per place type** | `rigs.ts`: ambient (contrast), room tint, lamp colour/intensity by day/night, pool colour + gain by time of day, cycle, flicker, fan, steam, ACES exposure. Club: darker, coloured additive pools + ceiling beams over the party zones, LED strips on the walls and skirting, a slow hue cycle + sweep (shader uniforms). Buka/restaurant/salon: warm tungsten. Bank/hospital/police/campus: cool fluorescent with a tube that catches every ~9 s. Market/park/street: sun patches + coloured tarps on poles (shade). LAPO home: one bare yellow bulb on a wire with its pool. Nepo: POP cornice + four warm downlight pools with soft beams. ACES tone mapping on both canvases (`flat` removed), fog from the time-of-day horizon colour. | `rigs.ts`, `scene.ts`, `kit.ts buildPools` |
| **Clutter kits** | Seeded per place (name hash) and per home layout, along the back/left walls, never on a zone, furniture, door or window: plastic chairs, crates of Star/Coke/Fanta/Gulder/Malt with bottles, coolers, buckets, a calendar (Oba/church picture), posters (party posters in clubs), a wall fan, a prepaid meter with its cable, an extension box with an orange lead, a water dispenser, a Ghana-must-go bag, slippers at the door; LAPO windows are louvres with burglar bars and a faded curtain. | `kit.ts buildClutter`, `room.ts` |
| **A world outside** | No more plate in a void: ground continues 110 m into the fog; in front (camera side, flat only) a kerb, gutters and an asphalt street with faded dashes (and potholes on compound roads); behind/left (never in front) block fences, neighbours' houses with zinc (compound) or tile (estate) roofs, mango/palm trees and a NEPA pole with sagging wires. Windows get a vertical sky gradient that follows the time of day. The welcome-back dollhouse keeps its island (it orbits). | `kit.ts buildOutside`, `room.ts`, `props.ts` |
| **Small motion** | Ceiling fan (own small mesh, spins), fluorescent flicker, club colour sweep, steam puffs over buka pots (one Points call, positions updated in place). Driven from the existing frame loops, so it runs at the idle 20–24 fps, nothing when hidden or paused, none on Low / reduced motion. No per-frame allocations. | `scene.ts` |
| **Camera + overlay** | Lower, more cinematic angle (home elevation 0.78 → 0.66, places 0.82 → 0.68; the fit code reframes). A CSS vignette + very light SVG film grain over the canvas (`.feel-overlay`, darker at night / in clubs, grain off on Low). Not on the welcome-back dollhouse. | `game.css`, both scenes |
| **Per-place sound** | `setSoundPlace()` in the existing synth: club kick + off-beat bass (background music ducks to 25 %), buka chatter + pots, market chatter + seller calls, bank AC/fluorescent hum, a neighbour's generator at night in face-me-I-face-you / hostel homes. Follows the Music setting and mute; nothing before the first tap; suspended when hidden. | `src/lib/sound.ts`, `src/screens/Game.tsx` |
| **Quality tiers** | Settings → **Graphics: Auto / Low / High** (`prefs.graphics`). Auto guesses from memory/cores/DPR, then a synced 5-frame render sample 1.5 s after the first scene can only step down to Low. Low: no fog, no light pools, half the clutter, DPR ≤ 1.25, 512 px atlas, no motion/grain. Dev: `?gfx=low|high`. | `quality.ts`, `SimSheet.tsx` |

### Cost (SwiftShader, `__home.stats()` / `__place.stats()`, phone 390 px unless noted, Graphics High)
| Scene | Before (calls / tris) | After (calls / tris) |
|---|---|---|
| LAPO face-me home | 42 / 11.5k | 45 / 16.1k (Low: 44 / 15.9k) |
| Nepo duplex | 50 / 14.5k | 52 / 23.1k |
| 360 Signature at night (phone / desk) | 48 / 14.0k · 55 / 15.3k | 50 / 21.2k · 57 / 22.5k |
| Mama Ebo | 49 / 12.1k | 53 / 18.3k |
| Oba Market | 47 / 13.3k | 49 / 22.3k |
| Bronze Bank | 49 / 12.0k | 52 / 17.1k |
All under the ~70 calls / ~25k triangles budget. CPU submit time (`bench()`) stays 0.2–0.9 ms. Note: the scene now
fills the whole screen (ground into the fog instead of a plate on a transparent canvas), so a pure software rasterizer
(SwiftShader at DPR 2) is fill-bound: ~118 ms per frame on High vs ~45 ms on Low. Real phone GPUs don't have that
problem, and Auto's frame sample drops such devices to Low automatically.

### Not done / next
- Sun shafts are floor patches, not slanted beams; dust motes skipped.
- Kit-specific clutter for the rarer types (shrine, palace, zoo, stadium...) uses the generic hall/market kits.
- The Auto tier's sample is one synced burst; a longer rolling sample could step back up.

## P1: lighting toned down (2026-10-06, user: "too strong, make it subtle")
Everything is softer, across every place and both homes; each place keeps its mood (club still dark with colour,
buka warm, bank cool), but nothing reads as neon and faces / pills stay readable.
- **Rigs** (`rigs.ts`): light pools ~40–60 % lower (club night 1.25 → 0.55, warm halls 0.95 → 0.36, cool 0.7 → 0.28,
  LAPO bulb 0.8 → 0.36, Nepo downlights 0.85 → 0.38, outdoor sun patches 0.22 → 0.09); lamps a notch lower
  (club 2.6 → 1.6, warm 2.8 → 2.0); more even ambient (club 0.66 → 0.78) and less room tint; exposure 1.5 → 1.35 in clubs.
- **Pools / beams** (`kit.ts`, `build.ts`): wider discs with a squared (soft) falloff, so there is no visible rim;
  club beams 0.22 → 0.08; the back-wall wash halved.
- **Club colour cycle** (`materials.ts`): hue drift 0.35 → 0.14 rad/s, sweep depth 35 % → 14 % and slower, 22 % less
  saturation. In `PlaceScene.tsx`: LED strips / lamp boxes glow at ~65 % (`mats.glow`), screens cycle slower and less
  saturated, the pink club lamp is paler, the club hemisphere a little brighter (faces).
- **Overlay** (`game.css`): vignette 0.28 → 0.14 (dark rooms 0.5 → 0.28) over a wider clear centre; grain 0.07 → 0.04.
- Low tier unchanged in kind (no fog, no pools). Before / after: scratchpad `p1/light-*-before-after.png`.

## VQ extension (2026-10-08)
The shared home/place solid material now uses roughness-aware `MeshStandardMaterial` shading while retaining the procedural atlas, baked AO, merged layers, and graphics tiers. Texture tiles feed a small per-surface roughness range (ceramic, wood, plaster, fabric, metal, and ground), so daylight and room lights shape surfaces across every home and place without adding new meshes or downloads. The city ground, buildings, downtown OSM core, roofs, trees, water, street furniture, and traffic also use roughness-tuned standard materials.

The LAPO room adds a visible surface cable to its bare bulb, and compound exteriors get a compact standby generator. NEPO home windows now have full-length curtains and a rail. This is a shared rendering/detail pass, not a finished photoreal overhaul: scene-by-scene visual review and low-end phone profiling remain release checks.

## P2: place soundtracks, the beat clock and the hype sounds (2026-10-06)
All original and synthesized (no songs, no samples); `src/lib/music.ts` holds the synth, `src/lib/sound.ts` plays it.
- **One scheduler** (100 ms tick, ~0.3 s lookahead, WebAudio-timed) for the place you're in; nothing runs while the
  tab is hidden (the context is suspended and the tick skips). After a stall it skips ahead instead of bursting.
- **Sample bank, not per-note synthesis:** kick, clap, rim, shaker, hats, the log drum (C2), a vocal "ah" chop,
  a Karplus-Strong pluck and a crowd bed are computed once in JS per sample rate; piano stabs and pads are rendered
  once per chord and cached. A hit is one `AudioBufferSourceNode` (+ a gain node only for velocity / a short gate).
  Pitch and slides come from `playbackRate`.
- **Club = amapiano, 113 BPM**, 16th grid with swing: the log drum (pitched, sliding hits on the Fm9 – Bbm9 – Ebmaj9 –
  Dbmaj9 roots), shakers on every 16th, offbeat hats + an open hat, a soft kick on the beat, clap on 2 and 4 with rim
  fills, jazzy electric-piano stabs (7ths / 9ths), a pad, vocal-chop blips. Six sections (16 / 16 / 8 breakdown with a
  low-pass sweep and a rim build / 16 / 16 / 8) and each pass through the arrangement picks other log and stab
  patterns, so it never loops exactly. It replaced the F1 club kick + bass.
- **Other places:** buka = a radio (band-passed) alternating every 24 bars between a highlife guitar pattern (118 BPM)
  and an Afrobeats groove (104 BPM), with a burst of static between songs, over the F1 chatter + pots; market =
  hawker calls (chop syllables with pitch moves) over a bustle bed; stadium = a crowd roar bed, "clap clap, clap-clap-
  clap, o-le!" chants every 10–18 s and random cheers; cinema = a slow low-passed minor pad with a soft boom; hotel
  lounge = ii-V-I jazz keys, a walking bass and brushes (84 BPM, swung); motor park = horns + "Ring road!" conductor
  calls. Bank hum and the generator stay drones. Home: no radio (the background music already plays there).
- **Levels:** each place has a bus level (club 0.12 → a groove peak of ~0.05 after the master), the background music
  ducks to 15 % in places with a soundtrack. Music setting + mute apply; nothing starts before the first tap.
- **Licensed track hook:** `setPlaceTrack(url)` / admin `music.club_track_url` (empty by default) loops an audio file
  in clubs instead of the synth (an `<audio>` element, paused while hidden).
- **Beat clock:** `readBeat()` returns one mutated object `{ bpm, phase, n, pulse, audible, hypeAge }`, read each frame
  by PlaceScene / crowdPose (no allocation). It follows the playing groove (context time minus output latency); with
  audio off or blocked it is a silent clock at 113 BPM, so the visuals still move to the beat.
- **Doremi stinger** (`stingerOn`): a bright detuned-saw do-re-mi-fa-sol-do arpeggio, a noise whoosh sweeping
  300 Hz → 6 kHz and an air-horn-ish swell of three detuned saws (~1.5 s). Plays on the Sound (SFX) bus with each club
  announcement; the groove ducks under it, then the crowd's "ayyy" (`cheerOn`: formant-filtered detuned voices + the
  crowd bed) rises on the music bus. The app-wide ticker gets a soft two-note bell (`softCueOn`).
- **Offline proof:** `renderOffline(kind, secs)` in music.ts renders any track / the stinger to WAV with an
  OfflineAudioContext (dev: `window.__blSound.render`). Club 8 s: RMS 0.159, peak 0.746 (master 0.8); the strongest
  onset period is 0.54 s ≈ 113 BPM.
