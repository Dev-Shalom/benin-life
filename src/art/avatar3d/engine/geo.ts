// Low-level procedural geometry: superellipse lofts, parametric grids, tubes and small primitives.
// Every builder returns an indexed BufferGeometry with position, normal and uv, so parts can be merged.
import {
  BufferGeometry,
  CylinderGeometry,
  Euler,
  Float32BufferAttribute,
  IcosahedronGeometry,
  Matrix4,
  Quaternion,
  SphereGeometry,
  Vector3,
  BoxGeometry,
  TorusGeometry,
  ConeGeometry,
} from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';

export type V3 = [number, number, number];

/**
 * One cross-section of a vertical loft: a superellipse at height `y` with half-width `w`, front depth `df`
 * (towards +z), back depth `db`, squareness `n` (2 = ellipse, higher = boxier) and centre offset x/z.
 */
export interface Ring {
  y: number;
  w: number;
  df: number;
  db?: number;
  n?: number;
  x?: number;
  z?: number;
  /** Soft vertical folds: amplitude (fraction of the radius) and count around. */
  ra?: number;
  rk?: number;
}

const sp = (t: number, e: number) => Math.sign(t) * Math.pow(Math.abs(t), e);
export const lerp = (a: number, b: number, t: number) => a + (b - a) * t;
export const clamp = (x: number, a = 0, b = 1) => Math.min(b, Math.max(a, x));
export const smooth = (a: number, b: number, x: number) => {
  const t = clamp((x - a) / (b - a));
  return t * t * (3 - 2 * t);
};

/** Angle a: 0 = front (+z), PI/2 = +x (the character's left), PI = back. */
export function ringXZ(r: Ring, a: number): [number, number] {
  const e = 2 / (r.n ?? 2);
  const s = Math.sin(a);
  const c = Math.cos(a);
  const f = r.ra ? 1 + r.ra * Math.cos((r.rk ?? 8) * a) : 1;
  return [(r.x ?? 0) + r.w * sp(s, e) * f, (r.z ?? 0) + (c >= 0 ? r.df : (r.db ?? r.df)) * sp(c, e) * f];
}

/** Ring at height y, linearly interpolated (rings sorted by y, either direction). */
export function ringAt(rings: Ring[], y: number): Ring {
  const asc = rings[0].y <= rings[rings.length - 1].y;
  const rs = asc ? rings : [...rings].reverse();
  if (y <= rs[0].y) return { ...rs[0], y };
  if (y >= rs[rs.length - 1].y) return { ...rs[rs.length - 1], y };
  for (let i = 0; i < rs.length - 1; i++) {
    const a = rs[i];
    const b = rs[i + 1];
    if (y >= a.y && y <= b.y) {
      const t = b.y === a.y ? 0 : (y - a.y) / (b.y - a.y);
      return {
        y,
        w: lerp(a.w, b.w, t),
        df: lerp(a.df, b.df, t),
        db: lerp(a.db ?? a.df, b.db ?? b.df, t),
        n: lerp(a.n ?? 2, b.n ?? 2, t),
        x: lerp(a.x ?? 0, b.x ?? 0, t),
        z: lerp(a.z ?? 0, b.z ?? 0, t),
        ra: lerp(a.ra ?? 0, b.ra ?? 0, t),
        rk: a.rk ?? b.rk,
      };
    }
  }
  return { ...rs[rs.length - 1], y };
}

/** Rings between y0 and y1 (inclusive, interpolated at the ends), each grown by `t`. */
export function sliceRings(rings: Ring[], y0: number, y1: number, t = 0): Ring[] {
  const lo = Math.min(y0, y1);
  const hi = Math.max(y0, y1);
  const inner = rings.filter((r) => r.y > lo + 1e-4 && r.y < hi - 1e-4);
  const out = [ringAt(rings, lo), ...inner, ringAt(rings, hi)].sort((a, b) => a.y - b.y);
  return out.map((r) => grow(r, t));
}

export function grow(r: Ring, t: number, tz = t): Ring {
  return { ...r, w: r.w + t, df: r.df + tz, db: (r.db ?? r.df) + tz };
}

