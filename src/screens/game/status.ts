import { secondsUntil } from '../../lib/format';
import type { GameState } from '../../lib/types';

export interface PlayerStatus {
  traveling: boolean;
  travelLeft: number;
  travelTotal: number;
  travelProgress: number; // 0–1
  busyLeft: number;
  /** Busy activity window in server-corrected ms (start null when the server never sent one). */
  busyStartMs: number | null;
  busyEndMs: number | null;
  jailLeft: number;
  hospLeft: number;
  protLeft: number;
  /** The server-corrected now these values were derived at (ms). */
  now: number;
  /** Can the player do location actions right now? */
  free: boolean;
  blockedReason: string | null;
}

export function deriveStatus(state: GameState, now: number): PlayerStatus {
  const p = state.profile;
  const t = state.travel;
  let travelLeft = 0;
  let travelTotal = 0;
  let travelProgress = 0;
  if (t) {
    const start = Date.parse(t.started_at);
    const end = Date.parse(t.arrives_at);
    travelTotal = Math.max(1, (end - start) / 1000);
    travelLeft = secondsUntil(t.arrives_at, now);
    travelProgress = Math.min(1, Math.max(0, (now - start) / (end - start || 1)));
  }
  const busyLeft = secondsUntil(p.busy_until, now);
  const busyEndMs = p.busy_until ? Date.parse(p.busy_until) : NaN;
  const busyStartRaw = p.busy_started_at ? Date.parse(p.busy_started_at) : NaN;
  const busyStartMs =
    Number.isFinite(busyStartRaw) && Number.isFinite(busyEndMs) && busyStartRaw < busyEndMs ? busyStartRaw : null;
  const jailLeft = secondsUntil(p.jailed_until, now);
  const hospLeft = secondsUntil(p.hospitalized_until, now);
  const protLeft = secondsUntil(p.protected_until, now);
  const blockedReason = t
    ? 'You dey road. Wait make you reach first.'
    : jailLeft > 0
      ? 'You dey police cell. Bail yourself or wait.'
      : hospLeft > 0
        ? 'You dey hospital bed. Rest small.'
        : busyLeft > 0
          ? `You dey busy${p.busy_label ? ` (${p.busy_label})` : ''}. Wait small.`
          : null;
  return {
    traveling: Boolean(t),
    travelLeft,
    travelTotal,
    travelProgress,
    busyLeft,
    busyStartMs,
    busyEndMs: Number.isFinite(busyEndMs) ? busyEndMs : null,
    jailLeft,
    hospLeft,
    protLeft,
    now,
    free: !blockedReason,
    blockedReason,
  };
}
