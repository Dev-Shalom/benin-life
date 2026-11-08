// Free roam: turns the RoamWorld data into merged meshes, one CHUNK at a time (phase 2 streaming). Style: the same calm flat-shaded
// low-poly look as the drive scene (vertex colours, no textures except the sign atlas), at human scale: kerbs, pavements, doors,
// windows, awnings, stalls, lamps. Roads, houses, footprints, landmarks, trees come from the SAME layout as the 3D city map.
// buildChunkGen is a generator: it yields between small batches so the streamer can spend a few milliseconds a frame on it.
import {
  CanvasTexture,
  Color,
  Group,
  Matrix4,
  Mesh,
  MeshBasicMaterial,
  MeshLambertMaterial,
  PlaneGeometry,
  Quaternion,
  SRGBColorSpace,
  ShapeUtils,
  Vector2,
  Vector3,
  type BufferGeometry,
} from 'three';
import { HomeBuilder } from '../../home3d/engine/build';
import { buildLandmarks, vnoise } from '../../city3d/engine/build';
import { KERB } from '../../city3d/engine/roadnet';
import type { ChunkData } from '../chunks';
import type { RoamBuilding, RoamWorld } from '../world';
import { Soup } from './soup';

const shade = (hex: string, k: number) => {
  const c = new Color(hex);
  c.multiplyScalar(k);
  return c;
};
const hash = (i: number) => {
  const h = Math.sin(i * 12.9898 + 78.233) * 43758.5453;
  return h - Math.floor(h);
};

export interface SignCell {
  /** UV rectangle in the atlas. */
  u0: number;
  v0: number;
  u1: number;
  v1: number;
}

export const SIGN_W = 512;
export const SIGN_H = 96;

/** Draw the sign atlas (dev/browser only). Returns the texture and where each place's cell is. */
export function makeSignAtlas(labels: { label: string; accent: string }[]): { tex: CanvasTexture; cells: SignCell[] } {
  const cols = 2;
  const rows = Math.max(1, Math.ceil(labels.length / cols));
  const cv = document.createElement('canvas');
  cv.width = SIGN_W * cols;
  cv.height = SIGN_H * rows;
  const g = cv.getContext('2d')!;
  const cells: SignCell[] = [];
  labels.forEach((l, i) => {
    const cx = (i % cols) * SIGN_W, cy = Math.floor(i / cols) * SIGN_H;
    g.fillStyle = l.accent;
    g.beginPath();
    g.roundRect(cx + 4, cy + 4, SIGN_W - 8, SIGN_H - 8, 14);
    g.fill();
    g.strokeStyle = 'rgba(255,255,255,0.85)';
    g.lineWidth = 4;
    g.beginPath();
    g.roundRect(cx + 10, cy + 10, SIGN_W - 20, SIGN_H - 20, 10);
    g.stroke();
    g.fillStyle = '#ffffff';
    g.textAlign = 'center';
    g.textBaseline = 'middle';
    let size = 46;
    g.font = `800 ${size}px system-ui, "Segoe UI", sans-serif`;
    while (g.measureText(l.label).width > SIGN_W - 56 && size > 20) {
      size -= 2;
      g.font = `800 ${size}px system-ui, "Segoe UI", sans-serif`;
    }
    g.fillText(l.label, cx + SIGN_W / 2, cy + SIGN_H / 2 + 2);
    cells.push({ u0: cx / cv.width, u1: (cx + SIGN_W) / cv.width, v0: 1 - (cy + SIGN_H) / cv.height, v1: 1 - cy / cv.height });
  });
  const tex = new CanvasTexture(cv);
  tex.colorSpace = SRGBColorSpace;
  tex.anisotropy = 4;
  return { tex, cells };
}


const ROAD_COL: Record<string, string> = { express: '#454850', main: '#464951', ring: '#454850', minor: '#4d5056', spur: '#53565b', dirt: '#a9906b' };
/** Bigger roads sit a hair higher so a junction is one clean surface (no z-fighting between road colours). */
const ROAD_Y: Record<string, number> = { ring: 0.066, express: 0.064, main: 0.06, minor: 0.054, spur: 0.05, dirt: 0.046 };

export interface Kit {
  W: RoamWorld;
  tier: 'low' | 'high';
  signs: { tex: CanvasTexture; cells: SignCell[] } | null;
  /** Index of the "Under construction" board in the atlas (after the places and the shop names). */
  uncIdx: number;
  mats: {
    solid: MeshLambertMaterial;
    glassLit: MeshBasicMaterial;
    glow: MeshBasicMaterial;
    glowLand: MeshBasicMaterial;
    sign: MeshBasicMaterial;
  };
  dispose(): void;
}

export function makeKit(W: RoamWorld, o: { tier: 'low' | 'high'; signs: { tex: CanvasTexture; cells: SignCell[] } | null; uncIdx: number }): Kit {
  const solid = new MeshLambertMaterial({ vertexColors: true });
  const glassLit = new MeshBasicMaterial({ vertexColors: true, color: '#6f93a8' });
  const glow = new MeshBasicMaterial({ vertexColors: true, color: '#d8d2c4' });
  const glowLand = new MeshBasicMaterial({ vertexColors: true, color: '#9db4c4' });
  const sign = new MeshBasicMaterial({ vertexColors: true, map: o.signs?.tex ?? null });
  return {
    W, tier: o.tier, signs: o.signs, uncIdx: o.uncIdx,
    mats: { solid, glassLit, glow, glowLand, sign },
    dispose() {
      solid.dispose(); glassLit.dispose(); glow.dispose(); glowLand.dispose(); sign.dispose();
      o.signs?.tex.dispose();
    },
  };
}

/** What one built chunk hands back to the streamer. */
export interface ChunkMesh {
  group: Group;
  tris: number;
  calls: number;
  /** Trees standing in the chunk (the streamer instances them): global index, 32 matrix floats (canopy, trunk), 3 colour floats, x / y / canopy radius. */
  treeIdx: Int32Array;
  treeMat: Float32Array;
  treeCol: Float32Array;
  treeInfo: Float32Array;
  /** Lamp pool spots (x, y). */
  lamps: Float32Array;
  dispose(): void;
}

const SLICE_BUILDINGS = 6;
const SLICE_ROADS = 24;

/**
 * Build one chunk. Yields between batches; the return value is the finished chunk. Everything is generated by the same code as
 * the phase 1 street, but only items listed in the chunk are visited and only triangles centred in the chunk are kept.
 */
