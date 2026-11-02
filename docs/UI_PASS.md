# UI pass: spacing, overflow and one clean look

Owner request: "Check out the UI of Benin Life and make it easy for players to have a good UI experience. Look at everything. Some texts are overflowing, some views look so tight. I need spacing everywhere." Follow-up: match the cleanliness of a competitor's screens (without copying brand, names or layouts).

This was a polish pass. Game logic, RPCs, the database, text, the brand and the 3D scenes are untouched. All changes are CSS plus two small UI-only bits in `AdminApp.tsx`.

## Where the changes live
| File | What |
|---|---|
| `src/styles/polish.css` | Shared comfort rules loaded after every stylesheet (selectors start with `:root` so lazy chunks cannot beat them): tap targets 40px, labels 12px, phone frame width, top pill fit at 360, sheet/modal padding and safe areas, chip rows scroll inside their own row, text wrapping, the fixes listed below. The tap and font lists are generated from the audit. |
| `src/styles/overlay.css` | Shared shape and spacing for everything that floats over the game (top pill, left rail, Today card, dock, needs pill, place card, sheets, modals, toasts), phone titles and empty states. **Superseded by the theme pass below:** its `--ov-*` names are now aliases of the theme tokens, so the overlays are light by default and dark indigo only when the player picks Dark. |
| `src/admin/admin.css` + `AdminApp.tsx` | Admin tables had no styles at all. They now look calm on wide screens and become wrapping cards on phones (column titles are copied into `data-label`). Admin buttons 40px, labels 12px, squeezed inputs take the whole row. |

Spacing scale (existing `--s1..--s8` stay): `--tap` 40px, `--gutter` 16px, `--card-pad` 14px, `--stack` 12px, `--ov-gap` 8px, `--ov-pad` 16px, `--ov-radius` 24px; `--fs-label` 12px, `--fs-body` 13.5px.

## Problems found and fixes (screen, problem, fix)
| Screen | Problem | Fix |
|---|---|---|
| Top pill (every game screen) | At 360px the money chip and the green "+" were pushed past the right edge (right = 371px) | Online count hidden under 400px, tighter gaps; a full figure (₦1,500,000,000,000) hides the clock extras and mood so it fits |
| Top pill / HUD chips | Money amount, mood, "+", event "x", Today "x" were 21 to 38px tall | 40px minimum, invisible bigger hit area on small round buttons |
| Phone frame (all apps) | 328px wide on 360 phones, content squeezed; the home bar covered the last row of every app | Frame is `100vw - 16px`, thinner bezel, 16px gutters, app body keeps a strip for the home bar |
| Phone apps | Back button 38px; tabs 33 to 38px; chips 32 to 36px | 40px minimum everywhere |
| Business | "Collect takings" cut to "Collect taki..." | Row wraps, button grows and does not shrink |
| Yahoo | "Need Lenovo ThinkPad..." button became a 92px tall blob | Pill radius 18px, min width, wraps cleanly |
| Houses (upgrades) | Price column squeezed the name into 2 words per line | Under 420px the price drops under the description |
| Benin Gist groups | Group names cut to "Ugbowo Hust..." in the list | Names may use two lines |
| Chowdeck, Cars, shops | Item descriptions cut at two lines; some names cut | Three lines, long names wrap |
| Ranks | The "You" row ran past the card edge; money band cut | Grid column is `minmax(0, 1fr)`, band may use two lines |
| Bank | `₦90,000,000,000` split over two lines in the balance card | Font scales with width, no wrapping inside the number |
| Boutique | Cards 9px wider than their column | `min-width: 0` on cards, meta row wraps |
| Sim sheet | Long usernames overflowed the header | `overflow-wrap: anywhere` |
| All sheets | Close button 38px, header padding tight, footer buttons close together | 42px close button, 28/64/12/20 header padding, 16px gutters, 14px footer padding with safe area, buttons stacked with 10px gap |
| Modals | No safe-area padding; 28px title wrapped badly on 360 | Safe-area padding, 22px title under 400px |
| Admin (all pages) | Tables unstyled and overflowing; Elections history headers overlapped; inputs cut ("Registration hou"); buttons 30px | Cards on phones, inputs full width, 40px buttons, 12px labels |
| Small text | About 110 distinct selectors under 12px (9 to 11.5px) | 12px floor (generated list) |
| Look and feel | White HUD, white sheets and mixed pop-ups looked busy and uneven | One dark indigo palette with large radius, even gaps, 40px chips, dark sheets with a bold title and full-width pill buttons |

## Check numbers
The in-page audit (`overflow`, `clipped text`, `tap targets under 40x40`, `text under 12px`, `wrapped button labels`, `page-level horizontal scroll`) ran on every snapshot of every screen (including scrolled positions inside sheets and phone apps). Counts are per screen and element ("distinct" = different selectors). The 3D map labels (`c3-*`), map attribution and the phone home-bar strip are excluded: they belong to the map scene.

