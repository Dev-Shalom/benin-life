// P1-MAP — procedural city generator. Everything is merged into a few big <path>
// strings per colour so the whole illustrated city stays at a few hundred DOM nodes.
import {
  AIRPORT, CAMPUS, CORES, FARMLAND, GRA_ZONE, KINGS_SQUARE, MARKETS, PALACE, POLICE, RAMAT, RING, RIVER,
  ROAD_HW, ROADS, RUNWAY, UBTH, PathBuf, at, circleD, inPoly, labelPath, rng, spline,
  type Pt, type RoadKind, type Spline,
} from './mapGeo';

export type RoofBucket = 'rust' | 'zinc' | 'red' | 'teal' | 'white' | 'thatch';
export const ROOF_BUCKETS: RoofBucket[] = ['rust', 'zinc', 'red', 'teal', 'white', 'thatch'];

export interface RoadOut {
  id: string;
  kind: RoadKind;
  d: string;
  hw: number;
}

export interface Vehicle {
  x: number;
  y: number;
  a: number; // degrees
  kind: 'car' | 'bus' | 'keke' | 'danfo';
  color: string;
}

export interface MapModel {
  roads: RoadOut[];
  spurs: string; // merged minor side-streets
  roadLabels: { id: string; d: string; text: string }[];
  river: Spline;
  /** walled compound yards (filled + stroked) */
  compound: string;
  /** every roof face of every building: drawn offset as the drop shadow and as corrugation */
  roofAll: string;
  roofs: Record<RoofBucket, [string, string, string]>; // light, mid, dark faces
  ridges: string;
  trees: { shadow: string; base: [string, string, string]; hi: [string, string, string] };
  bush: { shadow: string; base: string; mid: string; hi: string };
  grass: [string, string];
  palms: { shadow: string; frond: string; frondHi: string };
  stalls: [string, string, string, string, string]; // coloured awnings
  stallShade: string;
  vehicles: Vehicle[];
  lampPts: [number, number][];
  windowPts: [number, number][];
  stats: Record<string, number>;
}

/* ---------- spatial index ----------
 * Flat bucket grid over plain number arrays: queries are allocation-free index loops
 * (the generator runs ~40k of them on first paint, so this matters on low-end phones). */
class Idx {
  readonly xs: number[] = [];
  readonly ys: number[] = [];
  readonly as: number[] = [];
  readonly rs: number[] = [];
  private cells: number[][] = [];
  private cell: number;
  private dim: number;
  private maxR = 0;
  /** angle of the item found by the last minEdge() */
  qa = 0;
  constructor(cell: number) {
    this.cell = cell;
    this.dim = Math.ceil(1200 / cell);
  }
  private ci(v: number) {
    const c = Math.floor((v + 100) / this.cell);
    return c < 0 ? 0 : c >= this.dim ? this.dim - 1 : c;
  }
  add(x: number, y: number, a: number, r: number) {
    const i = this.xs.length;
    this.xs.push(x);
    this.ys.push(y);
    this.as.push(a);
    this.rs.push(r);
    if (r > this.maxR) this.maxR = r;
    const k = this.ci(y) * this.dim + this.ci(x);
    (this.cells[k] ??= []).push(i);
  }
  /** min over items of (distance - item radius), capped at lim; sets qa.
   *  Scans cells in rings outward from the query cell and stops once a ring can't beat
   *  the best so far, so queries next to a road (the common case) touch only a few cells. */
  minEdge(x: number, y: number, lim: number): number {
    let best = lim;
    let ang = 0;
    const { xs, ys, rs, as, cells, dim, cell, maxR } = this;
    const cx0 = this.ci(x);
    const cy0 = this.ci(y);
    const rings = Math.ceil((lim + maxR) / cell) + 1;
    for (let ring = 0; ring <= rings; ring++) {
      if ((ring - 1) * cell >= best + maxR) break;
      const ylo = cy0 - ring;
      const yhi = cy0 + ring;
      for (let cy = ylo; cy <= yhi; cy++) {
        if (cy < 0 || cy >= dim) continue;
        const edgeRow = cy === ylo || cy === yhi;
        const step = edgeRow ? 1 : 2 * ring;
        for (let cx = cx0 - ring; cx <= cx0 + ring; cx += step || 1) {
          if (cx < 0 || cx >= dim) continue;
          const arr = cells[cy * dim + cx];
          if (arr === undefined) continue;
          for (let k = 0; k < arr.length; k++) {
            const i = arr[k];
            const dx = xs[i] - x;
            const dy = ys[i] - y;
            const lim2 = best + rs[i];
            const d2 = dx * dx + dy * dy;
            if (d2 >= lim2 * lim2) continue;
            const e = Math.sqrt(d2) - rs[i];
            if (e < best) {
              best = e;
              ang = as[i];
            }
          }
        }
      }
    }
    this.qa = ang;
    return best;
  }
  /** true if any item i has distance < (r_i * f + rad * g). */
  hit(x: number, y: number, rad: number, f: number, g: number): boolean {
    const reach = this.maxR * f + rad * g;
    const x0 = this.ci(x - reach), x1 = this.ci(x + reach), y0 = this.ci(y - reach), y1 = this.ci(y + reach);
    const { xs, ys, rs, cells, dim } = this;
    for (let cy = y0; cy <= y1; cy++)
      for (let cx = x0; cx <= x1; cx++) {
        const arr = cells[cy * dim + cx];
        if (arr === undefined) continue;
        for (let k = 0; k < arr.length; k++) {
          const i = arr[k];
          const dx = xs[i] - x;
          const dy = ys[i] - y;
          const t = rs[i] * f + rad * g;
          if (dx * dx + dy * dy < t * t) return true;
        }
      }
    return false;
  }
}

