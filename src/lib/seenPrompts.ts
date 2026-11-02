// "Show once" memory for pop-ups that would otherwise nag (election registration, ...).
// Per browser, per player, per key (for example `reg.<cycleId>`). Storage can be blocked, so every call is wrapped.
const k = (uid: string, key: string) => `bl.seen.${uid}.${key}`;

export function wasSeen(uid: string, key: string): boolean {
  try { return window.localStorage.getItem(k(uid, key)) != null; } catch { return false; }
}
export function markSeen(uid: string, key: string): void {
  try { window.localStorage.setItem(k(uid, key), String(Date.now())); } catch { /* blocked storage */ }
}
