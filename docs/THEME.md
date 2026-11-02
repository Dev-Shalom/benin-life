# Light / Dark theme

Owner request: "I don't want the black background / dark mode forced on everyone. Put the light UI back. Players should switch dark mode themselves in their settings. Anything white turns dark and anything dark turns white, all text and images switch to the right colour, and it must not pop: a smooth transition."

Light is the default. Dark is the dark indigo look from the UI pass (`docs/UI_PASS.md`), now applied everywhere (HUD, sheets, pop-ups, phone apps, landing and auth pages) instead of only on the overlays. Game logic, the database and the 3D scenes are untouched.

## How the switch works
| Piece | File | What it does |
|---|---|---|
| Choice | `src/lib/prefs.ts` | `theme: 'light' \| 'dark' \| 'system'` in the `bl.prefs.v1` localStorage entry. Default `light`. |
| UI | `src/screens/game/SimSheet.tsx` (Sim sheet, Settings, "Appearance") | Three segmented buttons: Light, Dark, Match my phone. |
| Before first paint | inline `<script>` in `index.html` | Reads `bl.prefs.v1`, resolves `system` with `prefers-color-scheme`, sets `<html data-theme="light\|dark">`, the `theme-color` meta (browser bar) and `color-scheme` meta. No flash of the wrong theme on load. |
| Live | `src/lib/theme.ts` (`initTheme()` from `main.tsx`) | Subscribes to prefs (and, for "Match my phone", to the OS setting) and re-applies the theme. Keeps `<meta name="theme-color">` in step. |
| Smooth fade | `src/styles/tokens.css` (`html.theme-fade`) | While the player flips the theme, `theme.ts` adds `theme-fade` to `<html>` for 320 ms. It transitions `background-color`, `color`, `border-color`, `fill`, `stroke`, `box-shadow` and `outline-color` over 250 ms. The class is removed afterwards, so normal interactions are not slowed by a global transition. With `prefers-reduced-motion: reduce` the class is not added and the CSS also forces `transition: none`. Never added on page load. |

The game used to set `data-theme="night"` for the sky. That is now `data-daypart="day\|night"` (set by `setDaypart()` in `theme.ts`, used by Game and WelcomeBack). In the light theme night only deepens the page backdrop and the browser bar, as before.

## Tokens (`src/styles/tokens.css`)
Every colour on a themed surface is a CSS variable on `:root`. Light values are the defaults; `:root[data-theme='dark']` re-points them. Brand accents (green fills, gold, bronze, coral, the 3D art) keep their values in both themes.

| Token | Light | Dark | Use |
|---|---|---|---|
| `--bg`, `--bg-2` | `#eef4fa`, `#e3edf6` | `#0f1130`, `#171a3d` | Page behind everything |
| `--surface` | `#fff` | `#171a3d` | Cards, sheets, modals, phone cards |
| `--surface-2`, `--surface-3` | `#f2f4f7`, `#e6eaf0` | `#212551`, `#2c316a` | Inputs, rows in cards, tracks, chips |
| `--phone-bg` | `#f4f6f9` | `#0f1130` | Phone app interior (cards sit on it) |
| `--text` (`--ink`), `--text-2`, `--muted` | `#131a24`, `#435064`, `#5f6b7d` | `#f4f5ff`, `#cfd2f0`, `#a9aed6` | Text. `--border` = `--line`, `--text-muted` = `--muted` |
| `--line`, `--line-strong` | navy 8% / 16% | white 12% / 24% | Borders and rings |
| `--glass`, `--glass-strong` | white 94% / white | indigo 95% / `#171a3d` | Floating chrome (pill, rail, dock, place card) |
| `--scrim`, `--scrim-strong`, `--overlay` | navy 36% / 55% | near-black 62% / 72% | Behind sheets and modals |
| `--e1..e3`, `--shadow` | cool navy shadows | black shadows | Elevation |
| `--c-green`, `--c-red`, `--c-amber`, `--c-blue`, `--c-violet`, `--c-gold` | dark, saturated | light tints | Coloured TEXT and icons on a surface (money gains, warnings, links) |
| `--green-50/100`, `--amber-50/100`, `--red-50`, `--blue-50`, `--primary-soft` | pale fills | 16 to 28% alpha tints | Soft state backgrounds |
| `--tint-amber/red/green/blue/violet` | pale fills | alpha tints | Pale cards generated from the old hard-coded fills; text on them uses `--c-*` |
| `--ink-solid` + `--on-fill` | `#131a24` + white | `#3a4180` + white | A dark FILL with white text (selected chip, tooltip) |
| `--sel-bg` / `--sel-text`, `--pill-on` | ink / white; white | white / ink; `#3a4180` | Selected tab or dock item; selected segment |
| `--input-bg`, `--placeholder`, `--skeleton`, `--knob` | | | Forms and loaders |
| `--green-500/600/700`, `--grad-primary` | brand greens | same | Fills behind white labels. `--green-500` is `#0e874e` (white on it is 4.6:1) |
| `--ov-*` (`overlay.css`) | aliases of the tokens above | | Overlay shape (`--ov-radius`, `--ov-gap`, `--ov-pad`) and colour aliases |

