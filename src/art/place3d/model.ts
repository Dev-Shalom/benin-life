// L2 place interiors (docs/PLACES.md): data for the 3D interior, no three.js here (the game chunk imports it).
// The server sends zones (place_zones) with a centre, size and prop; everything else is derived:
//   * the room is sized from the zones (plus a margin and an entrance strip at the front),
//   * the kit (indoor hall / outdoor yard, colours, sign, lamps) comes from the place type,
//   * each zone has a spot where the Sim stands to use it, and a pose (stand / sit / dance / lie / swim),
//   * the walk grid blocks solid props (M1 pathing in ../sim/nav.ts),
//   * background people per zone follow the type's busy curve over the day (render cap crowd.max_visible).
import type { NpcMotion, PlaceNpc, PlaceZone } from '../../api/places';
import type { AvatarConfig, SceneType } from '../../lib/types';
import { applyPreset, normalizeAvatar, skinTone } from '../avatar3d/catalog';
import { blockRect, makeGrid, type NavGrid, type P2 } from '../sim/nav';

export type KitKind = 'indoor' | 'outdoor';

export interface Kit {
  kind: KitKind;
  floor: string;
  floorAlt?: string;
  /** Tile size for the checker (m). */
  tile?: number;
  wall: string;
  wallTop?: string;
  trim: string;
  /** Sign board colours. */
  signBg: string;
  signInk: string;
  /** Indoor: keep the lights on at night (0..1 how much darker it may get). */
  dimAtNight: number;
  /** Party lights (clubs): coloured glow on the dance floor, darker ambient. */
  party?: boolean;
  wallH: number;
}

const HALL: Kit = { kind: 'indoor', floor: '#d9d2c4', floorAlt: '#cfc6b5', tile: 1, wall: '#efe7d8', trim: '#b0793a', signBg: '#1f7a3f', signInk: '#ffffff', dimAtNight: 0.35, wallH: 2.6 };
const YARD: Kit = { kind: 'outdoor', floor: '#c49a6c', floorAlt: '#b98a5e', tile: 2, wall: '#c9c2b6', trim: '#8a5a33', signBg: '#d2342a', signInk: '#ffffff', dimAtNight: 1, wallH: 0.6 };

