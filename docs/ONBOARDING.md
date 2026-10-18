# Onboarding: intro, guided tour and the Help app

Everything a new player sees in their first minute, plus the Help app that stays on the phone. All of it is data-driven:
**one file for the tour, one file for the Help articles.**

> Rule (also in `docs/HANDOFF.md`): **when you add a feature, add a tour step and a Help article.**

## Files

| File | What |
|---|---|
| `src/onboarding/tourSteps.ts` | The tour, as data (`TOUR_STEPS`). Also the `toGame()`, `toPhone()`, `toSim()` helpers for `before()`. |
| `src/onboarding/helpArticles.ts` | The Help articles and topics (`HELP_ARTICLES`, `HELP_TOPICS`), plus `searchArticles()`. |
| `src/onboarding/Tour.tsx` + `tour.css` | The spotlight overlay and card. |
| `src/onboarding/tourStore.ts` | zustand store (`useTour`), `startTour()`, `startWhatsNew()`, and the "tour done" flag. |
| `src/onboarding/OnboardingHost.tsx` | Mounted once in `Game.tsx`. Starts the tour after the intro; shows "Take the tour?" to existing players. |
| `src/onboarding/Intro.tsx` + `intro.css` + `introStore.ts` | The cinematic intro. Mounted in `App.tsx` so it can cover the route change. |
| `src/screens/game/phone/HelpApp.tsx` + `.css` | The Help phone app (id `help`, icon 🛟). |
| `supabase/migrations/20261018000600_tour.sql` | `profiles.tour_done_at` + the `tour_done()` RPC. Test: `supabase/tests/tour_test.sql`. |

This replaced the old 4-card `JourneyGuide` (deleted); its `bl.journey.*` localStorage keys are no longer used.

## The intro (new accounts only)
Starts when the player taps **Move in** at the end of character creation (`CreateSim.tsx` calls `playIntro(...)`).
1. The screen fades to white (~0.75 s). The route changes to `/play` underneath, while it is fully white.
2. The brand medallion (`/brand/logo-medallion.svg`), "Welcome to **Benin Life**" (Outfit, coral) and "Experience life in Benin" fade in (~1 s).
3. Holds 2.5 s. A soft chord swell plays (`playSwell()` in `src/lib/sound.ts`); it stays silent when audio is not unlocked, muted or Sound effects are off.
4. Fades out, waits until the HUD exists (max 9 s), then the white lifts onto the game (~1 s).
5. The tour starts ~0.5 s later.

Tap, click or any key skips (a quick 0.4 s fade). With `prefers-reduced-motion` only opacity changes: nothing rises, scales or slides.
Existing players never see the intro.

## The tour
- **Spotlight:** one fixed element (`.tour__spot`) sits on the target. Its huge `box-shadow` is the dark overlay, so the target is a bright cut-out, ringed by a soft gold glow. It moves with `transform` and size transitions only. There is deliberately **no blur** over the WebGL canvas (cost on phones).
- **Card:** title, body, a few tick points, progress dots, **Back / Next / Skip tour**. It sits on the side of the target that has room (never over the target) and slides between steps. Keyboard: Left/Right arrows move, Esc skips.
- **Blocker:** a transparent layer swallows taps so the game cannot be used while the tour is up.
- **Targets** are real elements found with `data-tour="..."` attributes. Where the target is not visible (or does not appear within ~1.8 s) the step shows a centred card with no spotlight.
- **Layout:** positions are re-measured every 120 ms and on `resize`, `scroll` and `visualViewport` changes (on-screen keyboard). Everything is clamped to the visual viewport.
- **Once per account:** finishing or skipping a full tour saves `profiles.tour_done_at` through `tour_done()`, and `bl.tour.done.<userId>` in localStorage as a fallback (the RPC can fail offline). `isTourDone()` checks both.
- **Existing players** (no stamp yet) get a small "Take the tour?" prompt about 3.5 s after landing in the game. **Not now** counts as done (it never nags again); the tour stays one tap away in Settings and Help. The prompt never appears on top of an open sheet.
- **Replay:** Settings (Sim sheet, Settings tab) has "Replay the tour" and "Help and guides"; the Help app has "Replay the tour" and "What's new".
- **What's new:** `startWhatsNew()` runs only the steps flagged `isNew: true`. Flag the steps for your newest features and clear the flag later.
- **Show me:** a Help article's `tour: ['stepId', ...]` runs just those steps (kind `show`). It does not change the "done" flag.

