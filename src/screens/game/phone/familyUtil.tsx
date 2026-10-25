// Small helpers shared by the Family app's tabs (docs/LOVE.md): time wording, a once-a-second tick for countdowns, and a face.
import { useEffect, useState } from 'react';
import { AvatarPortrait } from '../../../art/avatar3d';
import { serverNow } from '../../../lib/clock';
import type { AvatarConfig } from '../../../lib/types';

/** 3725 -> "1 h 2 min", 130 -> "2 min 10 s", 40 -> "40 s". */
export function dur(sec: number): string {
  const s = Math.max(0, Math.ceil(sec));
  const d = Math.floor(s / 86400);
  const h = Math.floor((s % 86400) / 3600);
  const m = Math.floor((s % 3600) / 60);
  if (d > 0) return `${d} d ${h} h`;
  if (h > 0) return `${h} h ${m} min`;
  if (m > 0) return `${m} min${s % 60 ? ` ${s % 60} s` : ''}`;
  return `${s} s`;
}

/** Re-render once a second while `active` (countdowns). */
export function useTick(active: boolean): number {
  const [n, setN] = useState(0);
  useEffect(() => {
    if (!active) return;
    const id = window.setInterval(() => setN((x) => x + 1), 1000);
    return () => window.clearInterval(id);
  }, [active]);
  return n;
}

export const face = (a: AvatarConfig | null | undefined, size: number) => <AvatarPortrait config={(a ?? {}) as AvatarConfig} size={size} className="fm-face" alt="" />;

export const ago = (iso: string) => {
  const s = Math.max(0, (serverNow() - Date.parse(iso)) / 1000);
  if (s < 90) return 'just now';
  if (s < 3600) return `${Math.round(s / 60)} min ago`;
  if (s < 86400) return `${Math.round(s / 3600)} h ago`;
  return `${Math.round(s / 86400)} d ago`;
};