/** Kit per place type. Unknown types get the plain hall. */
export const KITS: Record<string, Kit> = {
  market: { ...YARD, floor: '#b98a5e', floorAlt: '#ad7e52', signBg: '#d2342a' },
  motorpark: { ...YARD, floor: '#8f8a84', floorAlt: '#85807a', signBg: '#1f7a3f' },
  street: { ...YARD, floor: '#7d7974', floorAlt: '#75716c', signBg: '#d9a441', signInk: '#2a160d' },
  pos: { ...YARD, floor: '#9a948c', floorAlt: '#8f8981', signBg: '#0b625a' },
  zoo: { ...YARD, floor: '#9fbf6e', floorAlt: '#95b565', tile: 3, wall: '#8a6a44', signBg: '#3f6e1c' },
  stadium: { ...YARD, floor: '#8e8a82', floorAlt: '#86827a', wall: '#d8d2c6', signBg: '#125a38' },
  monument: { ...YARD, floor: '#d8ccb6', floorAlt: '#cdbfa7', tile: 1.5, wall: '#b8ab95', signBg: '#6e4f26' },
  farm: { ...YARD, floor: '#8a6a44', floorAlt: '#7f6040', tile: 3, signBg: '#3a7420' },
  palace: { ...YARD, floor: '#c9a37a', floorAlt: '#bf9870', wall: '#b5552b', trim: '#7c3216', signBg: '#7c3216', signInk: '#f3d28a', wallH: 1.4 },
  car_dealer: { ...HALL, floor: '#e9edf0', floorAlt: '#dde3e8', tile: 1.5, wall: '#f4f6f8', trim: '#2c3540', signBg: '#2c3540', signInk: '#f3cf5e' },
  club: { ...HALL, floor: '#2a2438', floorAlt: '#241f31', wall: '#3a2f52', wallTop: '#2a2240', trim: '#d9a441', signBg: '#0b0c22', signInk: '#f3d28a', dimAtNight: 0, party: true },
  buka: { ...HALL, floor: '#c7b49a', floorAlt: '#bba78c', wall: '#f1d9a8', trim: '#a8361a', signBg: '#a8361a', dimAtNight: 0.25 },
  bank: { ...HALL, floor: '#e8e4dc', floorAlt: '#dcd6cb', tile: 1.2, wall: '#f6f3ee', trim: '#13512a', signBg: '#13512a' },
  hospital: { ...HALL, floor: '#e6eef0', floorAlt: '#dbe6e9', wall: '#f7fbfb', trim: '#b0202d', signBg: '#b0202d' },
  campus: { ...HALL, floor: '#d6cdbd', floorAlt: '#ccc2b0', wall: '#ede5d4', trim: '#224c92', signBg: '#224c92' },
  police: { ...HALL, floor: '#cfd3d8', floorAlt: '#c4c9cf', wall: '#e6ebf2', trim: '#1a285c', signBg: '#1a285c' },
  museum: { ...HALL, floor: '#d8c9ad', floorAlt: '#cdbd9f', wall: '#efe4cf', trim: '#74461c', signBg: '#74461c', signInk: '#fff6dc' },
  office: { ...HALL, floor: '#dfe4e8', floorAlt: '#d4dadf', wall: '#f4f7f9', trim: '#155a78', signBg: '#155a78' },
  cyber: { ...HALL, floor: '#cfd2dc', floorAlt: '#c4c8d3', wall: '#e8eaf2', trim: '#252886', signBg: '#252886' },
  shrine: { ...HALL, floor: '#a8754e', floorAlt: '#9c6b45', wall: '#c4552f', trim: '#4a0f1c', signBg: '#4a0f1c', signInk: '#f3d28a', dimAtNight: 0.5 },
  salon: { ...HALL, floor: '#e9dcdc', floorAlt: '#e0d0d0', wall: '#fbeef3', trim: '#a02c68', signBg: '#a02c68' },
  workshop: { ...HALL, floor: '#9a8a78', floorAlt: '#907f6d', wall: '#c9b8a0', trim: '#6a4116', signBg: '#6a4116', dimAtNight: 0.4 },
  airport: { ...HALL, floor: '#e3e7ea', floorAlt: '#d8dde1', tile: 1.5, wall: '#f4f7f9', trim: '#1c6a9a', signBg: '#1c6a9a' },
  mall: { ...HALL, floor: '#ecebe7', floorAlt: '#e2e0da', tile: 1.5, wall: '#f7f6f2', trim: '#a3182f', signBg: '#a3182f', dimAtNight: 0.2 },
  cinema: { ...HALL, floor: '#3a2f3f', floorAlt: '#332938', wall: '#4a2f3a', trim: '#f3d28a', signBg: '#151832', signInk: '#f3d28a', dimAtNight: 0 },
  hotel: { ...HALL, floor: '#e8dcc6', floorAlt: '#dccfb6', tile: 1.2, wall: '#f6efe2', trim: '#1d5874', signBg: '#1d5874', signInk: '#f3d28a', dimAtNight: 0.25 },
  home_face_me: { ...YARD, floor: '#b98a5e' },
  home_flat: { ...HALL },
  home_duplex: { ...HALL, floor: '#e8dcc6' },
};
export const kitFor = (scene: SceneType | string): Kit => KITS[scene] ?? HALL;

/** How the Sim uses a zone's prop. */
export type ZonePose = 'stand' | 'sit' | 'dance' | 'lie' | 'swim';

interface PropMeta {
  /** Blocks walking (the Sim stands at its front). */
  solid: boolean;
  /** Where the Sim stands: in front of it, or in the middle (walk-on zones). */
  spot: 'front' | 'centre';
  pose: ZonePose;
  /** Tap box height. */
  h: number;
}

const P = (solid: boolean, spot: 'front' | 'centre', pose: ZonePose = 'stand', h = 1.1): PropMeta => ({ solid, spot, pose, h });

