// R5: procedural layout of the 3D city in MAP space (pure numbers, no three.js).
// Roads, river, zones and density cores all come from the 2D map's data (src/art/map/mapGeo.ts),
// so every building, tree and car sits where the 2D map (and docs/MAP_GEO.md) says the city is.
import {
  AIRPORT, CAMPUS, CORES, FARMLAND, GRA_ZONE, GROVE, KINGS_SQUARE, MARKETS, PALACE, POLICE, RAMAT, RING, RIVER,
  ROAD_HW, ROADS, RUNWAY, UBTH, at, inPoly, rng, spline, type Pt, type RoadKind, type Spline,
} from '../../map/mapGeo';

export type Style = 'core' | 'res' | 'cramped' | 'gra' | 'campus' | 'market';
export type Roof = 'hip' | 'gable' | 'flat';

export interface Building {
  x: number;
  y: number;
  /** footprint along / across the facing direction (map units) */
  w: number;
  d: number;
  /** wall height (world units) */
  h: number;
  a: number; // yaw (rad, map space: angle of the frontage)
  wall: string;
  roof: string;
  roofType: Roof;
  lit: boolean;
}

export interface Tree {
  x: number;
  y: number;
  r: number; // canopy radius (map units)
  c: number; // colour index
  palm: boolean;
}

export interface Vehicle {
  road: number; // index into roadSplines
  s: number; // arc length along it
  lane: number; // +1 / -1 (side of the road)
  speed: number; // map units / s (0 = parked)
  kind: 'car' | 'bus' | 'keke';
  color: string;
  /** jam vehicles creep inside [s0, s1] */
  s0: number;
  s1: number;
  jam: boolean;
  /** parked vehicles: fixed map position */
  px?: number;
  py?: number;
  pa?: number;
}

export interface RoadLine {
  id: string;
  kind: RoadKind | 'ring' | 'spur';
  sp: Spline;
  hw: number;
  closed: boolean;
}

export interface CityLayout {
  roads: RoadLine[];
  river: Spline;
  buildings: Building[];
  trees: Tree[];
  vehicles: Vehicle[];
  lamps: [number, number][];
  /** map-space density lookup (0..1) for ground colour */
  urban: (x: number, y: number) => number;
  riverDist: (x: number, y: number, lim?: number) => number;
  ms: number;
}

const dist = (ax: number, ay: number, bx: number, by: number) => Math.sqrt((ax - bx) ** 2 + (ay - by) ** 2);

/** Simple bucket grid of circles in map space. */
class Grid {
  private cells = new Map<number, number[]>();
  readonly xs: number[] = [];
  readonly ys: number[] = [];
  readonly rs: number[] = [];
  readonly as: number[] = [];
  private cell: number;
  constructor(cell: number) {
    this.cell = cell;
  }
  private k(cx: number, cy: number) {
    return (cx + 64) * 4096 + (cy + 64);
  }
  add(x: number, y: number, r: number, a = 0) {
    const i = this.xs.length;
    this.xs.push(x);
    this.ys.push(y);
    this.rs.push(r);
    this.as.push(a);
    const key = this.k(Math.floor(x / this.cell), Math.floor(y / this.cell));
    const arr = this.cells.get(key);
    if (arr) arr.push(i);
    else this.cells.set(key, [i]);
  }
  /** min over items of (distance - r_i), capped at lim; `qa` gets that item's angle */
  qa = 0;
  edge(x: number, y: number, lim: number): number {
    let best = lim;
    const reach = Math.ceil((lim + 12) / this.cell);
    const cx = Math.floor(x / this.cell);
    const cy = Math.floor(y / this.cell);
    for (let j = cy - reach; j <= cy + reach; j++)
      for (let i = cx - reach; i <= cx + reach; i++) {
        const arr = this.cells.get(this.k(i, j));
        if (!arr) continue;
        for (const n of arr) {
          const e = dist(x, y, this.xs[n], this.ys[n]) - this.rs[n];
          if (e < best) {
            best = e;
            this.qa = this.as[n];
          }
        }
      }
    return best;
  }
}

