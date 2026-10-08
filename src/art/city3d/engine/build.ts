// R5: turns the city layout (map space) into a handful of three.js meshes.
// Budget (docs/CITY3D.md): ~30 draw calls and ~100k triangles for the whole city. Everything static
// is merged (ground, roads, landmarks) or instanced (buildings, roofs, trees, cars, lamps).
import {
  AdditiveBlending,
  BoxGeometry,
  BufferGeometry,
  CanvasTexture,
  Color,
  ConeGeometry,
  CylinderGeometry,
  DoubleSide,
  Float32BufferAttribute,
  Group,
  IcosahedronGeometry,
  InstancedMesh,
  Mesh,
  MeshBasicMaterial,
  MeshLambertMaterial,
  Object3D,
  PlaneGeometry,
  RingGeometry,
  SphereGeometry,
  ShapeUtils,
  Vector2,
  type Material,
} from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import { HomeBuilder } from '../../home3d/engine/build';
import {
  AIRPORT, BRIDGE, CAMPUS, DISTRICT_TINTS, FARMLAND, GRA_ZONE, GROVE, KINGS_SQUARE, MARKETS, PALACE, POLICE,
  RAMAT, RING, RUNWAY, STADIUM, TECH_HUB, TERMINAL, UBTH, at, inPoly, type Pt,
} from '../../map/mapGeo';
import { WS } from '../model';
import type { CityLayout, Style, Vehicle } from './layout';

const W = (mx: number) => (mx - 500) * WS;

/* ------------------------------------------------------------------ */
/* Flat geometry (ground, roads, river): positions + colours, normal up */
/* ------------------------------------------------------------------ */
class Flat {
  pos: number[] = [];
  col: number[] = [];
  idx: number[] = [];
  private c = new Color();
  private v(x: number, y: number, z: number) {
    this.pos.push(x, y, z);
    this.col.push(this.c.r, this.c.g, this.c.b);
    return this.pos.length / 3 - 1;
  }
  /** Ribbon along map-space points (with tangent angles), half width hw (map units). */
  strip(pts: { x: number; y: number; a: number }[], hw: number, y: number, color: string, closed = false) {
    if (pts.length < 2) return;
    this.c.set(color);
    const base = this.pos.length / 3;
    for (const p of pts) {
      const nx = -Math.sin(p.a) * hw;
      const ny = Math.cos(p.a) * hw;
      this.v(W(p.x + nx), y, W(p.y + ny));
      this.v(W(p.x - nx), y, W(p.y - ny));
    }
    const n = pts.length;
    const segs = closed ? n : n - 1;
    for (let i = 0; i < segs; i++) {
      const a = base + i * 2;
      const b = base + ((i + 1) % n) * 2;
      this.idx.push(a, b, a + 1, a + 1, b, b + 1);
    }
  }
  /** Quad from 4 map-space corners (counter-clockwise seen from above). */
  quad(p: [number, number][], y: number, color: string) {
    this.c.set(color);
    const b = this.pos.length / 3;
    for (const [x, z] of p) this.v(W(x), y, W(z));
    this.idx.push(b, b + 1, b + 2, b, b + 2, b + 3);
  }
  /** Oriented rectangle centred at map (x, y), length l along angle a, width w. */
  rect(x: number, y: number, l: number, w: number, a: number, yy: number, color: string) {
    const c = Math.cos(a);
    const s = Math.sin(a);
    const hl = l / 2;
    const hw = w / 2;
    this.quad(
      [
        [x - c * hl + s * hw, y - s * hl - c * hw],
        [x - c * hl - s * hw, y - s * hl + c * hw],
        [x + c * hl - s * hw, y + s * hl + c * hw],
        [x + c * hl + s * hw, y + s * hl - c * hw],
      ],
      yy,
      color,
    );
  }
  disc(x: number, y: number, r: number, yy: number, color: string, seg = 24, sx = 1) {
    this.c.set(color);
    const b = this.v(W(x), yy, W(y));
    for (let i = 0; i <= seg; i++) {
      const a = (i / seg) * Math.PI * 2;
      this.v(W(x + Math.cos(a) * r * sx), yy, W(y + Math.sin(a) * r));
    }
    for (let i = 0; i < seg; i++) this.idx.push(b, b + 2 + i, b + 1 + i);
  }
  /** Filled polygon (fan from its centroid; fine for the convex-ish zones). */
  poly(poly: readonly Pt[], yy: number, color: string) {
    this.c.set(color);
    let cx = 0;
    let cy = 0;
    for (const [x, y] of poly) {
      cx += x / poly.length;
      cy += y / poly.length;
    }
    const b = this.v(W(cx), yy, W(cy));
    for (const [x, y] of poly) this.v(W(x), yy, W(y));
    for (let i = 0; i < poly.length; i++) this.idx.push(b, b + 1 + ((i + 1) % poly.length), b + 1 + i);
  }
  geometry(): BufferGeometry {
    const g = new BufferGeometry();
    g.setAttribute('position', new Float32BufferAttribute(this.pos, 3));
    g.setAttribute('color', new Float32BufferAttribute(this.col, 3));
    const nrm = new Float32Array(this.pos.length);
    for (let i = 1; i < nrm.length; i += 3) nrm[i] = 1;
    g.setAttribute('normal', new Float32BufferAttribute(nrm, 3));
    g.setIndex(this.idx);
    return g;
  }
}

/* ------------------------------------------------------------------ */
/* Colours                                                              */
/* ------------------------------------------------------------------ */
const _b = new Color();
const smooth = (e0: number, e1: number, x: number) => {
  const t = Math.min(1, Math.max(0, (x - e0) / (e1 - e0)));
  return t * t * (3 - 2 * t);
};
// S3: softer, less saturated palette. The city sits on sandy paved ground (not an orange laterite
// stain), suburbs on dry grass, the bush a calm green. Low-frequency noise breaks up flat areas.
const BUSH = new Color('#8bb35f');
const SUBURB = new Color('#c4bb88');
const URBAN = new Color('#e0d1b2');
const CORE = new Color('#ddd3c1');
const LAWN = new Color('#97c264');
const BANK = new Color('#78ad55');
const BUSH_DARK = new Color('#78a352');

/** Smooth value noise in map space (deterministic, no allocations). */
function hash2(i: number, j: number): number {
  const h = Math.sin(i * 127.1 + j * 311.7) * 43758.5453;
  return h - Math.floor(h);
}
export function vnoise(x: number, y: number): number {
  const i = Math.floor(x);
  const j = Math.floor(y);
  const fx = x - i;
  const fy = y - j;
  const ux = fx * fx * (3 - 2 * fx);
  const uy = fy * fy * (3 - 2 * fy);
  const a = hash2(i, j);
  const b = hash2(i + 1, j);
  const c = hash2(i, j + 1);
  const d = hash2(i + 1, j + 1);
  return a + (b - a) * ux + (c - a) * uy + (a - b - c + d) * ux * uy;
}

