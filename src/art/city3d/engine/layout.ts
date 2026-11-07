// R5: procedural layout of the 3D city in MAP space (pure numbers, no three.js).
// Roads, river, zones and density cores all come from the 2D map's data (src/art/map/mapGeo.ts),
// so every building, tree and car sits where the 2D map (and docs/MAP_GEO.md) says the city is.
import {
  AIRPORT, CAMPUS, CORES, FARMLAND, GRA_ZONE, GROVE, KINGS_SQUARE, MARKETS, PALACE, POLICE, RAMAT, RING, RIVER, TECH_HUB,
  ROAD_HW, ROADS, RUNWAY, UBTH, at, inPoly, rng, spline, type Pt, type RoadKind, type Spline,
} from '../../map/mapGeo';
import osmCore from '../data/benin-core-buildings.json';
import { PLACE_ANCHORS } from '../data/anchors';
import { BUS, MODEL_FOOTPRINTS, PAD_SEEDS, padLayout } from './footprints';
import { outline, PolyIndex, pointInPoly, polyBox as polyBoxOf, polysOverlap, rectCorners, segDist } from './geom';
import { RoadNet } from './roadnet';

type OSMCoreData = {
  bounds: readonly [number, number, number, number];
  features: { id: string; levels: number; heightM: number; ring: [number, number][] }[];
};
const OSM_CORE = osmCore as unknown as OSMCoreData;

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
  /** district style (S3: plot colour, palette) */
  st: Style;
}

/** OSM footprint with a game-scaled height and the existing district palette. */
export interface OSMBuilding {
  id: string;
  ring: Pt[];
  h: number;
  wall: string;
  roof: string;
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

/** A motor park after it has been moved to clear ground (map units). */
export interface Pad {
  x: number;
  y: number;
  r: number;
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
  osmBuildings: OSMBuilding[];
  trees: Tree[];
  vehicles: Vehicle[];
  lamps: [number, number][];
  /** motor parks (pads, shelters and parked danfos stand on these) */
  pads: Pad[];
  /** exact road clearance queries (carriageway / pavement), see roadnet.ts */
  net: RoadNet;
  /** every footprint (data: 0 landmark / motor park, 1 OSM, 2 generated house) */
  fp: PolyIndex<number>;
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

// S3: one coherent palette per district instead of random confetti. Repeats weight the picks:
// core = pale concrete walls under grey zinc and rust; res = warm walls, terracotta/brown roofs with the
// odd blue; cramped = rusty zinc; GRA = white villas with terracotta, green and slate roofs.
const WALLS: Record<Style, string[]> = {
  core: ['#f1ece2', '#e9e2d4', '#f3e7cf', '#e4e6e3', '#efe0c4', '#f2ede6', '#dfe3e0', '#f0d9b8'],
  res: ['#f1e6cf', '#ead7b6', '#f3ece0', '#efd8b5', '#e7dcc6', '#f2e3c9', '#e6e0cf', '#efd2b0'],
  cramped: ['#e3cba8', '#dcc09a', '#e9d8bd', '#d6c3a5', '#e6cdab'],
  gra: ['#fbf8f1', '#f6f2e9', '#f3f3ef', '#f8eedc'],
  campus: ['#efe4cc', '#f2ead9', '#e6dcc4'],
  market: ['#d8c3a0', '#e3d2b3'],
};
const ROOFS: Record<Style, string[]> = {
  core: ['#8f979c', '#9aa2a6', '#7e878c', '#a85a3c', '#9b5434', '#b5674a', '#8f979c', '#6f7b82', '#3f6f9c'],
  res: ['#b5583a', '#a24f33', '#8a4b2c', '#9c5a35', '#c0643f', '#8f979c', '#7a4a32', '#b5583a', '#3f6f9c', '#2f7466'],
  cramped: ['#8a4a2c', '#7b4328', '#96553a', '#6e3b25', '#8f969b', '#9a5f42'],
  gra: ['#b8432f', '#c25b3c', '#2f6f55', '#3d5f80', '#b8432f', '#5d6a72'],
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
    if (dist(x, y, GROVE.x, GROVE.y) < GROVE.r || dist(x, y, TECH_HUB.x, TECH_HUB.y) < TECH_HUB.r) return true;
    return inPoly(x, y, CAMPUS) || inPoly(x, y, AIRPORT) || inPoly(x, y, PALACE) || inPoly(x, y, UBTH) || inPoly(x, y, POLICE) || inPoly(x, y, FARMLAND) || inRunway(x, y, 8);
  };
  // motor parks stay clear of generated buildings (their spots are settled below, once the roads are known)
  const pads: Pad[] = [];
  const onPad = (x: number, y: number) => pads.some((q) => dist(x, y, q.x, q.y) < q.r);