// L3 crowd LOD: a global segment multiplier while building a crowd character (1 = full detail, the default;
// the player's Sim, portraits and the creator never change). Only `withDetail` sets it.
let DETAIL = 1;
export function withDetail<T>(f: number, fn: () => T): T {
  const prev = DETAIL;
  DETAIL = f;
  try {
    return fn();
  } finally {
    DETAIL = prev;
  }
}
const lod = (n: number, min: number) => (DETAIL >= 1 ? n : Math.max(min, Math.round(n * DETAIL)));

/**
 * Parametric grid surface. `fn(u, v)` with u, v in [0,1]; u runs around (or across), v along.
 * Winding: (dP/du x dP/dv) points outward. Set `flip` when it does not.
 * UVs are in metres / tile (arc length), anchored at u = `uAnchor`, so fabric prints keep their scale.
 */
export function gridSurface(
  cols: number,
  rows: number,
  fn: (u: number, v: number) => V3,
  opts: { closed?: boolean; flip?: boolean; tile?: number; uAnchor?: number; patchUv?: boolean } = {},
): BufferGeometry {
  const { closed = false, flip = false, tile = 0.25, uAnchor = 0, patchUv = false } = opts;
  cols = lod(cols, closed ? 4 : 2);
  rows = lod(rows, 1);
  const nu = cols + 1;
  const nv = rows + 1;
  const pos = new Float32Array(nu * nv * 3);
  const uv = new Float32Array(nu * nv * 2);
  const pts: V3[] = [];
  for (let j = 0; j < nv; j++) {
    for (let i = 0; i < nu; i++) {
      const u = closed && i === cols ? 1 : i / cols;
      pts.push(fn(u, j / rows));
    }
  }
  // arc-length uvs
  const anchorI = Math.round(uAnchor * cols);
  const vAcc = new Float32Array(nu);
  for (let j = 0; j < nv; j++) {
    const uAcc = new Float32Array(nu);
    for (let i = anchorI + 1; i < nu; i++) uAcc[i] = uAcc[i - 1] + dist(pts[j * nu + i], pts[j * nu + i - 1]);
    for (let i = anchorI - 1; i >= 0; i--) uAcc[i] = uAcc[i + 1] - dist(pts[j * nu + i], pts[j * nu + i + 1]);
    for (let i = 0; i < nu; i++) {
      if (j > 0) vAcc[i] += dist(pts[j * nu + i], pts[(j - 1) * nu + i]);
      const k = j * nu + i;
      pos.set(pts[k], k * 3);
      if (patchUv) {
        uv[k * 2] = i / cols;
        uv[k * 2 + 1] = j / rows;
      } else {
        uv[k * 2] = uAcc[i] / tile;
        uv[k * 2 + 1] = vAcc[i] / tile;
      }
    }
  }
  const idx: number[] = [];
  for (let j = 0; j < rows; j++) {
    for (let i = 0; i < cols; i++) {
      const a = j * nu + i;
      const b = a + 1;
      const c = a + 1 + nu;
      const d = a + nu;
      if (flip) idx.push(a, c, b, a, d, c);
      else idx.push(a, b, c, a, c, d);
    }
  }
  const geo = new BufferGeometry();
  geo.setAttribute('position', new Float32BufferAttribute(pos, 3));
  geo.setAttribute('uv', new Float32BufferAttribute(uv, 2));
  geo.setIndex(idx);
  geo.computeVertexNormals();
  return geo;
}

function dist(a: V3, b: V3) {
  return Math.hypot(a[0] - b[0], a[1] - b[1], a[2] - b[2]);
}

export interface LoftOpts {
  seg?: number;
  /** Partial arc (open surfaces), radians. Default full loop. */
  a0?: number;
  a1?: number;
  tile?: number;
  /** Close the bottom / top with a fan. */
  capLo?: boolean;
  capHi?: boolean;
  patchUv?: boolean;
}

