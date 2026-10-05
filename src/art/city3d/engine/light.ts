// R5: day/night for the city from the game clock (hour as a float). Builds on the home's light
// curve so the home and the city change at the same moments.
import { homeLight } from '../../home3d/engine/light';

export interface CityLight {
  hemiSky: string;
  hemiGround: string;
  hemi: number;
  sun: string;
  sunI: number;
  sunDir: [number, number, number];
  /** scene background + fog colour */
  sky: string;
  /** 0 = full day, 1 = full night (dusk/dawn in between) */
  dark: number;
  /** landmark window colour (glass by day, warm light at night) */
  glow: string;
  water: string;
  bulbs: string;
}

const lerp = (a: number, b: number, t: number) => a + (b - a) * t;
function mix(a: string, b: string, t: number): string {
  const pa = parseInt(a.slice(1), 16);
  const pb = parseInt(b.slice(1), 16);
  const ch = (s: number) => Math.round(lerp((pa >> s) & 255, (pb >> s) & 255, t));
  return `#${((1 << 24) | (ch(16) << 16) | (ch(8) << 8) | ch(0)).toString(16).slice(1)}`;
}

export function cityLight(hour: number): CityLight {
  const h = ((hour % 24) + 24) % 24;
  const base = homeLight(h);
  // darkness: 0 by day, ramps over dusk (17.5–20) and dawn (5–7)
  let dark = 0;
  if (h >= 20 || h < 5) dark = 1;
  else if (h >= 17.5) dark = (h - 17.5) / 2.5;
  else if (h < 7) dark = 1 - (h - 5) / 2;
  const dusk = h >= 16.5 && h < 20 ? 1 - Math.abs(h - 18.5) / 2 : h >= 5 && h < 7.5 ? 1 - Math.abs(h - 6.2) / 1.4 : 0;
  let sky = mix('#cfe5f1', '#16203f', dark);
  if (dusk > 0) sky = mix(sky, '#f0b48a', Math.max(0, dusk) * 0.5);
  return {
    hemiSky: base.hemiSky,
    hemiGround: base.hemiGround,
    hemi: lerp(1.6, 0.75, dark),
    sun: base.sun,
    sunI: lerp(2.0, 0.3, dark),
    sunDir: base.sunDir,
    sky,
    dark,
    glow: mix('#9db4c4', '#ffd27a', dark),
    water: mix('#3d8fb8', '#1d3558', dark),
    bulbs: mix('#d8d2c4', '#fff1c2', dark),
  };
}
