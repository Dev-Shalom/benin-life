# Assets and licences

Benin Life ships no third-party art files. Everything visual is made in this repo.

| What | Where | Source and licence |
|---|---|---|
| 3D characters (bodies, heads, faces, hair, headwear, clothes, accessories) | `src/art/avatar3d/engine/` | **Procedural.** Built in code from lofted rings, ellipsoids and tubes at runtime. No third-party meshes, rigs or animations (no Quaternius/Kenney/Mixamo files). Project code. |
| Fabric patterns (Ankara, Adire, Aso-oke, lace, denim), coral beads, embroidery, T-shirt graphic | `src/art/avatar3d/engine/materials.ts` | **Procedural.** Drawn on a `<canvas>` at runtime. No image files. Project code. |
| Landing-page Sims | `public/art/sim-lapo.webp`, `public/art/sim-nepo.webp` | Rendered from our own 3D characters (`LANDING_SIMS` in `src/art/avatar3d/dev/AvatarLab.tsx`, "Landing images" section of `/dev/avatars`). Project art. |
| Location scenes, icons, logo, favicon | `src/art/`, `public/favicon.svg` | Hand-written SVG in this repo. Project art. |
| Fonts: Outfit, Figtree | Loaded from Google Fonts (`index.html`) | SIL Open Font License 1.1. |

## Libraries used for 3D
| Package | Licence |
|---|---|
| three | MIT |
| @react-three/fiber | MIT |
| @react-three/drei (installed, not yet imported) | MIT |

If you add a third-party model, texture, sound or font, add a row here with its source URL and licence before you commit it. Only CC0, CC-BY (with credit shown in-game) or MIT-style licences.
