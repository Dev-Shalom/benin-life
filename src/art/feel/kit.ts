// F1 real-feel geometry shared by the home and every place (docs/FEEL_PLAN.md): the world outside (ground
// that continues past the room into the fog, a street with gutters in front, neighbours' compounds behind)
// and lived-in Benin clutter kits (plastic chairs, crates of drinks, calendar, posters, wall fan, prepaid
// meter, extension box, water dispenser, cooler, buckets, slippers at the door...). All built into the
// same merged HomeBuilder (no extra draw calls), placed with a seeded random so each place is unique.
// Layout space: the room is x 0..W (left wall at x = 0), z 0..D (back wall at z = 0); the camera looks
// from +x/+z, so only flat things go in front (south/east) and tall things behind (north/west).
import type { HomeBuilder } from '../home3d/engine/build';

export type Rand = () => number;
export type Rect = [number, number, number, number]; // x0, z0, x1, z1

export function seeded(seed: number): Rand {
  let s = (seed * 2654435761) >>> 0 || 1;
  return () => {
    s = (s + 0x6d2b79f5) >>> 0;
    let t = s;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export function hashStr(s: string): number {
  let h = 2166136261;
  for (let i = 0; i < s.length; i++) h = Math.imul(h ^ s.charCodeAt(i), 16777619);
  return h >>> 0;
}

const pick = <T,>(r: Rand, a: readonly T[]): T => a[Math.floor(r() * a.length) % a.length];

// ---------------------------------------------------------------- outside
export interface OutsideOpts {
  /** The room / lot footprint. */
  x0: number; z0: number; x1: number; z1: number;
  seed: number;
  /** 'compound' (laterite, face-me neighbours), 'estate' (paved, walls, trees), 'city' (street, shops). */
  style: 'compound' | 'estate' | 'city';
  /** Skip the street (outdoor yards that already have their own ground). */
  street?: boolean;
  /** Clutter density 0..1 (Low tier halves it). */
  density?: number;
}

const HOUSE_COLS = ['#d9c9a8', '#c9d3c0', '#e2cfbd', '#b9c4cc', '#e6d7a6', '#cfb8a3'];

export function buildOutside(b: HomeBuilder, o: OutsideOpts) {
  const r = seeded(o.seed);
  const cx = (o.x0 + o.x1) / 2, cz = (o.z0 + o.z1) / 2;
  const den = o.density ?? 1;
  b.resetFrame();
  // the outside is far and simple: no subdivision (AO there is just the contact gradient)
  const prevAo = b.ao;
  b.ao = false;
  // ground: continues far past the room and fades into the fog
  const groundCol = o.style === 'estate' ? '#a39b8c' : o.style === 'city' ? '#9a8f80' : '#b07a4f';
  b.box(110, 0.05, 110, cx, -0.1, cz, groundCol, { mat: o.style === 'compound' ? 'ground' : 'concrete', seg: 1, noOcc: true, uv: 4 });
  // a ring of slightly darker earth right round the building (drip line, trodden path)
  b.box(o.x1 - o.x0 + 2.4, 0.02, o.z1 - o.z0 + 2.4, cx, -0.06, cz, o.style === 'compound' ? '#a06c45' : '#958d7f', { mat: 'concrete', seg: 1, noOcc: true });
  if (o.street !== false) {
    // street in front (south): kerb, gutter, asphalt, gutter, kerb (all flat: the camera looks over it)
    const z = o.z1 + 1.6;
    b.box(110, 0.06, 0.9, cx, -0.06, z + 0.45, '#b9b1a3', { mat: 'concrete', seg: 1, noOcc: true });
    b.box(110, 0.03, 0.55, cx, -0.07, z + 1.2, '#3f3c38', { mat: 'concrete', seg: 1, noOcc: true });
    b.box(110, 0.02, 0.3, cx, -0.06, z + 1.2, '#2b2a28', { mat: 'concrete', seg: 1, noOcc: true });
    b.box(110, 0.04, 6.4, cx, -0.07, z + 4.7, o.style === 'compound' ? '#5d5852' : '#46464b', { mat: 'asphalt', seg: 1, noOcc: true });
    for (let x = cx - 50; x < cx + 50; x += 3.2) b.box(1.4, 0.01, 0.12, x, -0.03, z + 4.7, '#cfc8b4', { mat: 'concrete', seg: 1, noOcc: true });
    b.box(110, 0.03, 0.55, cx, -0.07, z + 8.2, '#3f3c38', { mat: 'concrete', seg: 1, noOcc: true });
    // potholes + a puddle on the compound road (it's Benin)
    if (o.style === 'compound') for (let i = 0; i < 3; i++) b.box(0.6 + r(), 0.012, 0.4 + r() * 0.5, cx - 6 + r() * 12, -0.03, z + 3 + r() * 3.5, '#4a4540', { mat: 'concrete', seg: 1, noOcc: true });
  }
  // neighbours behind (north) and to the left (west): compounds with block fences and zinc roofs
  const behind: [number, number, number, boolean][] = []; // x, z, width, rotated (west side)
  for (let x = o.x0 - 9; x < o.x1 + 12; x += 6.5 + r() * 2.5) behind.push([x, o.z0 - 7 - r() * 2, 4.4 + r() * 1.8, false]);
  for (let z = o.z0 - 1; z < o.z1 + 6; z += 7 + r() * 2.5) behind.push([o.x0 - 7 - r() * 2, z, 4.4 + r() * 1.8, true]);
  for (const [hx, hz, hw, west] of behind) {
    const hd = 4.2 + r() * 1.2;
    const hh = o.style === 'estate' ? 2.8 + r() * 2.2 : 2.3 + r() * 0.4;
    const w = west ? hd : hw, d = west ? hw : hd;
    const col = pick(r, HOUSE_COLS);
    b.box(w, hh, d, hx, -0.05, hz, col, { mat: o.style === 'estate' ? 'paint' : 'plaster' });
    // roof: rusty zinc (compound) or tiles (estate), a shallow slab with an overhang
    const roof = o.style === 'estate' ? pick(r, ['#7a3b2a', '#5b5f66', '#8a4a2c']) : pick(r, ['#8d6f5a', '#a7b0b6', '#7f898f', '#96705a']);
    b.box(w + 0.5, 0.16, d + 0.5, hx, hh - 0.05, hz, roof, { mat: o.style === 'estate' ? 'tiles' : 'zinc', uv: 1.6 });
    b.box(w * 0.6, 0.35, d + 0.5, hx, hh + 0.08, hz, roof, { mat: o.style === 'estate' ? 'tiles' : 'zinc', uv: 1.6 });
    // a dark window or two facing the room
    if (!west) for (let i = 0; i < 2; i++) b.box(0.8, 0.8, 0.04, hx - w / 4 + i * (w / 2), 1.1, hz + d / 2 + 0.01, '#2c3138', { mat: 'metal' });
    else b.box(0.04, 0.8, 0.8, hx + w / 2 + 0.01, 1.1, hz, '#2c3138', { mat: 'metal' });
  }
  // block fences between us and them (behind + left), a painted gate
  const fh = o.style === 'estate' ? 2.1 : 1.6;
  const fcol = o.style === 'estate' ? '#d8d2c6' : '#bdb6a8';
  b.box(o.x1 - o.x0 + 6, fh, 0.18, cx + 1, -0.05, o.z0 - 2.2, fcol, { mat: 'block' });
  b.box(0.18, fh, o.z1 - o.z0 + 5, o.x0 - 2.2, -0.05, cz + 1.5, fcol, { mat: 'block' });
  if (o.style === 'estate') {
    b.box(o.x1 - o.x0 + 6, 0.08, 0.26, cx + 1, fh - 0.05, o.z0 - 2.2, '#9a8f80', { mat: 'concrete' });
    b.box(0.26, 0.08, o.z1 - o.z0 + 5, o.x0 - 2.2, fh - 0.05, cz + 1.5, '#9a8f80', { mat: 'concrete' });
  } else if (o.style === 'compound') {
    // A compact standby generator sits by the compound wall, grounded in the same Benin street scene.
    const gx = o.x1 + 2.1, gz = o.z1 - 0.9;
    b.box(0.9, 0.58, 0.54, gx, -0.04, gz, '#59616b', { mat: 'metal' });
    b.box(0.72, 0.38, 0.025, gx, 0.04, gz + 0.29, '#34383d', { mat: 'metal' });
    for (let i = -2; i <= 2; i++) b.box(0.018, 0.28, 0.03, gx + i * 0.12, 0.09, gz + 0.31, '#9aa3ab', { mat: 'metal' });
    b.box(0.13, 0.11, 0.018, gx + 0.25, 0.12, gz + 0.33, '#c64b3d', { mat: 'metal' });
    b.cyl(0.035, 0.035, 0.22, gx - 0.52, 0.36, gz, '#7f898f', { mat: 'metal', seg: 7 });
    for (const dx of [-0.31, 0.31]) b.box(0.1, 0.08, 0.08, gx + dx, -0.04, gz, '#25292c', { mat: 'metal' });
  }
  // trees behind (mango / almond / palm), never in front of the room
  const nt = Math.round((3 + r() * 2) * den);
  for (let i = 0; i < nt; i++) {
    const tx = o.x0 - 3 + r() * (o.x1 - o.x0 + 8);
    const tz = o.z0 - 3.2 - r() * 2.5;
    tree(b, i % 2 === 0 ? tx : o.x0 - 3.2 - r() * 2, i % 2 === 0 ? tz : o.z0 + r() * (o.z1 - o.z0), 0.9 + r() * 0.5, r() < 0.3);
  }
  // an electric pole behind with a sagging wire towards the room (NEPA!)
  const pz = o.z0 - 1.4;
  b.cyl(0.08, 0.1, 5.2, o.x0 + (o.x1 - o.x0) * 0.7, -0.05, pz, '#6b5338', { mat: 'wood', occ: true });
  b.box(1.1, 0.08, 0.08, o.x0 + (o.x1 - o.x0) * 0.7, 4.9, pz, '#4a3a28', { mat: 'wood' });
  for (const dx of [-3.5, 3.5]) b.box(0.02, 0.02, 3.6, o.x0 + (o.x1 - o.x0) * 0.7 + dx * 0.15, 4.85, pz - 1.5, '#1e1e20', { ry: dx * 0.08 });
  b.ao = prevAo;
}

export function tree(b: HomeBuilder, x: number, z: number, s: number, palm = false) {
  if (palm) {
    b.cyl(0.09 * s, 0.13 * s, 4.2 * s, x, -0.05, z, '#7a6046', { mat: 'wood', occ: true });
    for (let i = 0; i < 6; i++) b.box(0.25 * s, 0.06, 1.6 * s, x, 4.1 * s, z, '#3f7d32', { ry: (i * Math.PI) / 3, rx: 0.35, mat: 'fabric' });
    return;
  }
  b.cyl(0.13 * s, 0.18 * s, 1.6 * s, x, -0.05, z, '#6b4f36', { mat: 'wood', occ: true });
  b.cyl(1.2 * s, 1.5 * s, 1.1 * s, x, 1.4 * s, z, '#3f7a35', { seg: 9, mat: 'grass', occ: true });
  b.cyl(0.6 * s, 1.15 * s, 0.9 * s, x, 2.45 * s, z, '#4a8a3c', { seg: 9, mat: 'grass' });
}

// ---------------------------------------------------------------- clutter
export type ClutterKind = 'home_lapo' | 'home_nepo' | 'club' | 'buka' | 'office' | 'clinic' | 'market' | 'hall';

export interface ClutterCtx {
  W: number; D: number; H: number;
  kind: ClutterKind;
  seed: number;
  density: number;
  /** Footprints to keep clear (furniture, zones, doors), plus a margin. */
  avoid: Rect[];
  /** Spans of the back (z = 0) / left (x = 0) walls that hold windows, [from, to] along the wall. */
  windowsN?: [number, number][];
  windowsW?: [number, number][];
  /** The front door (slippers, mat), x along the front wall (z = D) or null. */
  door?: { x: number; z: number } | null;
  /** Outdoor: no walls to hang things on. */
  outdoor?: boolean;
}

const CHAIR_COLS = ['#f4f2ee', '#d2342a', '#2f6fb3', '#1f7a3f', '#f4f2ee', '#e9e4da'];

function hit(avoid: Rect[], x0: number, z0: number, x1: number, z1: number, m = 0.15): boolean {
  for (const a of avoid) if (x1 > a[0] - m && x0 < a[2] + m && z1 > a[1] - m && z0 < a[3] + m) return true;
  return false;
}

export function plasticChair(b: HomeBuilder, x: number, z: number, ry: number, c: string) {
  b.setFrame(x, 0, z, ry);
  b.box(0.42, 0.04, 0.42, 0, 0.42, 0, c, { mat: 'plain' });
  b.box(0.42, 0.42, 0.04, 0, 0.44, -0.2, c, { mat: 'plain', rx: -0.12 });
  for (const sx of [-0.18, 0.18]) for (const sz of [-0.18, 0.18]) b.box(0.035, 0.42, 0.035, sx, 0, sz, c, { mat: 'plain' });
  b.resetFrame();
}

/** A crate of drinks: Star (green bottles, amber crate), Coke (red crate), Fanta, Gulder, Malt. */
export function crate(b: HomeBuilder, x: number, z: number, ry: number, r: Rand, stack = 1) {
  const brand = pick(r, [
    ['#c98a1b', '#2f6b2a'], ['#c0221f', '#3a1a12'], ['#e07a10', '#e07a10'], ['#1d4f8a', '#5b3a12'], ['#3a2a1a', '#2b1a10'],
  ] as const);
  b.setFrame(x, 0, z, ry);
  for (let s = 0; s < stack; s++) {
    const y = s * 0.3;
    b.box(0.45, 0.28, 0.32, 0, y, 0, brand[0], { mat: 'plain' });
    if (s === stack - 1) for (let i = 0; i < 4; i++) for (let j = 0; j < 3; j++) b.cyl(0.025, 0.03, 0.12, -0.165 + i * 0.11, y + 0.26, -0.1 + j * 0.1, brand[1], { seg: 5 });
  }
  b.resetFrame();
}

function bucket(b: HomeBuilder, x: number, z: number, c: string) {
  b.cyl(0.17, 0.13, 0.32, x, 0, z, c, { seg: 10, mat: 'plain', occ: true });
  b.cyl(0.16, 0.16, 0.012, x, 0.3, z, '#2a4a6a', { seg: 10 });
}

function cooler(b: HomeBuilder, x: number, z: number, ry: number, c: string) {
  b.setFrame(x, 0, z, ry);
  b.box(0.6, 0.38, 0.38, 0, 0, 0, c, { mat: 'plain' });
  b.box(0.62, 0.07, 0.4, 0, 0.38, 0, '#f4f2ee', { mat: 'plain' });
  b.resetFrame();
}

function dispenser(b: HomeBuilder, x: number, z: number, ry: number) {
  b.setFrame(x, 0, z, ry);
  b.box(0.32, 0.95, 0.32, 0, 0, 0, '#eef0f0', { mat: 'metal' });
  b.box(0.08, 0.06, 0.04, -0.07, 0.62, 0.17, '#d2342a');
  b.box(0.08, 0.06, 0.04, 0.07, 0.62, 0.17, '#2f6fb3');
  b.cyl(0.14, 0.14, 0.42, 0, 0.95, 0, '#3b8fd4', { seg: 10, mat: 'plain' });
  b.resetFrame();
}

function slippers(b: HomeBuilder, x: number, z: number, r: Rand) {
  for (let i = 0; i < 2; i++) {
    const c = pick(r, ['#1f2a44', '#c0221f', '#2f6fb3', '#3a2a1a', '#e2b33b']);
    for (const s of [-0.06, 0.06]) b.box(0.09, 0.025, 0.24, x + i * 0.3 + s, 0, z + (r() - 0.5) * 0.1, c, { ry: (r() - 0.5) * 0.6, mat: 'leather' });
  }
}

function ghanaMustGo(b: HomeBuilder, x: number, z: number, ry: number) {
  b.box(0.6, 0.34, 0.34, x, 0, z, '#3e5f9e', { ry, mat: 'tarp', uv: 0.25 });
}

/** Things on the back wall (z = 0) at x, or on the left wall (x = 0) at z. */
function onWall(b: HomeBuilder, wall: 'n' | 'w', at: number, y: number) {
  if (wall === 'n') b.setFrame(at, y, 0.02, 0);
  else b.setFrame(0.02, y, at, Math.PI / 2);
}

function calendar(b: HomeBuilder, wall: 'n' | 'w', at: number, r: Rand) {
  onWall(b, wall, at, 1.3);
  b.box(0.36, 0.5, 0.01, 0, 0, 0, '#f4f1ea', { mat: 'paint' });
  b.box(0.32, 0.22, 0.012, 0, 0.25, 0, pick(r, ['#8a1c1c', '#1f4f8a', '#1f7a3f']), { mat: 'fabric' }); // the Oba / church picture
  b.box(0.05, 0.1, 0.014, 0, 0.3, 0, '#d9a441');
  for (let i = 0; i < 4; i++) b.box(0.28, 0.012, 0.013, 0, 0.04 + i * 0.045, 0, '#6b6b6b');
  b.resetFrame();
}

function poster(b: HomeBuilder, wall: 'n' | 'w', at: number, r: Rand, party = false) {
  onWall(b, wall, at, 1.15 + r() * 0.3);
  const w = 0.42 + r() * 0.2, h = 0.6 + r() * 0.15;
  const bg = party ? pick(r, ['#1a0f3a', '#3a0f2a', '#0f2a3a']) : pick(r, ['#f3e7c8', '#ffe0d0', '#d9ecff', '#e9f5d0']);
  const ink = party ? pick(r, ['#ff4fa3', '#7ee0c5', '#f3cf5e']) : pick(r, ['#c0221f', '#1f4f8a', '#1f7a3f', '#6d4aa0']);
  b.box(w, h, 0.008, 0, 0, 0, bg, { mat: 'paint' });
  b.box(w * 0.8, h * 0.35, 0.01, 0, h * 0.5, 0, ink, { mat: 'fabric' });
  b.box(w * 0.7, 0.05, 0.011, 0, h * 0.25, 0, ink);
  b.box(w * 0.5, 0.04, 0.011, 0, h * 0.12, 0, ink);
  b.resetFrame();
}

function meter(b: HomeBuilder, wall: 'n' | 'w', at: number) {
  onWall(b, wall, at, 1.5);
  b.box(0.2, 0.28, 0.08, 0, 0, 0, '#e9e4d6', { mat: 'plain' });
  b.box(0.12, 0.05, 0.01, 0, 0.18, 0.08, '#7ee08a', { layer: 'glow' });
  b.box(0.02, 1.5, 0.02, 0.06, -1.5, 0.02, '#222'); // cable down to the floor
  b.box(0.02, 0.6, 0.02, 0.06, 0.28, 0.02, '#222'); // and up to the ceiling
  b.resetFrame();
}

function wallFan(b: HomeBuilder, wall: 'n' | 'w', at: number) {
  onWall(b, wall, at, 2.0);
  b.box(0.1, 0.12, 0.12, 0, 0, 0.02, '#e9e4da', { mat: 'plain' });
  b.cyl(0.2, 0.2, 0.06, 0, -0.05, 0.22, '#f4f2ee', { rx: Math.PI / 2, seg: 12, mat: 'metal' });
  b.cyl(0.05, 0.05, 0.08, 0, -0.05, 0.26, '#2f6fb3', { rx: Math.PI / 2, seg: 8 });
  b.resetFrame();
}

function extension(b: HomeBuilder, x: number, z: number) {
  b.box(0.3, 0.05, 0.08, x, 0, z, '#f4f2ee', { mat: 'plain' });
  b.box(0.06, 0.012, 0.6, x - 0.18, 0, z + 0.25, '#e07a10', { ry: 0.4 }); // the orange cable
}

/** Lived-in clutter along the back and left walls (and by the door), skipping anything in `avoid`. */
export function buildClutter(b: HomeBuilder, c: ClutterCtx) {
  const r = seeded(c.seed);
  const den = Math.max(0, Math.min(1, c.density));
  const avoid = c.avoid.slice();
  const take = (x0: number, z0: number, x1: number, z1: number) => {
    if (x0 < 0.05 || z0 < 0.05 || x1 > c.W - 0.05 || z1 > c.D - 0.05) return false;
    if (hit(avoid, x0, z0, x1, z1)) return false;
    avoid.push([x0, z0, x1, z1]);
    return true;
  };
  // a floor spot hugging a wall
  const floorSpot = (size: number, tries = 8): { x: number; z: number; ry: number } | null => {
    for (let i = 0; i < tries; i++) {
      const west = r() < 0.45;
      const x = west ? 0.15 + size / 2 : 0.5 + r() * (c.W - 1);
      const z = west ? 0.5 + r() * (c.D - 1.4) : 0.15 + size / 2;
      if (take(x - size / 2, z - size / 2, x + size / 2, z + size / 2)) return { x, z, ry: west ? Math.PI / 2 : 0 };
    }
    return null;
  };
  // a wall spot (not over a window)
  const wallSpot = (w: number): { wall: 'n' | 'w'; at: number } | null => {
    for (let i = 0; i < 8; i++) {
      const wall: 'n' | 'w' = r() < 0.5 ? 'n' : 'w';
      const len = wall === 'n' ? c.W : c.D;
      const at = 0.5 + r() * (len - 1);
      const wins = (wall === 'n' ? c.windowsN : c.windowsW) ?? [];
      if (wins.some(([a, z]) => at + w / 2 > a - 0.15 && at - w / 2 < z + 0.15)) continue;
      const key: Rect = wall === 'n' ? [at - w / 2, -1, at + w / 2, -0.9] : [-1, at - w / 2, -0.9, at + w / 2];
      if (hit(avoid, key[0], key[1], key[2], key[3], 0.05)) continue;
      avoid.push(key);
      return { wall, at };
    }
    return null;
  };
  const n = (k: number) => Math.floor(k * den) + (r() < (k * den) % 1 ? 1 : 0);
  const walls = !c.outdoor;
  const kit = c.kind;

  // wall pieces
  if (walls) {
    const wallItems: ('calendar' | 'poster' | 'party' | 'meter' | 'fan')[] = [];
    if (kit === 'home_lapo') wallItems.push('calendar', 'poster', 'meter');
    if (kit === 'home_nepo') wallItems.push('poster', 'meter');
    if (kit === 'buka') wallItems.push('calendar', 'poster', 'fan', 'meter');
    if (kit === 'club') wallItems.push('party', 'party', 'party');
    if (kit === 'office' || kit === 'clinic' || kit === 'hall') wallItems.push('poster', 'calendar', 'meter');
    for (const it of wallItems) {
      if (r() > den + 0.15) continue;
      const s = wallSpot(it === 'meter' ? 0.3 : 0.6);
      if (!s) continue;
      if (it === 'calendar') calendar(b, s.wall, s.at, r);
      else if (it === 'poster' || it === 'party') poster(b, s.wall, s.at, r, it === 'party');
      else if (it === 'meter') meter(b, s.wall, s.at);
      else wallFan(b, s.wall, s.at);
    }
  }
  // floor pieces
  const chairs = { home_lapo: 1, home_nepo: 0, club: 0, buka: 3, office: 2, clinic: 3, market: 4, hall: 2 }[kit];
  for (let i = 0; i < n(chairs); i++) {
    const s = floorSpot(0.5);
    if (s) plasticChair(b, s.x, s.z, s.ry + (r() - 0.5) * 0.8, pick(r, CHAIR_COLS));
  }
  const crates = { home_lapo: 0, home_nepo: 0, club: 3, buka: 3, office: 0, clinic: 0, market: 4, hall: 0 }[kit];
  for (let i = 0; i < n(crates); i++) {
    const s = floorSpot(0.5);
    if (s) crate(b, s.x, s.z, s.ry + (r() - 0.5) * 0.3, r, 1 + Math.floor(r() * 3));
  }
  const buckets = { home_lapo: 2, home_nepo: 0, club: 0, buka: 2, office: 0, clinic: 1, market: 3, hall: 0 }[kit];
  for (let i = 0; i < n(buckets); i++) {
    const s = floorSpot(0.36);
    if (s) bucket(b, s.x, s.z, pick(r, ['#2f6fb3', '#d2342a', '#1f7a3f', '#e2b33b', '#6d4aa0']));
  }
  if (kit === 'buka' || kit === 'club' || kit === 'market' || kit === 'home_lapo') {
    for (let i = 0; i < n(kit === 'home_lapo' ? 0.6 : 1.2); i++) {
      const s = floorSpot(0.65);
      if (s) cooler(b, s.x, s.z, s.ry, pick(r, ['#2f6fb3', '#d2342a', '#1f7a3f']));
    }
  }
  if (kit === 'home_nepo' || kit === 'office' || kit === 'clinic' || kit === 'hall' || kit === 'buka') {
    if (r() < den + 0.2) {
      const s = floorSpot(0.4);
      if (s) dispenser(b, s.x, s.z, s.ry);
    }
  }
  if (walls && kit !== 'market') for (let i = 0; i < n(1); i++) {
    const s = floorSpot(0.4);
    if (s) extension(b, s.x, s.z);
  }
  if (kit === 'home_lapo' && r() < den + 0.3) {
    const s = floorSpot(0.65);
    if (s) ghanaMustGo(b, s.x, s.z, s.ry);
  }
  // slippers at the door (homes)
  if (c.door && (kit === 'home_lapo' || kit === 'home_nepo')) slippers(b, c.door.x - 0.3, c.door.z, r);
  b.resetFrame();
}

// ---------------------------------------------------------------- light pools
/** Light pools + beams for a room by rig kind (additive 'light' layer; gain follows the time of day). */
export function buildPools(b: HomeBuilder, o: { W: number; D: number; H: number; kind: string; seed: number; spots?: [number, number][]; rich?: boolean }) {
  const r = seeded(o.seed + 17);
  b.resetFrame();
  if (o.kind === 'club' || o.kind === 'lounge') {
    const cols = ['#ff3fa0', '#36d6ff', '#9b5cff', '#ffb03a', '#3affb0'];
    const spots = o.spots?.length ? o.spots : [[o.W / 2, o.D / 2]] as [number, number][];
    let i = 0;
    for (const [x, z] of spots) {
      for (let k = 0; k < 2; k++) {
        const c = cols[i++ % cols.length];
        const px = x + (r() - 0.5) * 1.6, pz = z + (r() - 0.5) * 1.6;
        // P1: wider, softer, dimmer pools; faint beams
        b.pool(px, pz, 1.5 + r() * 0.6, c, 0.025, 0.55);
        b.beam(px, o.H + 0.4, pz, 0.08, 0.85, c, 0.08);
      }
    }
    // a wash along the back wall
    for (let x = 1.5; x < o.W - 1; x += 2.6) b.pool(x, 0.6, 1.5, cols[(i++) % cols.length], 0.02, 0.28);
    return;
  }
  const spots = o.spots?.length ? o.spots : [[o.W / 2, o.D / 2]] as [number, number][];
  for (const [x, z] of spots) {
    b.pool(x, z, o.kind === 'home_lapo' ? 2.5 : 2.3, '#ffffff', 0.02, 0.6);
    if (o.kind === 'home_nepo') b.beam(x, o.H - 0.05, z, 0.06, 0.6, '#ffffff', 0.05);
  }
}
