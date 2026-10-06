# 3D avatars

The characters are built in code (low-poly, flat-shaded, no model files). Code lives in `src/art/avatar3d/`.

| File | Job |
|---|---|
| `index.ts` | Public API. Importing it does **not** load three.js. |
| `catalog.ts` | Option lists, outfit presets, `defaultAvatar`, `randomAvatar`, `normalizeAvatar`, `migrateAvatar`, `avatarKey`, `MODEL_VERSION`. No three.js. |
| `AvatarStage.tsx` → `engine/Stage.tsx` | Live drag-to-spin turntable (react-three-fiber). Lazy-loaded. **One per screen.** |
| `AvatarPortrait.tsx` → `engine/portrait.ts` | Cached still images for the HUD, chat, lists and cards. |
| `engine/character.ts` | Puts a whole character together from a config. |
| `engine/body.ts`, `head.ts`, `hair.ts`, `clothing.ts`, `accessories.ts` | The parts. |
| `engine/materials.ts` | Canvas-drawn fabric textures and the shared material cache. |
| `engine/anim.ts` | Idle (breathing, weight shift, head turns) and walk poses; M1 `poseLife` / `poseGait` / pose buffers for the 3D home (see below). |
| `dev/AvatarLab.tsx` | Dev gallery at `/dev/avatars` (dev server only). Show one section with `?s=presets|pviews|views|bodies|faces|features|hair|hats|acc|fabrics|portraits|landing|stats`. Extra params: `&g=male|female`, `&size=150`, `&yaw=1.57`. `stats` lists triangles and meshes per look. |

`/dev/create` (dev server only) mounts the creator without a session, for screenshots.

## Config format (`AvatarConfigV2`, `src/lib/types.ts`)
```jsonc
{
  "v": 2, "gender": "male", "body": "average", "skin": "tone4",
  "face": "oval",            // round | oval | square | long | heart | diamond
  "eyes": "almond", "brows": "soft", "nose": "broad", "lips": "medium", "mouth": "smile",
  "facialHair": "none", "hair": "low_cut", "hairColor": "#15100d",
  "hat": "cap",              // 'none' allowed
  "top":    { "s": "graphic_tee", "f": "plain", "c": "#25232b" },   // style, fabric, colour
  "bottom": { "s": "jeans", "f": "plain", "c": "#25232b" },
  "shoes":  { "s": "sneakers", "c": "#f4f1ea" },
  "accent": "#e0a526",       // headwear, tie, prints, embroidery, bags
  "accessories": ["shades", "watch", "chain", "bracelet", "phone"],
  "preset": "yahoo"          // last preset applied; a label only
}
```
- The server stores it as opaque jsonb. `create_profile` and `update_avatar` reject anything over 4000 characters. A v2 config is about 410–500 characters.
- `gender` must stay a top-level key, because `update_avatar` reads it.
- **Reading:** always go through `migrateAvatar(raw)`. It takes a v1 (2D) look, a v2 look, `{}`, `null` or junk and returns a valid v2 look. It never throws.
  - `state/game.ts` and `LocationSheet` already call it.
  - `AvatarPortrait` and `buildCharacter` call it again as a safety net.
  - For v1 looks, the old outfit becomes the matching preset and old pink drip becomes the black-and-gold Yahoo look. Skin, body, hair, colours and accessories are kept.

## Outfit presets
`OUTFIT_PRESETS` in `catalog.ts`. Each preset sets top, bottom, shoes, headwear, accent and accessories. Face, body and hair are kept. Every slot stays editable afterwards, and the creator shows "Edited" when the look no longer matches the preset.

Men get 12 presets: Bini Traditional Wear, Agbada, Senator, Owambe (Aso-oke), Yahoo Boy, Corporate, UNIBEN Student, Keke Rider, Nurse, Police, Streetwear and Casual Ankara.

Women get 12 presets: Bini Traditional Wear, Owambe, Boubou Kaftan, Big Girl Glam, Corporate, UNIBEN Student, Market Woman, Keke Rider, Nurse, Police, Streetwear and Casual Ankara.

The Yahoo Boy look is a black designer tee and black jeans, with a gold cap and gold print, white sneakers, shades, a gold chain, watch, bracelet and a phone. It has no pink.

## Portrait cache
- `engine/portrait.ts` holds **one** offscreen `WebGLRenderer` for the whole app.
  - Jobs run one at a time, and the renderer yields to the browser between them.
  - Each job returns a webp data URL (png if webp is not supported).
  - After 12 s idle the renderer is released.
  - If the context is lost, the job throws and is not cached, and the next job makes a fresh renderer.
- `AvatarPortrait.tsx` handles caching and when to render:
  - The cache key is `avatarKey(config)` (a hash that includes `MODEL_VERSION`), plus the view, a pixel size bucket and the yaw.
  - Images are kept in a memory LRU (240 entries) and in sessionStorage (newest 80, `bl.av2.*`).
  - A tile asks for its image only when it comes within about 400 px of the viewport.
  - A failed render is retried after 4 s, then after 8 s. While waiting, the tile shows a placeholder silhouette in the Sim's skin tone.
