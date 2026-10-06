// S2 welcome back: when to show the welcome-back screen before the game.
//
// - "last seen" lives in localStorage per user id (bl.lastSeen.<uid>), refreshed every minute while
//   the game is open and visible, and when the tab is hidden or closed.
// - sessionStorage (bl.welcomed.<uid>) marks that this tab already showed it, so a reload in the same
//   tab goes straight to the game.
// - It shows when this tab has not shown it yet, or when the player was away longer than
//   `life.welcome_after_minutes` (admin, default 30 real minutes). `life.welcome_enabled` turns it off.
// Every storage access is wrapped: private mode or blocked storage simply skips the screen's memory.

const seenKey = (uid: string) => `bl.lastSeen.${uid}`;
const doneKey = (uid: string) => `bl.welcomed.${uid}`;

function read(store: () => Storage, key: string): string | null {
  try {
    return store().getItem(key);
  } catch {
    return null;
  }
}
function write(store: () => Storage, key: string, value: string): void {
  try {
    store().setItem(key, value);
  } catch {
    /* private mode / blocked storage */
  }
}
const local = () => window.localStorage;
const session = () => window.sessionStorage;

/** Last time this player had the game open in this browser (ms), or null. */
export function lastSeen(uid: string): number | null {
  const v = Number(read(local, seenKey(uid)));
  return Number.isFinite(v) && v > 0 ? v : null;
}

export function touchLastSeen(uid: string, at = Date.now()): void {
  write(local, seenKey(uid), String(at));
}

/** This tab has shown (or skipped) the welcome screen. */
export function markWelcomed(uid: string): void {
  write(session, doneKey(uid), '1');
  touchLastSeen(uid);
}

export function shouldWelcome(uid: string, awayMinutes: number, now = Date.now()): boolean {
  if (read(session, doneKey(uid)) !== '1') return true;
  const seen = lastSeen(uid);
  return seen !== null && now - seen > Math.max(1, awayMinutes) * 60_000;
}

/**
 * Keep "last seen" fresh while the game is open. Calls `onReturn` when the tab comes back after
 * being hidden longer than the threshold. Returns a cleanup.
 */
export function trackPresence(uid: string, getAwayMinutes: () => number, onReturn: () => void): () => void {
  touchLastSeen(uid);
  const beat = window.setInterval(() => {
    if (document.visibilityState === 'visible') touchLastSeen(uid);
  }, 60_000);
  const onVis = () => {
    if (document.visibilityState === 'hidden') {
      touchLastSeen(uid);
      return;
    }
    const seen = lastSeen(uid);
    if (seen !== null && Date.now() - seen > Math.max(1, getAwayMinutes()) * 60_000) onReturn();
    else touchLastSeen(uid);
  };
  const onHide = () => touchLastSeen(uid);
  document.addEventListener('visibilitychange', onVis);
  window.addEventListener('pagehide', onHide);
  return () => {
    window.clearInterval(beat);
    document.removeEventListener('visibilitychange', onVis);
    window.removeEventListener('pagehide', onHide);
  };
}
