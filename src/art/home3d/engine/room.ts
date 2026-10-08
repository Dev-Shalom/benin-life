// Shell of a home: ground disc, yard, tiled floor, cut-away walls, windows, then every piece of
// furniture. Returns merged geometries per layer (see build.ts) in layout space; the scene centres it.
import type { BufferGeometry } from 'three';
import { KINDS, type HomeLayout } from '../model';
import { footprint, wallSegments } from '../nav';
import { buildClutter, buildOutside, buildPools, hashStr, type Rect } from '../../feel/kit';
import type { Mat } from '../../feel/atlas';
import { HomeBuilder, type Layer } from './build';
import { buildPiece, shadeHex } from './furniture';
import { bicycle, drawCar, motorcycle, type LuxCar } from '../../place3d/engine/cars';

export interface BuiltRoom {
  layers: Record<Layer, BufferGeometry | null>;
  tris: number;
  /** Ground disc radius (for camera framing). */
  radius: number;
  /** F1: Nepo-style home (tiles, paint, POP downlights) vs LAPO (cement, plaster, one bulb). */
  rich: boolean;
  /** F1: where the ceiling fan / bulb hang (layout space), null = none. */
  fan: [number, number, number] | null;
  bulb: [number, number, number];
}

/** F1: LAPO-type layouts get cement + peeling plaster + louvres; flat/duplex get tiles + paint. */
export const RICH_LAYOUTS = new Set(['flat', 'duplex']);

const T = 0.12; // wall thickness
const LOW = 0.32; // cut-away front wall height
const HALF = 1.15; // interior partition height
const DOLL = 0.7; // S2 dollhouse view (welcome-back orbit): every wall this low, so the camera sees in from any side

function tiles(b: HomeBuilder, x0: number, z0: number, x1: number, z1: number, a: string, bc: string | undefined, size: number, y: number, mat?: Mat) {
  if (mat) {
    // F1: one slab with the atlas (tiles with grout / worn cement), tinted between the two colours
    b.box(x1 - x0, 0.02, z1 - z0, (x0 + x1) / 2, y, (z0 + z1) / 2, bc ? mixCol(a, bc) : a, { mat, uv: mat === 'tiles' ? size * 2 : undefined });
    return;
  }
  if (!bc || bc === a) {
    b.box(x1 - x0, 0.02, z1 - z0, (x0 + x1) / 2, y, (z0 + z1) / 2, a);
    return;
  }
  const nx = Math.max(1, Math.round((x1 - x0) / size));
  const nz = Math.max(1, Math.round((z1 - z0) / size));
  const sx = (x1 - x0) / nx;
  const sz = (z1 - z0) / nz;
  // base colour as one slab, the alternate tiles on top (half the quads)
  b.box(x1 - x0, 0.02, z1 - z0, (x0 + x1) / 2, y, (z0 + z1) / 2, a);
  for (let i = 0; i < nx; i++)
    for (let j = 0; j < nz; j++) {
      if ((i + j) % 2 === 0) continue;
      b.box(sx, 0.004, sz, x0 + (i + 0.5) * sx, y + 0.02, z0 + (j + 0.5) * sz, bc);
    }
}

const LUXURY_CARS: Record<string, LuxCar> = {
  gwagon_g63: 'g63', gle63_coupe: 'gle63', lambo_urus: 'urus', tesla_cybertruck: 'cybertruck',
  escalade: 'escalade', benz_c300: 'c300', camry_new: 'camry',
};