let cached: MapModel | null = null;

/** Math.hypot is very slow in V8; this is the hot path of the generator. */
const dist = (ax: number, ay: number, bx: number, by: number) => {
  const dx = ax - bx;
  const dy = ay - by;
  return Math.sqrt(dx * dx + dy * dy);
};

export function getMapModel(): MapModel {
  if (!cached) cached = build();
  return cached;
}

/** Urban density is smooth, so sample it once on a coarse lattice and interpolate
 *  bilinearly: the generator asks for it ~25k times. */
const UG = 20;
const UN = 1000 / UG + 1;
let uGrid: Float32Array | null = null;
function urbanGrid(): Float32Array {
  const g = new Float32Array(UN * UN).fill(1);
  for (const [cx, cy, r, w] of CORES) {
    const k = 1 / (r * r * 1.38);
    const reach = Math.sqrt(8 / k);
    const i0 = Math.max(0, Math.floor((cx - reach) / UG));
    const i1 = Math.min(UN - 1, Math.ceil((cx + reach) / UG));
    const j0 = Math.max(0, Math.floor((cy - reach) / UG));
    const j1 = Math.min(UN - 1, Math.ceil((cy + reach) / UG));
    for (let j = j0; j <= j1; j++) {
      const dy = j * UG - cy;
      for (let i = i0; i <= i1; i++) {
        const dx = i * UG - cx;
        const d2 = (dx * dx + dy * dy) * k;
        if (d2 < 8) g[j * UN + i] *= 1 - w * Math.exp(-d2);
      }
    }
  }
  for (let i = 0; i < g.length; i++) g[i] = 1 - g[i];
  return g;
}
function urban(x: number, y: number): number {
  const g = (uGrid ??= urbanGrid());
  let fx = x / UG;
  let fy = y / UG;
  fx = fx < 0 ? 0 : fx > UN - 1.001 ? UN - 1.001 : fx;
  fy = fy < 0 ? 0 : fy > UN - 1.001 ? UN - 1.001 : fy;
  const i = fx | 0;
  const j = fy | 0;
  const tx = fx - i;
  const ty = fy - j;
  const k = j * UN + i;
  const a = g[k] + (g[k + 1] - g[k]) * tx;
  const b = g[k + UN] + (g[k + UN + 1] - g[k + UN]) * tx;
  return a + (b - a) * ty;
}

const str3 = (b: PathBuf[]): [string, string, string] => [b[0].toString(), b[1].toString(), b[2].toString()];

