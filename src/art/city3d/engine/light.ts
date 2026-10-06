// R5: day/night for the city from Benin time (hour as a float). Builds on the home's light curve so
// the home and the city change at the same moments. S1: continuous (no snapping), see src/lib/daylight.ts.
import { golden, mixHex as mix } from '../../../lib/daylight';
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
export function cityLight(hour: number): CityLight {
  const h = ((hour % 24) + 24) % 24;
  const base = homeLight(h);
  // darkness: 0 by day, eases over dusk (17:30-19:30) and dawn (05:30-07:00)
  const dark = base.dark;
  const dusk = golden(h);
  let sky = mix('#cfe5f1', '#16203f', dark);
  if (dusk > 0) sky = mix(sky, '#f0b48a', Math.max(0, dusk) * 0.5);
  return {
    hemiSky: mix(base.hemiSky, '#8fa2e0', dark * 0.5),
    hemiGround: base.hemiGround,
    hemi: lerp(1.6, 1.05, dark),
    sun: base.sun,
    sunI: lerp(2.0, 0.45, dark),
    sunDir: base.sunDir,
    sky,
    dark,
    glow: mix('#9db4c4', '#ffd27a', dark),
    water: mix('#3d8fb8', '#1d3558', dark),
    bulbs: mix('#d8d2c4', '#fff1c2', dark),
  };
}