  /* ---------- footprints that nothing may be built on: landmark models, then motor parks and placed buildings ---------- */
  const fp = new PolyIndex<number>(24);
  for (const m of MODEL_FOOTPRINTS) fp.add(m.poly, 0);
  const nearModel = (x: number, y: number, pad: number) => {
    for (const id of fp.query(x - pad, y - pad, x + pad, y + pad)) {
      const poly = fp.items[id].poly;
      if (pointInPoly(x, y, poly)) return true;
      for (let i = 0; i < poly.length; i++) {
        const a = poly[i];
        const b = poly[(i + 1) % poly.length];
        if (segDist(x, y, a[0], a[1], b[0], b[1]) < pad) return true;
      }
    }
    return false;
  };

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
        if (pts.length >= 3) {
          const sp2 = spline(pts);
          // a spur must not run into a landmark model either
          if (sp2.samples.some((q) => nearModel(q.x, q.y, 4))) continue;
          addRoad({ id: 'spur', kind: 'spur', sp: sp2, hw: 2.4, closed: false });
        }
      }
      s += R(22, 40) * (1.25 - u * 0.5);
      side = -side;
    }
  }

  /* ---------- exact road clearance + motor parks on clear ground ---------- */
  const net = new RoadNet(roads);
  // Pavement margin kept between any footprint and the paved edge (kerb strip included), map units.
  const MARGIN = 0.5;
  const onTarmac = (poly: readonly Pt[], margin = MARGIN) => {
    for (const [x, y] of outline(poly, 2.5)) if (net.clear(x, y, true, margin + 0.5) < margin) return true;
    return false;
  };
  // The seeded pad spots sit on junctions (the parked danfos and the shelter roof ended up on the carriageway).
  // Each park moves to the nearest clear ground, spiralling out in 3-unit steps.
  for (const [px, py, pr] of PAD_SEEDS) {
    let chosen: Pad | null = null;
    for (let rad = 0; rad <= 90 && !chosen; rad += 4) {
      const n = rad === 0 ? 1 : Math.ceil((rad * Math.PI * 2) / 5);
      for (let k = 0; k < n && !chosen; k++) {
        const a = (k / n) * Math.PI * 2;
        const cx = px + Math.cos(a) * rad;
        const cy = py + Math.sin(a) * rad;
        if (special(cx, cy) || riverDist(cx, cy, 30) < pr + 4) continue;
        const free = net.clear(cx, cy, true, 20);
        if (free < 2) continue; // centre on or beside the road
        const lay = padLayout(cx, cy, pr);
        if (free < 19 && lay.parts.some((q) => onTarmac(q, 1.2))) continue;
        if (lay.parts.some((q) => fp.query(...polyBoxOf(q)).some((id) => polysOverlap(q, fp.items[id].poly)))) continue;
        chosen = { x: cx, y: cy, r: pr };
      }
    }
    const q = chosen ?? { x: px, y: py, r: pr };
    pads.push(q);
    for (const part of padLayout(q.x, q.y, q.r).parts) fp.add(part, 0);
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
  /** is a place marker inside this footprint? (cheap distance test first) */
  const anchorIn = (poly: readonly Pt[], cx: number, cy: number, reach: number) => {
    for (const q of PLACE_ANCHORS) if (Math.abs(q[2] - cx) < reach && Math.abs(q[3] - cy) < reach && pointInPoly(q[2], q[3], poly)) return true;
    return false;
  };
  const buildings: Building[] = [];
  const osmBuildings: OSMBuilding[] = [];
  const occ = new Grid(14);
  const osmBounds = OSM_CORE.bounds;
  const inOsmCoverage = (x: number, y: number) => x >= osmBounds[0] && x <= osmBounds[2] && y >= osmBounds[1] && y <= osmBounds[3];
  for (const f of OSM_CORE.features) {
    const x = f.ring.reduce((sum, p) => sum + p[0], 0) / f.ring.length;
    const y = f.ring.reduce((sum, p) => sum + p[1], 0) / f.ring.length;
    // Keep the modeled landmark pads, King's Square and named roads clean.
    if (special(x, y) || onPad(x, y) || roadClear(x, y, 3) < 1.6) continue;
    let radius = 0;
    for (const p of f.ring) radius = Math.max(radius, dist(x, y, p[0], p[1]));
    if (radius < 0.45) continue;
    // exact footprint tests: not on the road or pavement, not on a landmark model, motor park or marker, not over
    // another footprint, and no corner inside a special zone (palace compound, campus, airport ...)
    {
      const [bx0, by0, bx1, by1] = polyBoxOf(f.ring);
      if (special(bx0, by0) || special(bx1, by0) || special(bx0, by1) || special(bx1, by1)) continue;
    }
    if (roadClear(x, y, 20) < radius + 4 && onTarmac(f.ring)) continue;
    if (fp.query(...polyBoxOf(f.ring)).some((id) => polysOverlap(f.ring, fp.items[id].poly))) continue;
    if (anchorIn(f.ring, x, y, radius + 1)) continue;
    fp.add(f.ring, 1);
    const st = styleAt(x, y, urban(x, y));
    const h = f.heightM > 0
      ? Math.max(0.22, Math.min(1.8, f.heightM * 0.075))
      : f.levels > 0
        ? Math.max(0.22, Math.min(1.8, f.levels * 0.22))
        : st === 'core' ? 0.46 : 0.38;
    osmBuildings.push({ id: f.id, ring: f.ring, h, wall: pick(WALLS[st]), roof: pick(ROOFS[st]) });
    occ.add(x, y, radius + 0.6);
  }
  const tryPlace = (x: number, y: number, a: number, st: Style, wMul = 1): boolean => {
    if (x < -40 || x > 1040 || y < -40 || y > 1040) return false;
    if (inOsmCoverage(x, y)) return false;
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
    // S3: test the footprint corners too, so no house pokes into the palace, square or markets
    if (st !== 'campus' && st !== 'market' && (special(x, y) || special(x + rad, y + rad) || special(x - rad, y - rad) || special(x + rad, y - rad) || special(x - rad, y + rad))) return false;
    if (onPad(x, y)) return false;
    const rc = roadClear(x, y, 30);
    if (rc < rad * 0.8) return false;
    if (riverDist(x, y, 40) < rad + 9) return false;
    if (occ.edge(x, y, 30) < rad * 0.92) return false;
    // exact footprint (roof overhang included): off the road and pavement, clear of every other footprint and of the markers
    const k = 1.1;
    const poly = rectCorners(x, y, w * k, d * k, a);
    if (rc < rad * 1.5 + 3 && onTarmac(poly)) return false;
    const grown = rectCorners(x, y, w * k + 0.8, d * k + 0.8, a);
    if (fp.query(...polyBoxOf(grown)).some((id) => polysOverlap(grown, fp.items[id].poly))) return false;
    if (anchorIn(grown, x, y, rad * 1.5 + 2)) return false;
    fp.add(poly, 2);
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
      st,
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
    // never on the road, the pavement or inside a building / landmark / motor park, forced or not
    if (net.clear(x, y, true, 1) < 0.3) return;
    if (fp.query(x, y, x, y).some((id) => pointInPoly(x, y, fp.items[id].poly))) return;
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
  // Traffic drives in two lanes per road (right-hand side, 0.48 x half-width off the centre line). Rules that keep it solid:
  //  - one speed per lane and equal spacing, so nothing ever overtakes (or drives through) the car in front;
  //  - a road only carries traffic on the stretch where it is clear of every higher-priority road (wider road wins),
  //    so two streams never cross at a junction; cars fade out / in at the ends of that stretch;
  //  - the Ramat Park queues stop short of the roundabout, and free traffic stays out of the queue stretch.
  const vehicles: Vehicle[] = [];
  const carColors = ['#f4f4f2', '#c8ccd0', '#2d3a4a', '#9b1d20', '#1f4f8f', '#3a3a3a', '#d9d2c2', '#6c7a3a'];
  const roadIdx = (id: string) => roads.findIndex((r) => r.id === id);
  const carries = (rd: RoadLine) => (rd.kind === 'express' || rd.kind === 'main' || rd.kind === 'ring') && rd.id !== 'ramat';
  const trafficRoads = roads.filter(carries);
  const beats = (a: RoadLine, b: RoadLine) => a.hw > b.hw || (a.hw === b.hw && roads.indexOf(a) < roads.indexOf(b));
  const GAP = 6; // free traffic stops this far before a queue
  const ROUNDABOUT_KEEP = 18; // queues and traffic stay this far from the Ramat Park island
  const usable = (rd: RoadLine): [number, number] => {
    const L = rd.sp.length;
    if (rd.closed) return [0, L];
    const rivals = trafficRoads.filter((o) => o !== rd && beats(o, rd));
    const rn = new RoadNet(rivals);
    const STEP = 3;
    let best: [number, number] = [0, 0];
    let start = -1;
    let last = 0;
    for (let s = 0; s < L; s += STEP) {
      const p = at(rd.sp, s);
      let ok = true;
      for (const lane of [1, -1]) {
        const off = rd.hw * 0.48 * lane;
        const cx = p.x - Math.sin(p.a) * off;
        const cy = p.y + Math.cos(p.a) * off;
        // a bus-sized box, a little inflated, must be off the carriageway of every road that beats this one
        for (const [x, y] of rectCorners(cx, cy, BUS[0] + 3, BUS[1] + 3, p.a)) if (rn.clear(x, y, false, 1) <= 0) ok = false;
        if (dist(cx, cy, RAMAT.x, RAMAT.y) < ROUNDABOUT_KEEP) ok = false;
      }
      if (ok) {
        if (start < 0) start = s;
        last = s;
      } else if (start >= 0) {
        if (last - start > best[1] - best[0]) best = [start, last];
        start = -1;
      }
    }
    if (start >= 0 && last - start > best[1] - best[0]) best = [start, last];
    return best;
  };
  const kindOf = (): Vehicle['kind'] => (rand() < 0.22 ? 'bus' : rand() < 0.25 ? 'keke' : 'car');
  const spawnLane = (ri: number, lane: number, s0: number, s1: number, n: number, speed: number, jam: boolean) => {
    const len = s1 - s0;
    for (let k = 0; k < n; k++) {
      const kind = jam ? (rand() < 0.3 ? 'bus' : rand() < 0.2 ? 'keke' : 'car') : kindOf();
      vehicles.push({
        road: ri,
        s: s0 + ((k + 0.5) * len) / n,
        lane,
        speed,
        kind,
        color: kind === 'bus' ? '#f2c230' : kind === 'keke' ? (jam || rand() < 0.5 ? '#f2c230' : '#2e9d58') : pick(carColors),
        s0,
        s1,
        jam,
      });
    }
  };
  // the Ramat Park go-slow: bumper-to-bumper queues on the three approaches; [road id, queue at the end of the road, queue length]
  const QUEUES: [string, boolean, number][] = [['akpakpava', true, 70], ['auchi', false, 80], ['agbor', false, 70]];
  const freeRange = new Map<number, [number, number]>();
  roads.forEach((rd, i) => {
    if (carries(rd)) freeRange.set(i, usable(rd));
  });
  for (const [id, fromEnd, qlen] of QUEUES) {
    const i = roadIdx(id);
    if (i < 0) continue;
    const [a, b] = freeRange.get(i) ?? [0, 0];
    const len = Math.min(qlen, b - a);
    if (len < 20) continue;
    const q0 = fromEnd ? b - len : a;
    const q1 = q0 + len;
    freeRange.set(i, fromEnd ? [a, q0 - GAP] : [q1 + GAP, b]);
    const n = Math.max(1, Math.floor(len / 7.4));
    for (const lane of [1, -1]) spawnLane(i, lane, q0, q1, n, R(0.8, 1.6), true);
  }
  // free traffic on the express and main roads and the Ring Road
  roads.forEach((rd, i) => {
    const r = freeRange.get(i);
    if (!r) return;
    const len = r[1] - r[0];
    if (len < 24) return;
    const n = Math.max(1, Math.round(len / (rd.kind === 'express' ? 68 : 96)));
    for (const lane of [1, -1]) spawnLane(i, lane, r[0], r[1], n, R(9, 15), false);
  });
  // parked danfos in the motor parks
  for (const q of pads) {
    for (const sl of padLayout(q.x, q.y, q.r).slots)
      vehicles.push({
        road: 0, s: 0, lane: 0, speed: 0, kind: 'bus', color: rand() < 0.75 ? '#f2c230' : '#f4f4f2', s0: 0, s1: 0, jam: false,
        px: sl.x, py: sl.y, pa: sl.a,
      });
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
      const lx = p.x - Math.sin(p.a) * side * off;
      const ly = p.y + Math.cos(p.a) * side * off;
      side = -side;
      // a lamp from one road can land on another road at a junction, or in a house: leave it out
      if (net.clear(lx, ly, false, 1) < 0.3) continue;
      if (fp.query(lx, ly, lx, ly).some((id) => pointInPoly(lx, ly, fp.items[id].poly))) continue;
      lamps.push([lx, ly]);
    }
  }

  return { roads, river, buildings, osmBuildings, trees, vehicles, lamps, pads, net, fp, urban, riverDist, ms: Math.round(performance.now() - t0) };
}

