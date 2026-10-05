// Day/night lighting for the home from the game clock (hour as a float, 0..24).
// Phases: night (<5), dawn (5-7), day, dusk (17.5-20), night (>20). Pure numbers, no three.js.

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
}

const lerp = (a: number, b: number, t: number) => a + (b - a) * t;
function mixHex(a: string, b: string, t: number): string {
  const pa = parseInt(a.slice(1), 16);
  const pb = parseInt(b.slice(1), 16);
  const ch = (s: number) => Math.round(lerp((pa >> s) & 255, (pb >> s) & 255, t));
  return `#${((1 << 24) | (ch(16) << 16) | (ch(8) << 8) | ch(0)).toString(16).slice(1)}`;
}

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

export function homeLight(hour: number): HomeLight {
  const h = ((hour % 24) + 24) % 24;
  let p: P;
  if (h < 5) p = NIGHT;
  else if (h < 6) p = blend(NIGHT, DUSK, h - 5);
  else if (h < 7.5) p = blend(DUSK, DAY, (h - 6) / 1.5);
  else if (h < 17.5) p = DAY;
  else if (h < 19) p = blend(DAY, DUSK, (h - 17.5) / 1.5);
  else if (h < 20.5) p = blend(DUSK, NIGHT, (h - 19) / 1.5);
  else p = NIGHT;
  // sun arcs east (morning, +x) to west (evening, -x); at night it is the moon, high in the south-east
  const dayT = Math.min(1, Math.max(0, (h - 6) / 13));
  const ang = dayT * Math.PI;
  const night = h >= 20 || h < 6;
  const sunDir: [number, number, number] = night ? [0.5, 1, 0.8] : [Math.cos(ang) * 0.9, 0.45 + Math.sin(ang), 0.75];
  const bg = night
    ? 'linear-gradient(180deg, #121a3a 0%, #24315e 55%, #34406e 100%)'
    : h < 7.5 || h >= 17.5
      ? 'linear-gradient(180deg, #f7c9a0 0%, #f3dcc4 45%, #e9e6ea 100%)'
      : 'linear-gradient(180deg, #bcdcf5 0%, #dcecf8 50%, #eef4fa 100%)';
  return { ...p, sunDir, bg, night };
}