function buildDuplexYard(b: HomeBuilder, vehicleId: string | null | undefined) {
  // A compact pool deck and one covered parking bay make the GRA plot feel lived in
  // without adding a second renderer or a large per-frame cost.
  b.box(4.0, 0.035, 2.9, 2.35, -0.005, 9.0, '#c9c2b5', { mat: 'concrete', noOcc: true });
  b.box(3.45, 0.32, 2.36, 2.35, -0.19, 9.0, '#60767a', { mat: 'tiles' });
  b.box(3.25, 0.025, 2.16, 2.35, -0.025, 9.0, '#54a9bd', { layer: 'glass', noOcc: true });
  for (let i = -1; i <= 1; i++) b.box(0.72, 0.008, 0.025, 2.35 + i * 0.92, -0.008, 9.0 + (i % 2) * 0.34, '#d4f1ee', { layer: 'glass', noOcc: true });
  // Two understated loungers, with the path from the south door left open.
  for (const x of [0.9, 3.8]) {
    b.box(0.66, 0.1, 1.5, x, 0.04, 8.35, '#eee8dc', { mat: 'plain' });
    b.box(0.66, 0.36, 0.1, x, 0.23, 7.66, '#eee8dc', { mat: 'plain', rx: -0.18 });
    for (const dx of [-0.25, 0.25]) b.box(0.04, 0.23, 0.04, x + dx, -0.05, 7.8, '#6b6256');
  }
  // Paved single-car bay; the entrance path at z=5.6 stays unobstructed.
  b.box(4.2, 0.035, 4.9, 12.35, -0.005, 8.05, '#aaa69c', { mat: 'concrete', noOcc: true });
  b.box(0.055, 0.012, 4.45, 10.48, 0.018, 8.05, '#efe9da', { noOcc: true });
  b.box(0.055, 0.012, 4.45, 14.22, 0.018, 8.05, '#efe9da', { noOcc: true });
  // Open pergola roof and warm post lights: it frames the vehicle without hiding it.
  for (const x of [10.48, 14.22]) for (const z of [5.75, 10.35]) {
    b.box(0.1, 2.35, 0.1, x, 0, z, '#687078', { mat: 'metal' });
    b.box(0.2, 0.11, 0.2, x, 2.34, z, '#ffdf9c', { layer: 'glow' });
  }
  b.box(3.84, 0.12, 0.12, 12.35, 2.35, 5.75, '#687078', { mat: 'metal' });
  b.box(3.84, 0.12, 0.12, 12.35, 2.35, 10.35, '#687078', { mat: 'metal' });
  for (const x of [10.8, 11.6, 12.4, 13.2, 14.0]) b.box(0.06, 0.08, 4.5, x, 2.35, 8.05, '#89919a', { mat: 'metal' });

  if (vehicleId && LUXURY_CARS[vehicleId]) {
    drawCar(b, LUXURY_CARS[vehicleId], 12.35, 8.05, 0, 0.72);
    b.resetFrame();
  } else if (vehicleId === 'bajaj_boxer') {
    b.setFrame(12.35, 0, 8.05, Math.PI / 2);
    motorcycle(b, 0.72);
    b.resetFrame();
  } else if (vehicleId === 'bicycle') {
    b.setFrame(12.35, 0, 8.05, Math.PI / 2);
    bicycle(b, 0.88);
    b.resetFrame();
  } else {
    // An empty bay still reads as a usable parking space.
    b.box(1.8, 0.012, 0.045, 12.35, 0.02, 8.05, '#d7d1c5', { noOcc: true });
  }
  // Small tropical planting softens the paved edges of the estate yard.
  for (const [x, z] of [[-0.45, 8.2], [-0.45, 9.7], [4.7, 8.5], [4.7, 9.8]] as const) {
    b.box(0.5, 0.23, 0.5, x, 0.05, z, '#a99a83', { mat: 'concrete' });
    b.cyl(0.34, 0.2, 0.72, x, 0.28, z, '#4d8a45', { seg: 7, mat: 'grass' });
  }
}