function groundColor(L: CityLayout, x: number, y: number, out: Color, edge = 1) {
  const u = L.urban(x, y);
  const n = vnoise(x / 90, y / 90) * 0.65 + vnoise(x / 31 + 17, y / 31 - 5) * 0.35;
  out.copy(BUSH).lerp(BUSH_DARK, smooth(0.35, 0.75, n) * 0.8 * edge);
  out.lerp(SUBURB, smooth(0.14, 0.5, u) * (0.75 + 0.25 * n));
  out.lerp(URBAN, smooth(0.5, 0.82, u));
  out.lerp(CORE, smooth(0.82, 0.97, u) * 0.7);
  // district tints, very light
  for (const [cx, cy, rx, ry, col] of DISTRICT_TINTS) {
    const d = ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2;
    if (d < 1) out.lerp(_b.set(col), (1 - d) * 0.08);
  }
  const g = Math.hypot(x - GRA_ZONE.x, y - GRA_ZONE.y);
  if (g < GRA_ZONE.r * 1.15) out.lerp(LAWN, 0.7 * (1 - smooth(GRA_ZONE.r * 0.7, GRA_ZONE.r * 1.15, g)));
  if (inPoly(x, y, CAMPUS) || inPoly(x, y, UBTH)) out.lerp(LAWN, 0.6);
  const rd = L.riverDist(x, y, 40);
  if (rd < 40) out.lerp(BANK, 0.85 * (1 - smooth(10, 40, rd)));
  // brightness speckle (very light), faded out at the edge of the generated ground
  const k = 1 + (n - 0.5) * 0.07 * edge;
  out.r *= k;
  out.g *= k;
  out.b *= k;
}

/** Plot (yard) colour under each building, by district style. */
const PLOT: Record<Style, string> = {
  core: '#d3c8b4',
  res: '#d9c49d',
  cramped: '#cba57c',
  gra: '#a9cf78',
  campus: '#b8d68a',
  market: '#c99a6a',
};

export interface CityMeshes {
  group: Group;
  /** Materials whose colour changes between day and night. */
  mats: {
    ground: MeshLambertMaterial;
    solid: MeshLambertMaterial;
    glow: MeshBasicMaterial;
    water: MeshLambertMaterial;
    windows: MeshBasicMaterial;
    bulbs: MeshBasicMaterial;
    pools: MeshBasicMaterial;
    shadow: MeshBasicMaterial;
  };
  nightOnly: Object3D[];
  vehicles: InstancedMesh;
  /** Move the traffic to time t (s). */
  animate(t: number): void;
  tris: number;
  dispose(): void;
}

/** Radial gradient texture (white centre → transparent) for glows and light pools. */
export function radialTexture(inner = 'rgba(255,255,255,1)', mid = 'rgba(255,255,255,0.35)'): CanvasTexture {
  const c = document.createElement('canvas');
  c.width = c.height = 64;
  const g = c.getContext('2d')!;
  const gr = g.createRadialGradient(32, 32, 0, 32, 32, 32);
  gr.addColorStop(0, inner);
  gr.addColorStop(0.45, mid);
  gr.addColorStop(1, 'rgba(255,255,255,0)');
  g.fillStyle = gr;
  g.fillRect(0, 0, 64, 64);
  return new CanvasTexture(c);
}

function windowTexture(): CanvasTexture {
  const c = document.createElement('canvas');
  c.width = 64;
  c.height = 16;
  const g = c.getContext('2d')!;
  g.fillStyle = '#ffffff';
  for (let i = 0; i < 4; i++) if (i !== 2) g.fillRect(2 + i * 16, 2, 11, 12);
  return new CanvasTexture(c);
}

/** Gable roof: ridge along x at y = 1, eaves at z = ±0.5 (non-indexed, flat normals). */
function gableGeometry(): BufferGeometry {
  const p = [
    // south slope
    -0.5, 0, 0.5, 0.5, 0, 0.5, 0.5, 1, 0, -0.5, 0, 0.5, 0.5, 1, 0, -0.5, 1, 0,
    // north slope
    0.5, 0, -0.5, -0.5, 0, -0.5, -0.5, 1, 0, 0.5, 0, -0.5, -0.5, 1, 0, 0.5, 1, 0,
    // gable ends
    0.5, 0, 0.5, 0.5, 0, -0.5, 0.5, 1, 0, -0.5, 0, -0.5, -0.5, 0, 0.5, -0.5, 1, 0,
  ];
  const g = new BufferGeometry();
  g.setAttribute('position', new Float32BufferAttribute(p, 3));
  g.computeVertexNormals();
  return g;
}

function vehicleGeometry(): BufferGeometry {
  const body = new BoxGeometry(1, 0.42, 0.5);
  body.translate(0, 0.29, 0);
  const cab = new BoxGeometry(0.55, 0.3, 0.46);
  cab.translate(-0.05, 0.64, 0);
  const paint = (g: BufferGeometry, v: number) => {
    const n = g.attributes.position.count;
    g.setAttribute('color', new Float32BufferAttribute(new Array(n * 3).fill(v), 3));
    g.deleteAttribute('uv');
  };
  paint(body, 1);
  paint(cab, 0.42);
  const m = mergeGeometries([body, cab])!;
  body.dispose();
  cab.dispose();
  return m;
}

const _o = new Object3D();
const _c = new Color();