const WALLS: Record<Style, string[]> = {
  core: ['#efe3c8', '#e9d3b0', '#f3ece0', '#d9e4ea', '#f0cfae', '#e2d8c9', '#cfdcc0'],
  res: ['#efe3c8', '#e8cfab', '#f1e9dc', '#d4e2e6', '#efc9a3', '#dcc9a6', '#d8e3c4'],
  cramped: ['#e2c49e', '#d9b48c', '#e9d6b9', '#cdbba0', '#e4c7a7'],
  gra: ['#f6f3ec', '#f1ece2', '#eef1ee', '#f4ead8'],
  campus: ['#efe4cc', '#f2ead9', '#e6dcc4'],
  market: ['#d8c3a0', '#e3d2b3'],
};
const ROOFS: Record<Style, string[]> = {
  core: ['#8a4b2c', '#9aa1a6', '#a8553a', '#7d858b', '#b8432f', '#2f7d7a', '#3d6fa8'],
  res: ['#8a4b2c', '#9c5a35', '#7f8a90', '#a0a8ad', '#8e3f2a', '#6f4a33'],
  cramped: ['#7b4328', '#8a4b2c', '#6e3b25', '#8f969b', '#7a5a45'],
  gra: ['#b8432f', '#2f7d7a', '#8a4b2c', '#3d6fa8', '#7d858b'],
  campus: ['#3f7d4a', '#2f6f45', '#4b8a52'],
  market: ['#2f6fd0', '#d63c32', '#f2b632', '#2e9d58', '#e06a1c', '#7a4ac8'],
};

let cached: CityLayout | null = null;
export function getCityLayout(): CityLayout {
  return (cached ??= build());
}

