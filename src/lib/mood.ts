// Mood from needs (R4, simple on purpose; feelings/moodlets arrive in Phase 2).
// Average of the six everyday needs, pulled down by the single worst one, poor health and stress.
import type { Profile } from './types';
import { HUD_NEEDS, NEED_TIP, type NeedKey } from './pidgin';

export interface Mood {
  label: string;
  emoji: string;
  tone: 'good' | 'ok' | 'warn' | 'bad';
  score: number;
}

export function needValue(p: Profile, k: NeedKey): number {
  const raw = k === 'bladder' ? (p.bladder ?? 100) : (p[k] as number);
  const v = Number(raw);
  return Number.isFinite(v) ? Math.max(0, Math.min(100, v)) : 0;
}

export function moodOf(p: Profile): Mood {
  const vals = HUD_NEEDS.map((k) => needValue(p, k));
  const avg = vals.reduce((a, b) => a + b, 0) / vals.length;
  const worst = Math.min(...vals);
  let score = avg * 0.7 + worst * 0.3;
  score -= Math.max(0, 60 - needValue(p, 'health')) * 0.5;
  score -= Math.max(0, needValue(p, 'stress') - 50) * 0.4;
  score = Math.max(0, Math.min(100, score));
  if (score >= 80) return { label: 'Very happy', emoji: '😄', tone: 'good', score };
  if (score >= 62) return { label: 'Happy', emoji: '🙂', tone: 'good', score };
  if (score >= 45) return { label: 'Fine', emoji: '😐', tone: 'ok', score };
  if (score >= 28) return { label: 'Uncomfortable', emoji: '😕', tone: 'warn', score };
  return { label: 'Miserable', emoji: '😫', tone: 'bad', score };
}

/** Up to `max` low needs (below `under`), worst first, that have a tip. */
export function lowNeeds(p: Profile, max = 2, under = 45): { key: NeedKey; value: number; text: string; emoji: string }[] {
  return HUD_NEEDS.map((k) => ({ key: k, value: needValue(p, k) }))
    .filter((x) => x.value < under && NEED_TIP[x.key])
    .sort((a, b) => a.value - b.value)
    .slice(0, max)
    .map((x) => ({ ...x, text: NEED_TIP[x.key]!.text, emoji: NEED_TIP[x.key]!.emoji }));
}