export function buildCity(L: CityLayout): CityMeshes {
  const group = new Group();
  const disposables: { dispose(): void }[] = [];
  const keep = <T extends { dispose(): void }>(x: T) => {
    disposables.push(x);
    return x;
  };
  let tris = 0;
  const countTris = (g: BufferGeometry, inst = 1) => {
    tris += ((g.index ? g.index.count : g.attributes.position.count) / 3) * inst;
  };
  const addMesh = (geo: BufferGeometry, mat: Material, name: string, order = 0) => {
    const m = new Mesh(geo, mat);
    m.name = name;
    m.matrixAutoUpdate = false;
    m.renderOrder = order;
    m.updateMatrix();
    group.add(m);
    countTris(geo);
    keep(geo);
    return m;
  };

  const mats = {
    ground: keep(new MeshLambertMaterial({ vertexColors: true })),
    solid: keep(new MeshLambertMaterial({ vertexColors: true, flatShading: true })),
    glow: keep(new MeshBasicMaterial({ vertexColors: true, color: '#9db4c4' })),
    water: keep(new MeshLambertMaterial({ color: '#3d8fb8' })),
    windows: keep(new MeshBasicMaterial({ color: '#ffdc8a', map: keep(windowTexture()), transparent: true, alphaTest: 0.5 })),
    bulbs: keep(new MeshBasicMaterial({ color: '#d8d2c4' })),
    pools: keep(new MeshBasicMaterial({ color: '#ffcf7a', map: keep(radialTexture()), transparent: true, opacity: 0.8, depthWrite: false, blending: AdditiveBlending })),
    shadow: keep(new MeshBasicMaterial({ color: '#2a1a10', transparent: true, opacity: 0.16, depthWrite: false })),
  };
  const nightOnly: Object3D[] = [];

  /* ---------- ground ---------- */
  {
    const N = 72;
    const span = 1200;
    const f = new Flat();
    const c = new Color();
    for (let j = 0; j <= N; j++)
      for (let i = 0; i <= N; i++) {
        const x = -100 + (i / N) * span;
        const y = -100 + (j / N) * span;
        // fade the noise out near the edge of the grid so it meets the plain skirt without a seam
        const e = Math.min(i, j, N - i, N - j) / 6;
        groundColor(L, x, y, c, Math.min(1, e));
        if (e < 1) c.lerp(BUSH, 1 - e);
        f.pos.push(W(x), 0, W(y));
        f.col.push(c.r, c.g, c.b);
      }
    for (let j = 0; j < N; j++)
      for (let i = 0; i < N; i++) {
        const a = j * (N + 1) + i;
        f.idx.push(a, a + N + 1, a + 1, a + 1, a + N + 1, a + N + 2);
      }
    // a wide skirt of bush beyond the generated ground, so a zoomed-out view never shows an edge
    const sk = BUSH.clone();
    const o = [-2400, 3400];
    const inn = [-100, 1100];
    const ring: [number, number][][] = [
      [[o[0], o[0]], [o[0], o[1]], [inn[0], inn[1]], [inn[0], inn[0]]],
      [[inn[0], inn[1]], [o[0], o[1]], [o[1], o[1]], [inn[1], inn[1]]],
      [[inn[1], inn[1]], [o[1], o[1]], [o[1], o[0]], [inn[1], inn[0]]],
      [[inn[1], inn[0]], [o[1], o[0]], [o[0], o[0]], [inn[0], inn[0]]],
    ];
    for (const q of ring) f.quad(q, -0.002, '#' + sk.getHexString());
    // crop fields on the NW farmland (Iguobazuwa side)
    for (let y = 175; y < 440; y += 12)
      for (let x = 0; x < 185; x += 22) {
        if (!inPoly(x + 11, y + 6, FARMLAND)) continue;
        f.rect(x + 11, y + 6, 20, 10, 0.08, 0.008, ((x / 22 + y / 12) | 0) % 3 === 0 ? '#c9b35a' : ((x + y) | 0) % 2 ? '#9cc25a' : '#7fb24e');
      }
    // King's Square lawn + paths, the palace forecourt, campus playing field, airport grass
    f.disc(KINGS_SQUARE.x, KINGS_SQUARE.y, RING.r - RING.hw + 1, 0.01, '#86b95a', 40);
    for (const a of [0, Math.PI / 2, Math.PI / 4, -Math.PI / 4]) f.rect(500, 500, 98, 3.2, a, 0.014, '#ead8b0');
    f.disc(500, 500, 14, 0.016, '#e9d7ae', 24);
    f.poly(PALACE, 0.01, '#c98b5d');
    f.poly(AIRPORT, 0.008, '#9fc06a');
    f.poly(POLICE.map(([x, y]) => [x + (x - 497) * 0.35, y + (y - 610) * 0.35] as Pt), 0.01, '#cfc4b0');
    f.disc(STADIUM.x, STADIUM.y, 13, 0.012, '#b5553a', 28, 1.45);
    f.disc(STADIUM.x, STADIUM.y, 10, 0.016, '#6fb04f', 28, 1.45);
    f.disc(GROVE.x, GROVE.y, GROVE.r, 0.006, '#4f8a3c', 20);
    // motor park pads
    for (const [px, py, pr] of [[452, 282, 13], [398, 52, 12], [705, 400, 10], [828, 352, 12]] as const) f.disc(px, py, pr, 0.012, '#b97b4f', 18, 1.25);
    // market grounds
    for (const [mx, my, mr] of MARKETS) f.disc(mx, my, mr + 2, 0.012, '#c99a6a', 22);
    // S3: a yard under every building (lawn in the GRA, paving in the core, packed earth elsewhere)
    for (const b of L.buildings) {
      if (b.st === 'market' || b.st === 'campus') continue;
      const pad = b.st === 'gra' ? 5 : b.st === 'cramped' ? 1.6 : 2.6;
      f.rect(b.x, b.y, b.w + pad, b.d + pad, b.a, 0.02, PLOT[b.st]);
    }
    addMesh(f.geometry(), mats.ground, 'ground');
  }

  /* ---------- river ---------- */
  {
    const f = new Flat();
    const pts = L.river.samples.filter((_, i) => i % 2 === 0);
    // S3: run the river on past both map edges (straight), so it never stops in the bush
    const runOn = (p: { x: number; y: number }, q: { x: number; y: number }) => {
      const a = Math.atan2(p.y - q.y, p.x - q.x);
      return { x: p.x + Math.cos(a) * 600, y: p.y + Math.sin(a) * 600, a: a };
    };
    const n0 = pts.length;
    const head = runOn(pts[0], pts[1]);
    const tail = runOn(pts[n0 - 1], pts[n0 - 2]);
    pts.unshift({ ...head, a: head.a + Math.PI, s: 0 });
    pts.push({ ...tail, s: 0 });
    f.strip(pts, 9, 0.018, '#5f9f45');
    addMesh(f.geometry(), mats.ground, 'banks');
    const w = new Flat();
    w.strip(pts, 6.2, 0.024, '#ffffff');
    addMesh(w.geometry(), mats.water, 'water');
  }

  /* ---------- roads ---------- */
  // S3: asphalt that reads as road: dark grey with pale kerbs, white edge lines and centre dashes on the
  // big roads (left out where two roads meet, so junctions stay clean), paved grey side streets, and
  // the open ends of the radial roads run on past the edge of the map instead of stopping in the bush.
  {
    const f = new Flat();
    const ROAD_COL: Record<string, string> = { express: '#41454d', main: '#484c54', ring: '#41454d', minor: '#64656a', spur: '#8e8a84', dirt: '#b47e52' };
    const KERB: Record<string, [number, string] | undefined> = {
      express: [1.4, '#e9e1d2'], main: [1.3, '#e9e1d2'], ring: [1.5, '#ece4d6'], minor: [0.9, '#ddd3c2'], spur: [0.7, '#d9cfbd'],
    };
    const Y: Record<string, number> = { spur: 0.034, dirt: 0.034, minor: 0.04, main: 0.046, express: 0.048, ring: 0.05 };
    const big = (k: string) => k === 'express' || k === 'main' || k === 'ring';
    // samples of every non-spur road, to find junctions
    const cell = 16;
    const jgrid = new Map<number, number[]>();
    const jx: number[] = [];
    const jy: number[] = [];
    const jr: number[] = [];
    const jh: number[] = [];
    L.roads.forEach((r, ri) => {
      if (r.kind === 'spur') return;
      for (let s = 0; s <= r.sp.length; s += 3) {
        const p = at(r.sp, s);
        const k = (Math.floor(p.x / cell) + 200) * 1000 + Math.floor(p.y / cell) + 200;
        const arr = jgrid.get(k);
        const n = jx.push(p.x) - 1;
        jy.push(p.y);
        jr.push(ri);
        jh.push(r.hw);
        if (arr) arr.push(n);
        else jgrid.set(k, [n]);
      }
    });
    const nearOther = (x: number, y: number, ri: number, pad: number) => {
      const cx = Math.floor(x / cell) + 200;
      const cy = Math.floor(y / cell) + 200;
      for (let j = cy - 1; j <= cy + 1; j++)
        for (let i = cx - 1; i <= cx + 1; i++) {
          const arr = jgrid.get(i * 1000 + j);
          if (!arr) continue;
          for (const n of arr) if (jr[n] !== ri && Math.hypot(jx[n] - x, jy[n] - y) < jh[n] + pad) return true;
        }
      return false;
    };
    /** A thin line along the road at lateral offset `off`, broken at junctions. */
    const line = (r: (typeof L.roads)[number], ri: number, off: number, w: number, color: string, yy: number) => {
      let run: { x: number; y: number; a: number }[] = [];
      const flush = () => {
        if (run.length > 1) f.strip(run, w / 2, yy, color);
        run = [];
      };
      for (let s = 0; s <= r.sp.length; s += 2.5) {
        const p = at(r.sp, s);
        const nx = -Math.sin(p.a) * off;
        const ny = Math.cos(p.a) * off;
        const x = p.x + nx;
        const y = p.y + ny;
        if (nearOther(x, y, ri, 2.2)) flush();
        else run.push({ x, y, a: p.a });
      }
      flush();
    };
    const ordered = L.roads.map((r, i) => [r, i] as const).sort((a, b) => Y[a[0].kind] - Y[b[0].kind]);
    for (const [r, ri] of ordered) {
      const pts = r.sp.samples.filter((_, i) => i % 2 === 0 || i === r.sp.samples.length - 1);
      // straight run-on past the map edge for roads that leave the map
      if (!r.closed && r.kind !== 'spur') {
        for (const end of [0, 1]) {
          const p = end ? pts[pts.length - 1] : pts[0];
          const q = end ? pts[pts.length - 2] : pts[1];
          if (!q || (p.x > 0 && p.x < 1000 && p.y > 0 && p.y < 1000)) continue;
          const a = Math.atan2(p.y - q.y, p.x - q.x);
          const ext = [p, { x: p.x + Math.cos(a) * 600, y: p.y + Math.sin(a) * 600, a }].map((e) => ({ ...e, a }));
          const kb = KERB[r.kind];
          if (kb) f.strip(ext, r.hw + kb[0], Y[r.kind] - 0.012, kb[1]);
          f.strip(ext, r.hw, Y[r.kind], ROAD_COL[r.kind]);
        }
      }
      const kb = KERB[r.kind];
      if (kb) f.strip(pts, r.hw + kb[0], r.kind === 'spur' ? 0.026 : 0.03, kb[1], r.closed);
      f.strip(pts, r.hw, Y[r.kind], ROAD_COL[r.kind], r.closed);
      if (big(r.kind)) {
        // edge lines
        line(r, ri, r.hw - 1.1, 0.75, '#e9e5dc', 0.056);
        line(r, ri, -(r.hw - 1.1), 0.75, '#e9e5dc', 0.056);
        // centre dashes (yellow on the expressways and the ring, white on main roads)
        const col = r.kind === 'main' ? '#efebe1' : '#f2cf5b';
        for (let s = 3; s < r.sp.length - 3; s += 10) {
          const p = at(r.sp, s);
          if (nearOther(p.x, p.y, ri, 3)) continue;
          f.rect(p.x, p.y, 4.8, 0.9, p.a, 0.057, col);
        }
      }
    }
    // Ramat Park roundabout island
    f.disc(RAMAT.x, RAMAT.y, 6.6, 0.058, '#ece4d6', 16);
    f.disc(RAMAT.x, RAMAT.y, 6, 0.06, '#6fae4f', 16);
    addMesh(f.geometry(), mats.ground, 'roads', 1);
  }

  /* ---------- landmarks (merged) ---------- */
  const lm = new HomeBuilder();
  buildLandmarks(lm);
  const lmGeo = lm.finish();
  if (lmGeo.solid) addMesh(lmGeo.solid, mats.solid, 'landmarks');
  if (lmGeo.glow) addMesh(lmGeo.glow, mats.glow, 'landmark-windows');
  lmGeo.glass?.dispose();
  lmGeo.screen?.dispose();

  /* ---------- buildings (instanced) ---------- */
  {
    const B = L.buildings;
    const flats = B.filter((b) => b.roofType === 'flat');
    const box = new BoxGeometry(1, 1, 1);
    box.translate(0, 0.5, 0);
    box.deleteAttribute('uv');
    const walls = new InstancedMesh(keep(box), mats.solid.clone(), B.length + flats.length);
    (walls.material as MeshLambertMaterial).vertexColors = false;
    keep(walls.material as Material);
    let k = 0;
    for (const b of B) {
      _o.position.set(W(b.x), 0, W(b.y));
      _o.rotation.set(0, -b.a, 0);
      _o.scale.set(b.w * WS, b.h, b.d * WS);
      _o.updateMatrix();
      walls.setMatrixAt(k, _o.matrix);
      walls.setColorAt(k++, _c.set(b.wall));
    }
    for (const b of flats) {
      _o.position.set(W(b.x), b.h, W(b.y));
      _o.rotation.set(0, -b.a, 0);
      _o.scale.set(b.w * WS * 1.03, 0.05, b.d * WS * 1.03);
      _o.updateMatrix();
      walls.setMatrixAt(k, _o.matrix);
      walls.setColorAt(k++, _c.set(b.roof).lerp(_b.set('#d9d4c8'), 0.55));
    }
    walls.name = 'walls';
    group.add(walls);
    countTris(box, walls.count);

    const hipGeo = keep(new ConeGeometry(Math.SQRT1_2, 1, 4, 1));
    hipGeo.rotateY(Math.PI / 4);
    hipGeo.translate(0, 0.5, 0);
    hipGeo.deleteAttribute('uv');
    const gabGeo = keep(gableGeometry());
    const roofMat = keep(new MeshLambertMaterial({ flatShading: true }));
    for (const [type, geo] of [['hip', hipGeo], ['gable', gabGeo]] as const) {
      const list = B.filter((b) => b.roofType === type);
      const im = new InstancedMesh(geo, roofMat, list.length);
      list.forEach((b, i) => {
        _o.position.set(W(b.x), b.h, W(b.y));
        _o.rotation.set(0, -b.a, 0);
        const rh = type === 'hip' ? Math.min(0.32, 0.12 + Math.min(b.w, b.d) * WS * 0.28) : Math.min(0.3, 0.1 + b.d * WS * 0.3);
        _o.scale.set(b.w * WS * 1.08, rh, b.d * WS * 1.1);
        _o.updateMatrix();
        im.setMatrixAt(i, _o.matrix);
        im.setColorAt(i, _c.set(b.roof));
      });
      im.name = 'roofs-' + type;
      group.add(im);
      countTris(geo, list.length);
    }

    // lit window bands (night only)
    const lit = B.filter((b) => b.lit);
    const bandGeo = keep(new BoxGeometry(1, 1, 1));
    const bands = new InstancedMesh(bandGeo, mats.windows, lit.reduce((n, b) => n + (b.h > 0.9 ? 2 : 1), 0));
    let j = 0;
    for (const b of lit) {
      const levels = b.h > 0.9 ? 2 : 1;
      for (let l = 0; l < levels; l++) {
        _o.position.set(W(b.x), b.h * (levels === 1 ? 0.5 : 0.32 + l * 0.38), W(b.y));
        _o.rotation.set(0, -b.a, 0);
        _o.scale.set(b.w * WS * 1.02, Math.min(0.2, b.h * 0.4), b.d * WS * 1.02);
        _o.updateMatrix();
        bands.setMatrixAt(j++, _o.matrix);
      }
    }
    bands.name = 'windows';
    bands.visible = false;
    group.add(bands);
    nightOnly.push(bands);

    // soft contact shadows (one quad each), offset a little to the north-east
    const shGeo = keep(new PlaneGeometry(1, 1));
    shGeo.rotateX(-Math.PI / 2);
    const sh = new InstancedMesh(shGeo, mats.shadow, B.length);
    B.forEach((b, i) => {
      _o.position.set(W(b.x) + b.h * 0.22, 0.062, W(b.y) - b.h * 0.12);
      _o.rotation.set(0, -b.a, 0);
      _o.scale.set(b.w * WS * 1.12 + b.h * 0.25, 1, b.d * WS * 1.12 + b.h * 0.15);
      _o.updateMatrix();
      sh.setMatrixAt(i, _o.matrix);
    });
    sh.name = 'shadows';
    sh.renderOrder = 2;
    group.add(sh);
    countTris(shGeo, B.length);
  }

  /* ---------- mapped Benin City core buildings (OpenStreetMap footprints) ---------- */
  if (L.osmBuildings.length) {
    const positions: number[] = [];
    const colors: number[] = [];
    const c = new Color();
    const vertex = (x: number, y: number, z: number, color: string) => {
      positions.push(x, y, z);
      c.set(color);
      colors.push(c.r, c.g, c.b);
    };
    const tri = (a: [number, number, number], b: [number, number, number], d: [number, number, number], color: string) => {
      vertex(...a, color); vertex(...b, color); vertex(...d, color);
    };
    for (const building of L.osmBuildings) {
      const ring = building.ring;
      if (ring.length < 3) continue;
      let area = 0;
      const contour = ring.map(([x, z]) => new Vector2(W(x), W(z)));
      for (let i = 0; i < contour.length; i++) {
        const a = contour[i], b = contour[(i + 1) % contour.length];
        area += a.x * b.y - b.x * a.y;
      }
      const ccw = area > 0;
      for (let i = 0; i < ring.length; i++) {
        const [x0, z0] = ring[i];
        const [x1, z1] = ring[(i + 1) % ring.length];
        const low0: [number, number, number] = [W(x0), 0, W(z0)];
        const low1: [number, number, number] = [W(x1), 0, W(z1)];
        const high0: [number, number, number] = [W(x0), building.h, W(z0)];
        const high1: [number, number, number] = [W(x1), building.h, W(z1)];
        if (ccw) {
          tri(low0, high0, high1, building.wall);
          tri(low0, high1, low1, building.wall);
        } else {
          tri(low0, high1, high0, building.wall);
          tri(low0, low1, high1, building.wall);
        }
      }
      const roofTris = ShapeUtils.triangulateShape(contour, []);
      for (const face of roofTris) {
        let [a, b, d] = face;
        const pa = contour[a], pb = contour[b], pd = contour[d];
        const signed = (pb.x - pa.x) * (pd.y - pa.y) - (pb.y - pa.y) * (pd.x - pa.x);
        // In Three.js x/z is the ground plane; reverse positive 2D winding to
        // keep roof normals pointed upward for the single merged mesh.
        if (signed > 0) [b, d] = [d, b];
        const p0 = ring[a], p1 = ring[b], p2 = ring[d];
        tri([W(p0[0]), building.h, W(p0[1])], [W(p1[0]), building.h, W(p1[1])], [W(p2[0]), building.h, W(p2[1])], building.roof);
      }
    }
    const geometry = new BufferGeometry();
    geometry.setAttribute('position', new Float32BufferAttribute(positions, 3));
    geometry.setAttribute('color', new Float32BufferAttribute(colors, 3));
    geometry.computeVertexNormals();
    addMesh(geometry, keep(new MeshLambertMaterial({ vertexColors: true, flatShading: true, side: DoubleSide })), 'osm-core-buildings');
  }

  /* ---------- trees and palms ---------- */
  {
    const T = L.trees.filter((t) => !t.palm);
    const P = L.trees.filter((t) => t.palm);
    const greens = ['#4f8f3a', '#5f9f45', '#3f7f35', '#6aa84c'];
    const canopyGeo = keep(new IcosahedronGeometry(1, 0));
    canopyGeo.deleteAttribute('uv');
    const leafMat = keep(new MeshLambertMaterial({ flatShading: true }));
    const canopy = new InstancedMesh(canopyGeo, leafMat, T.length);
    const trunkGeo = keep(new CylinderGeometry(0.5, 0.65, 1, 4, 1, true));
    trunkGeo.translate(0, 0.5, 0);
    trunkGeo.deleteAttribute('uv');
    const barkMat = keep(new MeshLambertMaterial({ color: '#7a5233', flatShading: true }));
    const trunks = new InstancedMesh(trunkGeo, barkMat, T.length + P.length);
    T.forEach((t, i) => {
      const r = t.r * WS;
      const th = r * 0.9;
      _o.position.set(W(t.x), th + r * 0.7, W(t.y));
      _o.rotation.set(0, t.x * 0.37, 0);
      _o.scale.set(r, r * 0.92, r);
      _o.updateMatrix();
      canopy.setMatrixAt(i, _o.matrix);
      canopy.setColorAt(i, _c.set(greens[t.c]));
      _o.position.set(W(t.x), 0, W(t.y));
      _o.scale.set(r * 0.18, th + r * 0.3, r * 0.18);
      _o.updateMatrix();
      trunks.setMatrixAt(i, _o.matrix);
    });
    const frondGeo = keep(new ConeGeometry(1, 0.38, 7, 1, true));
    frondGeo.deleteAttribute('uv');
    const frondMat = keep(new MeshLambertMaterial({ flatShading: true, side: DoubleSide }));
    const fronds = new InstancedMesh(frondGeo, frondMat, P.length);
    P.forEach((t, i) => {
      const r = t.r * WS;
      const th = r * 2.1;
      _o.position.set(W(t.x), 0, W(t.y));
      _o.rotation.set(0, 0, 0);
      _o.scale.set(r * 0.12, th, r * 0.12);
      _o.updateMatrix();
      trunks.setMatrixAt(T.length + i, _o.matrix);
      _o.position.set(W(t.x), th, W(t.y));
      _o.rotation.set(0, t.y * 0.5, 0);
      _o.scale.set(r * 1.05, r * 0.9, r * 1.05);
      _o.updateMatrix();
      fronds.setMatrixAt(i, _o.matrix);
      fronds.setColorAt(i, _c.set(greens[(t.c + 1) % 4]).lerp(_b.set('#9bbf4a'), 0.25));
    });
    for (const [im, n, g] of [[canopy, T.length, canopyGeo], [trunks, T.length + P.length, trunkGeo], [fronds, P.length, frondGeo]] as const) {
      group.add(im);
      countTris(g, n);
    }
    canopy.name = 'trees';
    trunks.name = 'trunks';
    fronds.name = 'palms';
  }

  /* ---------- street lamps ---------- */
  {
    const n = L.lamps.length;
    const poleGeo = keep(new BoxGeometry(0.035, 0.55, 0.035));
    poleGeo.translate(0, 0.275, 0);
    const poleMat = keep(new MeshLambertMaterial({ color: '#7d8389' }));
    const poles = new InstancedMesh(poleGeo, poleMat, n);
    const bulbGeo = keep(new BoxGeometry(0.12, 0.05, 0.08));
    const bulbs = new InstancedMesh(bulbGeo, mats.bulbs, n);
    const poolGeo = keep(new PlaneGeometry(1, 1));
    poolGeo.rotateX(-Math.PI / 2);
    const pools = new InstancedMesh(poolGeo, mats.pools, n);
    L.lamps.forEach(([x, y], i) => {
      _o.rotation.set(0, 0, 0);
      _o.scale.set(1, 1, 1);
      _o.position.set(W(x), 0, W(y));
      _o.updateMatrix();
      poles.setMatrixAt(i, _o.matrix);
      _o.position.set(W(x), 0.56, W(y));
      _o.updateMatrix();
      bulbs.setMatrixAt(i, _o.matrix);
      _o.position.set(W(x), 0.07, W(y));
      _o.scale.set(2.2, 1, 2.2);
      _o.updateMatrix();
      pools.setMatrixAt(i, _o.matrix);
    });
    poles.name = 'lamp-poles';
    bulbs.name = 'lamp-bulbs';
    pools.name = 'lamp-pools';
    pools.visible = false;
    pools.renderOrder = 3;
    nightOnly.push(pools);
    group.add(poles, bulbs, pools);
    countTris(poleGeo, n);
    countTris(bulbGeo, n);
  }

  /* ---------- vehicles ---------- */
  const V = L.vehicles;
  const vGeo = keep(vehicleGeometry());
  const vMat = keep(new MeshLambertMaterial({ vertexColors: true, flatShading: true }));
  const vehicles = new InstancedMesh(vGeo, vMat, V.length);
  vehicles.name = 'vehicles';
  V.forEach((v, i) => vehicles.setColorAt(i, _c.set(v.color)));
  group.add(vehicles);
  countTris(vGeo, V.length);
  const SIZE: Record<Vehicle['kind'], [number, number, number]> = { car: [0.36, 0.26, 0.2], bus: [0.52, 0.36, 0.24], keke: [0.2, 0.26, 0.15] };
  const placeVehicle = (i: number, v: Vehicle, s: number) => {
    let x: number, y: number, a: number;
    if (v.px !== undefined) {
      x = v.px;
      y = v.py!;
      a = v.pa!;
    } else {
      const rd = L.roads[v.road];
      const p = at(rd.sp, s);
      const off = rd.hw * 0.48 * v.lane;
      x = p.x - Math.sin(p.a) * off;
      y = p.y + Math.cos(p.a) * off;
      a = p.a + (v.lane < 0 ? Math.PI : 0);
    }
    const [l, h, w] = SIZE[v.kind];
    _o.position.set(W(x), 0.05, W(y));
    _o.rotation.set(0, -a, 0);
    _o.scale.set(l, h, w);
    _o.updateMatrix();
    vehicles.setMatrixAt(i, _o.matrix);
  };
  const animate = (t: number) => {
    for (let i = 0; i < V.length; i++) {
      const v = V[i];
      if (v.px !== undefined && t > 0) continue;
      const len = v.s1 - v.s0;
      let s: number;
      if (v.jam) {
        // stop-go creep towards Ramat Park, looping inside the queue
        const creep = t * v.speed * (0.5 + 0.5 * Math.sin(t * 0.7 + i));
        s = v.s0 + ((((v.s - v.s0 + creep * v.lane) % len) + len) % len);
      } else {
        s = (((v.s + t * v.speed * v.lane) % len) + len) % len;
      }
      placeVehicle(i, v, s);
    }
    vehicles.instanceMatrix.needsUpdate = true;
  };
  animate(0);

  return {
    group,
    mats,
    nightOnly,
    vehicles,
    animate,
    tris: Math.round(tris),
    dispose() {
      for (const d of disposables) d.dispose();
      group.traverse((o) => {
        if (o instanceof InstancedMesh) o.dispose();
      });
    },
  };
}


