// Home activities vs the Sim's furniture (server: get_my_state().home, 20261006000400_starter_furniture.sql).
// The server decides; this only reads its answer for the lists (label, allowed, reason, effect percent).
import type { GameState } from './types';

export interface HomeActView {
  label: string;
  ok: boolean;
  reason: string | null;
  pct: number;
}

/** How a home activity looks for this Sim. Non-home activities and old servers: as-is, allowed. */
export function homeAct(state: GameState, a: { id: string; name: string; home_only: boolean }): HomeActView {
  const info = a.home_only ? state.home?.activities?.[a.id] : undefined;
  if (!info) return { label: a.name, ok: true, reason: null, pct: 100 };
  return { label: info.label || a.name, ok: info.ok, reason: info.reason, pct: Number(info.pct) || 100 };
}

const GOOD_UP = ['hunger', 'energy', 'hygiene', 'fun', 'social', 'health', 'bladder'];

/** The activity's effects with the furniture percent applied to the good ones (same rule as the server). */
export function scaleEffects(effects: Record<string, number> | null, pct: number): Record<string, number> | null {
  if (!effects || pct === 100) return effects;
  const out: Record<string, number> = { ...effects };
  for (const [k, v] of Object.entries(effects)) {
    if (typeof v !== 'number') continue;
    if ((k === 'stress' && v < 0) || (GOOD_UP.includes(k) && v > 0)) out[k] = Math.round(v * pct) / 100;
  }
  return out;
}