/** Size (length, width) of each vehicle kind in map units: build.ts scales its unit mesh by the same numbers x 10. */
export const VEHICLE_SIZE: Record<Vehicle['kind'], readonly [number, number]> = { car: [3.6, 2.0], bus: [BUS[0], BUS[1]], keke: [2.0, 1.5] };

const wrap = (v: number, len: number) => ((v % len) + len) % len;
/** Stop-go creep of a queue: a monotone curve (never reverses) that averages ~0.5 per second. */
const jamPhase = (t: number) => 0.5 * t + (0.5 / 0.7) * (1 - Math.cos(0.7 * t));

/**
 * Where a vehicle is at time `t` (seconds): map position, heading and a 0..1 scale that fades traffic out and in where a
 * lane's stretch ends (so cars never pop). Used by the 3D city and by scripts/city-check.mjs.
 */
export function vehicleAt(roads: readonly RoadLine[], v: Vehicle, t: number): { x: number; y: number; a: number; k: number } {
  if (v.px !== undefined) return { x: v.px, y: v.py!, a: v.pa!, k: 1 };
  const rd = roads[v.road];
  const len = v.s1 - v.s0;
  const run = v.jam ? v.speed * jamPhase(t) : v.speed * t;
  const s = v.s0 + wrap(v.s - v.s0 + run * v.lane, len);
  const p = at(rd.sp, s);
  const off = rd.hw * 0.48 * v.lane;
  const closed = rd.closed && !v.jam;
  const edge = Math.min(s - v.s0, v.s1 - s);
  return { x: p.x - Math.sin(p.a) * off, y: p.y + Math.cos(p.a) * off, a: p.a + (v.lane < 0 ? Math.PI : 0), k: closed ? 1 : Math.max(0.001, Math.min(1, edge / 4)) };
}

/** Scenes whose marker is meant to sit on a road (street corners, PoS stands, motor parks). */
export const STREET_SCENES = new Set(['street', 'pos', 'motorpark']);

/**
 * Where a place marker is drawn: the seeded spot, moved to the nearest bit of ground that is not on the road or pavement
 * (street-type places may stay on their road) and not inside a house. Moves are a few map units at most.
 */
export function snapPlace(L: CityLayout, x: number, y: number, roadOk: boolean): { x: number; y: number } {
  const ok = (px: number, py: number) => {
    if (!roadOk && L.net.clear(px, py, true, 1) < 0.3) return false;
    return !L.fp.query(px, py, px, py).some((id) => L.fp.items[id].data >= 1 && pointInPoly(px, py, L.fp.items[id].poly));
  };
  if (ok(x, y)) return { x, y };
  for (let r = 1.5; r <= 30; r += 1.5)
    for (let k = 0, n = Math.ceil((r * Math.PI * 2) / 2); k < n; k++) {
      const px = x + Math.cos((k / n) * Math.PI * 2) * r;
      const py = y + Math.sin((k / n) * Math.PI * 2) * r;
      if (ok(px, py)) return { x: px, y: py };
    }
  return { x, y };
}