Rules of thumb:
- Text colour: `var(--text)`, `var(--text-2)`, `var(--muted)`, or `var(--c-green|red|amber|blue|violet|gold)` for coloured text. Never `color: var(--green-700)` (it is dark green: unreadable in dark).
- Fills: `var(--surface)`, `--surface-2`, `--surface-3`, `--tint-*`, `--glass`. A fill that must stay dark with white text is `var(--ink-solid)`.
- Borders and rings: `var(--line)` or `var(--line-strong)`.
- White on a coloured brand fill (`background: var(--green-600); color: #fff`) is fine in both themes; keep it, and keep it at 4.5:1 or better.
- Gold gradients with dark text (`#3a2600` on gold) stay literal in both themes: they are brand art, not a themed surface.
- Logos: the inline `<Logo>` follows `currentColor` for the wordmark ink and `--logo-accent` for the coral, so it flips with the theme. Use `tone="light"` or `"dark"` only when the logo sits on a fixed background.

## Adding a themed component
1. Style it only with the tokens above (spacing, radius and layout are yours; colours are variables).
2. If it needs a palette of its own, define the local variables as aliases of the global tokens, like `.phone-app--court { --ct-card: var(--surface); --ct-ink: var(--text); ... }` and `.msgs { --m-fill: var(--surface-2); ... }`. Do not put hex values in them.
3. If a colour has no token, add one to the `:root` block in `tokens.css` and its dark value in the `:root[data-theme='dark']` block. Do not write `@media (prefers-color-scheme: dark)` in components.
4. Inline styles and SVG: use `style={{ stroke: 'var(--line)' }}` rather than a hex. Illustrations (the 3D scenes, SVG art, coins, tier badges, emoji-on-colour app icons) keep their own colours.
5. Check both themes: `?theme` is not a URL flag; flip it in Settings, or run `localStorage.setItem('bl.prefs.v1', JSON.stringify({theme:'dark'}))` and reload.

## What stays the same in both themes
- The 3D scenes and the map. The white place labels on the map (`city3d.css`) stay white because the scene behind them does not change.
- The Yahoo app and its cash-out sheet: a deliberately dark "laptop screen" look (`YahooApp.css`).
- Emoji-on-colour phone app icons, avatars, the logo tile, brand gradients (gold, coral, green).
- Admin pages: they keep their own light look (`src/admin/admin.css`).

## Contrast check
`scratchpad` script `audit.mjs` (Playwright, 390x844) walks every visible text node on landing, sign-in, home with the Today list, the Sim sheet (7 tabs), the Alerts, Buy, Shortcuts and Look overlays, a pop-up, the phone home and 28 phone apps with their tabs, in both themes. It composites each element's text colour over the stacked backgrounds (worst gradient stop) and fails normal text under 4.5:1 and large text (24px, or 18.7px bold) under 3:1. Results are in `docs/UI_PASS.md` under "Theme pass".
