// Day/night lighting for the home from Benin time (hour as a float, 0..24).
// S1: continuous — every value eases with `nightness` (src/lib/daylight.ts: dusk 17:30-19:30, dawn
// 05:30-07:00, smoothstep) plus a warm golden tint mid-transition. Pure numbers, no three.js.
import { golden, mixHex, nightness } from '../../../lib/daylight';

export interface HomeLight {
  hemiSky: string;
  hemiGround: string;
  hemi: number;
  sun: string;
  sunI: number;
  /** Sun direction (unit-ish), from the scene centre towards the light. */
  sunDir: [number, number, number];
  /** Warm indoor lamp (point light) intensity. */
  lamp: number;
  /** Window glass colour and lamp-shade glow. */
  glass: string;
  glow: string;
  /** CSS background behind the transparent canvas. */
  bg: string;
  night: boolean;
  /** 0 = day, 1 = night (continuous). */
  dark: number;
  /** F1: the haze colour at the horizon (fog), matches the bottom of `bg`. */
  horizon: string;
}

const lerp = (a: number, b: number, t: number) => a + (b - a) * t;

const DAY = { hemiSky: '#f2f7ff', hemiGround: '#b7a58f', hemi: 1.55, sun: '#fff1dc', sunI: 2.1, lamp: 0, glass: '#bfe3f7', glow: '#f6e7c4' };
const DUSK = { hemiSky: '#ffd9b8', hemiGround: '#8a6a5a', hemi: 1.05, sun: '#ffb070', sunI: 1.25, lamp: 1.2, glass: '#f0a36c', glow: '#ffd27a' };
const NIGHT = { hemiSky: '#7d8cc4', hemiGround: '#433d5c', hemi: 0.9, sun: '#9fb4ff', sunI: 0.4, lamp: 3.2, glass: '#1c2a52', glow: '#ffcf6b' };

type P = typeof DAY;
function blend(a: P, b: P, t: number): P {
  return {
    hemiSky: mixHex(a.hemiSky, b.hemiSky, t),
    hemiGround: mixHex(a.hemiGround, b.hemiGround, t),
    hemi: lerp(a.hemi, b.hemi, t),
    sun: mixHex(a.sun, b.sun, t),
    sunI: lerp(a.sunI, b.sunI, t),
    lamp: lerp(a.lamp, b.lamp, t),
    glass: mixHex(a.glass, b.glass, t),
    glow: mixHex(a.glow, b.glow, t),
  };
}

// sky gradient stops (top, middle, bottom) for day, golden hour and night
const BG_DAY = ['#bcdcf5', '#dcecf8', '#eef4fa'];
const BG_GOLD = ['#f7c9a0', '#f3dcc4', '#e9e6ea'];
const BG_NIGHT = ['#121a3a', '#24315e', '#34406e'];

export function homeLight(hour: number): HomeLight {
  const h = ((hour % 24) + 24) % 24;
  const n = nightness(h);
  const g = golden(h);
  const p = blend(blend(DAY, NIGHT, n), DUSK, g * 0.85);
  // sun arcs east (morning, +x) to west (evening, -x); it eases into the moon, high in the south-east
  const dayT = Math.min(1, Math.max(0, (h - 6) / 13));
  const ang = dayT * Math.PI;
  const sun: [number, number, number] = [Math.cos(ang) * 0.9, 0.45 + Math.sin(ang), 0.75];
  const moon: [number, number, number] = [0.5, 1, 0.8];
  const sunDir: [number, number, number] = [lerp(sun[0], moon[0], n), lerp(sun[1], moon[1], n), lerp(sun[2], moon[2], n)];
  const stop = (i: number) => mixHex(mixHex(BG_DAY[i], BG_NIGHT[i], n), BG_GOLD[i], g * 0.9);
  const bg = `linear-gradient(180deg, ${stop(0)} 0%, ${stop(1)} 50%, ${stop(2)} 100%)`;
  return { ...p, sunDir, bg, night: n >= 0.5, dark: n, horizon: mixHex(stop(2), stop(1), 0.35) };
}
