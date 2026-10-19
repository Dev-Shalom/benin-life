// Disk-IO work (docs/DISK_IO.md): every poller asks this module before it calls the server.
//   * `canPoll()`: the tab is visible AND the player touched the game in the last 10 minutes (not AFK);
//   * `idleFactor()`: 1 while the player is active, 2 after 2 minutes without input (polls back off to half speed);
//   * `onResume(fn)`: runs when an AFK player comes back (a pointer, key or touch event), so the screen catches up at once.
// Input events are only timestamped (no state, no React renders), so this costs nothing while playing.

const AFK_MS = 10 * 60_000;
const SLOW_MS = 2 * 60_000;

let lastInput = Date.now();
const resumers = new Set<() => void>();

function touch() {
  const now = Date.now();
  const away = now - lastInput >= AFK_MS;
  lastInput = now;
  if (!away) return;
  for (const fn of [...resumers]) {
    try { fn(); } catch { /* a resumer must never break input handling */ }
  }
}

if (typeof window !== 'undefined') {
  for (const ev of ['pointerdown', 'pointermove', 'keydown', 'wheel', 'touchstart', 'focus'] as const) {
    window.addEventListener(ev, touch, { passive: true, capture: true });
  }
}

if (typeof document !== 'undefined') {
  // coming back to the tab counts as activity
  document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') touch(); });
}

/** Milliseconds since the last pointer / key / touch event. */
export const idleMs = () => Date.now() - lastInput;
/** True after 10 minutes without any input. */
export const isAfk = () => idleMs() >= AFK_MS;
/** Visible tab and not AFK: the only time a poller may call the server. */
export const canPoll = () => typeof document === 'undefined' || (document.visibilityState === 'visible' && !isAfk());
/** Poll period multiplier: 2 once the player has been idle for 2 minutes, else 1. */
export const idleFactor = () => (idleMs() >= SLOW_MS ? 2 : 1);
/** Run `fn` when an AFK player comes back. Returns the unsubscribe function. */
export function onResume(fn: () => void): () => void {
  resumers.add(fn);
  return () => void resumers.delete(fn);
}
