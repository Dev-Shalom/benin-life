# Marketing front end (landing, auth, legal, company card, About, FAQ, Partners)

Owner brief: "redesign the frontend pages, more sleek, more interactive, not AI slop, both dark and light mode, with a toggle to transition smoothly". The reference is the approved sponsor page (`public/sponsor/index.html`). Gameplay screens are untouched.

## Where things live
| Piece | File |
|---|---|
| Shared kit: tokens, fonts, nav, buttons, theme toggle, reveal, accordion, footer, theme-change CSS | `public/mk/mk.css` (static pages link it; React imports it through `src/styles/marketing.css`) |
| Behaviour for the static pages (theme toggle, frosted nav, reveal, count-up) | `public/mk/mk.js` |
| React page CSS (landing `lp-`, auth `au-`, legal `lg-`, company `cp-`, error `er-`) | `src/styles/marketing.css` |
| React chrome and hooks | `src/screens/mk/` (`Shell.tsx`, `ThemeToggle.tsx`, `useMk.ts`, `Accordion.tsx`, `Ph.tsx`, `icons.ts`) |
| Pages | `src/screens/Landing.tsx`, `Auth.tsx`, `Legal.tsx`, `CompanyPage.tsx`, `ErrorScreen.tsx`; static `public/about/`, `public/faq/`, `public/sponsor/` |
| Fonts (self-hosted woff2) | `public/fonts/outfit.woff2`, `figtree.woff2` (moved from `public/sponsor/fonts`) |
| Pictures | `public/sponsor/img/*.webp` (real 3D city screenshots), `public/mk/hero-700|1300.webp` (hero crop of the aerial view), `public/art/sim-*.webp` |

Everything is scoped under `.mk` (and `html.mk-page` for the page background), so the game's indigo theme (`docs/THEME.md`) is not affected. Marketing classes carry an `mk-`, `lp-`, `au-`, `lg-`, `cp-` or `er-` prefix. `:where(.mk)` is used for resets so single-class rules win.

## Look
- Type: Outfit for display (600, tracking -0.035em), Figtree for body. Families are registered as `BL Outfit` and `BL Figtree` so they never clash with the game's Google-loaded copies. Fonts are preloaded on marketing URLs only (inline script in `index.html`).
- Colour: graphite and off-white, one accent (Benin bronze). Dark: bg `#0e0f11`, accent `#d9a446`. Light: bg `#f6f5f2`, accent `#94610e` (white label on it is 5.2:1, bronze text on the page is 4.7:1). Tokens: `--bg --bg-2 --surface --line --line-2 --text --text-2 --text-3 --accent --accent-ink --accent-soft --danger --danger-soft --on-media --scrim --shadow`. Hard-coded colours live only in the token blocks.
- Shape: pill buttons, inputs and tabs; 22px cards (`--r-card`); 18px media and accordion items (`--r-media`).
- Layout: asymmetric hero, 4-up number row, pinned scroll story, 5-cell bento (6 columns, no empty cells), two-card band, split list, social band, accordion, centred final call. One eyebrow per three sections at most.
- Icons: Phosphor regular, paths copied from `@phosphor-icons/core` into `icons.ts` and inlined in the static pages. No hand-drawn icons.
- Copy rules: no em dashes, no real parties or brands, numbers only from the sponsor page (6,000+ signed up, 100+ at peak, free). The sponsor page's "ages 16-28" is not repeated on player pages: the game is 18+ (Terms section 1), so the landing says "18+".