export function buildRoom(L: HomeLayout, opts: { dollhouse?: boolean; density?: number; outside?: boolean; vehicleId?: string | null } = {}): BuiltRoom {
  const doll = Boolean(opts.dollhouse);
  const rich = RICH_LAYOUTS.has(L.id);
  const b = new HomeBuilder();
  const [lx0, lz0, lx1, lz1] = L.lot;
  const cx = (lx0 + lx1) / 2;
  const cz = (lz0 + lz1) / 2;
  const radius = Math.hypot(lx1 - lx0, lz1 - lz0) / 2 + 1.4;
  const seed = hashStr(L.id);

  if (doll || opts.outside === false) {
    // S2 dollhouse (welcome-back orbit) keeps its island: the camera circles it
    b.cyl(radius, radius + 0.25, 0.35, cx, -0.37, cz, '#a8c08a', { seg: 40, mat: 'grass' });
    b.cyl(radius + 0.25, radius + 0.4, 0.22, cx, -0.6, cz, '#b5552b', { seg: 40, mat: 'ground' });
  } else {
    // F1: the world outside (street in front, neighbours behind, ground into the fog)
    buildOutside(b, { x0: lx0, z0: lz0, x1: lx1, z1: lz1, seed, style: rich ? 'estate' : 'compound', density: opts.density });
  }
  b.box(lx1 - lx0 + 0.5, 0.02, lz1 - lz0 + 0.5, cx, -0.03, cz, L.yard?.colour ?? '#b98a5e', { mat: rich ? 'concrete' : 'ground' });
  if (L.id === 'duplex' && !doll) buildDuplexYard(b, opts.vehicleId);
  if (L.yard?.fence) {
    // low block fence round the compound, open where the house is
    b.box(lx1 - lx0 + 0.5, 0.5, 0.12, cx, -0.01, lz0 - 0.25, '#c9c2b6', { mat: 'block', uv: 1.2 });
    b.box(0.12, 0.5, lz1 - lz0 + 0.5, lx0 - 0.25, -0.01, cz, '#c9c2b6', { mat: 'block', uv: 1.2 });
  }
  // path from the door to the edge
  const door = L.doors[0];
  if (door) {
    const mid = (door[1] + door[2]) / 2;
    if (door[0] === 'e') b.box(lx1 - L.w + 0.5, 0.025, door[2] - door[1], (L.w + lx1 + 0.5) / 2, -0.02, mid, '#cbbfae');
    else b.box(door[2] - door[1], 0.025, lz1 - L.d + 0.5, mid, -0.02, (L.d + lz1 + 0.5) / 2, '#cbbfae');
  }

  // house slab + floor
  b.box(L.w + T, 0.12, L.d + T, L.w / 2 - T / 2 + T / 2, -0.12, L.d / 2, shadeHex(L.wall, 1.25), { mat: 'concrete' });
  const floorMat: Mat = rich || L.id === 'self_contain' ? 'tiles' : 'concrete';
  tiles(b, 0, 0, L.w, L.d, L.floor.a, L.floor.b, L.floor.tile ?? 0.6, -0.01, floorMat);
  for (const [x0, z0, x1, z1, a, bc, size] of L.patches ?? []) tiles(b, x0, z0, x1, z1, a, bc, size ?? 0.4, 0.008, 'tiles');

  // walls
  const H = doll ? DOLL : L.wallH;
  const inner = L.wallInner;
  const outer = L.wall;
  const skirt = shadeHex(inner, 0.82);
  b.mat = rich ? 'paint' : 'plaster';
  // north wall (z = 0) and west wall (x = 0): full height, coloured inside, dark cap on top
  b.box(L.w + T, H, T, L.w / 2 - T / 2, 0, -T / 2, inner);
  b.box(L.w + T, 0.04, T + 0.02, L.w / 2 - T / 2, H, -T / 2, outer);
  b.box(T, H, L.d, -T / 2, 0, L.d / 2, shadeHex(inner, 0.94));
  b.box(T + 0.02, 0.04, L.d, -T / 2, H, L.d / 2, outer);
  b.box(L.w, 0.1, 0.02, L.w / 2, 0, 0.01, skirt);
  b.box(0.02, 0.1, L.d, 0.01, 0, L.d / 2, skirt);
  // windows on the back walls: frame, glass, sill, curtains (not in the low dollhouse walls)
  for (const [side, a0, a1] of doll ? [] : L.windows) {
    const w = a1 - a0;
    const m = (a0 + a1) / 2;
    const y0 = 0.95;
    const hh = 1.15;
    if (!rich) {
      // louvre window: tilted glass blades in a metal frame, burglar-proof bars in front
      louvres(b, side, a0, a1, y0, hh);
      continue;
    }
    if (side === 'n') {
      b.box(w + 0.1, hh + 0.1, 0.03, m, y0 - 0.05, 0.015, '#f7f7f5');
      b.box(w, hh, 0.02, m, y0, 0.03, '#000', { layer: 'glass' });
      b.box(0.04, hh, 0.03, m, y0, 0.04, '#f7f7f5');
      b.box(w + 0.16, 0.05, 0.12, m, y0 - 0.06, 0.06, '#e8e4dc');
      b.box(0.22, hh + 0.25, 0.03, a0 - 0.08, y0 - 0.1, 0.06, '#d9a441');
      b.box(0.22, hh + 0.25, 0.03, a1 + 0.08, y0 - 0.1, 0.06, '#d9a441');
    } else {
      b.box(0.03, hh + 0.1, w + 0.1, 0.015, y0 - 0.05, m, '#f7f7f5');
      b.box(0.02, hh, w, 0.03, y0, m, '#000', { layer: 'glass' });
      b.box(0.03, hh, 0.04, 0.04, y0, m, '#f7f7f5');
      b.box(0.12, 0.05, w + 0.16, 0.06, y0 - 0.06, m, '#e8e4dc');
      b.box(0.03, hh + 0.25, 0.22, 0.06, y0 - 0.1, a0 - 0.08, '#d9a441');
      b.box(0.03, hh + 0.25, 0.22, 0.06, y0 - 0.1, a1 + 0.08, '#d9a441');
    }
    nepoCurtains(b, side, a0, a1, y0, hh);
  }
  b.mat = null;
  // POP ceiling cornice round the top of the walls (Nepo)
  if (rich && !doll) {
    b.box(L.w + T, 0.16, 0.1, L.w / 2 - T / 2, H - 0.16, 0.05, '#fbf8f2', { mat: 'paint' });
    b.box(0.1, 0.16, L.d, 0.05, H - 0.16, L.d / 2, '#fbf8f2', { mat: 'paint' });
  }
  // a wall clock and a calendar on the north wall
  if (!doll) {
    b.cyl(0.16, 0.16, 0.03, L.w - 0.6, 1.85, 0.02, '#f7f7f5', { rx: Math.PI / 2, seg: 14 });
    b.box(0.02, 0.1, 0.01, L.w - 0.6, 1.85, 0.04, '#222');
    b.box(0.3, 0.4, 0.01, 0.6, 1.55, 0.02, '#1f7a3f');
    b.box(0.26, 0.24, 0.012, 0.6, 1.58, 0.022, '#f4f1ea');
  }

  // low cut-away walls (south, east) with door gaps, and interior partitions
  b.mat = rich ? 'paint' : 'plaster';
  for (const [x1, z1, x2, z2] of wallSegments(L)) {
    const isNorth = z1 === 0 && z2 === 0;
    const isWest = x1 === 0 && x2 === 0;
    if (isNorth || isWest) continue;
    const outerWall = (z1 === L.d && z2 === L.d) || (x1 === L.w && x2 === L.w);
    const h = doll ? (outerWall ? DOLL : Math.min(HALF, DOLL)) : outerWall ? LOW : HALF;
    const col = outerWall ? shadeHex(L.wall, 1.4) : inner;
    if (z1 === z2) {
      const len = Math.abs(x2 - x1);
      if (len < 0.01) continue;
      b.box(len + (outerWall ? T : 0.1), h, outerWall ? T : 0.1, (x1 + x2) / 2 + (outerWall ? T / 2 : 0), 0, z1 + (outerWall ? T / 2 : 0), col);
      b.box(len + (outerWall ? T : 0.1), 0.03, (outerWall ? T : 0.1) + 0.01, (x1 + x2) / 2 + (outerWall ? T / 2 : 0), h, z1 + (outerWall ? T / 2 : 0), outer);
    } else {
      const len = Math.abs(z2 - z1);
      if (len < 0.01) continue;
      b.box(outerWall ? T : 0.1, h, len + (outerWall ? T : 0.1), x1 + (outerWall ? T / 2 : 0), 0, (z1 + z2) / 2 + (outerWall ? T / 2 : 0), col);
      b.box((outerWall ? T : 0.1) + 0.01, 0.03, len + (outerWall ? T : 0.1), x1 + (outerWall ? T / 2 : 0), h, (z1 + z2) / 2 + (outerWall ? T / 2 : 0), outer);
    }
  }
  b.mat = null;
  // door mat at each entrance
  for (const [side, a0, a1] of L.doors) {
    const m = (a0 + a1) / 2;
    if (side === 'e') b.box(0.5, 0.015, Math.min(0.9, a1 - a0 - 0.1), L.w + 0.45, 0, m, '#6b4f3a');
    else b.box(Math.min(0.9, a1 - a0 - 0.1), 0.015, 0.5, m, 0, L.d + 0.45, '#6b4f3a');
  }

  // furniture
  for (const f of L.furniture) {
    if (doll && f.kind === 'ac') continue; // wall unit: nothing to hang it on in the low dollhouse walls
    b.setFrame(f.x, f.y ?? 0, f.z, ((f.rot ?? 0) * Math.PI) / 2);
    buildPiece(b, f, L.wallH);
    void KINDS;
  }
  b.resetFrame();

  // F1: the bulb (LAPO: one bare bulb on a wire) / POP downlights (Nepo), lived-in clutter, light pools
  const H2 = L.wallH;
  const bulb: [number, number, number] = [L.w * 0.5, H2 - 0.35, L.d * 0.55];
  const fan: [number, number, number] | null = doll ? null : [L.w * 0.42, H2 - 0.12, L.d * 0.42];
  const pools: [number, number][] = [];
  if (!doll) {
    if (rich) {
      for (const [fx, fz] of [[0.3, 0.3], [0.7, 0.3], [0.3, 0.72], [0.7, 0.72]] as const) pools.push([L.w * fx, L.d * fz]);
    } else {
      b.box(0.012, 0.35, 0.012, bulb[0], bulb[1] + 0.1, bulb[2], '#222');
      // Exposed surface wiring gives the single-bulb LAPO room a specific, lived-in ceiling detail.
      b.box(0.012, 0.012, Math.max(0.1, bulb[2] - 0.12), bulb[0], H2 - 0.025, bulb[2] / 2, '#302a24', { mat: 'metal', noOcc: true });
      b.cyl(0.05, 0.035, 0.1, bulb[0], bulb[1], bulb[2], '#fff3c4', { layer: 'glow', seg: 8 });
      pools.push([bulb[0], bulb[2]]);
    }
    const avoid: Rect[] = L.furniture.map((f) => {
      const [x0, z0, x1, z1] = footprint(f);
      return [x0 - 0.1, z0 - 0.1, x1 + 0.1, z1 + 0.1] as Rect;
    });
    for (const [side, a0, a1] of L.doors) avoid.push(side === 'e' ? [L.w - 1.2, a0 - 0.2, L.w + 0.5, a1 + 0.2] : [a0 - 0.2, L.d - 1.2, a1 + 0.2, L.d + 0.5]);
    for (const [x1, z1, x2, z2] of L.partitions) avoid.push([Math.min(x1, x2) - 0.2, Math.min(z1, z2) - 0.2, Math.max(x1, x2) + 0.2, Math.max(z1, z2) + 0.2]);
    const door = L.doors[0];
    buildClutter(b, {
      W: L.w, D: L.d, H: L.wallH, kind: rich ? 'home_nepo' : 'home_lapo', seed, density: opts.density ?? 1, avoid,
      windowsN: L.windows.filter((w) => w[0] === 'n').map((w) => [w[1] - 0.4, w[2] + 0.4] as [number, number]),
      windowsW: L.windows.filter((w) => w[0] === 'w').map((w) => [w[1] - 0.4, w[2] + 0.4] as [number, number]),
      door: door ? (door[0] === 's' ? { x: (door[1] + door[2]) / 2, z: L.d + 0.75 } : { x: L.w + 0.75, z: (door[1] + door[2]) / 2 }) : null,
    });
    buildPools(b, { W: L.w, D: L.d, H: L.wallH, kind: rich ? 'home_nepo' : 'home_lapo', seed, spots: pools, rich });
  }
  const layers = b.finish();
  return { layers, tris: b.tris, radius, rich, fan, bulb };
}