export const PROPS: Record<string, PropMeta> = {
  stall: P(true, 'front', 'stand', 1.9),
  food_stall: P(true, 'front', 'stand', 1.9),
  crates: P(true, 'front'),
  restroom: P(true, 'front', 'stand', 2),
  counter: P(true, 'front', 'stand', 1.2),
  tables: P(false, 'centre', 'sit', 0.9),
  tv_screen: P(true, 'front', 'stand', 1.8),
  bar: P(true, 'front', 'stand', 1.3),
  dance_floor: P(false, 'centre', 'dance', 0.3),
  dj_booth: P(true, 'front', 'dance', 1.4),
  vip: P(false, 'centre', 'sit', 1),
  bank_counter: P(true, 'front', 'stand', 1.4),
  atm: P(true, 'front', 'stand', 1.8),
  seats: P(false, 'centre', 'sit', 0.9),
  shelves: P(true, 'front', 'stand', 1.9),
  beds: P(false, 'centre', 'lie', 0.8),
  desk: P(true, 'front', 'stand', 1.1),
  lecture: P(false, 'centre', 'sit', 1),
  trees: P(false, 'centre', 'sit', 0.6),
  bus: P(true, 'front', 'stand', 2.2),
  keke: P(true, 'front', 'stand', 1.6),
  grill: P(true, 'front', 'stand', 1.2),
  kiosk: P(true, 'front', 'stand', 2),
  bench: P(false, 'centre', 'sit', 0.8),
  board: P(true, 'front', 'stand', 1.8),
  gate: P(true, 'front', 'stand', 2.2),
  courtyard: P(false, 'centre', 'stand', 0.3),
  display: P(true, 'front', 'stand', 1.6),
  pedestals: P(false, 'centre', 'stand', 1.4),
  desks: P(false, 'centre', 'sit', 1),
  stage: P(true, 'front', 'stand', 1),
  altar: P(true, 'front', 'stand', 1.6),
  salon_chairs: P(false, 'centre', 'sit', 1.2),
  furnace: P(true, 'front', 'stand', 1.4),
  crops: P(false, 'centre', 'stand', 0.7),
  shed: P(true, 'front', 'stand', 2.2),
  aisles: P(false, 'centre', 'stand', 1.8),
  checkout: P(true, 'front', 'stand', 1.1),
  cinema_door: P(true, 'front', 'stand', 2.2),
  planters: P(false, 'centre', 'stand', 0.8),
  cinema_hall: P(false, 'centre', 'sit', 1.6),
  arcade: P(true, 'front', 'stand', 1.7),
  pool: P(false, 'centre', 'swim', 0.4),
  bed_lux: P(false, 'centre', 'lie', 0.9),
  cage: P(true, 'front', 'stand', 2),
  pen: P(true, 'front', 'stand', 1.2),
  stands: P(false, 'centre', 'sit', 1.6),
  pitch: P(false, 'centre', 'stand', 0.2),
  statue: P(true, 'front', 'stand', 3),
  cars: P(false, 'centre', 'stand', 1.4),
  lux_cars: P(true, 'front', 'stand', 1.5),
  car_lot: P(true, 'front', 'stand', 1.4),
  lane: P(false, 'centre', 'stand', 0.3),
  none: P(false, 'centre', 'stand', 0.5),
};
export const propMeta = (prop: string): PropMeta => PROPS[prop] ?? PROPS.none;

export interface Room {
  /** Width (x) and depth (z) in metres; the front (z = D) is the camera side, with the entrance strip. */
  W: number;
  D: number;
  /** Where the Sim walks in. */
  entry: P2;
  kit: Kit;
}

/** Size the room from the zones: every zone fits with a 1.2 m margin, plus a 1.8 m entrance strip at the front. */
export function roomFor(scene: SceneType | string, zones: PlaceZone[]): Room {
  let maxX = 9;
  let maxZ = 7;
  for (const z of zones) {
    maxX = Math.max(maxX, z.x + z.w / 2);
    maxZ = Math.max(maxZ, z.z + z.d / 2);
  }
  const W = Math.ceil((maxX + 1.2) * 2) / 2;
  const D = Math.ceil((maxZ + 1.8) * 2) / 2;
  return { W, D, entry: [W / 2, D - 0.5], kit: kitFor(scene) };
}

/** Facing of a zone's front: rot quarter turns, 0 = towards the camera (+z), 1 = +x, 2 = -z (back), 3 = -x. */
export function frontDir(rot: number): P2 {
  const r = ((rot % 4) + 4) % 4;
  return r === 0 ? [0, 1] : r === 1 ? [1, 0] : r === 2 ? [0, -1] : [-1, 0];
}