function build(): CityLayout {
  const t0 = performance.now();
  const rand = rng(20261005);
  const R = (a: number, b: number) => a + (b - a) * rand();
  const pick = <T,>(arr: T[]) => arr[Math.floor(rand() * arr.length)];

  /* ---------- density ---------- */
  const UG = 20;
  const UN = Math.ceil(1200 / UG) + 1; // grid from -100 to 1100
  const ug = new Float32Array(UN * UN).fill(1);
  for (const [cx, cy, r, w] of CORES) {
    const k = 1 / (r * r * 1.38);
    for (let j = 0; j < UN; j++) {
      const dy = j * UG - 100 - cy;
      for (let i = 0; i < UN; i++) {
        const dx = i * UG - 100 - cx;
        const d2 = (dx * dx + dy * dy) * k;
        if (d2 < 8) ug[j * UN + i] *= 1 - w * Math.exp(-d2);
      }
    }
  }
  for (let i = 0; i < ug.length; i++) ug[i] = 1 - ug[i];
  const urban = (x: number, y: number) => {
    let fx = (x + 100) / UG;
    let fy = (y + 100) / UG;
    fx = fx < 0 ? 0 : fx > UN - 1.001 ? UN - 1.001 : fx;
    fy = fy < 0 ? 0 : fy > UN - 1.001 ? UN - 1.001 : fy;
    const i = fx | 0;
    const j = fy | 0;
    const tx = fx - i;
    const ty = fy - j;
    const k = j * UN + i;
    const a = ug[k] + (ug[k + 1] - ug[k]) * tx;
    const b = ug[k + UN] + (ug[k + UN + 1] - ug[k + UN]) * tx;
    return a + (b - a) * ty;
  };

  /* ---------- roads ---------- */
  const roadHash = new Grid(16);
  const roads: RoadLine[] = [];
  const ringPts: Pt[] = [];
  for (let i = 0; i < 32; i++) {
    const a = (i / 32) * Math.PI * 2;
    ringPts.push([RING.x + Math.cos(a) * RING.r, RING.y + Math.sin(a) * RING.r]);
  }
  const addRoad = (r: RoadLine) => {
    roads.push(r);
    let next = 0;
    for (const p of r.sp.samples)
      if (p.s >= next) {
        roadHash.add(p.x, p.y, r.hw, p.a);
        next = p.s + 3.5;
      }
  };
  addRoad({ id: 'ring', kind: 'ring', sp: spline(ringPts, true), hw: RING.hw, closed: true });
  const ramatPts: Pt[] = [];
  for (let i = 0; i < 12; i++) {
    const a = (i / 12) * Math.PI * 2;
    ramatPts.push([RAMAT.x + Math.cos(a) * 11, RAMAT.y + Math.sin(a) * 11]);
  }
  addRoad({ id: 'ramat', kind: 'ring', sp: spline(ramatPts, true), hw: 5, closed: true });
  for (const rd of ROADS) addRoad({ id: rd.id, kind: rd.kind, sp: spline(rd.pts), hw: ROAD_HW[rd.kind], closed: false });

  const river = spline(RIVER);
  const riverHash = new Grid(30);
  for (let s = 0; s <= river.length; s += 4) {
    const p = at(river, s);
    riverHash.add(p.x, p.y, 0);
  }
  const riverDist = (x: number, y: number, lim = 60) => riverHash.edge(x, y, lim);
  const roadClear = (x: number, y: number, lim = 40) => roadHash.edge(x, y, lim);

  const inRunway = (x: number, y: number, pad: number) => {
    const { x1, y1, x2, y2, w } = RUNWAY;
    const dx = x2 - x1;
    const dy = y2 - y1;
    const t = Math.max(0, Math.min(1, ((x - x1) * dx + (y - y1) * dy) / (dx * dx + dy * dy)));
    return dist(x, y, x1 + t * dx, y1 + t * dy) < w / 2 + pad;
  };
  const special = (x: number, y: number) => {
    if (dist(x, y, KINGS_SQUARE.x, KINGS_SQUARE.y) < RING.r + RING.hw + 3 || dist(x, y, RAMAT.x, RAMAT.y) < 22) return true;
    for (const [mx, my, mr] of MARKETS) if (dist(x, y, mx, my) < mr + 2) return true;
    if (dist(x, y, GROVE.x, GROVE.y) < GROVE.r) return true;
    return inPoly(x, y, CAMPUS) || inPoly(x, y, AIRPORT) || inPoly(x, y, PALACE) || inPoly(x, y, UBTH) || inPoly(x, y, POLICE) || inPoly(x, y, FARMLAND) || inRunway(x, y, 8);
  };
  // motor park pads and the bridge approaches stay clear too
  const PADS: [number, number, number][] = [
    [452, 282, 13],
    [398, 52, 12],
    [705, 400, 10],
    [828, 352, 12],
  ];
  const onPad = (x: number, y: number) => PADS.some(([px, py, pr]) => dist(x, y, px, py) < pr);

  /* ---------- fishbone side streets (from the busy roads) ---------- */
  for (const rd of [...roads]) {
    if (rd.kind === 'ring' || rd.kind === 'dirt' || rd.kind === 'minor') continue;
    const sp = rd.sp;
    let s = R(16, 30);
    let side = rand() < 0.5 ? 1 : -1;
    while (s < sp.length - 10) {
      const p = at(sp, s);
      const u = urban(p.x, p.y);
      if (p.x > 5 && p.x < 995 && p.y > 5 && p.y < 995 && rand() < 0.15 + u * 0.75) {
        const nx = -Math.sin(p.a) * side;
        const ny = Math.cos(p.a) * side;
        const len = R(26, 64) * (0.6 + u * 0.6);
        const pts: Pt[] = [[p.x + nx * (rd.hw - 1), p.y + ny * (rd.hw - 1)]];
        for (let d = 10; d <= len; d += 10) {
          const x = p.x + nx * (d + rd.hw);
          const y = p.y + ny * (d + rd.hw);
          if (d > 12 && roadClear(x, y, 16) < 5) break;
          if (riverDist(x, y, 30) < 20 || special(x, y)) break;
          pts.push([x, y]);
        }
        if (pts.length >= 3) addRoad({ id: 'spur', kind: 'spur', sp: spline(pts), hw: 2.4, closed: false });
      }
      s += R(22, 40) * (1.25 - u * 0.5);
      side = -side;
    }
  }

  /* ---------- district style ---------- */
  const styleAt = (x: number, y: number, u: number): Style => {
    if (dist(x, y, GRA_ZONE.x, GRA_ZONE.y) < GRA_ZONE.r) return 'gra';
    // Upper Sakponba, Aduwawa, Ekenwan, outer Siluko: cramped face-me-I-face-you blocks
    if (dist(x, y, 725, 700) < 85 || dist(x, y, 850, 370) < 80 || dist(x, y, 260, 570) < 90 || dist(x, y, 320, 340) < 70) return 'cramped';
    if (u > 0.82 && dist(x, y, 500, 500) < 190) return 'core';
    return 'res';
  };

  /* ---------- buildings ---------- */
  const buildings: Building[] = [];
  const occ = new Grid(14);
  const tryPlace = (x: number, y: number, a: number, st: Style, wMul = 1): boolean => {
    if (x < -40 || x > 1040 || y < -40 || y > 1040) return false;
    let w: number, d: number, h: number, roofType: Roof;
    switch (st) {
      case 'core':
        w = R(7, 11);
        d = R(7, 10);
        h = rand() < 0.35 ? R(0.9, 1.7) : R(0.45, 0.8);
        roofType = h > 0.85 ? 'flat' : rand() < 0.6 ? 'hip' : 'gable';
        break;
      case 'gra':
        w = R(9, 13);
        d = R(8, 11);
        h = rand() < 0.5 ? R(0.7, 0.9) : R(0.45, 0.6);
        roofType = 'hip';
        break;
      case 'cramped':
        w = R(7, 10);
        d = R(4.5, 6);
        h = R(0.32, 0.42);
        roofType = rand() < 0.75 ? 'gable' : 'hip';
        break;
      case 'campus':
        w = R(14, 22);
        d = R(6, 8);
        h = R(0.6, 1.0);
        roofType = rand() < 0.5 ? 'gable' : 'flat';
        break;
      case 'market':
        w = R(3.5, 5);
        d = R(3, 4);
        h = R(0.14, 0.2);
        roofType = 'gable';
        break;
      default:
        w = R(6, 9);
        d = R(5.5, 8);
        h = rand() < 0.15 ? R(0.7, 0.95) : R(0.36, 0.5);
        roofType = h > 0.68 && rand() < 0.4 ? 'flat' : rand() < 0.55 ? 'hip' : 'gable';
    }
    w *= wMul;
    const rad = Math.max(w, d) * 0.5;
    if (st !== 'campus' && st !== 'market' && special(x, y)) return false;
    if (onPad(x, y)) return false;
    if (roadClear(x, y, 30) < rad * 0.8) return false;
    if (riverDist(x, y, 40) < rad + 9) return false;
    if (occ.edge(x, y, 30) < rad * 0.92) return false;
    occ.add(x, y, rad * 0.92);
    buildings.push({
      x,
      y,
      w,
      d,
      h,
      a,
      wall: pick(WALLS[st]),
      roof: pick(ROOFS[st]),
      roofType,
      lit: st === 'market' ? false : rand() < (h > 0.8 ? 0.85 : 0.55),
    });
    return true;
  };

  // frontage rows along every road
  for (const rd of roads) {
    if (rd.kind === 'dirt' || rd.id === 'ramat') continue;
    const sp = rd.sp;
    let s = R(2, 8);
    while (s < sp.length) {
      const p = at(sp, s);
      const u = urban(p.x, p.y);
      for (const side of [1, -1]) {
        const nx = -Math.sin(p.a) * side;
        const ny = Math.cos(p.a) * side;
        const st = styleAt(p.x, p.y, u);
        const pr = st === 'gra' ? 0.55 : st === 'cramped' ? 0.2 + u : 0.08 + u * 1.05;
        if (rand() > pr) continue;
        const depth = st === 'gra' ? 10 : 7;
        const off = rd.hw + 3 + depth / 2 + (st === 'gra' ? 4 : 0);
        tryPlace(p.x + nx * off, p.y + ny * off, p.a, st);
        if (u > 0.5 && rand() < u * 0.85) tryPlace(p.x + nx * (off + depth + 4), p.y + ny * (off + depth + 4), p.a, st);
        if (u > 0.75 && rand() < u * 0.6) tryPlace(p.x + nx * (off + 2 * depth + 8), p.y + ny * (off + 2 * depth + 8), p.a, st);
      }
      s += rd.kind === 'spur' ? R(8, 11) : R(9, 13);
    }
  }
  // infill inside the dense cores
  for (let n = 0; n < 2600; n++) {
    const x = R(-20, 1020);
    const y = R(-20, 1020);
    const u = urban(x, y);
    if (rand() > u * u * 0.9) continue;
    const c = roadClear(x, y, 60);
    if (c > 50) continue;
    tryPlace(x, y, roadHash.qa + (rand() < 0.15 ? Math.PI / 2 : 0), styleAt(x, y, u));
  }
  // UNIBEN: long faculty blocks in rows inside the campus
  {
    const rows: [number, number, number][] = [];
    for (let y = 104; y <= 158; y += 13) for (let x = 474; x <= 530; x += 20) rows.push([x, y, rand() < 0.3 ? Math.PI / 2 : 0]);
    for (const [x, y, a] of rows) {
      if (!inPoly(x, y, CAMPUS) || dist(x, y, 514, 140) < 16) continue;
      tryPlace(x + R(-2, 2), y + R(-1.5, 1.5), a, 'campus');
    }
  }
  // market stalls: rows of small tarps around each market
  for (const [mx, my, mr] of MARKETS) {
    for (let ring = 0.35; ring <= 1.0; ring += 0.22) {
      const n = Math.round(ring * mr * 0.9);
      for (let k = 0; k < n; k++) {
        const a = (k / n) * Math.PI * 2 + ring * 3;
        const x = mx + Math.cos(a) * mr * ring;
        const y = my + Math.sin(a) * mr * ring;
        if (roadClear(x, y, 20) < 4) continue;
        tryPlace(x, y, a + Math.PI / 2, 'market');
      }
    }
  }

  /* ---------- trees and palms ---------- */
  const trees: Tree[] = [];
  const treeOcc = new Grid(12);
  const addTree = (x: number, y: number, r: number, palm: boolean, force = false) => {
    if (!force) {
      if (roadClear(x, y, 20) < r * 0.6 + 1) return;
      if (riverDist(x, y, 20) < 7) return;
      if (occ.edge(x, y, 20) < r * 0.7) return;
      if (treeOcc.edge(x, y, 12) < r * 0.6) return;
      if (inRunway(x, y, 10) || inPoly(x, y, AIRPORT)) return;
    }
    treeOcc.add(x, y, r * 0.6);
    trees.push({ x, y, r, c: Math.floor(rand() * 4), palm });
  };
  // GRA: leafy
  for (let n = 0; n < 520; n++) {
    const a = rand() * Math.PI * 2;
    const rr = Math.sqrt(rand()) * GRA_ZONE.r * 1.1;
    addTree(GRA_ZONE.x + Math.cos(a) * rr, GRA_ZONE.y + Math.sin(a) * rr, R(3.2, 5.5), rand() < 0.18);
  }
  // King's Square: a ring of trees inside the Ring Road
  for (let k = 0; k < 18; k++) {
    const a = (k / 18) * Math.PI * 2 + 0.1;
    addTree(500 + Math.cos(a) * 41, 500 + Math.sin(a) * 41, R(3, 3.8), k % 3 === 0, true);
  }
  // campus lawns
  for (let n = 0; n < 160; n++) {
    const x = R(462, 540);
    const y = R(86, 168);
    if (inPoly(x, y, CAMPUS) && dist(x, y, 514, 140) > 14) addTree(x, y, R(2.8, 4.2), rand() < 0.25);
  }
  // river banks: gallery forest along the Ikpoba
  for (let s = 0; s < river.length; s += 3) {
    const p = at(river, s);
    for (const side of [1, -1]) {
      if (rand() < 0.7) continue;
      const off = R(9, 24);
      const x = p.x - Math.sin(p.a) * side * off;
      const y = p.y + Math.cos(p.a) * side * off;
      addTree(x, y, R(3, 5), rand() < 0.12);
    }
  }
  // the sacred grove by the shrine
  for (let n = 0; n < 40; n++) {
    const a = rand() * Math.PI * 2;
    const rr = Math.sqrt(rand()) * GROVE.r;
    addTree(GROVE.x + Math.cos(a) * rr, GROVE.y + Math.sin(a) * rr, R(3.5, 5), false, rr > 6);
  }
  // palace compound trees
  for (const [x, y] of [[392, 492], [420, 486], [390, 515], [421, 520]] as const) addTree(x, y, 3.2, true, true);
  // outskirts bush + scattered compound trees and palms
  for (let n = 0; n < 2600; n++) {
    const x = R(-90, 1090);
    const y = R(-90, 1090);
    const u = urban(x, y);
    const farm = inPoly(x, y, FARMLAND);
    if (farm && rand() < 0.85) continue;
    if (rand() > 0.12 + (1 - u) * 0.75) continue;
    addTree(x, y, R(3, 6) * (u < 0.3 ? 1.15 : 0.85), rand() < (u > 0.4 ? 0.3 : 0.14));
  }

  /* ---------- vehicles ---------- */
  const vehicles: Vehicle[] = [];
  const carColors = ['#f4f4f2', '#c8ccd0', '#2d3a4a', '#9b1d20', '#1f4f8f', '#3a3a3a', '#d9d2c2', '#6c7a3a'];
  const roadIdx = (id: string) => roads.findIndex((r) => r.id === id);
  // free traffic on the express and main roads
  roads.forEach((rd, i) => {
    if (rd.kind !== 'express' && rd.kind !== 'main' && rd.kind !== 'ring') return;
    if (rd.id === 'ramat') return;
    const n = Math.round(rd.sp.length / (rd.kind === 'express' ? 34 : 48));
    for (let k = 0; k < n; k++) {
      const kind = rand() < 0.22 ? 'bus' : rand() < 0.25 ? 'keke' : 'car';
      vehicles.push({
        road: i,
        s: R(0, rd.sp.length),
        lane: rand() < 0.5 ? 1 : -1,
        speed: R(9, 15) * (kind === 'keke' ? 0.7 : 1),
        kind,
        color: kind === 'bus' ? '#f2c230' : kind === 'keke' ? (rand() < 0.5 ? '#f2c230' : '#2e9d58') : pick(carColors),
        s0: 0,
        s1: rd.sp.length,
        jam: false,
      });
    }
  });
  // the Ramat Park go-slow: bumper-to-bumper queues on every approach
  const jam = (id: string, fromEnd: boolean, len: number) => {
    const i = roadIdx(id);
    if (i < 0) return;
    const L = roads[i].sp.length;
    const s0 = fromEnd ? L - len : 0;
    const s1 = fromEnd ? L : len;
    for (const lane of [1, -1])
      for (let s = s0 + R(0, 3); s < s1 - 2; s += R(6.2, 8)) {
        const kind = rand() < 0.3 ? 'bus' : rand() < 0.2 ? 'keke' : 'car';
        vehicles.push({
          road: i,
          s,
          lane,
          speed: R(0.8, 1.6),
          kind,
          color: kind === 'bus' ? '#f2c230' : kind === 'keke' ? '#f2c230' : pick(carColors),
          s0,
          s1,
          jam: true,
        });
      }
  };
  jam('akpakpava', true, 70);
  jam('auchi', false, 80);
  jam('agbor', false, 70);
  // parked danfos in the motor parks
  for (const [px, py, pr] of PADS) {
    const n = Math.round(pr * 0.7);
    for (let k = 0; k < n; k++) {
      const row = k % 2;
      const col = Math.floor(k / 2);
      vehicles.push({
        road: 0, s: 0, lane: 0, speed: 0, kind: 'bus', color: rand() < 0.75 ? '#f2c230' : '#f4f4f2', s0: 0, s1: 0, jam: false,
        px: px - pr * 0.55 + col * 4.4, py: py - 3 + row * 6.5, pa: Math.PI / 2,
      });
    }
  }

  /* ---------- street lamps ---------- */
  const lamps: [number, number][] = [];
  for (const rd of roads) {
    if (rd.kind === 'dirt' || rd.kind === 'spur' || rd.kind === 'minor') continue;
    const step = rd.kind === 'ring' ? 14 : 26;
    let side = 1;
    for (let s = 4; s < rd.sp.length; s += step) {
      const p = at(rd.sp, s);
      if (p.x < -10 || p.x > 1010 || p.y < -10 || p.y > 1010) continue;
      if (rd.kind !== 'ring' && urban(p.x, p.y) < 0.3) continue;
      const off = rd.hw + 1.5;
      lamps.push([p.x - Math.sin(p.a) * side * off, p.y + Math.cos(p.a) * side * off]);
      side = -side;
    }
  }

  return { roads, river, buildings, trees, vehicles, lamps, urban, riverDist, ms: Math.round(performance.now() - t0) };
}