function build(): MapModel {
  const T: Record<string, number> = {};
  let tLast = performance.now();
  const tick = (k: string) => {
    const now = performance.now();
    T['t_' + k] = Math.round(now - tLast);
    tLast = now;
  };
  const rand = rng(20261004);
  const R = (a: number, b: number) => a + (b - a) * rand();

  /* ---------- roads ---------- */
  const roadHash = new Idx(16);
  const roads: RoadOut[] = [];
  const roadLabels: MapModel['roadLabels'] = [];
  const splines = new Map<string, Spline>();

  const addSamples = (sp: Spline, hw: number) => {
    // walk the dense spline samples, keeping one every ~3.5 units (no per-point search)
    let next = 0;
    for (const p of sp.samples)
      if (p.s >= next) {
        roadHash.add(p.x, p.y, p.a, hw);
        next = p.s + 3.5;
      }
  };
  // Ring road
  for (let i = 0; i < 128; i++) {
    const a = (i / 128) * Math.PI * 2;
    roadHash.add(RING.x + Math.cos(a) * RING.r, RING.y + Math.sin(a) * RING.r, a + Math.PI / 2, RING.hw);
  }
  for (const rd of ROADS) {
    const sp = spline(rd.pts);
    splines.set(rd.id, sp);
    const hw = ROAD_HW[rd.kind];
    roads.push({ id: rd.id, kind: rd.kind, d: sp.d, hw });
    addSamples(sp, hw);
    for (const [text, pos] of rd.labels ?? []) {
      const half = text.length * 3.4 + 6;
      const c = sp.length * pos;
      roadLabels.push({ id: `${rd.id}-${pos}`, text, d: labelPath(sp, Math.max(0, c - half), Math.min(sp.length, c + half)) });
    }
  }

  const river = spline(RIVER);
  const riverHash = new Idx(30);
  for (let s = 0; s <= river.length; s += 4) {
    const p = at(river, s);
    riverHash.add(p.x, p.y, p.a, 0);
  }
  // x-extent of the river per 10-unit band of y: lets most queries bail out in O(1)
  const rMin = new Float32Array(110).fill(1e9);
  const rMax = new Float32Array(110).fill(-1e9);
  for (const p of river.samples) {
    const b = Math.max(0, Math.min(109, Math.floor((p.y + 50) / 10)));
    rMin[b] = Math.min(rMin[b], p.x);
    rMax[b] = Math.max(rMax[b], p.x);
  }
  const riverDist = (x: number, y: number, lim = 60) => {
    let best = lim;
    let lo = 1e9;
    let hi = -1e9;
    const b0 = Math.max(0, Math.floor((y - lim + 50) / 10));
    const b1 = Math.min(109, Math.floor((y + lim + 50) / 10));
    for (let b = b0; b <= b1; b++) {
      if (rMin[b] < lo) lo = rMin[b];
      if (rMax[b] > hi) hi = rMax[b];
    }
    if (x < lo - lim || x > hi + lim) return lim;
    return riverHash.minEdge(x, y, best);
  };
  /** clearance from the nearest road edge; the angle of that road is left in roadHash.qa. */
  const roadClear = (x: number, y: number, lim = 40) => roadHash.minEdge(x, y, lim);

  const inRunway = (x: number, y: number, pad: number) => {
    const { x1, y1, x2, y2, w } = RUNWAY;
    const dx = x2 - x1;
    const dy = y2 - y1;
    const L2 = dx * dx + dy * dy;
    const t = Math.max(0, Math.min(1, ((x - x1) * dx + (y - y1) * dy) / L2));
    return dist(x, y, x1 + t * dx, y1 + t * dy) < w / 2 + pad;
  };

  const special = (x: number, y: number) => {
    if (dist(x, y, KINGS_SQUARE.x, KINGS_SQUARE.y) < RING.r + RING.hw + 4 || dist(x, y, RAMAT.x, RAMAT.y) < 30) return true;
    for (const [mx, my, mr] of MARKETS) if (dist(x, y, mx, my) < mr + 3) return true;
    return inPoly(x, y, CAMPUS) || inPoly(x, y, AIRPORT) || inPoly(x, y, PALACE) || inPoly(x, y, UBTH) ||
      inPoly(x, y, POLICE) || inPoly(x, y, FARMLAND);
  };

  tick('roads');
  /* ---------- fishbone side streets ---------- */
  let spurs = '';
  const spurSplines: Spline[] = [];
  for (const rd of ROADS) {
    if (!rd.spurs) continue;
    const sp = splines.get(rd.id)!;
    const hw = ROAD_HW[rd.kind];
    let s = R(18, 36);
    let side = rand() < 0.5 ? 1 : -1;
    while (s < sp.length - 10) {
      const p = at(sp, s);
      const u = urban(p.x, p.y);
      if (p.x > 5 && p.x < 995 && p.y > 5 && p.y < 995 && rand() < 0.25 + u * 0.9) {
        const nx = -Math.sin(p.a) * side;
        const ny = Math.cos(p.a) * side;
        const len = R(28, 80) * (0.6 + u * 0.6);
        const bend = R(-0.35, 0.35);
        const pts: Pt[] = [[p.x + nx * (hw - 1), p.y + ny * (hw - 1)]];
        let ok = true;
        for (let d = 10; d <= len; d += 10) {
          const ang = Math.atan2(ny, nx) + bend * (d / len);
          const x = p.x + Math.cos(ang) * (d + hw);
          const y = p.y + Math.sin(ang) * (d + hw);
          if (d > 12) {
            if (roadClear(x, y, 16) < 4) break;
          }
          if (x < 4 || x > 996 || y < 4 || y > 996 || riverDist(x, y, 30) < 24 || special(x, y)) {
            ok = pts.length > 2;
            break;
          }
          pts.push([x, y]);
        }
        if (ok && pts.length >= 3) {
          const ssp = spline(pts);
          spurSplines.push(ssp);
          spurs += ssp.d;
        }
      }
      side = rand() < 0.7 ? -side : side;
      s += R(30, 56);
    }
  }
  for (const ssp of spurSplines) addSamples(ssp, ROAD_HW.minor - 0.6);

  tick('spurs');
  /* ---------- buildings ---------- */
  const bHash = new Idx(20);
  const yards = new PathBuf(4096);
  const ridges = new PathBuf(16384);
  const roofBufs = Object.fromEntries(ROOF_BUCKETS.map((b) => [b, [new PathBuf(), new PathBuf(), new PathBuf()]])) as Record<RoofBucket, [PathBuf, PathBuf, PathBuf]>;
  const windowPts: [number, number][] = [];
  let nB = 0;

  const LX = -0.62;
  const LY = -0.78; // light comes from the north-west
  const shade = (nx: number, ny: number) => {
    const v = nx * LX + ny * LY;
    return v > 0.35 ? 0 : v > -0.35 ? 1 : 2;
  };
  // scratch buffer for face corners (no per-building array allocation)
  const Q = new Float64Array(8);
  let qc = 0;
  let bc = 1;
  let bs = 0;
  let bx = 0;
  let by = 0;
  /** push the local point (lx, ly) of the current building into the scratch face */
  const q = (lx: number, ly: number) => {
    Q[qc++] = bx + lx * bc - ly * bs;
    Q[qc++] = by + lx * bs + ly * bc;
  };
  const face = (buf: PathBuf) => {
    buf.poly(Q, qc / 2);
    qc = 0;
  };

  const pickBucket = (x: number, y: number): RoofBucket => {
    const v = rand();
    const u = urban(x, y);
    if (u < 0.3 && v < 0.12) return 'thatch';
    if (v < 0.36) return 'rust';
    if (v < 0.66) return 'zinc';
    if (v < 0.8) return 'red';
    if (v < 0.9) return 'teal';
    return 'white';
  };

  const drawBuilding = (cx: number, cy: number, a: number, w: number, d: number, bucket: RoofBucket, withYard: boolean) => {
    const c = Math.cos(a);
    const s = Math.sin(a);
    bx = cx;
    by = cy;
    bc = c;
    bs = s;
    qc = 0;
    const hw = w / 2;
    const hd = d / 2;
    if (withYard) {
      const m = 3.2;
      q(-hw - m, -hd - m); q(hw + m, -hd - m); q(hw + m, hd + m + 1.5); q(-hw - m, hd + m + 1.5);
      face(yards);
    }
    const set = roofBufs[bucket];
    if (w / d > 1.25) {
      // gable: ridge along the long axis
      const top = shade(s, -c);
      q(-hw, -hd); q(hw, -hd); q(hw, 0); q(-hw, 0);
      face(set[top]);
      q(-hw, 0); q(hw, 0); q(hw, hd); q(-hw, hd);
      face(set[2 - top]);
      ridges.cxy(77, cx - hw * c, cy - hw * s).cxy(76, cx + hw * c, cy + hw * s);
    } else {
      // hip roof: 4 faces meeting at a short ridge
      const k = Math.max(0, hw - hd);
      q(-hw, -hd); q(hw, -hd); q(k, 0); q(-k, 0);
      face(set[shade(s, -c)]);
      q(hw, -hd); q(hw, hd); q(k, 0);
      face(set[shade(c, s)]);
      q(hw, hd); q(-hw, hd); q(-k, 0); q(k, 0);
      face(set[shade(-s, c)]);
      q(-hw, hd); q(-hw, -hd); q(-k, 0);
      face(set[shade(-c, -s)]);
    }
    bHash.add(cx, cy, 0, Math.sqrt(w * w + d * d) / 2 + (withYard ? 3 : 0));
    if (rand() < 0.5) windowPts.push([cx + R(-hw, hw) * 0.6 * c, cy + R(-hw, hw) * 0.6 * s]);
    nB++;
  };

  /** Cheapest rejection first: most candidates in built-up areas collide with a neighbour.
   *  `clear` = road clearance if the caller already measured it (≥ rad + 6), else -1. */
  const tryPlace = (cx: number, cy: number, a: number, w: number, d: number, compound = false, bucket: RoofBucket | null = null, force = false, clear = -1) => {
    if (cx < 6 || cx > 994 || cy < 6 || cy > 994) return false;
    const rad = Math.sqrt(w * w + d * d) / 2 + (compound ? 3 : 0);
    if (bHash.hit(cx, cy, rad, 0.86, 0.86)) return false;
    if (!force) {
      if ((clear < 0 ? roadClear(cx, cy, rad + 6) : clear) < rad * 0.82 + 1.2) return false;
      if (special(cx, cy)) return false;
      if (riverDist(cx, cy, 40) < 26) return false;
    }
    drawBuilding(cx, cy, a, w, d, bucket ?? pickBucket(cx, cy), compound);
    return true;
  };

  const inGRA = (x: number, y: number) => dist(x, y, GRA_ZONE.x, GRA_ZONE.y) < GRA_ZONE.r;

  // Landmark complexes (forced placement inside their zones)
  const complex = (polyPts: readonly Pt[], n: number, wmin: number, wmax: number, buckets: RoofBucket[], ang: number) => {
    let tries = 0;
    let placed = 0;
    const xs = polyPts.map((p) => p[0]);
    const ys = polyPts.map((p) => p[1]);
    while (placed < n && tries++ < n * 30) {
      const x = R(Math.min(...xs), Math.max(...xs));
      const y = R(Math.min(...ys), Math.max(...ys));
      if (!inPoly(x, y, polyPts)) continue;
      const w = R(wmin, wmax);
      const dd = R(wmin * 0.55, wmax * 0.6);
      if (roadClear(x, y, 20) < Math.sqrt(w * w + dd * dd) / 2) continue;
      if (tryPlace(x, y, ang + (rand() < 0.3 ? Math.PI / 2 : 0), w, dd, false, buckets[Math.floor(rand() * buckets.length)], true)) placed++;
    }
  };
  complex(CAMPUS, 16, 9, 17, ['white', 'teal', 'white', 'red'], -0.1);
  complex(UBTH, 9, 9, 16, ['white', 'white', 'teal'], 0.3);
  complex(POLICE, 3, 8, 11, ['teal', 'white'], 0);

  tick('complexes');
  // Frontage along roads
  const frontage = (sp: Spline, hw: number, density: number) => {
    let s = R(2, 8);
    while (s < sp.length) {
      const p = at(sp, s);
      for (const side of [-1, 1]) {
        const g = inGRA(p.x, p.y);
        const u = urban(p.x, p.y);
        if (rand() > u * density * (g ? 0.55 : 1.15)) continue;
        const w = R(6, 11) * (g ? 1.6 : 1);
        const d = R(5, 8.5) * (g ? 1.5 : 1);
        const off = hw + 2.2 + d / 2 + (g ? 4 : 0);
        const nx = -Math.sin(p.a) * side;
        const ny = Math.cos(p.a) * side;
        tryPlace(p.x + nx * off, p.y + ny * off, p.a, w, d, g || rand() < 0.12);
      }
      s += R(8.5, 12.5);
    }
  };
  for (const rd of ROADS) frontage(splines.get(rd.id)!, ROAD_HW[rd.kind], rd.kind === 'dirt' ? 0.5 : 1);
  for (const ssp of spurSplines) frontage(ssp, ROAD_HW.minor - 0.6, 1);
  // Ring road frontage
  for (let i = 0; i < 64; i++) {
    const a = (i / 64) * Math.PI * 2;
    const off = RING.r + RING.hw + 7;
    tryPlace(RING.x + Math.cos(a) * off, RING.y + Math.sin(a) * off, a + Math.PI / 2, R(8, 12), R(6, 8));
  }
  tick('frontage');
  // Interior infill
  for (let gy = 6; gy < 1000; gy += 10.5)
    for (let gx = 6; gx < 1000; gx += 10.5) {
      const x = gx + R(-4, 4);
      const y = gy + R(-4, 4);
      const g = inGRA(x, y);
      const u = urban(x, y);
      if (rand() > Math.pow(u, 1.25) * (g ? 0.35 : 1)) continue;
      const w = R(6, 11) * (g ? 1.6 : 1);
      const d = R(5, 8) * (g ? 1.5 : 1);
      const compound = g || rand() < 0.18 * (1 - u) + 0.05;
      const rad = Math.sqrt(w * w + d * d) / 2 + (compound ? 3 : 0);
      if (bHash.hit(x, y, rad, 0.86, 0.86)) continue;
      const rc = roadClear(x, y, 34);
      const a = rc < 33 ? roadHash.qa + (rand() < 0.15 ? Math.PI / 2 : 0) : Math.atan2(y - 500, x - 500) + Math.PI / 2;
      tryPlace(x, y, a, w, d, compound, null, false, rc);
    }

  tick('infill');
  /* ---------- vegetation ---------- */
  const treeShadow = new PathBuf(16384);
  const treeBase = [new PathBuf(), new PathBuf(), new PathBuf()];
  const treeHi = [new PathBuf(), new PathBuf(), new PathBuf()];
  const bushShadow = new PathBuf(32768);
  const bushBase = new PathBuf(32768);
  const bushMid = new PathBuf(16384);
  const bushHi = new PathBuf(32768);
  const palmShadow = new PathBuf();
  const palmFrond = new PathBuf(65536);
  const palmHi = new PathBuf(16384);
  let nT = 0;
  let nBush = 0;
  let nPalm = 0;

  const clearOfBuildings = (x: number, y: number, r: number) => {
    return !bHash.hit(x, y, r, 1, 0.6);
  };

  const tree = (x: number, y: number, r: number) => {
    const v = Math.floor(rand() * 3) as 0 | 1 | 2;
    treeShadow.circle(x + r * 0.45, y + r * 0.55, r);
    treeBase[v].circle(x, y, r);
    treeHi[v].circle(x - r * 0.3, y - r * 0.32, r * 0.52);
    nT++;
  };
  const palm = (x: number, y: number, r: number) => {
    const n = 7;
    const rot = R(0, Math.PI * 2);
    palmShadow.circle(x + r * 0.5, y + r * 0.6, r * 0.75);
    for (let i = 0; i < n; i++) {
      const a = rot + (i / n) * Math.PI * 2;
      const tx = x + Math.cos(a) * r;
      const ty = y + Math.sin(a) * r;
      const px = -Math.sin(a) * r * 0.22;
      const py = Math.cos(a) * r * 0.22;
      const mx = x + Math.cos(a) * r * 0.5;
      const my = y + Math.sin(a) * r * 0.5;
      // relative quadratic leaf: out along one edge, back along the other
      palmFrond.cxy(77, x, y).cxy(113, mx + px - x, my + py - y).ch(32).xy(tx - x, ty - y)
        .cxy(113, mx - px * 0.3 - tx, my - py * 0.3 - ty).ch(32).xy(x - tx, y - ty).ch(122);
      if (i % 2 === 0) palmHi.cxy(77, x, y).cxy(108, mx + px * 0.4 - x, my + py * 0.4 - y);
    }
    nPalm++;
  };
  const bush = (x: number, y: number, r: number) => {
    bushShadow.circle(x + r * 0.35, y + r * 0.45, r);
    bushBase.circle(x, y, r);
    if (rand() < 0.6) bushMid.circle(x - r * 0.2, y - r * 0.25, r * 0.7);
    bushHi.circle(x - r * 0.38, y - r * 0.4, r * 0.34);
    nBush++;
  };

  // Grass / savanna patches under everything on the outskirts
  const grass: [string, string] = ['', ''];
  for (let gy = 10; gy < 1000; gy += 30)
    for (let gx = 10; gx < 1000; gx += 30) {
      const x = gx + R(-12, 12);
      const y = gy + R(-12, 12);
      const u = urban(x, y);
      if (u > 0.5 || rand() > 0.75 - u) continue;
      if (inPoly(x, y, FARMLAND) || inPoly(x, y, AIRPORT)) continue;
      grass[rand() < 0.5 ? 0 : 1] += circleD(x, y, R(12, 26));
    }

  tick('grass');
  // Bush / forest masses on the rural fringe
  for (let gy = 5; gy < 1000; gy += 19)
    for (let gx = 5; gx < 1000; gx += 19) {
      const x = gx + R(-7.5, 7.5);
      const y = gy + R(-7.5, 7.5);
      const u = urban(x, y);
      if (u > 0.2 || rand() > (0.2 - u) * 3.4) continue;
      if (inPoly(x, y, FARMLAND) || inPoly(x, y, AIRPORT) || inPoly(x, y, CAMPUS)) continue;
      const r = R(8.5, 15.5);
      if (roadClear(x, y, 30) < r * 0.75 + 2) continue;
      if (riverDist(x, y, 30) < 15) continue;
      if (!clearOfBuildings(x, y, r)) continue;
      bush(x, y, r);
    }

  tick('bush');
  // Individual trees
  // 12-unit lattice; densities below are scaled ×1.44 to match the old 10-unit look
  for (let gy = 4; gy < 1000; gy += 12)
    for (let gx = 4; gx < 1000; gx += 12) {
      const x = gx + R(-5, 5);
      const y = gy + R(-5, 5);
      const u = urban(x, y);
      const rd = riverDist(x, y, 50);
      let g = (1 - u) * 0.12 + (u > 0.3 ? 0.06 : 0);
      if (inGRA(x, y)) g += 0.5;
      if (rd < 46) g += 0.45;
      if (inPoly(x, y, CAMPUS) || inPoly(x, y, UBTH)) g += 0.32;
      if (dist(x, y, 680, 660) < 22) g += 0.8; // sacred grove at the shrine
      if (rand() > g * 1.44 || rd < 13) continue;
      if (inPoly(x, y, FARMLAND) || inRunway(x, y, 10) || inPoly(x, y, PALACE)) continue;
      const r = R(3.2, 6.2) * (inGRA(x, y) ? 1.15 : 1);
      if (!clearOfBuildings(x, y, r)) continue;
      if (roadClear(x, y, 20) < r * 0.6 + 0.8) continue;
      if (special(x, y) && !inPoly(x, y, CAMPUS) && !inPoly(x, y, UBTH) && !inPoly(x, y, AIRPORT)) continue;
      if (inPoly(x, y, AIRPORT) && rand() < 0.85) continue;
      if (rand() < (rd < 46 ? 0.25 : 0.12)) palm(x, y, r * 1.25);
      else tree(x, y, r);
    }

  tick('trees');
  // Oil palms in Iguobazuwa farmland (field edges)
  for (let i = 0; i < 260; i++) {
    const x = R(0, 160);
    const y = R(595, 1000);
    if (!inPoly(x, y, FARMLAND)) continue;
    const edge = Math.abs(((y - 600) % 70) - 35) > 29 || Math.abs((x % 48) - 24) > 20;
    if (!edge && rand() < 0.8) continue;
    if (roadClear(x, y, 14) < 5) continue;
    palm(x, y, R(5, 7.5));
  }

  tick('farmPalms');
  /* ---------- market stalls ---------- */
  const stalls = [new PathBuf(), new PathBuf(), new PathBuf(), new PathBuf(), new PathBuf()];
  const stallShade = new PathBuf();
  for (const [mx, my, mr] of MARKETS) {
    roadClear(mx, my, 60);
    const ang = roadHash.qa;
    const c = Math.cos(ang);
    const s = Math.sin(ang);
    for (let gx = -mr; gx <= mr; gx += 5.4)
      for (let gy = -mr; gy <= mr; gy += 5.4) {
        if (Math.hypot(gx, gy) > mr) continue;
        if (Math.abs(gy) < 1.5 || Math.abs(gx) < 1.4) continue; // aisles
        const x = mx + gx * c - gy * s;
        const y = my + gx * s + gy * c;
        if (roadClear(x, y, 12) < 2.5) continue;
        const k = Math.floor(rand() * 5);
        const h = 2.1;
        bx = x;
        by = y;
        bc = c;
        bs = s;
        qc = 0;
        q(-h, -h); q(h, -h); q(h, h); q(-h, h);
        face(stalls[k]);
        q(-h, 0); q(h, 0); q(h, h); q(-h, h);
        face(stallShade);
      }
  }

  /* ---------- vehicles ---------- */
  const vehicles: Vehicle[] = [];
  const carColors = ['#e9e4dc', '#c8312a', '#2f4f8f', '#1d1d2b', '#d9a441', '#7b8794', '#f1f1f1'];
  const putOn = (id: string, from: number, to: number, n: number, jam: boolean) => {
    const sp = splines.get(id)!;
    const hw = ROAD_HW[roads.find((r) => r.id === id)!.kind];
    for (let i = 0; i < n; i++) {
      const s = jam ? from + ((to - from) * i) / n + R(-1.5, 1.5) : R(from, to);
      const p = at(sp, Math.max(0, Math.min(sp.length, s)));
      const lane = rand() < 0.5 ? -1 : 1;
      const v = rand();
      const kind: Vehicle['kind'] = v < 0.16 ? 'bus' : v < 0.3 ? 'danfo' : v < 0.38 && id !== 'auchi' ? 'keke' : 'car';
      const color = kind === 'bus' ? '#1f7a3f' : kind === 'danfo' || kind === 'keke' ? '#f2c230' : carColors[Math.floor(rand() * carColors.length)];
      vehicles.push({
        x: p.x - Math.sin(p.a) * lane * hw * 0.48,
        y: p.y + Math.cos(p.a) * lane * hw * 0.48,
        a: ((p.a * 180) / Math.PI) + (lane < 0 ? 180 : 0),
        kind,
        color,
      });
    }
  };
  // Ramat Park go-slow: queues on every approach
  putOn('akpakpava', splines.get('akpakpava')!.length - 70, splines.get('akpakpava')!.length - 14, 7, true);
  putOn('auchi', 14, 80, 7, true);
  putOn('agbor', 14, 66, 6, true);
  // light traffic elsewhere
  putOn('sapele', 30, 400, 5, false);
  putOn('ugbowo', 30, 420, 6, false);
  putOn('airport', 20, 200, 2, false);
  putOn('siluko', 30, 300, 2, false);
  putOn('sakponba', 20, 260, 3, false);
  putOn('mission', 20, 200, 2, false);
  for (let i = 0; i < 8; i++) {
    const a = R(0, Math.PI * 2);
    const lane = rand() < 0.5 ? -4 : 4;
    vehicles.push({
      x: RING.x + Math.cos(a) * (RING.r + lane),
      y: RING.y + Math.sin(a) * (RING.r + lane),
      a: (a * 180) / Math.PI + (lane > 0 ? 90 : -90),
      kind: rand() < 0.2 ? 'bus' : 'car',
      color: carColors[Math.floor(rand() * carColors.length)],
    });
  }

  /* ---------- night street lamps along paved roads ---------- */
  const lampPts: [number, number][] = [];
  for (const rd of roads) {
    if (rd.kind === 'dirt' || rd.kind === 'minor') continue;
    const sp = splines.get(rd.id)!;
    let side = 1;
    for (let s = 6; s < sp.length; s += 26) {
      const p = at(sp, s);
      if (p.x < 0 || p.x > 1000 || p.y < 0 || p.y > 1000) continue;
      if (urban(p.x, p.y) < 0.25) continue;
      const off = rd.hw + 1.5;
      lampPts.push([p.x - Math.sin(p.a) * off * side, p.y + Math.cos(p.a) * off * side]);
      side = -side;
    }
  }
  for (let i = 0; i < 20; i++) {
    const a = (i / 20) * Math.PI * 2;
    lampPts.push([RING.x + Math.cos(a) * (RING.r + RING.hw + 1.5), RING.y + Math.sin(a) * (RING.r + RING.hw + 1.5)]);
  }

  const roofs = Object.fromEntries(ROOF_BUCKETS.map((b) => [b, str3(roofBufs[b])])) as MapModel['roofs'];
  tick('rest');
  return {
    roads,
    spurs,
    roadLabels,
    river,
    compound: yards.toString(),
    roofAll: ROOF_BUCKETS.map((b) => roofs[b].join('')).join(''),
    roofs,
    ridges: ridges.toString(),
    trees: { shadow: treeShadow.toString(), base: str3(treeBase), hi: str3(treeHi) },
    bush: { shadow: bushShadow.toString(), base: bushBase.toString(), mid: bushMid.toString(), hi: bushHi.toString() },
    grass,
    palms: { shadow: palmShadow.toString(), frond: palmFrond.toString(), frondHi: palmHi.toString() },
    stalls: stalls.map(String) as MapModel['stalls'],
    stallShade: stallShade.toString(),
    vehicles,
    lampPts,
    windowPts: windowPts.filter((_, i) => i % 2 === 0 || urban(windowPts[i][0], windowPts[i][1]) > 0.6),
    stats: { ...T, buildings: nB, trees: nT, bush: nBush, palms: nPalm, spurs: spurSplines.length, lamps: lampPts.length, vehicles: vehicles.length },
  };
}