/** Vertical loft through rings (sorted by y ascending). */
export function loft(rings: Ring[], opts: LoftOpts = {}): BufferGeometry {
  const rs = [...rings].sort((a, b) => a.y - b.y);
  const { a0 = 0, a1 = Math.PI * 2, tile = 0.25 } = opts;
  const seg = lod(opts.seg ?? 14, 4);
  // crowd LOD: fewer rings too (every other one at half detail); the first and last always stay
  const rows = DETAIL >= 1 ? rs.length - 1 : Math.max(1, Math.min(rs.length - 1, Math.round((rs.length - 1) * Math.min(1, DETAIL * 2))));
  const full = Math.abs(a1 - a0 - Math.PI * 2) < 1e-6;
  const geo = withDetail(1, () => gridSurface(
    seg,
    rows,
    (u, v) => {
      const r = rs[Math.round(v * (rs.length - 1))];
      const [x, z] = ringXZ(r, lerp(a0, a1, u));
      return [x, r.y, z];
    },
    { closed: full, tile, uAnchor: full ? 0 : 0.5, patchUv: opts.patchUv },
  ));
  const parts = [geo];
  if (opts.capLo) parts.push(fanCap(rs[0], seg, true));
  if (opts.capHi) parts.push(fanCap(rs[rs.length - 1], seg, false));
  return parts.length === 1 ? geo : merge(parts);
}

function fanCap(r: Ring, seg: number, down: boolean): BufferGeometry {
  const pos: number[] = [(r.x ?? 0), r.y, (r.z ?? 0)];
  for (let i = 0; i <= seg; i++) {
    const [x, z] = ringXZ(r, (i / seg) * Math.PI * 2);
    pos.push(x, r.y, z);
  }
  const idx: number[] = [];
  for (let i = 1; i <= seg; i++) {
    if (down) idx.push(0, i + 1, i);
    else idx.push(0, i, i + 1);
  }
  const geo = new BufferGeometry();
  geo.setAttribute('position', new Float32BufferAttribute(pos, 3));
  geo.setAttribute('uv', new Float32BufferAttribute(new Float32Array((seg + 2) * 2), 2));
  geo.setIndex(idx);
  geo.computeVertexNormals();
  return geo;
}

/** Tube along a polyline with per-point radii. Ends are closed with a point. */
export function tube(points: V3[], radii: number[] | number, sides = 5, tile = 0.1): BufferGeometry {
  sides = lod(sides, 3);
  const P = points.map((p) => new Vector3(...p));
  const n = P.length;
  const R = (i: number) => (Array.isArray(radii) ? radii[Math.min(i, radii.length - 1)] : radii);
  // parallel-transport frames
  const T: Vector3[] = P.map((_, i) => {
    const a = P[Math.max(0, i - 1)];
    const b = P[Math.min(n - 1, i + 1)];
    return b.clone().sub(a).normalize();
  });
  let N = new Vector3(0, 0, 1);
  if (Math.abs(N.dot(T[0])) > 0.9) N = new Vector3(1, 0, 0);
  N = N.sub(T[0].clone().multiplyScalar(N.dot(T[0]))).normalize();
  const Ns: Vector3[] = [];
  const Bs: Vector3[] = [];
  for (let i = 0; i < n; i++) {
    if (i > 0) {
      const q = new Quaternion().setFromUnitVectors(T[i - 1], T[i]);
      N = N.clone().applyQuaternion(q);
    }
    Ns.push(N.clone());
    Bs.push(T[i].clone().cross(N).normalize());
  }
  // rows: start tip, n rings, end tip
  const ringsPts: V3[][] = [];
  const tip = (p: Vector3): V3[] => Array.from({ length: sides + 1 }, () => [p.x, p.y, p.z]);
  ringsPts.push(tip(P[0].clone().addScaledVector(T[0], -R(0) * 0.6)));
  for (let i = 0; i < n; i++) {
    const row: V3[] = [];
    for (let k = 0; k <= sides; k++) {
      const a = (k / sides) * Math.PI * 2;
      const r = R(i);
      const p = P[i].clone().addScaledVector(Ns[i], Math.cos(a) * r).addScaledVector(Bs[i], Math.sin(a) * r);
      row.push([p.x, p.y, p.z]);
    }
    ringsPts.push(row);
  }
  ringsPts.push(tip(P[n - 1].clone().addScaledVector(T[n - 1], R(n - 1) * 0.6)));
  return gridSurface(sides, ringsPts.length - 1, (u, v) => ringsPts[Math.round(v * (ringsPts.length - 1))][Math.round(u * sides)], {
    closed: true,
    tile,
  });
}

