// L1 action timing on the client (docs/REAL_LIFE_PLAN.md "Action timing rule").
// * Durations mirror the server (20261006000100_real_time.sql): bl_activity_seconds, bl_shift_seconds.
//   They are only estimates for the chips; the real window always comes from the server
//   (profiles.busy_started_at / busy_until, travel_started_at / arrives_at).
// * Live progress: while an action runs, the need bars move smoothly from profiles.busy_needs_from
//   (the values just before the action's effects) to the current values (the server already applied
//   the effects at the start, so it stays authoritative); shift pay/XP count up the same way.
import { useEffect, useState } from 'react';
import { getCfg, useConfig } from './config';
import { serverNow } from './clock';
import { realDuration } from './format';
import type { Profile } from './types';

const SCALE_KEYS = ['energy', 'hunger', 'hygiene', 'bladder', 'fun', 'social'] as const;
const LIVE_KEYS = ['hunger', 'energy', 'hygiene', 'fun', 'social', 'stress', 'health', 'bladder'] as const;

export interface TimedActivity {
  game_minutes: number;
  effects: Record<string, number> | null;
  max_seconds?: number | null;
  min_seconds?: number | null;
  scale_by_need?: boolean | null;
}

type Read = <T>(k: string, f: T) => T;

/** 'short' (seconds per action, default) or 'game_minutes' (the old durations). */
export function actionShort(read: Read = getCfg): boolean {
  return read<string>('action.mode', 'short') !== 'game_minutes';
}

function round1(n: number): number {
  return Math.round(n * 10) / 10;
}

function num(v: unknown, f: number): number {
  const n = Number(v);
  return Number.isFinite(n) ? n : f;
}

/** Real seconds an activity will take for this player (same formula as the server). */
export function activitySeconds(a: TimedActivity, p: Partial<Profile> | null, read: Read = getCfg): number {
  if (!actionShort(read)) return a.game_minutes * read('time.real_seconds_per_game_minute', 0.75);
  const max = Math.max(num(a.max_seconds, 8), 0.5);
  const min = Math.min(Math.max(num(a.min_seconds, 0), 0), max);
  if (!(read('action.scale_by_need', true) && (a.scale_by_need ?? true)) || !p) return round1(max);
  const eff = a.effects ?? {};
  let key: string | null = null;
  let best = 0;
  for (const k of SCALE_KEYS) {
    const v = num(eff[k], 0);
    if (v > best) {
      best = v;
      key = k;
    }
  }
  let missing: number;
  if (key) missing = 100 - num((p as Record<string, unknown>)[key], 100);
  else if (num(eff.stress, 0) < 0) missing = num(p.stress, 0);
  else return round1(max);
  missing = Math.max(0, Math.min(100, missing));
  return round1(Math.max(min, (max * missing) / 100));
}

/** Real seconds of one work shift. */
export function shiftSeconds(shiftGameMinutes: number, read: Read = getCfg): number {
  return actionShort(read)
    ? Math.max(1, num(read('action.shift_seconds', 18), 18))
    : shiftGameMinutes * read('time.real_seconds_per_game_minute', 0.75);
}

/** Chip label for a real duration: "≈15 s", "≈1m 30s". */
export function secondsLabel(seconds: number): string {
  const s = Math.max(1, Math.round(seconds));
  return s < 60 ? `≈${s} s` : `≈${realDuration(s)}`;
}

/** Re-renders with the server-corrected now every `ms` while `active` (cheap: one timer). */
export function useLiveNow(active: boolean, ms = 100): number {
  const [now, setNow] = useState(serverNow);
  useEffect(() => {
    if (!active) return;
    setNow(serverNow());
    const id = window.setInterval(() => setNow(serverNow()), ms);
    return () => window.clearInterval(id);
  }, [active, ms]);
  return active ? now : serverNow();
}

/** 0–1 through the busy window, or null when nothing is running. */
export function busyFraction(p: Profile, now: number): number | null {
  if (!p.busy_until || !p.busy_started_at) return null;
  const end = Date.parse(p.busy_until);
  const start = Date.parse(p.busy_started_at);
  if (!Number.isFinite(end) || !Number.isFinite(start) || end <= start || now >= end) return null;
  return Math.max(0, Math.min(1, (now - start) / (end - start)));
}

function ease(t: number): number {
  // gentle ease-out so the bar settles into its final value
  return 1 - (1 - t) * (1 - t);
}

/** The profile with need values interpolated over the running action (unchanged when idle). */
export function liveProfile(p: Profile, now: number): Profile {
  const from = p.busy_needs_from;
  const f = busyFraction(p, now);
  if (!from || f === null) return p;
  const t = ease(f);
  const out: Record<string, unknown> = { ...p };
  for (const k of LIVE_KEYS) {
    const a = Number(from[k]);
    const b = Number((p as unknown as Record<string, unknown>)[k]);
    if (Number.isFinite(a) && Number.isFinite(b)) out[k] = a + (b - a) * t;
  }
  return out as unknown as Profile;
}

/** Live-filling profile for need bars: ticks ~10×/s only while an action with a start snapshot runs. */
export function useLiveProfile(p: Profile): Profile {
  const running = Boolean(p.busy_needs_from) && busyFraction(p, serverNow()) !== null;
  const now = useLiveNow(running);
  return running ? liveProfile(p, now) : p;
}

/** Re-render on config edits (so chip estimates follow admin changes). */
export function useActionConfig(): Read {
  const { cfg } = useConfig();
  return cfg;
}