| Check (instances per screen, distinct selectors in brackets) | 360x780 before | 360x780 after | 390x844 before | 390x844 after |
|---|---|---|---|---|
| Snapshots audited | 351 | 347 | 312 | 315 |
| Screens with page-level horizontal scroll | 0 | 0 | 0 | 0 |
| Elements pushed past the screen edge | 114 (3) | 0 | 2 (2) | 0 |
| Clipped text without an ellipsis | 28 (10) | 41 (2)* | 3 (1) | 1 (1)* |
| Tap targets under 40x40 | 1655 (92) | 318 (11)** | 1437 (92) | 376 (11)** |
| Text under 12px | 1537 (108) | 343 (10) | 1383 (110) | 352 (11) |
| Button labels wrapping badly (taller than 64px) | 6 (4) | 13 (6) | 9 (5) | 3 (3) |

\* The two remaining selectors are the event banner title (a bold word inside a line that ends with an ellipsis on purpose) and the "You" tag in the Ranks list, fixed in the last commit after that screen's final audit run (the "rich" player screen was not re-shot).
\** Round buttons with an invisible 6px hit area, the map credit link and the 3D map's tiny pins. The remaining "under 12px" selectors are emoji-only badges and the map credit.
The "wrapping" counts rise at 360 because the three-line descriptions and wrapping pills are now allowed to take their natural height; they are cards with long labels (company pricing, dealers, kitchen pots, Yahoo laptop), not broken buttons.

Tap targets that still show under 40px in the audit are the round buttons that have a 6px invisible hit area around them (measured by their drawn size, so the check cannot see the area), and the OpenStreetMap credit link.

## Screens covered (360x780 and 390x844)
Landing, sign in, sign up (with error), terms, privacy; creator (name, look, traits, dream with "How did you hear about us?"); welcome-back screen and gift card (before and after claim); 3D home HUD with Today list, event banner and journey/gem/daily rows; map, place panels and shops, Work tab, chat, Buy sheet, shortcuts; Sim sheet (all 7 tabs including Settings and "Keep my own music playing"), Edit look, Boutique; Alerts; weekly calendar ("This week in Benin"), daily reward and gems; life-moment card; receipts, house furniture sheet, garage, lounge, spray, arrange bar; the club HUD; phone lock, home and every app (Jobs, Hustles, School, Bank and Invest, Business, Company, Houses with tabs, Cars, Chowdeck with Kitchen and Prices, Market, Messages, Benin Gist feed, groups and group chat, Stories, Family, Love, Kids, Benin Votes with Industry offices, My Office, Gang, Yahoo, Ranks, Police, Ride, Billboards, Boutique, Help, Feedback, Alerts, Settings, Wallet), with every tab inside them; Admin (Overview, Players with the Grant toolbox, Content, Settings, Offices, Property, Gist, Elections, Economy, Growth and the rest).

Screenshots: `scratchpad/ui-pass/before/` and `scratchpad/ui-pass/after/` (named by screen and width; `-s2`, `-s3` are scrolled positions).

## Not fixed, and why
- Map labels on the 3D city overlap each other when many places are close (scene layout, out of scope for a HUD pass).
- Narrow tab rows (Bank has six tabs) scroll inside their own row at 360px; there is no fade hint yet.
- The Boutique full-screen shop keeps its own light look (it is a shop, not an overlay).
- A right-hand column of round icon buttons was not added: Benin Life has no such column (map zoom buttons and the dock do that job) and adding one would change layouts.
- Long single-line names that are meant to be one line (chat names, list rows) still end with an ellipsis.

## Theme pass: Light default, Dark on request (2026-11-14)
The dark indigo overlays were forced on everyone. They are now the **Dark** theme, chosen in Sim sheet, Settings, Appearance (Light / Dark / Match my phone). Light is the default and restores the light HUD, sheets, pop-ups and phone apps with the UI pass's spacing, sizes and consistency kept. How it works, the token table and how to add a themed component: `docs/THEME.md`.

What changed in CSS: colours on themed surfaces are variables (`src/styles/tokens.css`); ~780 hard-coded colours in 40 stylesheets were converted; Court, Messages, Boutique and the Spark chart use tokens; the overlay flip block was removed. Contrast fixes found by the audit (both themes): primary green button 3.4:1 to 4.6:1 (`--green-500/600`, `--grad-primary`), danger gradient, red badges, disabled buttons (now grey fill with `--muted` text instead of a faded green), Day badge, Claim button, Messages blue, Bank/House/Invest/Cooking/Food gradient cards (white labels never fade), "You" tag.

### Contrast results (390x844, automated, `scratchpad/theme/audit.mjs`)
Every visible text node on 94 states per theme: landing, sign-in, sign-up, terms, privacy; home and the Today list; the Sim sheet (7 tabs); Alerts, Buy, Shortcuts and Look overlays; a pop-up; the phone home; 28 phone apps with their tabs. Rule: normal text 4.5:1, large text (24px, or 18.7px bold) 3:1, worst gradient stop.
| | Failing text nodes before fixes | After fixes |
|---|---|---|
| Light | 692 (258 selectors) on the first full run | 35 (8 selectors) |
| Dark | 626 (249 selectors) | 35 (8 selectors) |
The 8 left are the same in both themes and are not themed surfaces: the phone home wallpaper (status bar and icon labels over a sunset gradient, measured at the brightest stop, with a text shadow), the Ranks podium step numbers (decorative, animated), the crew-tag preview (colour picked by the player), and a dimmed "Vacant" label in Politics. The Ranks app and the Yahoo app keep their own dark look in both themes.
Screenshots (Light and Dark pairs, 390x844, plus a mid-transition frame): `scratchpad/theme/`.