/* ------------------------------------------------------------------ */
/* Landmarks                                                            */
/* ------------------------------------------------------------------ */
function buildLandmarks(b: HomeBuilder) {
  const at2 = (mx: number, my: number, yaw = 0) => b.setFrame(W(mx), 0, W(my), yaw);

  // --- Benin National Museum: the round drum in the middle of King's Square
  at2(500, 500);
  b.cyl(1.05, 1.1, 0.06, 0, 0, 0, '#e8dcc2', { seg: 20 });
  b.cyl(0.78, 0.8, 0.62, 0, 0.06, 0, '#efe4cc', { seg: 16 });
  b.cyl(0.81, 0.81, 0.1, 0, 0.42, 0, '#b5552b', { seg: 16 });
  b.cyl(0.62, 0.84, 0.14, 0, 0.68, 0, '#8d939a', { seg: 16 });
  b.cyl(0.79, 0.79, 0.14, 0, 0.16, 0, '#7fb6d6', { seg: 16, layer: 'glow' });
  b.box(0.36, 0.34, 0.3, 0, 0.06, 0.8, '#efe4cc');
  b.box(0.42, 0.05, 0.36, 0, 0.4, 0.8, '#b5552b');
  // flagpoles at the entrance
  for (const x of [-0.5, 0.5]) {
    b.box(0.025, 0.7, 0.025, x, 0, 1.15, '#d0d0d0');
    b.box(0.18, 0.11, 0.01, x + 0.09, 0.56, 1.15, '#1f8a4c');
  }

  // --- Oba's Palace: walled compound W of King's Square, steep pyramid roofs, bronze bird
  {
    // compound wall along the polygon
    b.resetFrame();
    for (let i = 0; i < PALACE.length; i++) {
      const [x1, y1] = PALACE[i];
      const [x2, y2] = PALACE[(i + 1) % PALACE.length];
      const len = Math.hypot(x2 - x1, y2 - y1) * WS;
      b.setFrame(W((x1 + x2) / 2), 0, W((y1 + y2) / 2), -Math.atan2(y2 - y1, x2 - x1));
      b.box(len + 0.08, 0.3, 0.12, 0, 0, 0, '#9e4329');
      b.box(len + 0.1, 0.04, 0.16, 0, 0.3, 0, '#7a3220');
    }
    // the main hall and wings (laterite-red walls)
    at2(405, 503);
    b.box(2.0, 0.55, 1.1, 0, 0, -0.15, '#b04b2e');
    b.box(0.9, 0.5, 0.8, -0.95, 0, 0.75, '#b04b2e');
    b.box(0.9, 0.5, 0.8, 0.85, 0, 0.8, '#b04b2e');
    b.box(2.04, 0.06, 1.14, 0, 0.55, -0.15, '#7a3220');
    // carved band on the hall
    b.box(2.02, 0.07, 1.12, 0, 0.22, -0.15, '#e6c48a');
    // pyramid roofs (turrets)
    // S3: rust-red zinc roofs (lighter than before, so the shapes read from far away)
    const turret = (x: number, z: number, r: number, h: number) => b.cyl(0, r, h, x, 0.55, z, '#7e4630', { seg: 4, ry: Math.PI / 4 });
    turret(0, -0.15, 0.95, 1.35);
    turret(-0.95, 0.75, 0.62, 0.8);
    turret(0.85, 0.8, 0.62, 0.8);
    turret(-0.75, -0.25, 0.5, 0.75);
    turret(0.75, -0.25, 0.5, 0.75);
    // bronze bird (the Bird of Prophecy) on the tallest roof, on a short mast; S3: 1.8x bigger
    const k = 1.8;
    const by = 0.55 + 1.35 - 0.06;
    b.box(0.06, 0.3, 0.06, 0, by, -0.15, '#6b4420');
    const bird = (w: number, h: number, d: number, x: number, y: number, col: string, o?: { rx: number }) =>
      b.box(w * k, h * k, d * k, x * k, by + 0.22 + y * k, -0.15, col, o);
    bird(0.36, 0.15, 0.14, 0, 0, '#b97f3c'); // body
    bird(0.13, 0.13, 0.12, 0.2, 0.1, '#c8924a'); // head
    bird(0.13, 0.04, 0.05, 0.31, 0.13, '#e0aa45'); // beak
    bird(0.2, 0.04, 0.52, -0.03, 0.08, '#a8702f', { rx: 0.3 }); // wings
    bird(0.16, 0.09, 0.1, -0.22, 0.06, '#a8702f'); // tail
    // ceremonial gate facing King's Square (east)
    b.box(0.14, 0.62, 0.14, 1.6, 0, -0.45, '#9e4329');
    b.box(0.14, 0.62, 0.14, 1.6, 0, 0.25, '#9e4329');
    b.cyl(0, 0.62, 0.5, 1.6, 0.62, -0.1, '#5e3a2a', { seg: 4, ry: Math.PI / 4 });
    b.box(0.06, 0.36, 0.56, 1.66, 0, -0.1, '#d9a441');
  }

  // --- Oba Market: big zinc sheds in the middle of the stalls
  for (const [mx, my, mr, id] of MARKETS) {
    at2(mx, my, 0.15);
    const big = id === 'oba_market';
    const l = (big ? 2.0 : 1.2) * (mr / 22) * 1.2;
    b.box(l, 0.32, 0.7, 0, 0, 0, '#d8c3a0');
    b.box(l + 0.1, 0.05, 0.42, 0, 0.36, -0.17, '#9aa1a6', { rx: 0.42 });
    b.box(l + 0.1, 0.05, 0.42, 0, 0.36, 0.17, '#8a9196', { rx: -0.42 });
    if (big) {
      b.box(1.2, 0.3, 0.6, 0.2, 0, 1.0, '#d8c3a0');
      b.box(1.3, 0.05, 0.38, 0.2, 0.34, 0.85, '#9aa1a6', { rx: 0.42 });
      b.box(1.3, 0.05, 0.38, 0.2, 0.34, 1.15, '#8a9196', { rx: -0.42 });
    }
  }

  // --- UNIBEN gate on the Ugbowo road (campus to the east of the road)
  at2(476, 128, Math.PI / 2 - 0.15);
  for (const z of [-0.55, 0.55]) {
    b.box(0.16, 0.75, 0.16, 0, 0, z, '#f2efe6');
    b.box(0.2, 0.08, 0.2, 0, 0.75, z, '#1f7a3f');
  }
  b.box(0.14, 0.18, 1.3, 0, 0.6, 0, '#1f7a3f');
  b.box(0.15, 0.08, 1.1, 0, 0.62, 0, '#d9a441');
  // UNIBEN tower block (Senate building)
  at2(497, 118);
  b.box(0.7, 1.5, 0.55, 0, 0, 0, '#efe4cc');
  b.box(0.72, 0.5, 0.57, 0, 0.35, 0, '#9fc3d8', { layer: 'glow' });
  b.box(0.72, 0.3, 0.57, 0, 1.05, 0, '#9fc3d8', { layer: 'glow' });
  b.box(0.76, 0.05, 0.6, 0, 1.5, 0, '#3f7d4a');
  // stadium stands
  at2(STADIUM.x, STADIUM.y);
  b.box(0.2, 0.22, 1.6, -1.95, 0, 0, '#d8d2c4');
  b.box(0.2, 0.22, 1.6, 1.95, 0, 0, '#d8d2c4');

  // --- UBTH: tall white teaching hospital with a red cross on the roof
  at2(421, 170);
  b.box(1.9, 1.35, 0.75, 0, 0, 0, '#f2f4f5');
  b.box(0.7, 0.8, 1.4, -0.75, 0, 0.55, '#eef1f2');
  b.box(0.7, 0.8, 1.4, 0.75, 0, 0.55, '#eef1f2');
  for (const y of [0.25, 0.6, 0.95]) b.box(1.92, 0.14, 0.77, 0, y, 0, '#9fc3d8', { layer: 'glow' });
  b.box(1.94, 0.05, 0.79, 0, 1.35, 0, '#c9d2d8');
  b.box(0.5, 0.06, 0.14, 0, 1.4, 0, '#d63c32');
  b.box(0.14, 0.06, 0.5, 0, 1.4, 0, '#d63c32');
  b.box(0.5, 0.22, 0.06, 0, 0.82, 0.4, '#d63c32');

  // --- Bronze Tech Hub (V1-3): glass coworking block, laterite-clad wing, solar roof, gold sign
  at2(TECH_HUB.x, TECH_HUB.y, 0.1);
  b.box(2.2, 0.03, 1.9, 0, 0.01, 0.2, '#b8aea2');
  b.box(1.4, 0.95, 0.9, -0.3, 0, 0, '#dfe6e8');
  b.box(1.42, 0.32, 0.92, -0.3, 0.1, 0, '#9fc3d8', { layer: 'glow' });
  b.box(1.42, 0.3, 0.92, -0.3, 0.55, 0, '#9fc3d8', { layer: 'glow' });
  b.box(0.65, 0.95, 0.9, 0.72, 0, 0, '#b5552b');
  for (const x of [0.5, 0.62, 0.74, 0.86, 0.98]) b.box(0.04, 0.5, 0.02, x, 0.4, 0.46, '#8a5a34');
  b.cyl(0.12, 0.12, 0.02, 0.72, 0.68, 0.47, '#d9a441', { seg: 12, rx: Math.PI / 2, layer: 'glow' });
  b.box(2.12, 0.05, 0.96, 0.03, 0.95, 0, '#ece8de');
  b.box(1.42, 0.09, 0.05, -0.3, 0.45, 0.47, '#1e2030');
  b.box(0.8, 0.04, 0.04, -0.3, 0.47, 0.5, '#d9a441', { layer: 'glow' });
  for (const x of [-0.8, -0.4, 0, 0.4]) b.box(0.36, 0.04, 0.6, x, 1.02, -0.04, '#24407e');

  // --- Benin Airport: runway, terminal, tower and a parked plane
  {
    const { x1, y1, x2, y2, w } = RUNWAY;
    const ang = Math.atan2(y2 - y1, x2 - x1);
    const len = Math.hypot(x2 - x1, y2 - y1) * WS;
    b.setFrame(W((x1 + x2) / 2), 0, W((y1 + y2) / 2), -ang);
    b.box(len, 0.03, w * WS, 0, 0.01, 0, '#3e4249');
    for (let s = -len / 2 + 0.4; s < len / 2 - 0.3; s += 0.7) b.box(0.36, 0.035, 0.07, s, 0.01, 0, '#f4f1e8');
    for (const s of [-len / 2 + 0.15, len / 2 - 0.15]) b.box(0.18, 0.035, w * WS * 0.8, s, 0.01, 0, '#f4f1e8');
    // terminal + apron
    at2(TERMINAL.x, TERMINAL.y, -ang);
    b.box(2.2, 0.03, 1.4, -0.3, 0.01, 0.15, '#9aa0a6');
    b.box(1.6, 0.42, 0.55, -0.2, 0, 0.6, '#f1f1ee');
    b.box(1.62, 0.18, 0.57, -0.2, 0.12, 0.6, '#9fc3d8', { layer: 'glow' });
    b.box(1.7, 0.05, 0.65, -0.2, 0.42, 0.6, '#1f7a3f');
    b.cyl(0.09, 0.11, 1.0, 0.75, 0, 0.75, '#efefea', { seg: 8 });
    b.cyl(0.2, 0.16, 0.18, 0.75, 1.0, 0.75, '#9fc3d8', { seg: 8, layer: 'glow' });
    b.cyl(0.22, 0.22, 0.05, 0.75, 1.18, 0.75, '#d0d0cc', { seg: 8 });
    // plane (white, green stripe)
    b.cyl(0.09, 0.09, 1.1, -0.6, 0.18, -0.05, '#f6f6f4', { seg: 8, rz: Math.PI / 2 });
    b.box(0.32, 0.03, 1.2, -0.55, 0.2, -0.05, '#e6e6e2');
    b.box(0.18, 0.28, 0.03, -1.1, 0.24, -0.05, '#1f7a3f');
    b.box(0.14, 0.02, 0.42, -1.1, 0.27, -0.05, '#e6e6e2');
  }

  // --- Police Command HQ (GRA): blue-and-white block with a flag
  at2(497, 610);
  b.box(1.5, 0.62, 0.9, 0, 0, 0, '#eef2f7');
  b.box(1.52, 0.1, 0.92, 0, 0.32, 0, '#1d4f9c');
  b.box(1.56, 0.06, 0.96, 0, 0.62, 0, '#1d4f9c');
  b.box(1.52, 0.14, 0.92, 0, 0.42, 0, '#9fc3d8', { layer: 'glow' });
  b.box(0.03, 1.1, 0.03, 0.9, 0, 0.55, '#d0d0d0');
  b.box(0.1, 0.16, 0.01, 0.95, 0.92, 0.55, '#1f8a4c');
  b.box(0.1, 0.16, 0.012, 1.05, 0.92, 0.55, '#ffffff');
  b.box(0.1, 0.16, 0.01, 1.15, 0.92, 0.55, '#1f8a4c');

  // --- Bridge over the Ikpoba on Akpakpava Rd
  b.setFrame(W(BRIDGE.x), 0, W(BRIDGE.y), -BRIDGE.a);
  b.box(2.6, 0.07, 1.5, 0, 0.12, 0, '#a7a49d');
  for (const z of [-0.72, 0.72]) b.box(2.6, 0.12, 0.06, 0, 0.19, z, '#e3ded3');
  for (const x of [-0.7, 0.7]) b.box(0.18, 0.13, 1.3, x, 0, 0, '#8d8a84');
  b.box(2.5, 0.01, 1.2, 0, 0.19, 0, '#4a4e57');

  // --- Motor parks: shelters on the pads
  for (const [px, py, pr] of [[452, 282, 13], [398, 52, 12], [705, 400, 10], [828, 352, 12]] as const) {
    at2(px, py + pr * 0.55);
    for (const x of [-pr * 0.05, pr * 0.05]) b.box(0.05, 0.32, 0.05, x, 0, 0, '#7d8389');
    b.box(pr * 0.14, 0.04, 0.45, 0, 0.32, 0, '#d63c32');
  }

  // --- Ramat Park: a small monument on the roundabout
  at2(RAMAT.x, RAMAT.y);
  b.cyl(0.2, 0.25, 0.12, 0, 0.06, 0, '#e3ded3', { seg: 8 });
  b.box(0.08, 0.6, 0.08, 0, 0.18, 0, '#b0793a');

  // --- Baba Osagie's shrine in the grove: thatched hut
  at2(GROVE.x + 4, GROVE.y + 3);
  b.cyl(0.32, 0.32, 0.28, 0, 0, 0, '#c9874f', { seg: 8 });
  b.cyl(0, 0.46, 0.42, 0, 0.28, 0, '#c9a45a', { seg: 8 });
  b.box(0.08, 0.06, 0.08, 0.38, 0, 0.2, '#f4f1e8');

  // --- Iguobazuwa farm huts on the NW edge
  for (const [x, y] of [[60, 290], [95, 330], [48, 370]] as const) {
    at2(x, y);
    b.cyl(0.3, 0.3, 0.25, 0, 0, 0, '#c9874f', { seg: 7 });
    b.cyl(0, 0.42, 0.36, 0, 0.25, 0, '#c9a45a', { seg: 7 });
  }

  // --- Exit sign gantries are HTML (readable text); add their posts here
  b.resetFrame();
}

