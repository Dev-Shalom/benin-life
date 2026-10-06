// Shell of a home: ground disc, yard, tiled floor, cut-away walls, windows, then every piece of
// furniture. Returns merged geometries per layer (see build.ts) in layout space; the scene centres it.
import type { BufferGeometry } from 'three';
import { KINDS, type HomeLayout } from '../model';
import { wallSegments } from '../nav';
import { HomeBuilder, type Layer } from './build';
import { buildPiece, shadeHex } from './furniture';

export interface BuiltRoom {
  layers: Record<Layer, BufferGeometry | null>;
  tris: number;
  /** Ground disc radius (for camera framing). */
  radius: number;
}

const T = 0.12; // wall thickness
const LOW = 0.32; // cut-away front wall height
const HALF = 1.15; // interior partition height
const DOLL = 0.7; // S2 dollhouse view (welcome-back orbit): every wall this low, so the camera sees in from any side

function tiles(b: HomeBuilder, x0: number, z0: number, x1: number, z1: number, a: string, bc: string | undefined, size: number, y: number) {
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

export function buildRoom(L: HomeLayout, opts: { dollhouse?: boolean } = {}): BuiltRoom {
  const doll = Boolean(opts.dollhouse);
  const b = new HomeBuilder();
  const [lx0, lz0, lx1, lz1] = L.lot;
  const cx = (lx0 + lx1) / 2;
  const cz = (lz0 + lz1) / 2;
  const radius = Math.hypot(lx1 - lx0, lz1 - lz0) / 2 + 1.4;

  // ground: a low grassy island with a laterite rim, and the yard
  b.cyl(radius, radius + 0.25, 0.35, cx, -0.37, cz, '#a8c08a', { seg: 40 });
  b.cyl(radius + 0.25, radius + 0.4, 0.22, cx, -0.6, cz, '#b5552b', { seg: 40 });
  b.box(lx1 - lx0 + 0.5, 0.02, lz1 - lz0 + 0.5, cx, -0.03, cz, L.yard?.colour ?? '#b98a5e');
  if (L.yard?.fence) {
    // low block fence round the compound, open where the house is
    b.box(lx1 - lx0 + 0.5, 0.5, 0.12, cx, -0.01, lz0 - 0.25, '#c9c2b6');
    b.box(0.12, 0.5, lz1 - lz0 + 0.5, lx0 - 0.25, -0.01, cz, '#c9c2b6');
  }
  // path from the door to the edge
  const door = L.doors[0];
  if (door) {
    const mid = (door[1] + door[2]) / 2;
    if (door[0] === 'e') b.box(lx1 - L.w + 0.5, 0.025, door[2] - door[1], (L.w + lx1 + 0.5) / 2, -0.02, mid, '#cbbfae');
    else b.box(door[2] - door[1], 0.025, lz1 - L.d + 0.5, mid, -0.02, (L.d + lz1 + 0.5) / 2, '#cbbfae');
  }

  // house slab + floor
  b.box(L.w + T, 0.12, L.d + T, L.w / 2 - T / 2 + T / 2, -0.12, L.d / 2, shadeHex(L.wall, 1.25));
  tiles(b, 0, 0, L.w, L.d, L.floor.a, L.floor.b, L.floor.tile ?? 0.6, -0.01);
  for (const [x0, z0, x1, z1, a, bc, size] of L.patches ?? []) tiles(b, x0, z0, x1, z1, a, bc, size ?? 0.4, 0.008);

  // walls
  const H = doll ? DOLL : L.wallH;
  const inner = L.wallInner;
  const outer = L.wall;
  const skirt = shadeHex(inner, 0.82);
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
  }
  // a wall clock and a calendar on the north wall
  if (!doll) {
    b.cyl(0.16, 0.16, 0.03, L.w - 0.6, 1.85, 0.02, '#f7f7f5', { rx: Math.PI / 2, seg: 14 });
    b.box(0.02, 0.1, 0.01, L.w - 0.6, 1.85, 0.04, '#222');
    b.box(0.3, 0.4, 0.01, 0.6, 1.55, 0.02, '#1f7a3f');
    b.box(0.26, 0.24, 0.012, 0.6, 1.58, 0.022, '#f4f1ea');
  }

  // low cut-away walls (south, east) with door gaps, and interior partitions
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
  // a ceiling bulb glow marker above the main room (the real light is a point light)
  const layers = b.finish();
  return { layers, tris: b.tris, radius };
}
