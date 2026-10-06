// F1 light rig + palette per place type (docs/FEEL_PLAN.md "Mood lighting per place"). Pure numbers.
// club = dark, coloured pools, LED strips, slow colour cycle; buka = warm tungsten; bank/hospital = cool
// fluorescent (with a flicker); market = sun patches + tarp shade; LAPO home = one yellow bulb; Nepo home
// = warm POP downlights. Everything still follows the time of day (homeLight / daylight.ts).

export interface Rig {
  /** Hemisphere (ambient) multiplier: < 1 = darker corners and more contrast. */
  ambient: number;
  /** Hemisphere sky tint mixed in indoors (the colour of the room light). */
  tint: string;
  tintMix: number;
  /** The point lamp colour + intensity by day / night. */
  lamp: string;
  lampDay: number;
  lampNight: number;
  /** Light pools / beams: colour + gain by day / night. */
  pool: string;
  poolDay: number;
  poolNight: number;
  /** Club: slow hue cycle + sweep on pools and LED strips. */
  cycle: boolean;
  /** Fluorescent tubes: an occasional flicker. */
  flicker: boolean;
  fan: boolean;
  steam: boolean;
  /** Tone-mapping exposure (ACES). */
  exposure: number;
}

const BASE: Rig = {
  ambient: 0.85, tint: '#fff1dc', tintMix: 0.2, lamp: '#ffcf8a', lampDay: 0.9, lampNight: 2.4,
  pool: '#ffd9a0', poolDay: 0.25, poolNight: 0.8, cycle: false, flicker: false, fan: false, steam: false, exposure: 1.3,
};
const COOL: Rig = { ...BASE, tint: '#e6f4ff', tintMix: 0.35, lamp: '#e8f4ff', lampDay: 1.1, lampNight: 2.2, pool: '#d8f0ff', poolDay: 0.35, poolNight: 0.7, flicker: true, fan: true, exposure: 1.25 };
const WARM: Rig = { ...BASE, tint: '#ffd9a8', tintMix: 0.35, lamp: '#ffc070', lampDay: 1, lampNight: 2.8, pool: '#ffc27a', poolDay: 0.35, poolNight: 0.95, fan: true, exposure: 1.3 };
const OUT: Rig = { ...BASE, ambient: 0.95, tintMix: 0, lampDay: 0, lampNight: 0.8, pool: '#ffe6b0', poolDay: 0.22, poolNight: 0.1, exposure: 1.25 };

export const RIGS: Record<string, Rig> = {
  club: { ...BASE, ambient: 0.66, tint: '#7a5cff', tintMix: 0.45, lamp: '#ff6fc8', lampDay: 0.6, lampNight: 2.6, pool: '#ffffff', poolDay: 0.7, poolNight: 1.25, cycle: true, exposure: 1.5 },
  lounge: { ...BASE, ambient: 0.6, tint: '#7a5cff', tintMix: 0.4, lamp: '#ff6fc8', pool: '#ffffff', poolDay: 0.6, poolNight: 1.1, cycle: true, exposure: 1.4 },
  buka: { ...WARM, steam: true },
  restaurant: { ...WARM, steam: true },
  bank: COOL,
  hospital: COOL,
  police: { ...COOL, tint: '#e9eef7' },
  campus: COOL,
  cyber: { ...COOL, fan: false },
  tech: { ...COOL, fan: false, flicker: false },
  salon: { ...WARM, steam: false },
  market: OUT,
  motorpark: OUT,
  street: OUT,
  pos: OUT,
  home_lapo: { ...BASE, ambient: 0.78, tint: '#ffe0a0', tintMix: 0.25, lamp: '#ffc25c', lampDay: 0.4, lampNight: 3.0, pool: '#ffcf6b', poolDay: 0, poolNight: 0.8, fan: true, exposure: 1.3 },
  home_nepo: { ...BASE, ambient: 0.9, tint: '#fff0dc', tintMix: 0.2, lamp: '#ffd9a8', lampDay: 0.6, lampNight: 2.6, pool: '#ffe2b8', poolDay: 0.05, poolNight: 0.85, exposure: 1.25 },
};

export function rigFor(scene: string, outdoor: boolean): Rig {
  return RIGS[scene] ?? (outdoor ? OUT : BASE);
}