export function* buildChunkGen(kit: Kit, ck: ChunkData): Generator<void, ChunkMesh> {
  const W = kit.W;
  const o = { tier: kit.tier, signs: kit.signs };
  const L = W.L;
  const group = new Group();
  const geos: BufferGeometry[] = [];
  let tris = 0;
  let calls = 0;
  const clip: [number, number, number, number] = [ck.x0, ck.y0, ck.x1, ck.y1];
  const mk = () => { const s = new Soup(); s.clip = clip; return s; };
  const solid = mk();
  const groundSoup = solid;
  const glassDark = solid;
  const glassLit = mk();
  const glow = mk();
  const signSoup = mk();
  signSoup.withUv = true;
  const inChunk = (x: number, y: number, p = 0) => x >= ck.x0 - p && x < ck.x1 + p && y >= ck.y0 - p && y < ck.y1 + p;

  /* ================= ground ================= */
  {
    const cell = 15;
    const fx0 = Math.floor(ck.x0 / cell) * cell, fy0 = Math.floor(ck.y0 / cell) * cell;
    for (let z = fy0; z < ck.y1; z += cell)
      for (let x = fx0; x < ck.x1; x += cell) {
        const n = vnoise(x * 0.02, z * 0.02) * 0.5 + vnoise(x * 0.07, z * 0.07) * 0.5;
        const urban = L.urban(x + cell / 2, z + cell / 2);
        // sandy paving in town, drier grass out in the suburbs
        const c = new Color('#cbbf9f').lerp(new Color('#a8b378'), Math.max(0, 0.75 - urban) * 0.9).multiplyScalar(0.94 + n * 0.1);
        groundSoup.quad([x, 0, z], [x, 0, z + cell], [x + cell, 0, z + cell], [x + cell, 0, z], c, [0, 1, 0]);
      }
  }
  // King's Square: lawn, paths, a plaza round the museum
  if (inChunk(500, 500, 60)) {
    const cx = 500, cz = 500;
    const fan = (r: number, y: number, hex: string) => {
      const N = 40;
      for (let i = 0; i < N; i++) {
        const a0 = (i / N) * Math.PI * 2, a1 = ((i + 1) / N) * Math.PI * 2;
        groundSoup.tri(cx, y, cz, cx + Math.cos(a0) * r, y, cz + Math.sin(a0) * r, cx + Math.cos(a1) * r, y, cz + Math.sin(a1) * r, hex, 0, 1, 0);
      }
    };
    fan(49.2, 0.02, '#8db95f');
    fan(20, 0.032, '#d9cfb8');
    const ring = (r0: number, r1: number, y: number, hex: string) => {
      const N = 56;
      for (let i = 0; i < N; i++) {
        const a0 = (i / N) * Math.PI * 2, a1 = ((i + 1) / N) * Math.PI * 2;
        groundSoup.quad([cx + Math.cos(a0) * r0, y, cz + Math.sin(a0) * r0], [cx + Math.cos(a1) * r0, y, cz + Math.sin(a1) * r0], [cx + Math.cos(a1) * r1, y, cz + Math.sin(a1) * r1], [cx + Math.cos(a0) * r1, y, cz + Math.sin(a0) * r1], hex, [0, 1, 0]);
      }
    };
    ring(33, 35.2, 0.032, '#d9cfb8');
    for (let k = 0; k < 4; k++) {
      const a = (k * Math.PI) / 2 + Math.PI / 4;
      groundSoup.strip(cx + Math.cos(a) * 20, cz + Math.sin(a) * 20, cx + Math.cos(a) * 49.4, cz + Math.sin(a) * 49.4, 3.2, 0.034, '#d9cfb8');
    }
    groundSoup.strip(cx, cz + 20, cx, cz + 49.4, 3.6, 0.034, '#d9cfb8');
  }
  yield;
  // yards under the houses
  for (const bi of ck.buildings) {
    const b = W.buildings[bi];
    if (b.detail !== 1 || b.osm || !b.rect) continue;
    const r = b.rect;
    const gra = b.roofType !== 'flat' && hash(b.poly[0][0]) < 0.4;
    const c = Math.cos(r.a), s = Math.sin(r.a);
    const hw = r.w / 2 + 1.6, hd = r.d / 2 + 1.6;
    const P = (lx: number, lz: number) => [r.x + lx * c - lz * s, 0.012, r.y + lx * s + lz * c];
    groundSoup.quad(P(-hw, -hd), P(hw, -hd), P(hw, hd), P(-hw, hd), gra ? '#a3c26c' : '#d9cdb0', [0, 1, 0]);
  }

  /* ================= roads ================= */
  let dashPhase = 0;
  for (let q = 0; q < ck.roadSegs.length; q++) {
    if (q > 0 && q % SLICE_ROADS === 0) yield;
    const ri = Math.floor(ck.roadSegs[q] / 100000), i = ck.roadSegs[q] % 100000;
    const rd = L.roads[ri];
    const S = rd.sp.samples;
    const kerbW = KERB[rd.kind] ?? 0.8;
    const asph = ROAD_COL[rd.kind] ?? '#4a4d53';
    const n = S.length;
    const a = S[i], b = S[(i + 1) % n];
    const nax = -Math.sin(a.a), nay = Math.cos(a.a), nbx = -Math.sin(b.a), nby = Math.cos(b.a);
    const P = (p: typeof a, nx: number, ny: number, off: number, y: number) => [p.x + nx * off, y, p.y + ny * off];
    const quadOff = (o0: number, o1: number, y: number, hex: string | Color) =>
      groundSoup.quad(P(a, nax, nay, o0, y), P(b, nbx, nby, o0, y), P(b, nbx, nby, o1, y), P(a, nax, nay, o1, y), hex, [0, 1, 0]);
    if (kerbW > 0) {
      quadOff(rd.hw, rd.hw + kerbW, 0.03, '#d4cbbb');
      quadOff(-rd.hw - kerbW, -rd.hw, 0.03, '#d4cbbb');
    }
    quadOff(-rd.hw, rd.hw, ROAD_Y[rd.kind] ?? 0.06, asph);
    const mx = (a.x + b.x) / 2, my = (a.y + b.y) / 2;
    const junction = L.net.clear(mx, my, false, 1, ri) < -0.4;
    if (junction) continue;
      if (kerbW > 0) {
        // gutters, kerb stones (two tones in turn) and, here and there, a strip of red earth beside the pavement
        quadOff(rd.hw - 0.32, rd.hw, 0.072, '#3a3d43');
        quadOff(-rd.hw, -rd.hw + 0.32, 0.072, '#3a3d43');
        const kc = i % 2 ? '#c6bfb1' : '#b0a99b';
        quadOff(rd.hw, rd.hw + 0.2, 0.078, kc);
        quadOff(-rd.hw - 0.2, -rd.hw, 0.078, kc);
        if (hash(i * 3 + ri * 11) < 0.35) quadOff(rd.hw + kerbW, rd.hw + kerbW + 0.9, 0.02, '#b8694a');
        if (hash(i * 5 + ri * 13) < 0.35) quadOff(-rd.hw - kerbW - 0.9, -rd.hw - kerbW, 0.02, '#b8694a');
      }
      if (rd.kind !== 'dirt' && rd.kind !== 'spur' && hash(i * 7 + ri) < 0.85) {
        quadOff(rd.hw - 0.6, rd.hw - 0.45, 0.08, '#d3cebe');
        quadOff(-rd.hw + 0.45, -rd.hw + 0.6, 0.08, '#d3cebe');
      }
      if (rd.kind === 'main' || rd.kind === 'express' || rd.kind === 'ring') {
        const gold = rd.kind !== 'main';
        dashPhase++;
        if (rd.kind === 'ring' || rd.kind === 'express') {
          quadOff(-0.28, -0.1, 0.08, '#c9ad50');
          quadOff(0.1, 0.28, 0.08, '#c9ad50');
        } else if (dashPhase % 2 === 0) {
          quadOff(-0.1, 0.1, 0.08, gold ? '#c9ad50' : '#d3cebe');
        }
      }

    // a pothole or a patch now and then on the wider roads
    if (rd.kind !== 'dirt' && rd.kind !== 'spur' && hash(ri * 131 + i * 7) < 0.012) {
      const off = (hash(ri * 3 + i) - 0.5) * rd.hw * 1.5;
      const px = a.x - Math.sin(a.a) * off, pz = a.y + Math.cos(a.a) * off;
      if (L.net.clear(px, pz, false, 1, ri) >= 0) {
        const rr = 0.35 + hash(ri + i * 9) * 0.35;
        const ph = hash(ri * 7 + i) * 6;
        for (let k = 0; k < 6; k++) {
          const a0 = ph + (k / 6) * 6.283, a1 = ph + ((k + 1) / 6) * 6.283;
          groundSoup.tri(px, 0.085, pz, px + Math.cos(a0) * rr, 0.085, pz + Math.sin(a0) * rr * 0.8, px + Math.cos(a1) * rr, 0.085, pz + Math.sin(a1) * rr * 0.8, i % 2 ? '#34373c' : '#5a5d62', 0, 1, 0);
        }
      }
    }
  }
  yield;

  /* ================= buildings ================= */
  const tanks: number[] = [];
  let nb = 0;
  for (const bi of ck.buildings) {
    if (++nb % SLICE_BUILDINGS === 0) yield;
    const b = W.buildings[bi];
    if (b.lm) {
      // landmark models are drawn by buildLandmarks; they only get their door (palace gate, police entrance) and sign here
      if (b.place >= 0 && b.doorEdge >= 0) {
        const n = b.poly.length;
        const a = b.poly[b.doorEdge], c = b.poly[(b.doorEdge + 1) % n];
        let area = 0;
        for (let i = 0; i < n; i++) area += b.poly[i][0] * b.poly[(i + 1) % n][1] - b.poly[(i + 1) % n][0] * b.poly[i][1];
        const sgn = area > 0 ? 1 : -1;
        const len = Math.hypot(c[0] - a[0], c[1] - a[1]);
        const ex = (c[0] - a[0]) / len, ey = (c[1] - a[1]) / len;
        // the compound wall is about 1.2 m thick (centred on the polygon edge): put the gate on its outer face
        const nx0 = sgn * ey, ny0 = -sgn * ex, o2 = 0.68;
        addDoor(b, bi, [a[0] + nx0 * o2, a[1] + ny0 * o2], [c[0] + nx0 * o2, c[1] + ny0 * o2], ex, ey, nx0, ny0, len);
      }
      continue;
    }
    buildBuilding(b, bi);
  }

  function buildBuilding(b: RoamBuilding, bi: number) {
    const poly = b.poly;
    const h = b.h;
    const n = poly.length;
    let area = 0;
    for (let i = 0; i < n; i++) area += poly[i][0] * poly[(i + 1) % n][1] - poly[(i + 1) % n][0] * poly[i][1];
    const sgn = area > 0 ? 1 : -1;
    const plinthH = 0.45;
    const wallCol = new Color(b.wall).multiplyScalar(0.93 + hash(bi * 5 + 1) * 0.12);
    const plinth = shade(b.wall, 0.78);
    for (let i = 0; i < n; i++) {
      const a = poly[i], c = poly[(i + 1) % n];
      const len = Math.hypot(c[0] - a[0], c[1] - a[1]);
      if (len < 0.05) continue;
      const ex = (c[0] - a[0]) / len, ey = (c[1] - a[1]) / len;
      const nx = sgn * ey, ny = -sgn * ex;
      const A0 = [a[0], 0, a[1]], C0 = [c[0], 0, c[1]], A1 = [a[0], h, a[1]], C1 = [c[0], h, c[1]];
      const AP = [a[0], plinthH, a[1]], CP = [c[0], plinthH, c[1]];
      const nrm = [nx, 0, ny];
      if (b.detail !== 1) {
        // the far backdrop: one wall quad, no trim
        solid.quad(A0, C0, C1, A1, wallCol, nrm, 0.88, 1);
        continue;
      }
      solid.quad(A0, C0, CP, AP, plinth, nrm, 0.8, 1);
      solid.quad(AP, CP, [c[0], h - 0.4, c[1]], [a[0], h - 0.4, a[1]], wallCol, nrm, 0.93, 1);
      // cornice band at the top, a little proud of the wall
      solid.quad([a[0] + nx * 0.06, h - 0.4, a[1] + ny * 0.06], [c[0] + nx * 0.06, h - 0.4, c[1] + ny * 0.06], [c[0] + nx * 0.06, h, c[1] + ny * 0.06], [a[0] + nx * 0.06, h, a[1] + ny * 0.06], shade(b.wall, 1.07), nrm);
      // damp stain / peeling patch on some walls
      if (len > 2.5 && hash(bi * 7 + i) < 0.3) {
        const t0 = hash(bi + i * 3) * 0.5, wdt = Math.min(1.6, len * 0.35);
        const u0 = t0 * len, u1 = u0 + wdt;
        solid.quad([a[0] + ex * u0 + nx * 0.02, plinthH, a[1] + ey * u0 + ny * 0.02], [a[0] + ex * u1 + nx * 0.02, plinthH, a[1] + ey * u1 + ny * 0.02], [a[0] + ex * u1 + nx * 0.02, plinthH + 1.0 + hash(i) * 0.8, a[1] + ey * u1 + ny * 0.02], [a[0] + ex * u0 + nx * 0.02, plinthH + 1.0 + hash(i) * 0.8, a[1] + ey * u0 + ny * 0.02], shade(b.wall, 0.86), nrm);
      }
      if (b.detail !== 1 || len < 2.0) continue;
      // windows: only where the wall faces open ground (not into the next building)
      const mx = (a[0] + c[0]) / 2, my = (a[1] + c[1]) / 2;
      const isDoor = i === b.doorEdge;
      const visible = W.col.clear(mx + nx * 0.7, my + ny * 0.7, 0.2, -1, false) || isDoor;
      if (!visible) continue;
      if (isDoor) addDoor(b, bi, a, c, ex, ey, nx, ny, len);
      const margin = len < 3.4 ? 0.5 : 0.8;
      const cols = Math.max(len < 3.4 ? 1 : 0, Math.floor((len - margin * 2) / 2.7));
      const floors = Math.max(1, Math.floor((h - 0.2) / 3));
      for (let f = 0; f < floors; f++) {
        const y0 = 0.45 + f * 3 + 0.95;
        const y1 = y0 + 1.25;
        if (y1 > h - 0.4) continue;
        for (let k = 0; k < cols; k++) {
          const t = (margin + ((k + 0.5) * (len - margin * 2)) / cols) / len;
          if (isDoor && f === 0 && Math.abs(t - b.doorT) * len < (b.place >= 0 ? 1.9 : 1.3)) continue;
          const px = a[0] + (c[0] - a[0]) * t + nx * 0.035, pz = a[1] + (c[1] - a[1]) * t + ny * 0.035;
          const hwid = 0.5;
          const q = [[px - ex * hwid, y0, pz - ey * hwid], [px + ex * hwid, y0, pz + ey * hwid], [px + ex * hwid, y1, pz + ey * hwid], [px - ex * hwid, y1, pz - ey * hwid]];
          const lit = hash(bi * 31 + f * 7 + k) < 0.7 && (b.lit || hash(bi) < 0.6);
          const wq = (u0: number, u1: number, ya: number, yb: number, col: string, off: number) =>
            solid.quad([px + ex * u0 + nx * off, ya, pz + ey * u0 + ny * off], [px + ex * u1 + nx * off, ya, pz + ey * u1 + ny * off],
              [px + ex * u1 + nx * off, yb, pz + ey * u1 + ny * off], [px + ex * u0 + nx * off, yb, pz + ey * u0 + ny * off], col, nrm);
          if (o.tier === 'high' || hash(bi + k) < 0.4) wq(-0.62, 0.62, y0 - 0.1, y1 + 0.1, '#ece5d4', -0.012);
          (lit ? glassLit : glassDark).quad(q[0], q[1], q[2], q[3], lit ? '#ffffff' : '#4d6b7d', nrm);
          // burglary-proof bars on about half of the windows
          if (o.tier === 'high' && hash(bi * 17 + f * 3 + k) < 0.45) for (const u of [-0.2, 0.2]) wq(u - 0.022, u + 0.022, y0, y1, '#2f3338', 0.05);
        }
      }
    }
    // roof
    const roofCol = new Color(b.roof);
    if (b.roofType !== 'flat' && b.rect) {
      pitchedRoof(b, h, roofCol, wallCol);
    } else {
      const ring = poly.map(([x, y]) => new Vector2(x, y));
      const cap = ShapeUtils.triangulateShape(ring, []);
      for (const [i0, i1, i2] of cap) {
        const p0 = poly[i0], p1 = poly[i1], p2 = poly[i2];
        solid.tri(p0[0], h + 0.45, p0[1], p1[0], h + 0.45, p1[1], p2[0], h + 0.45, p2[1], roofCol, 0, 1, 0);
      }
      for (let i = 0; i < n; i++) {
        const a = poly[i], c = poly[(i + 1) % n];
        const len = Math.hypot(c[0] - a[0], c[1] - a[1]) || 1;
        const nx = (sgn * (c[1] - a[1])) / len, ny = (-sgn * (c[0] - a[0])) / len;
        solid.quad([a[0], h, a[1]], [c[0], h, c[1]], [c[0], h + 0.45, c[1]], [a[0], h + 0.45, a[1]], shade(b.wall, 0.7), [nx, 0, ny]);
      }
      if (b.detail === 1 && h > 4.5 && hash(bi * 13) < 0.3) {
        let cx = 0, cy = 0;
        for (const [x, y] of poly) { cx += x / n; cy += y / n; }
        tanks.push(cx, h + 0.45, cy);
      }
    }
  }

  function pitchedRoof(b: RoamBuilding, h: number, roof: Color, wall: Color) {
    const r = b.rect!;
    const c = Math.cos(r.a), s = Math.sin(r.a);
    const ow = b.over ?? 0.4;
    const hw = r.w / 2 + ow, hd = r.d / 2 + ow;
    const rh = Math.max(1.1, Math.min(2.6, Math.min(r.w, r.d) * 0.28));
    const P = (lx: number, y: number, lz: number) => [r.x + lx * c - lz * s, y, r.y + lx * s + lz * c];
    const e0 = P(-hw, h, -hd), e1 = P(hw, h, -hd), e2 = P(hw, h, hd), e3 = P(-hw, h, hd);
    const alongX = r.w >= r.d;
    const N3 = (lx: number, ly: number, lz: number) => [lx * c - lz * s, ly, lx * s + lz * c];
    const ridge = (a: number, b2: number, y: number) => (alongX ? [P(a, y, 0), P(b2, y, 0)] : [P(0, y, a), P(0, y, b2)]);
    const yr = h + rh;
    if (b.roofType === 'gable') {
      if (alongX) {
        const [r0, r1] = ridge(-hw + 0.1, hw - 0.1, yr);
        solid.quad(e0, e1, r1, r0, roof, N3(0, 1, -1), 1);
        solid.quad(e3, e2, r1, r0, roof, N3(0, 1, 1), 1);
        solid.tri(e0[0], h, e0[2], e3[0], h, e3[2], r0[0], yr, r0[2], wall, -c, 0, -s);
        solid.tri(e1[0], h, e1[2], e2[0], h, e2[2], r1[0], yr, r1[2], wall, c, 0, s);
      } else {
        const [r0, r1] = ridge(-hd + 0.1, hd - 0.1, yr);
        solid.quad(e0, e3, r1, r0, roof, N3(-1, 1, 0), 1);
        solid.quad(e1, e2, r1, r0, roof, N3(1, 1, 0), 1);
        solid.tri(e0[0], h, e0[2], e1[0], h, e1[2], r0[0], yr, r0[2], wall, N3(0, 0, -1)[0], 0, N3(0, 0, -1)[2]);
        solid.tri(e3[0], h, e3[2], e2[0], h, e2[2], r1[0], yr, r1[2], wall, N3(0, 0, 1)[0], 0, N3(0, 0, 1)[2]);
      }
    } else {
      // hip: ridge shortened to leave sloped ends
      const half = Math.abs(hw - hd) * 0.9;
      const [r0, r1] = alongX ? [P(-half, yr, 0), P(half, yr, 0)] : [P(0, yr, -half), P(0, yr, half)];
      if (alongX) {
        solid.quad(e0, e1, r1, r0, roof, N3(0, 1, -0.7), 1);
        solid.quad(e3, e2, r1, r0, roof, N3(0, 1, 0.7), 1);
        solid.tri(e0[0], h, e0[2], e3[0], h, e3[2], r0[0], yr, r0[2], roof, N3(-0.7, 1, 0)[0], 1, N3(-0.7, 1, 0)[2], 0.95);
        solid.tri(e1[0], h, e1[2], e2[0], h, e2[2], r1[0], yr, r1[2], roof, N3(0.7, 1, 0)[0], 1, N3(0.7, 1, 0)[2], 0.95);
      } else {
        solid.quad(e0, e3, r1, r0, roof, N3(-0.7, 1, 0), 1);
        solid.quad(e1, e2, r1, r0, roof, N3(0.7, 1, 0), 1);
        solid.tri(e0[0], h, e0[2], e1[0], h, e1[2], r0[0], yr, r0[2], roof, N3(0, 1, -0.7)[0], 1, N3(0, 1, -0.7)[2], 0.95);
        solid.tri(e3[0], h, e3[2], e2[0], h, e2[2], r1[0], yr, r1[2], roof, N3(0, 1, 0.7)[0], 1, N3(0, 1, 0.7)[2], 0.95);
      }
    }
    // eaves underside darker line
    void wall;
  }

  function addDoor(b: RoamBuilding, bi: number, a: readonly [number, number], c: readonly [number, number], ex: number, ey: number, nx: number, ny: number, len: number) {
    const place = b.place >= 0 ? W.places[b.place] : null;
    const shop = !place && b.shop !== undefined;
    const accentHex = place ? place.accent : ['#c0643f', '#2e9d58', '#5c7fb5', '#d9822b', '#7a4ac8', '#3f7f9c'][Math.floor(hash(bi * 3) * 6)];
    const wid = place ? place.door.w : shop ? 2.2 : 1.0;
    const t = place ? ((place.door.x - a[0]) * ex + (place.door.y - a[1]) * ey) / len : b.doorT;
    const px = a[0] + (c[0] - a[0]) * t, pz = a[1] + (c[1] - a[1]) * t;
    const nrm = [nx, 0, ny];
    const dh = Math.min(2.2, b.h - 0.6);
    const palace = place?.scene === 'palace';
    const wood = palace ? new Color('#33201a') : place ? shade(place.accent, 0.72) : new Color(['#5b3a24', '#3f5f6a', '#6b3b2a', '#4a4f57'][Math.floor(hash(bi) * 4)]);
    const off = 0.045;
    const hw = wid / 2;
    const Q = (u: number, y: number, o = off) => [px + ex * u + nx * o, y, pz + ey * u + ny * o];
    // frame + door leaf
    solid.quad(Q(-hw - 0.14, 0.05, 0.03), Q(hw + 0.14, 0.05, 0.03), Q(hw + 0.14, dh + 0.14, 0.03), Q(-hw - 0.14, dh + 0.14, 0.03), '#e9e2d2', nrm);
    if (place && b.h > 3.6) {
      // shop front: a wide glass door with a dark inside
      solid.quad(Q(-hw, 0.05), Q(hw, 0.05), Q(hw, dh), Q(-hw, dh), wood, nrm);
      glassLit.quad(Q(-hw + 0.12, 0.55, 0.06), Q(hw - 0.12, 0.55, 0.06), Q(hw - 0.12, dh - 0.15, 0.06), Q(-hw + 0.12, dh - 0.15, 0.06), '#ffffff', nrm);
    } else if (shop) {
      // a roller shutter, pulled half up on some
      const up = hash(bi * 9) < 0.5 ? 0.9 : 0;
      solid.quad(Q(-hw, 0.05), Q(hw, 0.05), Q(hw, dh), Q(-hw, dh), '#2a2d36', nrm);
      solid.quad(Q(-hw, 0.05, 0.06), Q(hw, 0.05, 0.06), Q(hw, dh - up, 0.06), Q(-hw, dh - up, 0.06), '#9aa0a6', nrm);
      for (let r2 = 1; r2 < 6; r2++) solid.quad(Q(-hw, 0.05 + ((dh - up) * r2) / 6, 0.075), Q(hw, 0.05 + ((dh - up) * r2) / 6, 0.075), Q(hw, 0.09 + ((dh - up) * r2) / 6, 0.075), Q(-hw, 0.09 + ((dh - up) * r2) / 6, 0.075), '#6d737a', nrm);
      if (up) glassLit.quad(Q(-hw + 0.1, dh - up, 0.065), Q(hw - 0.1, dh - up, 0.065), Q(hw - 0.1, dh - 0.05, 0.065), Q(-hw + 0.1, dh - 0.05, 0.065), '#ffffff', nrm);
    } else {
      solid.quad(Q(-hw, 0.05), Q(hw, 0.05), Q(hw, dh), Q(-hw, dh), wood, nrm);
      solid.quad(Q(hw * 0.55, 1.0, 0.08), Q(hw * 0.78, 1.0, 0.08), Q(hw * 0.78, 1.12, 0.08), Q(hw * 0.55, 1.12, 0.08), '#d9a441', nrm);
    }
    if (place || shop) glow.box(px + nx * 0.3, Math.min(b.h - 0.3, dh + 0.28), pz + ny * 0.3, 0.4, 0.1, 0.18, Math.atan2(ey, ex), '#ffffff', 1);
    // step
    solid.box(px + nx * 0.25, 0, pz + ny * 0.25, wid + 0.9, 0.12, 0.5, Math.atan2(ey, ex), '#c9c2b2', 1);
    if ((place || shop) && !palace) {
      const accent = new Color(accentHex);
      // awning over the door
      const aw = Math.max(2.6, wid + 1.2);
      const ya = Math.min(dh + 0.45, b.h - 0.85);
      const proj = 1.05;
      const A = [px - ex * aw / 2 + nx * 0.04, ya + 0.1, pz - ey * aw / 2 + ny * 0.04];
      const B = [px + ex * aw / 2 + nx * 0.04, ya + 0.1, pz + ey * aw / 2 + ny * 0.04];
      const C = [px + ex * aw / 2 + nx * proj, ya - 0.28, pz + ey * aw / 2 + ny * proj];
      const D = [px - ex * aw / 2 + nx * proj, ya - 0.28, pz - ey * aw / 2 + ny * proj];
      solid.quad(A, B, C, D, accent, [0, 1, 0]);
      const stripes = Math.round(aw / 0.5);
      for (let k = 0; k < stripes; k += 2) {
        const u0 = -aw / 2 + (k * aw) / stripes, u1 = -aw / 2 + ((k + 1) * aw) / stripes;
        const S = (u: number, f: number) => [px + ex * u + nx * (0.04 + (proj - 0.04) * f), ya + 0.1 - 0.38 * f + 0.012, pz + ey * u + ny * (0.04 + (proj - 0.04) * f)];
        solid.quad(S(u0, 0), S(u1, 0), S(u1, 1), S(u0, 1), '#f4efe3', [0, 1, 0]);
      }
      solid.quad(C, D, [D[0], D[1] - 0.18, D[2]], [C[0], C[1] - 0.18, C[2]], shade(accentHex, 0.8), nrm);
      // sign board above
      addSign(place ? b.place : W.places.length + b.shop!, px, ya + 1.35, pz, ex, ey, nx, ny, Math.min(3.0, Math.max(2.4, aw)), 0.62, 0.07);
    }
    if (palace) {
      addSign(b.place, px + nx * 0.3, 4.75, pz + ny * 0.3, ex, ey, nx, ny, 3.6, 0.7, 0.4);
      // the palace gate: tall red-earth pillars with pyramid caps, a dark double gate with gold studs, a bronze plaque
      for (const sg of [-1, 1]) {
        const ux = px + ex * (hw + 0.75) * sg, uz = pz + ey * (hw + 0.75) * sg;
        solid.box(ux + nx * 0.3, 0, uz + ny * 0.3, 0.9, 4.6, 0.9, Math.atan2(ey, ex), '#a14a30', 0.85);
        solid.box(ux + nx * 0.3, 4.6, uz + ny * 0.3, 1.1, 0.2, 1.1, Math.atan2(ey, ex), '#6e2f1f', 1);
        solid.cyl(ux + nx * 0.3, 4.8, uz + ny * 0.3, 0.7, 0.02, 1.2, '#7e4630', 4);
        solid.box(ux + nx * 0.3, 3.6, uz + ny * 0.3, 0.2, 0.2, 0.2, 0, '#d9a441', 1);
      }
      solid.box(px + nx * 0.3, 3.5, pz + ny * 0.3, wid + 2.6, 0.5, 0.7, Math.atan2(ey, ex), '#8d3a24', 0.9);
      for (let k = -2; k <= 2; k++) solid.box(px + ex * k * 0.35 + nx * 0.1, 1.3, pz + ey * k * 0.35 + ny * 0.1, 0.12, 0.12, 0.08, 0, '#d9a441', 1);
    }
  }

  function addSign(placeIdx: number, px: number, yTop: number, pz: number, ex: number, ey: number, nx: number, ny: number, w: number, hgt: number, off: number, backToo = false) {
    const cell = o.signs?.cells[placeIdx];
    if (!cell) return;
    const nrm = [nx, 0, ny];
    const right = [ny, 0, -nx]; // viewer's right when looking at the sign from outside
    const Q = (u: number, y: number): number[] => [px + right[0] * u + nx * off, y, pz + right[2] * u + ny * off];
    signSoup.quadUv(Q(-w / 2, yTop - hgt), Q(w / 2, yTop - hgt), Q(w / 2, yTop), Q(-w / 2, yTop), nrm, cell.u0, cell.v0, cell.u1, cell.v1);
    if (backToo) {
      const Qb = (u: number, y: number): number[] => [px + right[0] * u - nx * off, y, pz + right[2] * u - ny * off];
      signSoup.quadUv(Qb(w / 2, yTop - hgt), Qb(-w / 2, yTop - hgt), Qb(-w / 2, yTop), Qb(w / 2, yTop), [-nx, 0, -ny], cell.u0, cell.v0, cell.u1, cell.v1);
    }
    void ex; void ey;
    // dark backing board
    solid.box(px + nx * (off - 0.05), yTop - hgt - 0.04, pz + ny * (off - 0.05), w + 0.14, hgt + 0.08, 0.06, Math.atan2(-nx, ny), '#2a2d36', 1);
  }


  for (let i = 0; i < tanks.length; i += 3) solid.cyl(tanks[i], tanks[i + 1], tanks[i + 2], 0.6, 0.55, 0.95, '#b9c4c9', 7);
  yield;

  /* ================= GRA compound walls ================= */
  for (const wi of ck.walls) {
    const w = W.walls[wi];
    solid.box(w.x, 0, w.y, w.len, 1.8, 0.3, w.a, '#ece3cf', 0.85, '#cfc4aa');
    solid.box(w.x, 1.8, w.y, w.len + 0.1, 0.12, 0.42, w.a, '#b9ad92', 0.9);
    const c = Math.cos(w.a), s = Math.sin(w.a);
    for (const sg of [-1, 1]) solid.box(w.x + c * (w.len / 2) * sg, 0, w.y + s * (w.len / 2) * sg, 0.5, 2.1, 0.5, w.a, '#e4d9c1', 0.85, '#b9ad92');
  }

  /* ================= place entrances: arches, shut gates and kiosks ================= */
  for (const pi of ck.places) {
    const pl = W.places[pi];
    const d = pl.door;
    if (d.kind === 'arch') {
      const lx = -d.ny, ly = d.nx; // along the arch
      const hw = d.w / 2;
      const acc = pl.accent;
      for (const sgn of [-1, 1]) {
        solid.cyl(d.x + lx * hw * sgn, 0, d.y + ly * hw * sgn, 0.2, 0.2, 3.5, shade(acc, 0.75), 6);
        solid.box(d.x + lx * hw * sgn, 3.5, d.y + ly * hw * sgn, 0.5, 0.18, 0.5, 0, '#2a2d36', 1);
      }
      solid.box(d.x, 3.55, d.y, d.w + 0.3, 0.16, 0.26, Math.atan2(ly, lx), shade(acc, 0.8), 1);
      addSign(pi, d.x, 3.5, d.y, lx, ly, d.nx, d.ny, Math.max(3.4, d.w - 0.6), 0.85, 0.06, true);
      // bunting-ish flags (tiny coloured boxes)
      for (let k = 0; k < 6; k++) {
        const u = -hw + ((k + 0.5) * d.w) / 6;
        solid.box(d.x + lx * u, 2.8, d.y + ly * u, 0.22, 0.28, 0.02, Math.atan2(ly, lx), ['#d63c32', '#f2b632', '#2e9d58', '#2f6fd0', '#e06a1c', '#7a4ac8'][k % 6], 1);
      }
    }
  }

  // a closed place (the airport): a shut steel gate, a striped barrier, its name and an "Under construction" board
  for (const pi of ck.places) {
    const pl = W.places[pi];
    const d = pl.door;
    if (d.kind !== 'gate') continue;
    const lx = -d.ny, ly = d.nx;
    const hw = d.w / 2;
    const ang = Math.atan2(ly, lx);
    for (const sg of [-1, 1]) {
      solid.box(d.x + lx * hw * sg, 0, d.y + ly * hw * sg, 0.7, 3.2, 0.7, ang, '#bdb5a4', 0.85, '#8d8575');
      solid.box(d.x + lx * hw * sg, 3.2, d.y + ly * hw * sg, 0.95, 0.18, 0.95, ang, '#8d8575', 1);
    }
    // two steel leaves with vertical bars, a chain and padlock in the middle
    solid.box(d.x, 0.15, d.y, d.w - 0.7, 2.3, 0.1, ang, '#4b5560', 0.85);
    for (let k = -6; k <= 6; k++) solid.box(d.x + lx * k * 0.5 + d.nx * 0.07, 0.15, d.y + ly * k * 0.5 + d.ny * 0.07, 0.06, 2.3, 0.06, ang, '#2f363e', 1);
    solid.box(d.x + d.nx * 0.1, 1.15, d.y + d.ny * 0.1, 0.5, 0.22, 0.12, ang, '#c9ad50', 1);
    // a red and white barrier pole across the road side, cones either side
    for (let k = 0; k < 6; k++) {
      const u0 = -hw + 0.4 + (k * (d.w - 0.8)) / 6;
      solid.box(d.x + lx * (u0 + (d.w - 0.8) / 12) + d.nx * 1.0, 0.95, d.y + ly * (u0 + (d.w - 0.8) / 12) + d.ny * 1.0, (d.w - 0.8) / 6, 0.12, 0.12, ang, k % 2 ? '#f4efe3' : '#d63c32', 1);
    }
    for (const sg of [-1, 1]) solid.cyl(d.x + lx * (hw + 0.5) * sg + d.nx * 1.0, 0, d.y + ly * (hw + 0.5) * sg + d.ny * 1.0, 0.2, 0.04, 0.6, '#e8742c', 6);
    addSign(pi, d.x + d.nx * 0.2, 4.35, d.y + d.ny * 0.2, lx, ly, d.nx, d.ny, 4.8, 0.85, 0.12, true);
    addSign(kit.uncIdx, d.x + d.nx * 0.2, 2.15, d.y + d.ny * 0.2, lx, ly, d.nx, d.ny, 3.6, 0.7, 0.16, true);
    glow.box(d.x + d.nx * 0.3, 3.4, d.y + d.ny * 0.3, 0.3, 0.2, 0.2, ang, '#ffffff', 1);
  }
  for (const ki of ck.kiosks) {
    const k = W.kiosks[ki];
    const pl = W.places[k.placeIdx];
    if (!pl) continue;
    const d = pl.door;
    const acc = new Color(pl.accent);
    const c = Math.cos(k.a), s = Math.sin(k.a);
    solid.box(k.x, 0, k.y, 2.4, 2.35, 1.8, k.a, '#e8e1d0', 0.8);
    solid.box(k.x, 2.35, k.y, 2.7, 0.14, 2.1, k.a, acc, 1);
    // window opening + counter on the street side
    const nrm = [d.nx, 0, d.ny];
    const ex = c, ey = s;
    const Q = (u: number, y: number, o: number) => [d.x + ex * u + d.nx * o, y, d.y + ey * u + d.ny * o];
    glassLit.quad(Q(-0.8, 1.05, 0.02), Q(0.8, 1.05, 0.02), Q(0.8, 2.0, 0.02), Q(-0.8, 2.0, 0.02), '#ffffff', nrm);
    glow.box(d.x + d.nx * 0.5, 2.3, d.y + d.ny * 0.5, 0.5, 0.1, 0.2, k.a, '#ffffff', 1);
    solid.box(d.x + d.nx * 0.12, 0.95, d.y + d.ny * 0.12, 1.7, 0.08, 0.34, k.a, '#8a5a33', 1);
    // umbrella
    solid.cyl(k.x + c * 0.7 - s * 0.0, 2.35, k.y + s * 0.7, 0.04, 0.04, 1.0, '#59616b', 5);
    solid.cyl(k.x + c * 0.7, 3.2, k.y + s * 0.7, 1.15, 0.05, 0.4, acc, 8, 1);
    const cell = o.signs?.cells[k.placeIdx];
    if (cell) {
      const right = [d.ny, 0, -d.nx];
      const px = d.x + d.nx * 0.2, pz = d.y + d.ny * 0.2;
      const Qs = (u: number, y: number): number[] => [px + right[0] * u + d.nx * 0.05, y, pz + right[2] * u + d.ny * 0.05];
      signSoup.quadUv(Qs(-1.15, 2.5), Qs(1.15, 2.5), Qs(1.15, 3.1), Qs(-1.15, 3.1), nrm, cell.u0, cell.v0, cell.u1, cell.v1);
    }
  }

  yield;

  /* ================= stalls ================= */
  for (const si of ck.stalls) {
    const st = W.stalls[si];
    const c = Math.cos(st.a), s = Math.sin(st.a);
    solid.box(st.x, 0, st.y, st.w, 0.85, st.d, st.a, '#8a5a33', 0.85, '#a97d4d');
    // goods on the counter
    const goods = ['#d63c32', '#f2b632', '#2e9d58', '#e06a1c', '#f4efe3'];
    for (let k = 0; k < 4; k++) {
      const u = -st.w / 2 + 0.3 + k * 0.4;
      solid.box(st.x + c * u + st.fx * 0.05, 0.85, st.y + s * u + st.fy * 0.05, 0.3, 0.18, 0.3, st.a + k, goods[(k + Math.floor(st.x)) % goods.length], 0.9);
    }
    if (hash(st.x * 7 + st.y) < 0.55) {
      // a big striped umbrella
      const ux = st.x - st.fx * 0.7, uz = st.y - st.fy * 0.7;
      solid.cyl(ux, 0, uz, 0.04, 0.04, 2.45, '#59616b', 4);
      const um = [st.color, '#f4efe3'];
      for (let q2 = 0; q2 < 8; q2++) {
        const a0 = (q2 / 8) * 6.283, a1 = ((q2 + 1) / 8) * 6.283;
        solid.tri(ux + Math.cos(a0) * 1.7, 2.3, uz + Math.sin(a0) * 1.7, ux + Math.cos(a1) * 1.7, 2.3, uz + Math.sin(a1) * 1.7, ux, 2.85, uz, um[q2 % 2], Math.cos((a0 + a1) / 2), 0.7, Math.sin((a0 + a1) / 2));
      }
      solid.box(st.x + st.fx * 0.9, 0, st.y + st.fy * 0.9, 0.5, 0.4, 0.5, st.a + 0.3, '#b08850', 0.85);
      continue;
    }
    // canopy on four poles
    for (const [u, v] of [[-1, -1], [1, -1], [1, 1], [-1, 1]]) {
      const px = st.x + c * u * (st.w / 2 + 0.2) - s * v * (st.d / 2 + 0.55) - st.fx * 0.4;
      const pz = st.y + s * u * (st.w / 2 + 0.2) + c * v * (st.d / 2 + 0.55) - st.fy * 0.4;
      solid.cyl(px, 0, pz, 0.04, 0.04, 2.3, '#59616b', 4);
    }
    solid.box(st.x - st.fx * 0.4, 2.3, st.y - st.fy * 0.4, st.w + 0.7, 0.07, st.d + 1.4, st.a, st.color, 1);
    solid.box(st.x + st.fx * 0.9, 0, st.y + st.fy * 0.9 + 0, 0.5, 0.4, 0.5, st.a + 0.3, '#b08850', 0.85);
  }


  /* ================= Igun Street: bronze pieces on plinths ================= */
  for (const di of ck.displays) {
    const d = W.displays[di];
    solid.box(d.x, 0, d.y, 0.55, 0.85, 0.55, 0, '#6d655a', 0.85, '#8a8274');
    if (d.kind === 'bust') {
      solid.cyl(d.x, 0.85, d.y, 0.2, 0.15, 0.3, '#b07a3a', 7);
      solid.cyl(d.x, 1.15, d.y, 0.13, 0.12, 0.22, '#c28a44', 7);
      solid.cyl(d.x, 1.37, d.y, 0.1, 0.02, 0.16, '#9a6a30', 7);
    } else {
      solid.box(d.x, 0.85, d.y, 0.45, 0.6, 0.07, 0.6, '#b07a3a', 0.9);
      solid.box(d.x, 1.2, d.y, 0.3, 0.2, 0.09, 0.6, '#d19b52', 1);
    }
  }


  /* ================= parked cars ================= */
  const carBody = (x: number, z: number, a: number, hex: string, kind: 'car' | 'bus' | 'keke') => {
    const c = new Color(hex);
    if (kind === 'car') {
      solid.box(x, 0.28, z, 3.9, 0.62, 1.8, a, c, 0.85);
      solid.box(x - Math.cos(a) * 0.15, 0.9, z - Math.sin(a) * 0.15, 2.1, 0.55, 1.6, a, shade(hex, 0.96), 0.9, '#cfd6da');
      glassDark.box(x - Math.cos(a) * 0.15, 0.95, z - Math.sin(a) * 0.15, 2.14, 0.4, 1.62, a, '#33444f', 1);
      for (const [u, v] of [[1.25, 0.9], [-1.25, 0.9], [1.25, -0.9], [-1.25, -0.9]]) solid.cyl(x + Math.cos(a) * u - Math.sin(a) * v, 0, z + Math.sin(a) * u + Math.cos(a) * v, 0.32, 0.32, 0.22, '#1d1f24', 6);
    } else {
      // a danfo / minibus: a deep lower body, a black (or red) waist band, a glazed cabin with a roof rack, a raked windscreen, wheels
      const ch = Math.cos(a), sh = Math.sin(a);
      const at2 = (u: number) => [x + ch * u, z + sh * u];
      const band = hex.toLowerCase().startsWith('#f') && c.g > 0.5 && c.b < 0.4 ? '#1c1c1f' : '#c8372d';
      solid.box(x, 0.38, z, 5.3, 0.95, 2.1, a, c, 0.85);
      solid.box(x, 0.88, z, 5.34, 0.2, 2.14, a, band, 1);
      glassDark.box(x - ch * 0.15, 1.33, z - sh * 0.15, 4.6, 0.75, 2.04, a, '#33444f', 1);
      solid.box(x - ch * 0.15, 2.07, z - sh * 0.15, 4.7, 0.09, 2.0, a, shade(hex, 1.08), 1);
      // windscreen pillars and a roof rack
      const [fx2, fz2] = at2(2.3);
      solid.box(fx2, 1.2, fz2, 0.2, 0.9, 2.0, a, c, 0.9);
      const [rx2, rz2] = at2(-0.4);
      solid.box(rx2, 2.16, rz2, 3.4, 0.06, 1.7, a, '#2a2d33', 1);
      for (const [u, v] of [[1.7, 1.02], [-1.7, 1.02], [1.7, -1.02], [-1.7, -1.02]]) solid.cyl(x + ch * u - sh * v, 0, z + sh * u + ch * v, 0.4, 0.4, 0.26, '#1d1f24', 7);
    }
  };

  for (const pi of ck.parked) {
    const v = W.parked[pi];
    carBody(v.x, v.y, v.a, v.color, v.kind);
  }

  /* ================= lamps ================= */
  const lampSpots: number[] = [];
  {
    // the arm points at the nearest road sample
    const samples: number[] = [];
    for (const q of ck.roadSegs) {
      const sm = L.roads[Math.floor(q / 100000)].sp.samples[q % 100000];
      samples.push(sm.x, sm.y);
    }
    for (const li of ck.lamps) {
      const [lx, ly] = W.lamps[li];
      let best = Infinity, tx = lx, ty = ly;
      for (let k = 0; k < samples.length; k += 2) {
        const dd = (samples[k] - lx) ** 2 + (samples[k + 1] - ly) ** 2;
        if (dd < best) { best = dd; tx = samples[k]; ty = samples[k + 1]; }
      }
      const d = Math.hypot(tx - lx, ty - ly) || 1;
      const dx = (tx - lx) / d, dy = (ty - ly) / d;
      solid.cyl(lx, 0, ly, 0.1, 0.06, 5.4, '#59616b', 6);
      const ang = Math.atan2(dy, dx);
      solid.box(lx + dx * 0.7, 5.3, ly + dy * 0.7, 1.5, 0.08, 0.1, ang, '#59616b', 1);
      glow.box(lx + dx * 1.35, 5.18, ly + dy * 1.35, 0.55, 0.12, 0.3, ang, '#ffffff', 1);
      lampSpots.push(lx + dx * 1.35, ly + dy * 1.35);
    }
  }

  /* ================= the fence round the city, road-closed barriers ================= */
  for (const ei of ck.edge) {
    const e = W.edge[ei];
    if (e.kind === 'barrier') {
      solid.box(e.x, 0.2, e.y, 3.0, 0.14, 0.12, e.a, '#f4efe3', 1);
      solid.box(e.x, 0.55, e.y, 3.0, 0.14, 0.12, e.a, '#d63c32', 1);
      solid.box(e.x, 0.9, e.y, 3.0, 0.14, 0.12, e.a, '#f4efe3', 1);
      solid.cyl(e.x - Math.cos(e.a) * 1.5, 0, e.y - Math.sin(e.a) * 1.5, 0.05, 0.05, 1.1, '#59616b', 4);
      solid.cyl(e.x + Math.cos(e.a) * 1.5, 0, e.y + Math.sin(e.a) * 1.5, 0.05, 0.05, 1.1, '#59616b', 4);
      if (hash(e.x + e.y) < 0.5) solid.cyl(e.x + 0.4, 0, e.y + 0.4, 0.2, 0.04, 0.55, '#e8742c', 6);
    } else {
      solid.box(e.x, 0.1, e.y, 3.0, 0.07, 0.07, e.a, '#8a7a5c', 1);
      solid.box(e.x, 0.6, e.y, 3.0, 0.07, 0.07, e.a, '#8a7a5c', 1);
      solid.cyl(e.x, 0, e.y, 0.06, 0.06, 0.95, '#6b5a40', 4);
    }
  }
  yield;

  /* ================= landmarks (the very models the city map draws) ================= */
  for (const key of ck.landmarks) {
    const hb = new HomeBuilder();
    hb.ao = false;
    buildLandmarks(hb, [key]);
    yield;
    const parts = hb.finish();
    yield;
    for (const layer of ['solid', 'glow'] as const) {
      const g = parts[layer];
      if (!g) continue;
      g.scale(10, 10, 10);
      g.translate(500, 0, 500);
      for (const k of Object.keys(g.attributes)) if (k !== 'position' && k !== 'normal' && k !== 'color') g.deleteAttribute(k);
      const m = new Mesh(g, layer === 'solid' ? kit.mats.solid : kit.mats.glowLand);
      m.name = 'landmark-' + key;
      group.add(m);
      geos.push(g);
      calls++;
      tris += (g.index ? g.index.count : g.attributes.position.count) / 3;
    }
    parts.glass?.dispose();
    parts.screen?.dispose();
    parts.light?.dispose();
    yield;
  }

  /* ================= finish the soups ================= */
  const add = function* (soup: Soup, mat: MeshLambertMaterial | MeshBasicMaterial, name: string): Generator<void> {
    if (!soup.size) return;
    const g = yield* soup.geometryGen();
    const m = new Mesh(g, mat);
    m.name = name;
    group.add(m);
    geos.push(g);
    calls++;
    tris += g.attributes.position.count / 3;
  };
  yield* add(solid, kit.mats.solid, 'solid');
  yield;
  yield* add(glassLit, kit.mats.glassLit, 'glass-lit');
  yield* add(glow, kit.mats.glow, 'glow');
  yield* add(signSoup, kit.mats.sign, 'signs');

  /* ================= trees: matrices for the streamer's instanced canopy + trunk ================= */
  const palette = ['#5f9a4b', '#6aa655', '#4f8a43', '#78ad55', '#5a9456', '#6e9f4c'];
  const nt = ck.trees.length;
  const treeIdx = new Int32Array(nt);
  const treeMat = new Float32Array(nt * 32);
  const treeCol = new Float32Array(nt * 3);
  const treeInfo = new Float32Array(nt * 3);
  {
    const m4 = new Matrix4(), q = new Quaternion(), v3 = new Vector3(), sc = new Vector3(), yA = new Vector3(0, 1, 0);
    const cc = new Color();
    ck.trees.forEach((ti, k) => {
      const t = W.trees[ti];
      const r = t.palm ? 1.9 : Math.max(1.5, Math.min(3.6, t.r * 0.95));
      const trunkH = t.palm ? 6.4 : 2.6 + r * 0.35;
      const top = t.palm ? trunkH : trunkH + r * 0.55;
      q.setFromAxisAngle(yA, hash(ti) * 6.28);
      m4.compose(v3.set(t.x, top, t.y), q, sc.set(r, t.palm ? r * 0.38 : r * 0.82, r));
      m4.toArray(treeMat, k * 32);
      m4.compose(v3.set(t.x, 0, t.y), q, sc.set(t.palm ? 0.2 : 0.26, trunkH, t.palm ? 0.2 : 0.26));
      m4.toArray(treeMat, k * 32 + 16);
      cc.set(t.palm ? '#4f9a52' : palette[t.c % palette.length]).multiplyScalar(0.92 + hash(ti * 3) * 0.14);
      treeCol[k * 3] = cc.r; treeCol[k * 3 + 1] = cc.g; treeCol[k * 3 + 2] = cc.b;
      treeInfo[k * 3] = t.x; treeInfo[k * 3 + 1] = t.y; treeInfo[k * 3 + 2] = r;
      treeIdx[k] = ti;
      tris += 30;
    });
  }
  return {
    group, tris, calls, treeIdx, treeMat, treeCol, treeInfo, lamps: Float32Array.from(lampSpots),
    dispose() {
      for (const g of geos) g.dispose();
    },
  };
}

