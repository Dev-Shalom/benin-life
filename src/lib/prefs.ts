// Per-device preferences (R4): sound, music, mute, lite map, clean screen. Stored in localStorage
// (every access in try/catch: private mode, blocked storage). src/lib/sound.ts (S1) reads mute/sfx/music;
// R5's lite map reads liteMap.
import { create } from 'zustand';

export type ThemeChoice = 'light' | 'dark' | 'system';

export interface Prefs {
  /** Appearance: Light (default), Dark, or follow the phone (prefers-color-scheme). docs/THEME.md */
  theme: ThemeChoice;
  /** Master mute (the speaker in the HUD pill). */
  muted: boolean;
  sfx: boolean;
  music: boolean;
  /** Use the light 2D map instead of the 3D city (R5 reads this; also auto on slow networks). */
  liteMap: boolean;
  /** Hide HUD chrome (wish chips, needs, dock) for a clean look at the home. */
  clean: boolean;
  /** F1: 3D quality. auto = detect (src/art/feel/quality.ts). */
  graphics: 'auto' | 'low' | 'high';
  /** Keep the player's own music (Spotify etc.) playing: the game starts no media element and no game music on its own. */
  keepOwnMusic: boolean;
  /** Show the 3D drive scene while travelling (off = the old instant travel). docs/DRIVE.md */
  driveScene: boolean;
}

const KEY = 'bl.prefs.v1';
const DEFAULTS: Prefs = { theme: 'light', muted: false, sfx: true, music: true, liteMap: false, clean: false, graphics: 'auto', keepOwnMusic: true, driveScene: true };

function load(): Prefs {
  try {
    const raw = localStorage.getItem(KEY);
    if (!raw) return { ...DEFAULTS };
    const v = JSON.parse(raw) as Partial<Prefs>;
    return {
      theme: v.theme === 'dark' || v.theme === 'system' ? v.theme : 'light',
      muted: typeof v.muted === 'boolean' ? v.muted : DEFAULTS.muted,
      sfx: typeof v.sfx === 'boolean' ? v.sfx : DEFAULTS.sfx,
      music: typeof v.music === 'boolean' ? v.music : DEFAULTS.music,
      liteMap: typeof v.liteMap === 'boolean' ? v.liteMap : DEFAULTS.liteMap,
      clean: typeof v.clean === 'boolean' ? v.clean : DEFAULTS.clean,
      graphics: v.graphics === 'low' || v.graphics === 'high' ? v.graphics : 'auto',
      // older saved prefs have no key: default ON, their Music / SFX choices stay as they were
      keepOwnMusic: typeof v.keepOwnMusic === 'boolean' ? v.keepOwnMusic : DEFAULTS.keepOwnMusic,
      driveScene: typeof v.driveScene === 'boolean' ? v.driveScene : DEFAULTS.driveScene,
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
  toggle: (k: Exclude<keyof Prefs, 'graphics' | 'theme'>) => void;
}

export const usePrefs = create<PrefsStore>((set, get) => ({
  ...load(),
  set: (patch) => {
    set(patch);
    const { theme, muted, sfx, music, liteMap, clean, graphics, keepOwnMusic, driveScene } = get();
    save({ theme, muted, sfx, music, liteMap, clean, graphics, keepOwnMusic, driveScene });
  },
  toggle: (k) => get().set({ [k]: !get()[k] } as Partial<Prefs>),
}));

/** True when this device has a saved Light / Dark / Match my phone choice. Without one, the marketing pages follow the phone (docs/FRONTEND.md). */
export function hasStoredTheme(): boolean {
  try {
    const v = JSON.parse(localStorage.getItem(KEY) || '{}') as Partial<Prefs> | null;
    return v?.theme === 'light' || v?.theme === 'dark' || v?.theme === 'system';
  } catch {
    return false;
  }
}

/** True on very slow or data-saver connections (navigator.connection), for R5's automatic lite map. */
export function isSlowNetwork(): boolean {
  try {
    const c = (navigator as unknown as { connection?: { effectiveType?: string; saveData?: boolean } }).connection;
    return Boolean(c && (c.saveData || c.effectiveType === 'slow-2g' || c.effectiveType === '2g'));
  } catch {
    return false;
  }
}
