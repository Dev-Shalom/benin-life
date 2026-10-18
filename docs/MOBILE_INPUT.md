# Mobile text input: keyboard, zoom and composers

Every text box a player types in (place chat, house chat, DMs, the place card "Say something", Messages search,
Yahoo invites, Feedback, Spray, Billboard ads, gifts, admin) follows one pattern. Follow it for any new input.

## What goes wrong without it
iOS Safari and Android Chrome (default `interactive-widget=resizes-visual`) do **not** shrink the layout
viewport when the keyboard opens. Only `window.visualViewport` shrinks. So:

- `100vh` / `100dvh` heights and `position: fixed; bottom: 0` all sit behind the keyboard.
- iOS pans the page to reach the field, and zooms in if the field's font is under 16px.
- A phone-style frame with a fixed height plus header chrome (streak card, chips, quick replies) leaves **0px**
  for the message list. It looks like "all the messages got wiped" (they are still in the list, with no room).

## The pattern

1. **`src/lib/keyboard.ts`** (started once in `main.tsx`, never torn down) publishes on `<html>`:
   - `--vvh`: visible height (visual viewport), `--kb`: px the keyboard covers, `--vv-top`: iOS page pan.
   - `html.has-kb`: a text field is focused and the keyboard covers more than 80px (pinch-zoom does not count).
   - It also resets any document scroll iOS applied, and nudges the focused field inside its own scroller.
   - `useKeyboardInset()` returns `{ kb, vvh, open }` in React. `useViewportVars()` in `chatKit` is an alias.
2. **`src/styles/keyboard.css`** (loaded last):
   - Every text field is at least 16px on touch screens, so iOS never zooms.
   - `.kb-composer`: the shared composer box. It is `position: sticky; bottom: 0; flex: none` inside the
     chat column. Never `fixed` to the layout viewport.
   - `html.has-kb` (phones and portrait iPad, width under 900px): sheets, modals and the phone get
     `padding-bottom: var(--kb)` and `padding-top: var(--vv-top)`, and size to `--vvh`. The phone frame fills the
     visible area and drops its status bar. Chat extras (`.dm-private`, `.dm-streak`, `.dm-chips`, `.dm-quick`,
     `.chat__rules`) fold away until the keyboard closes. The place card's say-box rides on top of the keyboard.
   - Desktop (900px and wider with no keyboard) is untouched: sheet and phone positions do not change.

## Rules for new inputs
- Put it inside `Sheet`, `Modal` or the phone, or use `.kb-composer` at the bottom of a flex column. Size with
  `var(--vvh, 100dvh)`, not `100vh`.
- Layout decisions use **width**, never `innerHeight` or a `(min-height)` media query: the keyboard changes the
  height and would flip or remount the tree. Never put a height-derived value in a React `key`.
- Keep message lists and drafts in a store or a ref (`useChat`, DM state), and never clear a list while a refetch
  is pending.
- Do not `disabled` a field while sending (it blurs and the keyboard closes). Use `readOnly`.
- Global key handlers must ignore events from `INPUT`, `TEXTAREA`, `SELECT` and contenteditable (see
  `useGameShortcuts`). Tap-outside handlers must not close a panel because a field is focused.
- Do not call `scrollIntoView({ block: 'end' | 'center' })` on focus. `useThreadScroll` keeps the newest message
  in view when the list resizes.
- Add `enterKeyHint`, and `inputMode="numeric"` for amounts.

## Testing
Playwright cannot open a real keyboard. Simulate it by overriding `window.visualViewport` with an init script
(height = innerHeight - keyboard) and dispatching `resize`, and by `page.setViewportSize` to a shorter height for
the "resizes-content" case. Assert: message count unchanged, typed text kept, input inside the visible area,
composer under about 25% of it, last message visible. The scripts used for the fix live in the session
scratchpad (`textbox/kb.mjs`, `textbox/test.mjs`).
