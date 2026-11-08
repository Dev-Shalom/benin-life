// Free roam: turns the RoamWorld data into a handful of merged meshes. Style: the same calm flat-shaded low-poly look as the
// drive scene (vertex colours, no textures except the sign atlas), at human scale: kerbs, pavements, doors, windows,
// awnings, stalls, lamps. Roads, houses, footprints, landmarks, trees come from the SAME layout as the 3D city map.
import {
  CanvasTexture,
  Color,
  CylinderGeometry,
  DynamicDrawUsage,
  Group,
  IcosahedronGeometry,
  InstancedMesh,
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
  type Material,
} from 'three';
import { HomeBuilder } from '../../home3d/engine/build';
import { buildLandmarks, vnoise } from '../../city3d/engine/build';
import { KERB } from '../../city3d/engine/roadnet';
import type { RoamBuilding, RoamWorld } from '../world';
import { ChunkedSoup, Soup } from './soup';

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

export interface Street {
  group: Group;
  /** Materials the scene tunes with the time of day. */
  mats: {
    solid: MeshLambertMaterial;
    glassLit: MeshBasicMaterial;
    glow: MeshBasicMaterial;
    glowLand: MeshBasicMaterial;
    sign: MeshBasicMaterial;
    pool: MeshBasicMaterial;
  };
  pools: InstancedMesh;
  blobs: InstancedMesh;
  /** Hide / show one tree canopy (the camera fades trees that would fill the screen). */
  treeFade(i: number, hide: boolean): void;
  treeInfo: { x: number; y: number; r: number }[];
  /** Instances 0..staticBlobs-1 are tree shadows (static); the rest are for people and cars. */
  staticBlobs: number;
  tris: number;
  meshTris: Record<string, number>;
  dispose(): void;
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

interface Opts {
  tier: 'low' | 'high';
  signs: { tex: CanvasTexture; cells: SignCell[] } | null;
}

export function buildStreet(W: RoamWorld, o: Opts): Street {
  const L = W.L;
  const group = new Group();
  const owned: { dispose(): void }[] = [];
  const own = <T extends { dispose(): void }>(x: T) => (owned.push(x), x);
  const [fx0, fy0, fx1, fy1] = W.far;
  const [bx0, by0, bx1, by1] = W.box;
  const inFar = (x: number, y: number, p = 0) => x > fx0 - p && x < fx1 + p && y > fy0 - p && y < fy1 + p;
  const inBox = (x: number, y: number, p = 0) => x > bx0 - p && x < bx1 + p && y > by0 - p && y < by1 + p;
  let tris = 0;
  const meshTris: Record<string, number> = {};

  const solidMat = own(new MeshLambertMaterial({ vertexColors: true }));
  // ground + paving + roads (layers separated by small y offsets), buildings and props: one soup in chunks, so what is off screen is skipped
  const solid = new ChunkedSoup(105);
  const groundSoup = solid;
  const glassDark = new Soup();
  const glassLit = new Soup();
  const glow = new Soup(); // lamp bulbs, landmark glass
  const signSoup = new Soup();
  signSoup.withUv = true;

  /* ================= ground ================= */
  {
    const cell = 14;
    for (let z = fy0; z < fy1; z += cell)
      for (let x = fx0; x < fx1; x += cell) {
        const n = vnoise(x * 0.02, z * 0.02) * 0.5 + vnoise(x * 0.07, z * 0.07) * 0.5;
        const urban = L.urban(x + cell / 2, z + cell / 2);
        // sandy paving in town, drier grass out in the suburbs
        const c = new Color('#cbbf9f').lerp(new Color('#a8b378'), Math.max(0, 0.75 - urban) * 0.9).multiplyScalar(0.94 + n * 0.1);
        groundSoup.quad([x, 0, z], [x, 0, z + cell], [x + cell, 0, z + cell], [x + cell, 0, z], c, [0, 1, 0]);
      }
  }
  // King's Square: lawn, paths, a plaza round the museum
  {
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
  // yards under the houses
  for (const b of W.buildings) {
    if (b.detail !== 1 || b.osm || !b.rect) continue;
    const r = b.rect;
    const gra = b.roofType !== 'flat' && hash(b.poly[0][0]) < 0.4;
    const c = Math.cos(r.a), s = Math.sin(r.a);
    const hw = r.w / 2 + 1.6, hd = r.d / 2 + 1.6;
    const P = (lx: number, lz: number) => [r.x + lx * c - lz * s, 0.012, r.y + lx * s + lz * c];
    groundSoup.quad(P(-hw, -hd), P(hw, -hd), P(hw, hd), P(-hw, hd), gra ? '#a3c26c' : '#d9cdb0', [0, 1, 0]);
  }

  /* ================= roads ================= */
  for (const ri of W.roadIdx) {
    const rd = L.roads[ri];
    const S = rd.sp.samples;
    const kerbW = KERB[rd.kind] ?? 0.8;
    const asph = ROAD_COL[rd.kind] ?? '#4a4d53';
    const n = S.length;
    const segs = rd.closed ? n : n - 1;
    let dashPhase = 0;
    for (let i = 0; i < segs; i++) {
      const a = S[i], b = S[(i + 1) % n];
      if (!inFar(a.x, a.y, 6) && !inFar(b.x, b.y, 6)) continue;
      const detail = inBox(a.x, a.y, 20) || inBox(b.x, b.y, 20);
      const nax = -Math.sin(a.a), nay = Math.cos(a.a), nbx = -Math.sin(b.a), nby = Math.cos(b.a);
      const P = (p: typeof a, nx: number, ny: number, off: number, y: number) => [p.x + nx * off, y, p.y + ny * off];
      const quadOff = (o0: number, o1: number, y: number, hex: string | Color) =>
        groundSoup.quad(P(a, nax, nay, o0, y), P(b, nbx, nby, o0, y), P(b, nbx, nby, o1, y), P(a, nax, nay, o1, y), hex, [0, 1, 0]);
      if (kerbW > 0) {
        quadOff(rd.hw, rd.hw + kerbW, 0.03, '#d4cbbb');
        quadOff(-rd.hw - kerbW, -rd.hw, 0.03, '#d4cbbb');
      }
      quadOff(-rd.hw, rd.hw, ROAD_Y[rd.kind] ?? 0.06, asph);
      if (!detail) continue;
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
    }
  }

  // a few potholes and patches on the wider roads
  {
    let n = 0;
    for (const ri of W.roadIdx) {
      const rd = L.roads[ri];
      if (rd.kind === 'dirt' || rd.kind === 'spur') continue;
      for (let k = 0; k < 6 && n < 26; k++) {
        const sp = rd.sp.samples[Math.floor(hash(ri * 17 + k * 5) * rd.sp.samples.length)];
        if (!inBox(sp.x, sp.y, 0)) continue;
        const off = (hash(ri * 3 + k) - 0.5) * rd.hw * 1.5;
        const x = sp.x - Math.sin(sp.a) * off, z = sp.y + Math.cos(sp.a) * off;
        if (L.net.clear(x, z, false, 1, ri) < 0) continue;
        const rr = 0.35 + hash(ri + k * 9) * 0.35;
        const ph = hash(ri * 7 + k) * 6;
        for (let q = 0; q < 6; q++) {
          const a0 = ph + (q / 6) * 6.283, a1 = ph + ((q + 1) / 6) * 6.283;
          groundSoup.tri(x, 0.085, z, x + Math.cos(a0) * rr, 0.085, z + Math.sin(a0) * rr * 0.8, x + Math.cos(a1) * rr, 0.085, z + Math.sin(a1) * rr * 0.8, k % 2 ? '#34373c' : '#5a5d62', 0, 1, 0);
        }
        n++;
      }
    }
  }

  /* ================= buildings ================= */
    const tanks: number[] = [];
  W.buildings.forEach((b, bi) => {
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
      return;
    }
    buildBuilding(b, bi);
  });

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

  /* ================= place entrances: arches and kiosks ================= */
  W.places.forEach((pl, pi) => {
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
  });
  W.kiosks.forEach((k) => {
    const pl = W.places[k.placeIdx];
    if (!pl) return;
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
  });

  /* ================= stalls ================= */
  for (const st of W.stalls) {
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
  for (const d of W.displays) {
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
      solid.box(x, 0.35, z, 5.2, 2.0, 2.3, a, c, 0.85);
      glassDark.box(x, 1.5, z, 5.24, 0.7, 2.34, a, '#33444f', 1);
    }
  };
  for (const v of W.parked) carBody(v.x, v.y, v.a, v.color, v.kind);

  /* ================= lamps ================= */
  const lampSpots: [number, number][] = [];
  {
    // pointing arm towards the nearest road sample
    const samples: [number, number][] = [];
    for (const ri of W.roadIdx) for (const sm of L.roads[ri].sp.samples) if (inBox(sm.x, sm.y, 30)) samples.push([sm.x, sm.y]);
    for (const [lx, ly] of W.lamps) {
      let best = Infinity, tx = lx, ty = ly;
      for (const [sx, sy] of samples) {
        const dd = (sx - lx) ** 2 + (sy - ly) ** 2;
        if (dd < best) { best = dd; tx = sx; ty = sy; }
      }
      const d = Math.hypot(tx - lx, ty - ly) || 1;
      const dx = (tx - lx) / d, dy = (ty - ly) / d;
      solid.cyl(lx, 0, ly, 0.1, 0.06, 5.4, '#59616b', 6);
      const ang = Math.atan2(dy, dx);
      solid.box(lx + dx * 0.7, 5.3, ly + dy * 0.7, 1.5, 0.08, 0.1, ang, '#59616b', 1);
      glow.box(lx + dx * 1.35, 5.18, ly + dy * 1.35, 0.55, 0.12, 0.3, ang, '#ffffff', 1);
      lampSpots.push([lx + dx * 1.35, ly + dy * 1.35]);
    }
  }

  /* ================= the fence round the area, road-closed barriers ================= */
  for (const e of W.edge) {
    if (e.kind === 'barrier') {
      solid.box(e.x, 0.2, e.y, 3.0, 0.14, 0.12, e.a, '#f4efe3', 1);
      solid.box(e.x, 0.55, e.y, 3.0, 0.14, 0.12, e.a, '#d63c32', 1);
      solid.box(e.x, 0.9, e.y, 3.0, 0.14, 0.12, e.a, '#f4efe3', 1);
      solid.cyl(e.x - Math.cos(e.a) * 1.5, 0, e.y - Math.sin(e.a) * 1.5, 0.05, 0.05, 1.1, '#59616b', 4);
      solid.cyl(e.x + Math.cos(e.a) * 1.5, 0, e.y + Math.sin(e.a) * 1.5, 0.05, 0.05, 1.1, '#59616b', 4);
    } else {
      solid.box(e.x, 0.1, e.y, 3.0, 0.07, 0.07, e.a, '#8a7a5c', 1);
      solid.box(e.x, 0.6, e.y, 3.0, 0.07, 0.07, e.a, '#8a7a5c', 1);
      solid.cyl(e.x, 0, e.y, 0.06, 0.06, 0.95, '#6b5a40', 4);
    }
  }
  // traffic cones beside the barriers
  for (const e of W.edge) if (e.kind === 'barrier' && hash(e.x + e.y) < 0.5) solid.cyl(e.x + 0.4, 0, e.y + 0.4, 0.2, 0.04, 0.55, '#e8742c', 6);

  /* ================= landmarks (the very models the city map draws) ================= */
  let glowLand: BufferGeometry | null = null;
  {
    const hb = new HomeBuilder();
    hb.ao = false;
    buildLandmarks(hb, W.landmarks);
    const parts = hb.finish();
    for (const [layer, mat] of [['solid', solidMat], ['glow', null]] as const) {
      const g = parts[layer];
      if (!g) continue;
      g.scale(10, 10, 10);
      g.translate(500, 0, 500);
      for (const k of Object.keys(g.attributes)) if (k !== 'position' && k !== 'normal' && k !== 'color') g.deleteAttribute(k);
      if (layer === 'solid') {
        const m = new Mesh(own(g), mat!);
        m.name = 'landmarks';
        group.add(m);
        tris += (g.index ? g.index.count : g.attributes.position.count) / 3;
      } else {
        glowLand = g;
      }
    }
    parts.glass?.dispose();
    parts.screen?.dispose();
    parts.light?.dispose();
  }

  /* ================= finish the soups ================= */
  const meshes: Mesh[] = [];
  const add = (soup: Soup, mat: Material, name: string) => {
    if (!soup.pos.length) return null;
    const g = soup.geometry();
    const m = new Mesh(own(g), mat);
    m.name = name;
    m.frustumCulled = false;
    group.add(m);
    meshes.push(m);
    tris += g.attributes.position.count / 3;
    meshTris[name] = g.attributes.position.count / 3;
    return m;
  };
  const glassLitMat = own(new MeshBasicMaterial({ vertexColors: true, color: '#6f93a8' }));
  const glassDarkMat = own(new MeshLambertMaterial({ vertexColors: true }));
  const glowMat = own(new MeshBasicMaterial({ vertexColors: true, color: '#d8d2c4' }));
  const glowLandMat = own(new MeshBasicMaterial({ vertexColors: true, color: '#9db4c4' }));
  const signMat = own(new MeshBasicMaterial({ vertexColors: true, map: o.signs?.tex ?? null }));
  {
    let i = 0;
    for (const [, c] of solid.chunks) {
      const m = add(c, solidMat, 'chunk');
      if (m) {
        m.name = 'chunk-' + i++;
        m.frustumCulled = true;
      }
    }
    meshTris.chunks = i;
    meshTris.chunkTris = solid.tris;
  }
  add(glassDark, glassDarkMat, 'glass');
  add(glassLit, glassLitMat, 'glass-lit');
  add(glow, glowMat, 'glow');
  if (glowLand) {
    const m = new Mesh(own(glowLand), glowLandMat);
    m.name = 'landmark-glow';
    group.add(m);
    tris += glowLand.attributes.position.count / 3;
  }
  if (signSoup.pos.length) add(signSoup, signMat, 'signs');

  /* ================= trees: instanced canopy + trunk ================= */
  const palette = ['#5f9a4b', '#6aa655', '#4f8a43', '#78ad55', '#5a9456', '#6e9f4c'];
  const trees = W.trees;
  const canopyGeo = own(new IcosahedronGeometry(1, 0));
  const canopyMat = own(new MeshLambertMaterial({ flatShading: true }));
  const canopy = new InstancedMesh(canopyGeo, canopyMat, trees.length);
  const trunkGeo = own(new CylinderGeometry(0.5, 0.7, 1, 5));
  trunkGeo.translate(0, 0.5, 0);
  const trunkMat = own(new MeshLambertMaterial({ color: '#7a5a3c', flatShading: true }));
  const trunks = new InstancedMesh(trunkGeo, trunkMat, trees.length);
  const m4 = new Matrix4();
  const q = new Quaternion();
  const v3 = new Vector3();
  const sc = new Vector3();
  const treeBlobs: number[] = [];
  const canopyMats: Matrix4[] = [];
  const treeInfo: { x: number; y: number; r: number }[] = [];
  trees.forEach((t, i) => {
    const r = t.palm ? 1.9 : Math.max(1.5, Math.min(3.6, t.r * 0.95));
    const trunkH = t.palm ? 6.4 : 2.6 + r * 0.35;
    const top = t.palm ? trunkH : trunkH + r * 0.55;
    q.setFromAxisAngle(v3.set(0, 1, 0), hash(i) * 6.28);
    // trunk
    m4.compose(v3.set(t.x, 0, t.y), q, sc.set(t.palm ? 0.2 : 0.26, trunkH, t.palm ? 0.2 : 0.26));
    trunks.setMatrixAt(i, m4);
    // canopy
    m4.compose(v3.set(t.x, top, t.y), q, sc.set(r, t.palm ? r * 0.38 : r * 0.82, r));
    canopy.setMatrixAt(i, m4);
    canopyMats.push(m4.clone());
    treeInfo.push({ x: t.x, y: t.y, r });
    canopy.setColorAt(i, new Color(t.palm ? '#4f9a52' : palette[t.c % palette.length]).multiplyScalar(0.92 + hash(i * 3) * 0.14));
    treeBlobs.push(t.x, t.y, r * 1.5);
  });
  canopy.instanceMatrix.needsUpdate = true;
  if (canopy.instanceColor) canopy.instanceColor.needsUpdate = true;
  trunks.instanceMatrix.needsUpdate = true;
  canopy.frustumCulled = false;
  trunks.frustumCulled = false;
  group.add(canopy, trunks);
  tris += trees.length * 20 + trees.length * 10;

  /* ================= lamp pools (night) and blob shadows ================= */
  const poolTex = own(softDisc('255,214,130', 0.95, 0.4));
  const poolMat = own(new MeshBasicMaterial({ map: poolTex, transparent: true, depthWrite: false, opacity: 0, blending: 2 /* additive */ }));
  const flat = flatDisc();
  own(flat);
  const pools = new InstancedMesh(flat, poolMat, Math.max(1, lampSpots.length));
  lampSpots.forEach(([x, y], i) => {
    m4.compose(v3.set(x, 0.1, y), q.identity(), sc.set(11, 1, 11));
    pools.setMatrixAt(i, m4);
  });
  pools.frustumCulled = false;
  pools.renderOrder = 3;
  group.add(pools);

  const blobTex = own(softDisc('18,20,30', 0.5, 0.2));
  const blobMat = own(new MeshBasicMaterial({ map: blobTex, transparent: true, depthWrite: false }));
  const MAX_BLOBS = treeBlobs.length / 3 + 80;
  const blobs = new InstancedMesh(flat, blobMat, MAX_BLOBS);
  blobs.instanceMatrix.setUsage(DynamicDrawUsage);
  for (let i = 0; i < treeBlobs.length / 3; i++) {
    m4.compose(v3.set(treeBlobs[i * 3], 0.09, treeBlobs[i * 3 + 1]), q.identity(), sc.set(treeBlobs[i * 3 + 2] * 1.5, 1, treeBlobs[i * 3 + 2] * 1.5));
    blobs.setMatrixAt(i, m4);
  }
  blobs.frustumCulled = false;
  blobs.renderOrder = 2;
  group.add(blobs);
  blobs.count = treeBlobs.length / 3;


  const hidden = new Uint8Array(trees.length);
  const zero = new Matrix4().makeScale(0, 0, 0);
  const treeFade = (i: number, hide: boolean) => {
    if (hidden[i] === (hide ? 1 : 0)) return;
    hidden[i] = hide ? 1 : 0;
    canopy.setMatrixAt(i, hide ? zero : canopyMats[i]);
    canopy.instanceMatrix.needsUpdate = true;
  };

  return {
    treeFade,
    treeInfo,
    group,
    mats: { solid: solidMat, glassLit: glassLitMat, glow: glowMat, glowLand: glowLandMat, sign: signMat, pool: poolMat },
    pools,
    blobs,
    staticBlobs: treeBlobs.length / 3,
    tris: tris + 500,
    meshTris,
    dispose() {
      for (const x of owned) x.dispose();
      o.signs?.tex.dispose();
    },
  };
}

/** A unit horizontal quad (side 1 x scale) for pools and blob shadows. */
function flatDisc(): BufferGeometry {
  const g = new PlaneGeometry(1, 1);
  g.rotateX(-Math.PI / 2);
  return g;
}

/** A soft round spot: the colour with alpha 'a0' in the middle, 'a1' halfway out, 0 at the edge (no light fringe). */
function softDisc(rgb: string, a0: number, a1: number): CanvasTexture {
  const c = document.createElement('canvas');
  c.width = c.height = 64;
  const g = c.getContext('2d')!;
  const gr = g.createRadialGradient(32, 32, 0, 32, 32, 31);
  gr.addColorStop(0, `rgba(${rgb},${a0})`);
  gr.addColorStop(0.5, `rgba(${rgb},${a1})`);
  gr.addColorStop(1, `rgba(${rgb},0)`);
  g.fillStyle = gr;
  g.fillRect(0, 0, 64, 64);
  return new CanvasTexture(c);
}
