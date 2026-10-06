// R5: data for the 3D city (no three.js here, so the game chunk can import it cheaply).
// Layout comes from the same map-space data as the 2D map (src/art/map/mapGeo.ts, docs/MAP_GEO.md):
// map space is 1000×1000, north up, King's Square at (500,500). The 3D world uses x = east, z = south,
// y = up, with 1 world unit = 10 map units.
import type { Location, SceneType } from '../../lib/types';
import { isNightRisky, PIN_META, shortName } from '../map/mapGeo';

export { isNightRisky, shortName };

/** World units per map unit. */
export const WS = 0.1;
export const toWorld = (mx: number, my: number): [number, number] => [(mx - 500) * WS, (my - 500) * WS];
export const toMap = (wx: number, wz: number): [number, number] => [wx / WS + 500, wz / WS + 500];

/** Emoji shown on each place pill, by scene. */
export const SCENE_EMOJI: Record<SceneType, string> = {
  market: '🧺',
  hospital: '🏥',
  campus: '🎓',
  palace: '👑',
  museum: '🏛️',
  club: '🎶',
  bank: '🏦',
  police: '🚓',
  motorpark: '🚌',
  street: '🛣️',
  pos: '💳',
  home_face_me: '🏠',
  home_flat: '🏢',
  home_duplex: '🏡',
  farm: '🌾',
  airport: '✈️',
  shrine: '🪔',
  workshop: '⚒️',
  buka: '🍲',
  salon: '💈',
  cyber: '💻',
  office: '💼',
  mall: '🛒',
  cinema: '🎬',
  hotel: '🏨',
  zoo: '🦁',
  stadium: '🏟️',
  monument: '🗽',
  car_dealer: '🚘',
};

/** A few places get a more specific emoji than their scene's. */
const ID_EMOJI: Record<string, string> = {
  uniben_hostel: '🛏️',
  bronze_tech_hub: '🚀',
  igun_street: '🔥',
  ring_road_pos: '💳',
  third_east: '🛣️',
  mama_ebo: '🌶️',
  rome_club: '🪩',
  versus_lounge: '🍸',
};

export const placeEmoji = (l: Pick<Location, 'id' | 'scene'>) => ID_EMOJI[l.id] ?? SCENE_EMOJI[l.scene] ?? '📍';

/** 1 = landmark (label shows from far away), 2 = local place (label shows when zoomed in). */
export const placeTier = (id: string): 1 | 2 => PIN_META[id]?.tier ?? 2;

export type CityFilter = 'goslow' | 'neighbours' | 'danger' | 'markets' | 'gov';

export const FILTERS: { id: CityFilter; label: string; emoji: string }[] = [
  { id: 'goslow', label: 'Go-slow', emoji: '🔴' },
  { id: 'neighbours', label: 'Neighbours', emoji: '🏘️' },
  { id: 'danger', label: 'Danger zones', emoji: '⚠️' },
  { id: 'markets', label: 'Markets', emoji: '🧺' },
  { id: 'gov', label: 'Gov & services', emoji: '🏛️' },
];

/** Congestion at or above this counts as a go-slow (Ramat Park 2.2, Uselu 1.6, the PoS lines 1.5). */
export const GO_SLOW_MIN = 1.5;

/** Does a place match a filter? `crowd` is players per place (when the game has it). */
export function matchesFilter(f: CityFilter, l: Location, crowd?: Record<string, number>): boolean {
  switch (f) {
    case 'goslow':
      return l.congestion >= GO_SLOW_MIN;
    case 'neighbours':
      return (crowd?.[l.id] ?? 0) > 0;
    case 'danger':
      return isNightRisky(l);
    case 'markets':
      return l.scene === 'market';
    case 'gov':
      return l.scene === 'police' || l.scene === 'hospital' || l.scene === 'bank';
  }
}

export const FILTER_COLOR: Record<CityFilter, string> = {
  goslow: '#e5484d',
  neighbours: '#2f8cff',
  danger: '#e5484d',
  markets: '#f2a516',
  gov: '#1f9d63',
};

/** Yellow "Coming soon" pills: features that arrive later, pinned where they will live. */
export const COMING_SOON: { id: string; x: number; y: number; emoji: string; label: string; note: string }[] = [
  {
    id: 'airport_link',
    x: 300,
    y: 655,
    emoji: '✈️',
    label: 'Airport link',
    note: 'Fly to Lagos and Abuja from Benin Airport. Coming soon.',
  },
];

/** Green road signs at the edges (same as the 2D map's exits). */
export const EXIT_SIGNS: { text: string; sub: string; x: number; y: number; arrow: string }[] = [
  { text: 'LAGOS', sub: 'via Oluku', x: 345, y: 8, arrow: '↑' },
  { text: 'AUCHI', sub: 'via Aduwawa', x: 960, y: 300, arrow: '→' },
  { text: 'AGBOR', sub: 'Asaba', x: 960, y: 488, arrow: '→' },
  { text: 'SAPELE', sub: 'Warri', x: 590, y: 975, arrow: '↓' },
  { text: 'FARMS', sub: 'Iguobazuwa', x: 60, y: 238, arrow: '←' },
];

/** District names on the ground (map space). Road names come from ROADS (mapGeo) since S3. */
export const DISTRICT_NAMES: { t: string; x: number; y: number }[] = [
  { t: 'OREDO', x: 560, y: 540 },
  { t: 'G.R.A.', x: 400, y: 715 },
  { t: 'UGBOWO', x: 560, y: 70 },
  { t: 'USELU', x: 395, y: 250 },
  { t: 'NEW BENIN', x: 650, y: 255 },
  { t: 'IKPOBA HILL', x: 780, y: 520 },
  { t: 'ADUWAWA', x: 880, y: 280 },
  { t: 'SAKPONBA', x: 625, y: 690 },
  { t: 'UPPER SAKPONBA', x: 790, y: 770 },
  { t: 'SILUKO', x: 290, y: 395 },
  { t: 'EKENWAN', x: 170, y: 560 },
  { t: 'OLUKU', x: 300, y: 80 },
];

/** Can this device draw WebGL at all? (Otherwise the lite 2D map is the only map.) */
export function webglAvailable(): boolean {
  try {
    const c = document.createElement('canvas');
    const gl = c.getContext('webgl2') || c.getContext('webgl');
    if (!gl) return false;
    (gl as WebGLRenderingContext).getExtension('WEBGL_lose_context')?.loseContext();
    return true;
  } catch {
    return false;
  }
}