/**
 * The low-detail backdrop of a chunk: ground, road ribbons and every building as a plain box with a flat roof, merged into ONE mesh.
 * Cheap enough to build in one go (a few milliseconds); it is shown only while the detailed chunk is not loaded.
 */
export function buildFarChunk(kit: Kit, ck: ChunkData): ChunkMesh {
  const W = kit.W;
  const L = W.L;
  const group = new Group();
  const s = new Soup();
  s.clip = [ck.x0, ck.y0, ck.x1, ck.y1];
  const gx = (ck.x0 + ck.x1) / 2, gz = (ck.y0 + ck.y1) / 2;
  const urban = L.urban(gx, gz);
  const ground = new Color('#cbbf9f').lerp(new Color('#a8b378'), Math.max(0, 0.75 - urban) * 0.9).multiplyScalar(0.96);
  s.quad([ck.x0, -0.02, ck.y0], [ck.x0, -0.02, ck.y1], [ck.x1, -0.02, ck.y1], [ck.x1, -0.02, ck.y0], ground, [0, 1, 0]);
  for (let q = 0; q < ck.roadSegs.length; q += 2) {
    const ri = Math.floor(ck.roadSegs[q] / 100000), i = ck.roadSegs[q] % 100000;
    const rd = L.roads[ri];
    const S = rd.sp.samples;
    const a = S[i], b = S[(i + 1) % S.length];
    const j = (i + 2) % S.length;
    const c2 = S[j] && !(rd.closed === false && i + 2 >= S.length) ? S[j] : b;
    const hw = rd.hw + (KERB[rd.kind] ?? 0.6);
    const col = ROAD_COL[rd.kind] ?? '#4a4d53';
    s.quad(
      [a.x - Math.sin(a.a) * hw, 0.03, a.y + Math.cos(a.a) * hw], [c2.x - Math.sin(c2.a) * hw, 0.03, c2.y + Math.cos(c2.a) * hw],
      [c2.x + Math.sin(c2.a) * hw, 0.03, c2.y - Math.cos(c2.a) * hw], [a.x + Math.sin(a.a) * hw, 0.03, a.y - Math.cos(a.a) * hw], col, [0, 1, 0]);
    void b;
  }
  for (const bi of ck.buildings) {
    const b = W.buildings[bi];
    const poly = b.poly;
    const n = poly.length;
    let area = 0;
    for (let i = 0; i < n; i++) area += poly[i][0] * poly[(i + 1) % n][1] - poly[(i + 1) % n][0] * poly[i][1];
    const sgn = area > 0 ? 1 : -1;
    const wallCol = new Color(b.wall).multiplyScalar(0.95);
    for (let i = 0; i < n; i++) {
      const a = poly[i], c = poly[(i + 1) % n];
      const len = Math.hypot(c[0] - a[0], c[1] - a[1]);
      if (len < 0.05) continue;
      const nx = (sgn * (c[1] - a[1])) / len, ny = (-sgn * (c[0] - a[0])) / len;
      s.quad([a[0], 0, a[1]], [c[0], 0, c[1]], [c[0], b.h, c[1]], [a[0], b.h, a[1]], wallCol, [nx, 0, ny], 0.9, 1);
    }
    const roofCol = new Color(b.roof);
    const cap = ShapeUtils.triangulateShape(poly.map(([x, y]) => new Vector2(x, y)), []);
    for (const [i0, i1, i2] of cap) {
      const p0 = poly[i0], p1 = poly[i1], p2 = poly[i2];
      s.tri(p0[0], b.h + 0.4, p0[1], p1[0], b.h + 0.4, p1[1], p2[0], b.h + 0.4, p2[1], roofCol, 0, 1, 0);
    }
  }
  // trees as dark green blobs would add little at this distance; the fog does the rest
  const g = s.geometry();
  const m = new Mesh(g, kit.mats.solid);
  m.name = 'far';
  group.add(m);
  return {
    group, tris: g.attributes.position.count / 3, calls: 1,
    treeIdx: new Int32Array(0), treeMat: new Float32Array(0), treeCol: new Float32Array(0), treeInfo: new Float32Array(0), lamps: new Float32Array(0),
    dispose() {
      g.dispose();
    },
  };
}

/** A unit horizontal quad (side 1 x scale) for pools and blob shadows. */
export function flatDisc(): BufferGeometry {
  const g = new PlaneGeometry(1, 1);
  g.rotateX(-Math.PI / 2);
  return g;
}

/** A soft round spot: the colour with alpha 'a0' in the middle, 'a1' halfway out, 0 at the edge (no light fringe). */
export function softDisc(rgb: string, a0: number, a1: number): CanvasTexture {
  const c = document.createElement('canvas');
  c.width = c.height = 64;
  const g = c.getContext('2d')!;
  const gr = g.createRadialGradient(32, 32, 0, 32, 32, 31);
  gr.addColorStop(0, `rgba(${rgb},${a0})`);
  gr.addColorStop(0.5, `rgba(${rgb},${a1})`);
  gr.addColorStop(1, `rgba(${rgb},0)`);
  g.fillStyle = gr;
  g.fillRect(0, 0, 64, 64);
  return new CanvasTexture(g.canvas);
}