// ---------------------------------------------------------------------------------------------
// Primitives with a transform
// ---------------------------------------------------------------------------------------------

export interface Xf {
  p?: V3;
  r?: V3;
  s?: V3 | number;
}

export function xf(geo: BufferGeometry, t: Xf): BufferGeometry {
  const m = new Matrix4();
  const s = t.s === undefined ? [1, 1, 1] : typeof t.s === 'number' ? [t.s, t.s, t.s] : t.s;
  m.compose(
    new Vector3(...(t.p ?? [0, 0, 0])),
    new Quaternion().setFromEuler(new Euler(...(t.r ?? [0, 0, 0]), 'YXZ')),
    new Vector3(s[0], s[1], s[2]),
  );
  geo.applyMatrix4(m);
  return geo;
}

/** Scaled sphere (ellipsoid). */
export function ellipsoid(rx: number, ry: number, rz: number, t: Xf = {}, ws = 10, hs = 7): BufferGeometry {
  const g = new SphereGeometry(1, lod(ws, 4), lod(hs, 3));
  g.scale(rx, ry, rz);
  return xf(g, t);
}

export function box(sx: number, sy: number, sz: number, t: Xf = {}): BufferGeometry {
  return xf(new BoxGeometry(sx, sy, sz), t);
}

export function cyl(rTop: number, rBot: number, h: number, t: Xf = {}, seg = 10, open = false): BufferGeometry {
  return xf(new CylinderGeometry(rTop, rBot, h, lod(seg, 4), 1, open), t);
}

export function cone(r: number, h: number, t: Xf = {}, seg = 6): BufferGeometry {
  return xf(new ConeGeometry(r, h, lod(seg, 3), 1), t);
}

export function torus(r: number, tubeR: number, t: Xf = {}, rs = 4, ts = 12, arc = Math.PI * 2): BufferGeometry {
  return xf(new TorusGeometry(r, tubeR, lod(rs, 3), lod(ts, 4), arc), t);
}

export function bead(r: number, t: Xf = {}): BufferGeometry {
  return xf(new IcosahedronGeometry(r, 0), t);
}

/** Orientation that turns +z towards `n` (for placing things on a surface). */
export function faceTo(n: Vector3): V3 {
  const e = new Euler().setFromQuaternion(new Quaternion().setFromUnitVectors(new Vector3(0, 0, 1), n.clone().normalize()), 'YXZ');
  return [e.x, e.y, e.z];
}

/** Merge geometries (all must be indexed with position/normal/uv). */
export function merge(parts: BufferGeometry[]): BufferGeometry {
  const clean = parts.map((g) => {
    const out = g.index ? g : g;
    for (const k of Object.keys(out.attributes)) if (!['position', 'normal', 'uv'].includes(k)) out.deleteAttribute(k);
    if (!out.getAttribute('uv')) out.setAttribute('uv', new Float32BufferAttribute(new Float32Array(out.getAttribute('position').count * 2), 2));
    if (!out.getAttribute('normal')) out.computeVertexNormals();
    return out;
  });
  const m = mergeGeometries(clean, false);
  if (!m) throw new Error('merge failed');
  return m;
}

export function triCount(geo: BufferGeometry): number {
  return geo.index ? geo.index.count / 3 : geo.getAttribute('position').count / 3;
}

/** Deterministic hash noise in [-1, 1]. */
export function hash3(x: number, y: number, z = 0): number {
  const s = Math.sin(x * 127.1 + y * 311.7 + z * 74.7) * 43758.5453;
  return (s - Math.floor(s)) * 2 - 1;
}

/** Seeded PRNG (mulberry32). */
export function prng(seed: number) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
