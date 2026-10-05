// Per-device preferences (R4): sound, music, mute, lite map, clean screen. Stored in localStorage
// (every access in try/catch: private mode, blocked storage). There is no audio yet; these only
// remember the player's choice so the sound work and R5's lite map can read them.
import { create } from 'zustand';

export interface Prefs {
  /** Master mute (the speaker in the HUD pill). */
  muted: boolean;
  sfx: boolean;
  music: boolean;
  /** Use the light 2D map instead of the 3D city (R5 reads this; also auto on slow networks). */
  liteMap: boolean;
  /** Hide HUD chrome (wish chips, needs, dock) for a clean look at the home. */
  clean: boolean;
}

const KEY = 'bl.prefs.v1';
const DEFAULTS: Prefs = { muted: false, sfx: true, music: false, liteMap: false, clean: false };

function load(): Prefs {
  try {
    const raw = localStorage.getItem(KEY);
    if (!raw) return { ...DEFAULTS };
    const v = JSON.parse(raw) as Partial<Prefs>;
    return {
      muted: typeof v.muted === 'boolean' ? v.muted : DEFAULTS.muted,
      sfx: typeof v.sfx === 'boolean' ? v.sfx : DEFAULTS.sfx,
      music: typeof v.music === 'boolean' ? v.music : DEFAULTS.music,
      liteMap: typeof v.liteMap === 'boolean' ? v.liteMap : DEFAULTS.liteMap,
      clean: typeof v.clean === 'boolean' ? v.clean : DEFAULTS.clean,
    };
  } catch {
    return { ...DEFAULTS };
  }
}

function save(p: Prefs) {
  try {
    localStorage.setItem(KEY, JSON.stringify(p));
  } catch {
    /* storage blocked: keep it for this session only */
  }
}

interface PrefsStore extends Prefs {
  set: (patch: Partial<Prefs>) => void;
  toggle: (k: keyof Prefs) => void;
}

export const usePrefs = create<PrefsStore>((set, get) => ({
  ...load(),
  set: (patch) => {
    set(patch);
    const { muted, sfx, music, liteMap, clean } = get();
    save({ muted, sfx, music, liteMap, clean });
  },
  toggle: (k) => get().set({ [k]: !get()[k] } as Partial<Prefs>),
}));

/** True on very slow or data-saver connections (navigator.connection), for R5's automatic lite map. */
export function isSlowNetwork(): boolean {
  try {
    const c = (navigator as unknown as { connection?: { effectiveType?: string; saveData?: boolean } }).connection;
    return Boolean(c && (c.saveData || c.effectiveType === 'slow-2g' || c.effectiveType === '2g'));
  } catch {
    return false;
  }
}