function mixCol(a: string, c: string): string {
  const pa = parseInt(a.slice(1), 16), pc = parseInt(c.slice(1), 16);
  const ch = (s: number) => Math.round((((pa >> s) & 255) + ((pc >> s) & 255)) / 2);
  return `#${((1 << 24) | (ch(16) << 16) | (ch(8) << 8) | ch(0)).toString(16).slice(1)}`;
}

/** LAPO louvre window: aluminium frame, tilted glass blades, burglar bars. */
function louvres(b: HomeBuilder, side: 'n' | 'w', a0: number, a1: number, y0: number, hh: number) {
  const w = a1 - a0;
  const m = (a0 + a1) / 2;
  const frame = '#9aa3ab';
  const n = 7;
  if (side === 'n') {
    b.box(w + 0.08, hh + 0.08, 0.04, m, y0 - 0.04, 0.02, frame, { mat: 'metal' });
    b.box(w, hh, 0.01, m, y0, 0.012, '#000', { layer: 'glass' });
    for (let i = 0; i < n; i++) b.box(w - 0.04, 0.012, 0.11, m, y0 + 0.08 + i * (hh / n), 0.06, '#c9d6dc', { rx: -0.5, mat: 'metal' });
    for (let x = a0 + 0.12; x < a1; x += 0.16) b.box(0.016, hh, 0.016, x, y0, 0.13, '#3a3f45', { mat: 'metal' });
    b.box(w + 0.2, 0.05, 0.14, m, y0 - 0.07, 0.07, '#c9c2b6', { mat: 'concrete' });
  } else {
    b.box(0.04, hh + 0.08, w + 0.08, 0.02, y0 - 0.04, m, frame, { mat: 'metal' });
    b.box(0.01, hh, w, 0.012, y0, m, '#000', { layer: 'glass' });
    for (let i = 0; i < n; i++) b.box(0.11, 0.012, w - 0.04, 0.06, y0 + 0.08 + i * (hh / n), m, '#c9d6dc', { rz: 0.5, mat: 'metal' });
    for (let z = a0 + 0.12; z < a1; z += 0.16) b.box(0.016, hh, 0.016, 0.13, y0, z, '#3a3f45', { mat: 'metal' });
    b.box(0.14, 0.05, w + 0.2, 0.07, y0 - 0.07, m, '#c9c2b6', { mat: 'concrete' });
  }
  // faded curtain bunched at one side
  if (side === 'n') b.box(0.24, hh + 0.2, 0.04, a0 - 0.06, y0 - 0.1, 0.07, '#b5503c', { mat: 'fabric' });
  else b.box(0.04, hh + 0.2, 0.24, 0.07, y0 - 0.1, a0 - 0.06, '#b5503c', { mat: 'fabric' });
}