/** Where the Sim stands to use a zone, and which way it faces (yaw: 0 = looking towards +z). */
export function zoneSpot(z: PlaceZone, room: Room): { p: P2; yaw: number } {
  const m = propMeta(z.prop);
  if (m.spot === 'centre') {
    // walk-on zones: a little in front of the middle, facing into the room's back
    return { p: [z.x, Math.min(room.D - 0.4, z.z + Math.min(0.5, z.d / 4))], yaw: Math.PI };
  }
  const [dx, dz] = frontDir(z.rot);
  const ext = dx !== 0 ? z.w / 2 : z.d / 2;
  const p: P2 = [z.x + dx * (ext + 0.5), z.z + dz * (ext + 0.5)];
  p[0] = Math.min(room.W - 0.4, Math.max(0.4, p[0]));
  p[1] = Math.min(room.D - 0.4, Math.max(0.4, p[1]));
  // face the prop
  return { p, yaw: Math.atan2(-dx, -dz) };
}

/** Walk grid: 0.25 m cells, border walls, solid props blocked with a small clearance pad. */
export function buildPlaceGrid(room: Room, zones: PlaceZone[]): NavGrid {
  const g = makeGrid([0, 0, room.W, room.D], 0.25);
  for (const z of zones) {
    if (!propMeta(z.prop).solid) continue;
    blockRect(g, z.x - z.w / 2, z.z - z.d / 2, z.x + z.w / 2, z.z + z.d / 2, 0.12);
  }
  return g;
}

/* ------------------------------------------------------------------ */
/* Background people (L3-lite)                                         */
/* ------------------------------------------------------------------ */

/** Busy curve 0..1 by hour (Benin time) per place type; the background crowd follows it. */
const BUSY: Record<string, (h: number) => number> = {
  club: (h) => (h >= 22 || h < 3 ? 1 : h >= 21 || h < 5 ? 0.6 : 0.05),
  market: (h) => (h >= 7 && h < 18 ? (h >= 9 && h < 15 ? 1 : 0.7) : h >= 6 && h < 20 ? 0.3 : 0.05),
  buka: (h) => (h >= 12 && h < 15 ? 1 : h >= 7 && h < 21 ? 0.55 : 0.1),
  campus: (h) => (h >= 8 && h < 17 ? 1 : h >= 17 && h < 22 ? 0.4 : 0.1),
  motorpark: (h) => (h >= 6 && h < 10 ? 1 : h >= 16 && h < 20 ? 0.9 : h >= 5 && h < 22 ? 0.5 : 0.1),
  street: (h) => (h >= 17 && h < 23 ? 0.9 : h >= 7 && h < 17 ? 0.6 : 0.2),
  bank: (h) => (h >= 8 && h < 16 ? 0.9 : 0.1),
  stadium: (h) => (h >= 15 && h < 19 ? 1 : h >= 6 && h < 9 ? 0.4 : 0.15),
  cinema: (h) => (h >= 17 && h < 23 ? 1 : h >= 11 && h < 17 ? 0.5 : 0.05),
  mall: (h) => (h >= 11 && h < 20 ? 1 : h >= 9 && h < 22 ? 0.5 : 0.05),
  hotel: (h) => (h >= 18 && h < 23 ? 0.8 : 0.45),
  zoo: (h) => (h >= 10 && h < 16 ? 1 : h >= 8 && h < 18 ? 0.5 : 0),
};
export function busyness(scene: string, hour: number): number {
  const f = BUSY[scene];
  if (f) return f(((hour % 24) + 24) % 24);
  const h = ((hour % 24) + 24) % 24;
  return h >= 8 && h < 20 ? 0.7 : 0.15;
}