## Motion
| What | Spec |
|---|---|
| Easings | `--ease-out cubic-bezier(0.23,1,0.32,1)`, `--ease-io cubic-bezier(0.77,0,0.175,1)`, `--ease-drawer cubic-bezier(0.32,0.72,0,1)` |
| Entrance (`.mk-rise`) | opacity, translateY(18px), blur(6px) to none, 800ms ease-out, 80ms stagger via `--i` |
| Media (`.mk-reveal-media`) | clip-path inset(8%) with 28px radius to full, plus scale 1.04 to 1, 1300 to 1500ms |
| Press | `scale(.97)` on `:active`, 160ms; hover effects only under `(hover: hover) and (pointer: fine)` |
| Story | the step in the middle 10% of the viewport (IntersectionObserver) picks the pinned picture; crossfade 700ms with blur and scale |
| Accordion | button plus `role=region`; `grid-template-rows 0fr to 1fr`, 380ms; closed panel is `inert` and `visibility:hidden` |
| Nav | frosted after the first 8px, a sentinel and IntersectionObserver (no scroll listeners) |
| Reduced motion | reveal and story become 200ms opacity fades, the theme switch is instant, smooth scroll off |

The hero reveals on the next frame after load. Hidden states exist only when JS has added `.mk-js`, so the static pages read without script.

## Theme toggle
- One pill (sun left, moon right, bronze thumb) in every marketing nav. It flips Light and Dark. "Match my phone" stays in the game's Settings (Appearance).
- It writes the game's own preference: `theme` in `localStorage` key `bl.prefs.v1` (static pages merge the key and keep the other prefs). The choice therefore carries between pages and into the game.
- First visit with nothing saved: marketing pages follow the phone (and its live changes). The game still defaults to light, so when a player with no saved choice leaves the marketing pages, the game theme applies (`useMarketingPage` in `useMk.ts`). Picking a theme once saves it everywhere.
- No flash: `index.html` (React pages) and an inline head script (static pages) set `data-theme` before first paint. On marketing URLs `index.html` also adds `html.mk-page`, which paints the graphite or off-white page colour. Keep its path list in sync with `src/lib/marketing.ts`.
- Transition: `document.startViewTransition` with a circular `clip-path` growing from the centre of the button to the farthest corner, 520ms, ease-out (WAAPI on `::view-transition-new(root)`, `html.mk-vt` scopes the pseudo-element CSS). No View Transitions: 250ms colour fade (`html.theme-fade`). Reduced motion: instant. Never runs on page load. Code: `setThemeAnimated` in `src/lib/theme.ts` and `public/mk/mk.js`.
- `theme-color` meta follows the theme (`#0e0f11` / `#f6f5f2` on marketing pages).

## Pages
- **Landing (`/`)**: nav (links, toggle, Log in, Start playing), hero with the real aerial city, number row, pinned story (King's Square, Oba Market, the roads, night), bento (business and careers, family, clubs, elections and court, social), "born into a different life" with the two Sim renders, how it starts, TikTok, four quick answers, final call with the 18+ note, footer (About, FAQ, Partners, TikTok, Terms, Privacy). Sign-up and log-in links are `/auth?mode=signup` and `/auth?mode=signin`. `?src=` and `?ref=` are still captured in `main.tsx`. The LCP image is preloaded (with srcset) by the inline script, sized, and webp. Below-the-fold images are lazy.
- **Auth (`/auth`)**: logic, field names, validation, Supabase calls and messages are unchanged. Picture panel on desktop, form only on phones. Labels above inputs, helper or error text below (`role=alert`), the placeholder is only an example address. Modes: sign up, log in, forgot, reset.
- **Terms and Privacy**: text unchanged. The contents list is built from the `h2` headings in the page, sticky from 960px, current section highlighted by an observer.
- **Company card (`/c/:id`)** and **ErrorScreen**: same chrome and tokens, logic unchanged.
- **About, FAQ, Partners**: static HTML with the kit. Meta, canonical and JSON-LD are unchanged. The FAQ accordion supports `/faq/#q3` deep links.

## Checks
`npx tsc -b`, `npm run build`, `npm run city-check`. Screenshots at 390x844 and 1440x900 in both themes were reviewed for every page. Contrast was audited with a Playwright script that composites text over its background (AA: 4.5:1 normal, 3:1 large).