- **Never** put a live canvas in the HUD, chat or lists. Use `<AvatarPortrait>`, or `getAvatarImage()` outside React.
- **Bump `MODEL_VERSION`** whenever the model's look changes, so cached images re-render.

## Performance budget (low-end Android)
- three.js (≈188 kB gzip) and react-three-fiber (≈54 kB gzip) are separate lazy vendor chunks (`vite.config.ts`). The character code is ≈24 kB gzip. None of this is in the index chunk.
  - A portrait-only screen loads three + character + portrait.
  - A turntable also loads r3f.
- The turntable runs with `frameloop="demand"`. It redraws at about 30 fps while idle, every frame while spinning, and not at all when off-screen or in a hidden tab. DPR is capped at 1.5. There are no shadow maps; the shadow is a blob texture.
- Materials and textures are shared and cached by colour. Geometry is merged per bone and material.
- A look is 8k–16k triangles in 33–50 meshes. Box braids are the most expensive hair at about 6.5k triangles.

## Adding things
**A hairstyle**
1. Add `{ id, label, gender? }` to `AVATAR_OPTIONS.hair` in `catalog.ts`.
2. Add a `case` in `buildHair` (`engine/hair.ts`). Build it from `h.shell(...)` (a layer on the scalp), `volume(...)` (puffy shapes), `tube(...)` (braids and locs) or `cap(...)`. Push the geometry into `R.hair`.
3. For long hair, set `R.long = true`.
4. If a v1 id maps to it, add it to `V1_HAIR`.

**An outfit piece**
1. Add the style id to `AVATAR_OPTIONS.top` or `.bottom`.
2. Add a `case` in `buildTop` or the bottoms builder in `engine/clothing.ts`. Use `loft(rings)` around the torso or limbs, with `c.m.top` or `c.m.bottom` so the fabric and colour pickers work.
3. If it covers the legs, add it to `FULL_LENGTH_TOPS`.

**A preset**
- Add an entry to `OUTFIT_PRESETS`. Use colours from `OUTFIT_COLOURS` where you can, so the swatches show as selected.

**An accessory**
- Add it to `AVATAR_OPTIONS.accessories` and build it in `engine/accessories.ts`.

**After any change**
1. Check `/dev/avatars` (`?s=pviews` for front, side and back).
2. Bump `MODEL_VERSION`.
3. Update the landing webps if the landing looks changed.

## M1 rig animation (Sim movement & life, 2026-10-06)
All procedural, in `engine/anim.ts`, no animation files. `poseIdle` / `poseWalk` above are unchanged (turntable + cached portraits use them, so `MODEL_VERSION` did not change).
- **`resetRig(c)`**: every bone back to the bind pose (computed from `bonePositions(dims)`, cached per character) then `restPose`. Every M1 pose starts with it, so nothing leaks from the last pose (a bent knee from the walk, a raised arm from a fidget).
- **`poseLife(c, t, salt, { tired, happy, reduced, idleFor })`** the home idle: breathing every ~4 s (chest lifts and tips back, shoulders out, slower when tired); weight shifts that hold on one leg 4-9 s and ease over 1.1 s (hips slide and roll over the standing leg, the free knee softens, thighs counter-rotate so the feet stay planted); look-arounds (smaller with long hair); a fidget in ~3 of 4 9.5 s slots (scratch head, check left hand, shoulder roll, hands on hips, foot tap; 1.6-2.4 s, eased in/out); mood: `tired` slumps chest/neck/head and pulls the arms in, `happy` lifts the chest with a small bounce. `reduced` (prefers-reduced-motion) = 45 % amplitudes and no fidgets. `idleFor` fades fidgets and look-arounds in over ~1.5 s after a walk. A pure function of time: any number of Sims can share one clock.
- **`poseGait(c, phase, w, opts)`** walk cycle driven by a phase in cycles (1 cycle = 2 steps) that the scene advances by `distance / (2 · stepLength(c, w))`, so the feet keep pace with the ground at any speed. Legs and arms swing in opposition; the swing knee bends (`cos` phase), soles stay flat through the stance (foot counter-rotates the leg); the hips drop by the standing leg's angle (inverted pendulum: lowest at double support), sway over the standing leg and the swing hip drops a touch; chest counter-twists; head steadied. `w` (0..1 gait weight) shortens and softens the steps while speeding up/slowing down. `stride` (wrappers, robes) scales the swing; `cruiseSpeed(c)` = ~2.25 steps/s but at least 0.72 m/s (short steps get a quicker cadence instead of sliding).
- **Pose buffers**: `capturePose` / `applyPose` / `mixPose` (16 bones × position + rotation = 96 floats, angles mixed the short way). The home mixes idle↔walk by the gait weight and blends 0.42 s between states.
- **Blinks**: not done. The eyes are merged into the head mesh per material, so a blink would need a separate lid mesh per character; at the home's zoom the eyes are 1-2 px. Revisit with close-up cameras (L2).
