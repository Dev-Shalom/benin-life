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