/** Floor-length fabric panels and a slim rail give NEPO windows a softer, more finished silhouette. */
function nepoCurtains(b: HomeBuilder, side: 'n' | 'w', a0: number, a1: number, y0: number, hh: number) {
  const m = (a0 + a1) / 2;
  const panel = Math.min(0.34, (a1 - a0) * 0.22);
  const top = y0 + hh + 0.08;
  if (side === 'n') {
    b.box(a1 - a0 + 0.28, 0.035, 0.035, m, top, 0.095, '#887b69', { mat: 'metal' });
    for (const x of [a0 - 0.015, a1 + 0.015]) {
      b.box(panel, hh + 0.18, 0.055, x, y0 - 0.04, 0.085, '#c7b69e', { mat: 'fabric' });
      for (let i = -1; i <= 1; i++) b.box(0.018, hh + 0.12, 0.06, x + i * panel * 0.22, y0 - 0.01, 0.12, '#ad9b83', { mat: 'fabric' });
    }
  } else {
    b.box(0.035, 0.035, a1 - a0 + 0.28, 0.095, top, m, '#887b69', { mat: 'metal' });
    for (const z of [a0 - 0.015, a1 + 0.015]) {
      b.box(0.055, hh + 0.18, panel, 0.085, y0 - 0.04, z, '#c7b69e', { mat: 'fabric' });
      for (let i = -1; i <= 1; i++) b.box(0.06, hh + 0.12, 0.018, 0.12, y0 - 0.01, z + i * panel * 0.22, '#ad9b83', { mat: 'fabric' });
    }
  }
}