const NAMES_M = ['Osas', 'Efosa', 'Osaro', 'Ehis', 'Tunde', 'Emeka', 'Uyi', 'Nosa', 'Ikpomwosa', 'Eghosa', 'Kingsley', 'Chidi', 'Femi', 'Ade'];
const NAMES_F = ['Osato', 'Ivie', 'Eki', 'Omo', 'Adesuwa', 'Itohan', 'Ngozi', 'Blessing', 'Precious', 'Ese', 'Amaka', 'Tobi', 'Joy', 'Uyi'];
/** Shirt / wrapper colours (Benin prints, coral, ECTS green, indigo). */
export const NPC_COLORS = ['#d2342a', '#1f7a3f', '#2f6fb3', '#d9a441', '#6d4aa0', '#e07a2e', '#0b625a', '#c74b8a', '#f3f0e8', '#3a3f6e', '#b5552b', '#7dbb45'];
export const SKIN = ['#5a3a26', '#6b4430', '#7a4e36', '#4a2f20', '#8a5a3c', '#3f281b'];

export interface NpcPlan {
  id: string;
  name: string;
  /** World position in room space, facing yaw. */
  p: P2;
  yaw: number;
  color: string;
  legs: string;
  skin: string;
  female: boolean;
  /** Animates (dance floor, stands) or just breathes. */
  lively: boolean;
  seated: boolean;
  /** Real player (blue @name pill + green dot) or a background person (white pill). */
  player: boolean;
  /** L3: role ("Hype man"), what they do, their lines (tap = bubble), their look (nearest ones get the full rig). */
  role?: string;
  motion?: NpcMotion;
  line?: string | null;
  lines?: string[];
  avatar?: AvatarConfig | null;
  headliner?: boolean;
  /** P1: the zone they belong to, and how they move around (see engine/wander.ts). */
  zone?: string;
  wander?: WanderKind;
}

/** P1: how a person moves around a place. fixed = on their spot (DJ / hype man behind the booth); seat = stays
 * seated; stay = small steps around their spot (bouncer, trader, cashier); dance = shuffles on the floor;
 * waiter = between the bar and the tables; roam = walks to spots in their zone or a nearby zone. */
export type WanderKind = 'fixed' | 'seat' | 'stay' | 'dance' | 'waiter' | 'roam';

export function wanderKind(motion: NpcMotion | undefined, seated: boolean, role?: string): WanderKind {
  if (seated) return 'seat';
  switch (motion) {
    case 'dj':
    case 'hype':
      return 'fixed';
    case 'dance':
      return 'dance';
    case 'serve':
      return role && /waiter|waitress/i.test(role) ? 'waiter' : 'stay';
    case 'guard':
    case 'trade':
    case 'work':
    case 'cheer':
    case 'sit':
      return 'stay';
    default:
      return 'roam';
  }
}

/** P1: where the DJ (and the hype man, `side` ±1) stand: on the riser behind the booth, facing the room. */
export function boothSpot(z: PlaceZone, side = 0): { p: P2; yaw: number } {
  const odd = ((z.rot % 4) + 4) % 2 === 1;
  const lw = odd ? z.d : z.w;
  const ld = odd ? z.w : z.d;
  const bd = Math.min(0.6, ld * 0.45);
  const lz = -ld / 2 + (ld - bd - 0.15) / 2 + 0.02;
  const lx = side * Math.min(0.75, lw / 2 - 0.35);
  const yaw = (z.rot * Math.PI) / 2;
  const c = Math.cos(yaw);
  const sn = Math.sin(yaw);
  return { p: [z.x + lx * c + lz * sn, z.z - lx * sn + lz * c], yaw };
}

