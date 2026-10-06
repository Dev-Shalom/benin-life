// S1 smooth day/night: one continuous darkness curve from real Benin (WAT) time, shared by the 3D home,
// the 3D city and the HUD. No snapping: dusk darkens 17:30 -> 19:30, dawn brightens 05:30 -> 07:00
// (smoothstep). Game rules (night robberies, "Bank your cash") still use clock.is_night (20:00-06:00).
// Pure numbers, no three.js.

export const DUSK_START = 17.5;
export const DUSK_END = 19.5;
export const DAWN_START = 5.5;
export const DAWN_END = 7;

export function smoothstep(a: number, b: number, x: number): number {
  const t = Math.min(1, Math.max(0, (x - a) / (b - a)));
  return t * t * (3 - 2 * t);
}

/** 0 = full day, 1 = full night, eased in between. `hour` is a float 0..24. */
export function nightness(hour: number): number {
  const h = ((hour % 24) + 24) % 24;
  if (h >= 12) return smoothstep(DUSK_START, DUSK_END, h);
  return 1 - smoothstep(DAWN_START, DAWN_END, h);
}

/** 0..1, peaks in the middle of dusk / dawn (warm golden tint). */
export function golden(hour: number): number {
  const n = nightness(hour);
  return 4 * n * (1 - n);
}

/** For icons and the UI theme: the sky reads as night (flips mid-dusk ~18:30, mid-dawn ~06:15). */
export function looksNight(hour: number): boolean {
  return nightness(hour) >= 0.5;
}

const lerp = (a: number, b: number, t: number) => a + (b - a) * t;
export function mixHex(a: string, b: string, t: number): string {
  const pa = parseInt(a.slice(1), 16);
  const pb = parseInt(b.slice(1), 16);
  const ch = (s: number) => Math.round(lerp((pa >> s) & 255, (pb >> s) & 255, t));
  return `#${((1 << 24) | (ch(16) << 16) | (ch(8) << 8) | ch(0)).toString(16).slice(1)}`;
}

/** Dev only: `?hour=18.75` (or `__daylight.set(18.75)`) pins the visual hour for checking dusk/dawn. */
export function devHourOverride(): number | null {
  if (!import.meta.env.DEV || typeof window === 'undefined') return null;
  const w = window as unknown as { __blHour?: number };
  if (typeof w.__blHour === 'number') return w.__blHour;
  const q = new URLSearchParams(window.location.search).get('hour');
  const v = q === null ? NaN : Number(q);
  return Number.isFinite(v) ? v : null;
}
