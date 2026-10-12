# Benin Life brand

## The logo
Two royal swords of the Benin Kingdom stand on either side of a coral bead:

- **Ada (left): authority.** The Oba's state sword. A chief carries it upright before the Oba as a sign of his right to rule. The blade is drawn long and slightly curved, widening toward a broad, rounded, blunt tip. It has a small guard, an ivory grip wrapped in coral bands and a round coral pommel.
- **Eben (right): celebration.** The ceremonial sword that chiefs raise, spin and throw up in the air to honour the Oba at the **Ugie** festivals. The blade is drawn as a broad leaf or fan shape with a central spine. It is pierced with circles and lozenges (openwork). It has a short ivory grip and the eben's ring handle at the base.
- **Coral bead and strand: the palace.** Coral beads are the Oba's regalia. The large bead sits between the swords, and a strand of beads hangs from hilt to hilt.

Together the mark says what the game is about: a life in Benin City between hard work and authority (Ada) and celebration and community (Eben).

The mark is an original, simplified drawing. It is not a copy of any palace emblem, state crest or museum object. Keep it respectful: the swords always stand tip-up, and they are never shown in a fight, broken, upside down or used as a joke.

## Colours
| Token | Hex | Use |
|---|---|---|
| Bronze | `#C8922E` (highlight `#F4D58A`, shadow `#7E5016`) | Sword blades, rules |
| Coral | `#C0392B` (highlight `#F07A62`, shadow `#7E1E14`) | Bead, pommel, ring, "Life" on light backgrounds |
| Coral (on dark) | `#E8664F` | "Life" on dark backgrounds |
| Warm black | `#1E1410` | Icon tile, wordmark on light backgrounds |
| Ivory | `#F7EBD3` | Grips, wordmark on dark backgrounds |

The wordmark is Outfit ExtraBold (800); "LIFE" in the stacked logo is Outfit Bold (700) with wide tracking. In the files the wordmark is converted to paths, so it never depends on font loading.

## Variants
| Variant | When to use |
|---|---|
| **Full** (horizontal: Ada · Benin Life · Eben) | Headers, footers, settings, share image |
| **Stacked** (emblem over Benin / LIFE) | Sign-in, splash-style hero spots, square spaces |
| **Mark** (emblem on a warm-black tile) | App icon, favicon, avatars, the admin header, small UI spots |
| **Mark, simplified** | 40 px and below, used automatically by `<Logo>`. It has a bigger bead, three lozenge perforations and no strand, so it reads at 16 px |
| **Mono** | One colour (stamps, embossing, notification badge). Use `logo-mark-mono*.svg` or `logo-full-mono.svg` |

## Clear space and minimum size
- **Clear space:** leave space on every side at least the width of the coral bead (about 1/6 of the mark's height). In the full logo, that is about the height of the "e" in "Benin".
- **Minimum size:** the full logo at 28 px tall, the stacked logo at 96 px tall, and the mark at 14 px (the simplified drawing kicks in below 40 px).

## Do
- Use the tile mark on busy or photographic backgrounds.
- On light backgrounds use ink + coral for the wordmark (`tone="light"`, or let it follow `currentColor`). On dark backgrounds use ivory + light coral (`tone="dark"`).
- Use the mono mark wherever only one colour is possible.

## Don't
- Swap the swords' sides (the Ada is always left and the Eben always right), tilt them more than shown or cross them into a fighting X.
- Recolour the blades anything other than bronze (or the single mono colour).
- Stretch, outline, add drop-shadows to the wordmark, or set "Benin Life" in another font next to the swords.
- Put the full-colour logo without a tile on mid-tone backgrounds where bronze loses contrast.
- Turn it into a coat of arms (adding shields, crowns or supporters): it is a game brand, not an official emblem.

## Files
Source of truth: `scripts/brand/geom.py` (sword geometry), `scripts/brand/textpath.py` (wordmark outlines) and `scripts/brand/build_brand.py` (layouts). To rebuild:

```bash
pip install fonttools
(mkdir -p scripts/brand/.fonts && cd scripts/brand/.fonts && npm pack @fontsource/outfit@5 && tar xzf fontsource-outfit-*.tgz)
python3 scripts/brand/build_brand.py     # SVGs + src/ui/logoArt.ts
node scripts/brand/render.mjs            # PNGs + favicon.ico (playwright + ImageMagick)
```

| File | What |
|---|---|
| `public/brand/logo-full.svg`, `logo-full-on-dark.svg`, `logo-full-mono.svg` | Horizontal logo |
| `public/brand/logo-stacked.svg`, `logo-stacked-on-dark.svg` | Stacked logo |
| `public/brand/logo-mark.svg` | Icon on tile (detailed) |
| `public/brand/logo-mark-small.svg` | Icon on tile (simplified, for small sizes) |
| `public/brand/logo-mark-plain.svg` | Icon without tile |
| `public/brand/logo-mark-mono.svg`, `logo-mark-mono-white.svg` | Single colour |
| `public/brand/icon-maskable.svg`, `icon-apple.svg`, `og-image.svg` | Sources for the PNG icons and share image |
| `public/favicon.svg`, `public/favicon.ico` (16/32/48) | Favicon (simplified mark) |
| `public/apple-touch-icon.png` (180) | iOS home screen |
| `public/icon-192.png`, `icon-512.png`, `icon-maskable-512.png` | PWA manifest icons (the maskable one is full-bleed, with the emblem inside the 80% safe zone) |
| `public/badge-96.png` | Web-push badge (white silhouette) used by `public/sw.js` |
| `public/og-image.png` (1200x630) | Open Graph / Twitter share image |
| `src/ui/Logo.tsx` | `<Logo variant="full" \| "stacked" \| "mark" size tile tone title />`, inline SVG |
| `src/ui/logoArt.ts` | Generated inline SVG bodies (do not edit by hand) |

## Where the logo appears in the app
- Landing page: full logo in the header and footer, and the mark on the final call-to-action card.
- Sign-in / sign-up: the stacked logo as the page heading, with the 18+ badge under it.
- Loading / splash screen: the mark inside a pulsing ring of coral beads.
- Error screen: the full logo.
- Setup screen: the mark.
- Terms and Privacy pages: the mark in the page header.
- In game:
  - The HUD Beta badge (shown when the HUD rail is open) has a tiny mark.
  - Settings shows the full logo above the 18+ note.
  - A receipt from Benin Life itself (one with no named seller) shows the mark.
- Admin: the mark replaces the old crown tile, in both the sidebar and the mobile top bar.
- Browser and devices: favicon, apple-touch-icon, PWA icons, admin push notification icon and badge, and the share image (`og:image` / `twitter:image`).