/** An npc_roster look (partial AvatarConfigV2 + `preset` = outfit preset, optional top colour) -> a full look. */
export function npcAvatar(raw: Record<string, unknown> | null | undefined): AvatarConfig {
  const r = raw ?? {};
  let cfg = normalizeAvatar({ v: 2, ...r });
  if (typeof r.preset === 'string') cfg = applyPreset(cfg, r.preset);
  const top = r.top as { c?: unknown } | undefined;
  if (top && typeof top.c === 'string' && /^#[0-9a-f]{6}$/i.test(top.c)) cfg = { ...cfg, top: { ...cfg.top, c: top.c } };
  return cfg;
}

function hash(s: string): number {
  let h = 2166136261;
  for (let i = 0; i < s.length; i++) h = Math.imul(h ^ s.charCodeAt(i), 16777619);
  return h >>> 0;
}
function rng(seed: number) {
  let s = seed % 2147483647 || 1;
  return () => (s = (s * 16807) % 2147483647) / 2147483647;
}

/**
 * Who is drawn inside: real players first (up to the cap), then background people spread over the zones
 * by the type's busy curve. Deterministic per place + hour, so the crowd doesn't reshuffle on every render.
 * `perZone` = config places.npc_per_zone, `cap` = crowd.max_visible.
 */
export function planCrowd(opts: {
  placeId: string;
  scene: string;
  hour: number;
  room: Room;
  zones: PlaceZone[];
  grid: NavGrid;
  players: { id: string; username: string; avatar?: AvatarConfig | null }[];
  /** L3: named people from place_people() (undefined = still loading: none drawn; null = failed: old random people). */
  npcs?: PlaceNpc[] | null;
  /** Everyone there per the crowd profile (place_people().total). */
  npcTotal?: number;
  perZone: number;
  cap: number;
  closed: boolean;
}): { shown: NpcPlan[]; total: number } {
  const { room, zones, grid } = opts;
  const hourKey = Math.floor(opts.hour);
  const rnd = rng(hash(`${opts.placeId}:${hourKey}`));
  const busy = opts.closed ? 0.1 : busyness(opts.scene, opts.hour);
  const used: P2[] = [];
  const free = (p: P2) => {
    const c = Math.floor(p[0] / grid.cell);
    const r = Math.floor(p[1] / grid.cell);
    if (c <= 0 || r <= 0 || c >= grid.cols - 1 || r >= grid.rows - 1 || grid.blocked[r * grid.cols + c]) return false;
    return used.every((u) => Math.hypot(u[0] - p[0], u[1] - p[1]) > 0.55);
  };
  const near = (z: PlaceZone): { p: P2; yaw: number; seated: boolean; key?: string } | null => {
    const m = propMeta(z.prop);
    for (let tries = 0; tries < 14; tries++) {
      let p: P2;
      if (m.spot === 'centre') p = [z.x + (rnd() - 0.5) * z.w * 0.8, z.z + (rnd() - 0.5) * z.d * 0.8];
      else {
        const s = zoneSpot(z, room);
        const [dx, dz] = frontDir(z.rot);
        const side = (rnd() - 0.5) * (dx !== 0 ? z.d : z.w) * 0.9;
        p = [s.p[0] + (dx === 0 ? side : dx * rnd() * 0.6), s.p[1] + (dz === 0 ? side : dz * rnd() * 0.6)];
      }
      if (m.spot === 'centre' ? p[0] > 0.3 && p[1] > 0.3 && p[0] < room.W - 0.3 && p[1] < room.D - 0.3 && used.every((u) => Math.hypot(u[0] - p[0], u[1] - p[1]) > 0.55) : free(p)) {
        used.push(p);
        const s = zoneSpot(z, room);
        const yaw = m.spot === 'centre' ? (m.pose === 'dance' ? rnd() * Math.PI * 2 : Math.PI + (rnd() - 0.5) * 1.2) : s.yaw + (rnd() - 0.5) * 0.8;
        return { p, yaw, seated: m.pose === 'sit' || m.pose === 'lie', key: z.key };
      }
    }
    return null;
  };
  const shown: NpcPlan[] = [];
  const cap = Math.max(0, Math.round(opts.cap));
  // real players, spread over random zones
  for (const pl of opts.players) {
    if (shown.length >= cap || !zones.length) break;
    const z = zones[Math.floor(rnd() * zones.length)];
    const at = near(z);
    if (!at) continue;
    const look = pl.avatar ? normalizeAvatar(pl.avatar) : null;
    const female = look ? look.gender === 'female' : rnd() < 0.5;
    shown.push({
      id: pl.id, name: `@${pl.username}`, p: at.p, yaw: at.yaw,
      color: look?.top.c ?? NPC_COLORS[hash(pl.id) % NPC_COLORS.length], legs: look?.bottom.c ?? '#2a2d3a',
      skin: look ? skinTone(look.skin).base : SKIN[hash(pl.id) % SKIN.length], female,
      lively: propMeta(z.prop).pose === 'dance', seated: at.seated, player: true, avatar: look,
      motion: propMeta(z.prop).pose === 'dance' ? 'dance' : 'idle',
      zone: z.key, wander: at.seated ? 'seat' : propMeta(z.prop).pose === 'dance' ? 'dance' : 'roam',
    });
  }
  if (opts.npcs !== null) {
    // L3: the named people present (server-seeded, the same for every player)
    const list = opts.closed ? [] : (opts.npcs ?? []);
    const byKey = new Map(zones.map((z) => [z.key, z]));
    const danceZ = zones.filter((z) => propMeta(z.prop).pose === 'dance');
    const djZ = zones.find((z) => z.prop === 'dj_booth');
    let rr = 0;
    let boothSide = 0;
    for (const n of list) {
      if (shown.length >= cap || !zones.length) break;
      const z = (n.zone && byKey.get(n.zone))
        || (n.motion === 'dance' && danceZ.length ? danceZ[Math.floor(rnd() * danceZ.length)] : null)
        || ((n.motion === 'dj' || n.motion === 'hype') && djZ ? djZ : null)
        || zones[(rr++ + Math.floor(rnd() * 2)) % zones.length];
      // P1: the DJ (and the hype man beside them) stand behind the booth, facing the room
      const booth = (n.motion === 'dj' || n.motion === 'hype') && z.prop === 'dj_booth';
      let at = booth ? null : near(z) ?? near(zones[Math.floor(rnd() * zones.length)]);
      if (booth) {
        const bs = boothSpot(z, n.motion === 'dj' && boothSide === 0 ? 0 : (boothSide % 2 ? -1 : 1));
        boothSide++;
        at = { p: bs.p, yaw: bs.yaw, seated: false, key: z.key };
      }
      if (!at) continue;
      const zKey = at.key ?? z.key;
      const look = npcAvatar(n.avatar);
      const pose = propMeta(z.prop).pose;
      const motion: NpcMotion = n.motion === 'sit' && !at.seated ? 'idle' : at.seated && n.motion !== 'serve' ? 'sit' : n.motion;
      // performers face the room (the camera side), everyone else as placed
      const yaw = booth ? at.yaw : motion === 'hype' || motion === 'dj' ? zoneSpot(z, room).yaw + Math.PI : at.yaw;
      const seated = at.seated && motion === 'sit';
      shown.push({
        id: `npc-${n.id}`, name: n.name, p: at.p, yaw, color: look.top.c, legs: look.bottom.c, skin: skinTone(look.skin).base,
        female: look.gender === 'female', lively: motion === 'dance' || motion === 'hype' || motion === 'cheer' || pose === 'dance',
        seated, player: false, role: n.role, motion, line: n.line, lines: n.lines, avatar: look,
        headliner: n.headliner, zone: zKey, wander: booth ? 'fixed' : wanderKind(motion, seated, n.role),
      });
    }
    return { shown, total: opts.players.length + Math.max(opts.npcTotal ?? 0, list.length) };
  }
  // background people
  let npcTotal = 0;
  for (const z of zones) {
    const m = propMeta(z.prop);
    const want = Math.round(opts.perZone * busy * (m.pose === 'dance' || z.prop === 'stands' ? 2 : 1) + (rnd() < busy * 0.5 ? 1 : 0) - (rnd() < 0.3 ? 1 : 0));
    const n = Math.max(0, Math.min(5, want));
    npcTotal += n;
    for (let i = 0; i < n && shown.length < cap; i++) {
      const at = near(z);
      if (!at) continue;
      const female = rnd() < 0.5;
      const names = female ? NAMES_F : NAMES_M;
      shown.push({
        id: `npc-${z.key}-${i}`,
        name: names[Math.floor(rnd() * names.length)],
        p: at.p,
        yaw: at.yaw,
        color: NPC_COLORS[Math.floor(rnd() * NPC_COLORS.length)],
        legs: rnd() < 0.5 ? '#2a2d3a' : female ? NPC_COLORS[Math.floor(rnd() * NPC_COLORS.length)] : '#4a4038',
        skin: SKIN[Math.floor(rnd() * SKIN.length)],
        female,
        lively: m.pose === 'dance' || z.prop === 'stands',
        seated: at.seated,
        player: false,
        zone: z.key,
        wander: at.seated ? 'seat' : m.pose === 'dance' ? 'dance' : 'roam',
      });
    }
  }
  return { shown, total: opts.players.length + npcTotal };
}