/* ------------------------------------------------------------------ */
/* Dynamic overlays                                                     */
/* ------------------------------------------------------------------ */

/** Ground ring (flat, unit radius) for markers and filter highlights. */
export function ringGeometry(inner = 0.72): BufferGeometry {
  const g = new RingGeometry(inner, 1, 40);
  g.rotateX(-Math.PI / 2);
  return g;
}

/** Ribbon along a map-space polyline (for the travel route), y above the roads. */
export function routeGeometry(pts: Pt[], hw: number): { geo: BufferGeometry; lengths: number[] } {
  const f = new Flat();
  const S: { x: number; y: number; a: number }[] = [];
  const lengths: number[] = [];
  let len = 0;
  for (let i = 0; i < pts.length; i++) {
    const p = pts[i];
    const q = pts[Math.min(pts.length - 1, i + 1)];
    const o = pts[Math.max(0, i - 1)];
    if (i > 0) len += Math.hypot(p[0] - o[0], p[1] - o[1]);
    S.push({ x: p[0], y: p[1], a: Math.atan2(q[1] - o[1], q[0] - o[0]) });
    lengths.push(len);
  }
  f.strip(S, hw, 0.09, '#ffffff');
  return { geo: f.geometry(), lengths };
}

/** The keke used as the travel marker (merged, vertex coloured). */
export function kekeGeometry(): BufferGeometry {
  const b = new HomeBuilder();
  b.box(0.9, 0.36, 0.5, 0, 0.1, 0, '#f2c230');
  b.box(0.6, 0.06, 0.54, -0.1, 0.72, 0, '#1f7a3f');
  for (const z of [-0.24, 0.24]) b.box(0.05, 0.3, 0.05, -0.36, 0.42, z, '#2a2a2a');
  b.box(0.05, 0.3, 0.05, 0.22, 0.42, 0, '#2a2a2a');
  b.box(0.14, 0.2, 0.46, 0.36, 0.42, 0, '#9fc3d8');
  for (const [x, z] of [[-0.3, -0.26], [-0.3, 0.26], [0.36, 0]] as const) b.cyl(0.11, 0.11, 0.08, x, 0.11, z, '#222', { seg: 8, rx: Math.PI / 2 });
  return b.finish().solid!;
}

export function pinGeometry(): BufferGeometry {
  const head = new SphereGeometry(0.32, 10, 8);
  head.translate(0, 1.15, 0);
  const tip = new ConeGeometry(0.22, 0.75, 8);
  tip.rotateX(Math.PI);
  tip.translate(0, 0.65, 0);
  head.deleteAttribute('uv');
  tip.deleteAttribute('uv');
  const g = mergeGeometries([head, tip])!;
  head.dispose();
  tip.dispose();
  return g;
}
