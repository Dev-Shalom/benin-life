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

// P1: everything toned down to a soft, subtle ambience (pools ~half, softer beams, gentler club cycle,
// lamps a notch lower, more even ambient so faces read). Each place keeps its mood.
const BASE: Rig = {
  ambient: 0.9, tint: '#fff1dc', tintMix: 0.14, lamp: '#ffcf8a', lampDay: 0.8, lampNight: 1.8,
  pool: '#ffd9a0', poolDay: 0.1, poolNight: 0.3, cycle: false, flicker: false, fan: false, steam: false, exposure: 1.25,
};
const COOL: Rig = { ...BASE, tint: '#e6f4ff', tintMix: 0.22, lamp: '#e8f4ff', lampDay: 0.95, lampNight: 1.7, pool: '#d8f0ff', poolDay: 0.12, poolNight: 0.28, flicker: true, fan: true, exposure: 1.22 };
const WARM: Rig = { ...BASE, tint: '#ffd9a8', tintMix: 0.24, lamp: '#ffc070', lampDay: 0.9, lampNight: 2.0, pool: '#ffc27a', poolDay: 0.13, poolNight: 0.36, fan: true, exposure: 1.25 };
const OUT: Rig = { ...BASE, ambient: 0.97, tintMix: 0, lampDay: 0, lampNight: 0.6, pool: '#ffe6b0', poolDay: 0.09, poolNight: 0.05, exposure: 1.22 };

export const RIGS: Record<string, Rig> = {
  club: { ...BASE, ambient: 0.78, tint: '#7a66d8', tintMix: 0.3, lamp: '#f08ac8', lampDay: 0.5, lampNight: 1.6, pool: '#ffffff', poolDay: 0.3, poolNight: 0.55, cycle: true, exposure: 1.35 },
  lounge: { ...BASE, ambient: 0.75, tint: '#7a66d8', tintMix: 0.28, lamp: '#f08ac8', pool: '#ffffff', poolDay: 0.28, poolNight: 0.5, cycle: true, exposure: 1.3 },
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
  home_lapo: { ...BASE, ambient: 0.84, tint: '#ffe0a0', tintMix: 0.18, lamp: '#ffc25c', lampDay: 0.35, lampNight: 2.1, pool: '#ffcf6b', poolDay: 0, poolNight: 0.36, fan: true, exposure: 1.25 },
  home_nepo: { ...BASE, ambient: 0.92, tint: '#fff0dc', tintMix: 0.14, lamp: '#ffd9a8', lampDay: 0.5, lampNight: 1.9, pool: '#ffe2b8', poolDay: 0.03, poolNight: 0.38, exposure: 1.22 },
};

export function rigFor(scene: string, outdoor: boolean): Rig {
  return RIGS[scene] ?? (outdoor ? OUT : BASE);
}