### Adding a tour step
1. Give the element a stable attribute: `<button data-tour="my-feature">`. Prefer an attribute on a component that is always rendered while its screen is open. (`Tabs` accepts `tourPrefix="x"` and writes `data-tour="x-<tabId>"` on each tab.)
2. Add an entry to `TOUR_STEPS` in `tourSteps.ts`, in the order the player should meet it:

```ts
{
  id: 'my-feature',                       // unique, kebab-case; Help articles refer to it
  target: '[data-tour="my-feature"]',     // CSS selector; "a, b" tries a then b; null = centred card
  title: 'My feature',
  body: 'One or two short sentences. English with light Pidgin.',
  points: ['Optional tick line.', 'Another one.'],
  placement: 'bottom',                    // 'auto' (default) | 'top' | 'bottom' | 'left' | 'right' | 'center'
  isNew: true,                            // optional: also shown by "What's new"
  before: () => toPhone('home'),          // optional: get the screen ready
},
```
3. `before()` runs every time the step is shown (including Back). Use the helpers: `toGame()` closes every sheet and the phone, `toPhone('home' | '<app id>')` opens the phone, `toSim('skills')` opens the Sim sheet on a tab. Steps that need nothing special still call `toGame` so the previous step's sheet is closed.
4. Keep targets **small** (an icon, a button, a pill). A target that fills the screen leaves no room for the card.
5. Add or update the Help article's `tour` list so "Show me" can reach it.

## The Help app
Phone, then **Help** (🛟). A search box, "Replay the tour" and "What's new" buttons, then articles grouped by topic. An article has a summary, a numbered **How to**, **Where to find it**, **Good to know** and a **Show me** button (when it has a `tour` list).

Search matches every word against title, summary, steps, tips, where, keywords and topic name.

**Deep links:** `/play?go=help` opens the list; `/play?go=help:<article id>` opens one article (for example `go=help:topup`). The regex lives in `src/lib/deeplink.ts`.

### Adding an article
Add an object to `HELP_ARTICLES` in `helpArticles.ts` (put it under its topic; add a topic to `HELP_TOPICS` if needed):

```ts
{
  id: 'my-feature',            // URL-safe; becomes go=help:my-feature
  topic: 'money',
  title: 'Short, plain title',
  summary: 'One or two sentences.',
  steps: ['Do this.', 'Then this.'],
  where: 'Phone, then My Feature.',
  tips: ['Optional.'],
  tour: ['my-feature'],        // optional, step ids for Show me
  keywords: 'words players might type, including slang',
},
```
Rules for the copy: facts come from the docs and the code; never invent numbers. **Prices, rates and limits that an admin can change are not written down: say "check the app for current prices".** Short sentences. If the feature has a `docs/*.md`, link the facts from there.

## Admin overrides
Not built. The articles and steps live in code, which is enough while the team is small. If it is needed later, add an admin content table and merge its rows over `HELP_ARTICLES` by `id` in `HelpApp.tsx`.

## Testing
- `bash scripts/sql-test.sh -- supabase/tests/tour_test.sql` for the flag.
- Browser: sign up a fresh account through Auth and CreateSim, watch the intro, step through every tour step on a 375x667 phone, a 390x844 phone, an iPad and a desktop. For each step check that the card is inside the viewport, does not overlap the spotlighted target and that the target is the one named by `data-tour`.
- Delete the test accounts afterwards (`delete from auth.users where email like 'tour%@test.local'`).
