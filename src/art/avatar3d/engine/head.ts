// The head is one parametric surface P(v, a): v runs chin (0) -> crown (1), a runs around (0 = front).
// The head mesh, face features, facial hair, hairstyles and hats are all built on it, so every
// hairstyle fits every face shape. Coordinates here are head-local (origin = Dims.headCenter).
import { BufferGeometry, Quaternion, Vector3 } from 'three';
import { clamp, ellipsoid, gridSurface, lerp, loft, merge, ringXZ, smooth, tube, type Ring, type V3 } from './geo';

/** Feature heights (head-local, before the face shape's vertical scale). */
export const FEATURE = {
  eyeY: 0.0,
  eyeX: 0.0305,
  browY: 0.027,
  noseY: -0.034,
  mouthY: -0.066,
  earY: -0.008,
};

// y, w, df, db, z, n   (front of face = z + df)
const KEYS: [number, number, number, number, number, number][] = [
  [-0.117, 0.013, 0.009, 0.011, 0.05, 2],
  [-0.109, 0.034, 0.026, 0.038, 0.038, 2],
  [-0.092, 0.054, 0.046, 0.058, 0.025, 2.1],
  [-0.068, 0.066, 0.063, 0.072, 0.015, 2.2],
  [-0.038, 0.073, 0.078, 0.085, 0.008, 2.2],
  [-0.01, 0.078, 0.085, 0.093, 0.004, 2.2],
  [0.02, 0.08, 0.088, 0.098, 0.0, 2.2],
  [0.05, 0.08, 0.09, 0.102, -0.003, 2.15],
  [0.08, 0.075, 0.086, 0.102, -0.007, 2.1],
  [0.104, 0.062, 0.072, 0.093, -0.011, 2],
  [0.12, 0.04, 0.049, 0.07, -0.014, 2],
  [0.127, 0.0, 0.0, 0.0, -0.016, 2],
];

interface ShapeMod {
  w?: number[];
  n?: number[];
  ys?: number;
  z?: number[];
  df?: number[];
}

const SHAPES: Record<string, ShapeMod> = {
  oval: {},
  round: { w: [1.9, 1.45, 1.22, 1.12, 1.07, 1.05, 1.03, 1.01, 1, 1, 1, 1], ys: 0.93, z: [-0.007, -0.005, -0.002, 0, 0, 0, 0, 0, 0, 0, 0, 0] },
  square: { w: [2.7, 1.85, 1.32, 1.12, 1.04, 1.01, 1, 1, 1.02, 1.05, 1.07, 1], n: [3.8, 3.6, 3.3, 2.9, 2.5, 2.3, 2.2, 2.2, 2.4, 2.5, 2.3, 2], ys: 0.98 },
  long: { w: [0.9, 0.92, 0.92, 0.93, 0.93, 0.93, 0.93, 0.93, 0.93, 0.93, 0.93, 1], ys: 1.12 },
  heart: { w: [0.45, 0.62, 0.8, 0.93, 1.0, 1.04, 1.07, 1.1, 1.1, 1.08, 1.06, 1], z: [0.006, 0.004, 0.001, 0, 0, 0, 0, 0, 0, 0, 0, 0] },
  diamond: { w: [0.62, 0.74, 0.86, 0.98, 1.07, 1.11, 1.06, 0.95, 0.88, 0.86, 0.9, 1], ys: 1.03 },
};

const FEMALE_W = [0.84, 0.87, 0.92, 0.95, 0.97, 0.98, 0.98, 0.98, 0.98, 0.98, 0.98, 1];

function catmull(p0: number, p1: number, p2: number, p3: number, t: number) {
  return 0.5 * (2 * p1 + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (-p0 + 3 * p1 - 3 * p2 + p3) * t * t * t);
}

export interface ShellSpec {
  a0?: number;
  a1?: number;
  cols: number;
  rows: number;
  /** Lower edge (head-local y) for angle a. */
  yLo: (a: number) => number;
  /** Upper edge; omit for the crown. */
  yHi?: (a: number) => number;
  /** Offset along the normal; k = 0 at the lower edge, 1 at the upper edge. */
  thick?: (a: number, k: number, v: number) => number;
  /** Full control of the vertex (overrides thick). */
  map?: (p: Vector3, n: Vector3, a: number, k: number, v: number) => Vector3;
  tile?: number;
}

export class HeadSurface {
  readonly keys: Ring[];
  readonly ys: number;
  readonly female: boolean;
  private vTable: { v: number; y: number }[] = [];

  constructor(face: string, female: boolean) {
    const m = SHAPES[face] ?? SHAPES.oval;
    this.female = female;
    // Exaggerate the shape so it still reads in a 46px HUD portrait (and through the narrower female jaw).
    const amp = female ? (face === 'round' ? 1.9 : 1.55) : face === 'square' ? 1.1 : 1.3;
    const ex = (k: number | undefined) => (k === undefined ? 1 : Math.max(0.3, 1 + (k - 1) * amp));
    this.ys = ex(m.ys) * (female ? 0.965 : 1);
    this.keys = KEYS.map(([y, w, df, db, z, n], i) => ({
      y: y * this.ys,
      w: w * ex(m.w?.[i]) * (female ? FEMALE_W[i] : 1),
      df: df * (m.df?.[i] ?? 1),
      db,
      z: z + (m.z?.[i] ?? 0),
      n: m.n?.[i] ?? n,
    }));
    for (let i = 0; i <= 200; i++) {
      const v = i / 200;
      this.vTable.push({ v, y: this.ring(v).y });
    }
  }

  ring(v: number): Ring {
    const K = this.keys;
    const f = clamp(v) * (K.length - 1);
    const i = Math.min(K.length - 2, Math.floor(f));
    const t = f - i;
    const k0 = K[Math.max(0, i - 1)];
    const k1 = K[i];
    const k2 = K[i + 1];
    const k3 = K[Math.min(K.length - 1, i + 2)];
    const c = (sel: (r: Ring) => number) => catmull(sel(k0), sel(k1), sel(k2), sel(k3), t);
    return {
      y: c((r) => r.y),
      w: Math.max(0, c((r) => r.w)),
      df: Math.max(0, c((r) => r.df)),
      db: Math.max(0, c((r) => r.db ?? r.df)),
      z: c((r) => r.z ?? 0),
      n: c((r) => r.n ?? 2),
    };
  }

  pt(v: number, a: number): Vector3 {
    const r = this.ring(v);
    const [x, z] = ringXZ(r, a);
    return new Vector3(x, r.y, z);
  }

  nrm(v: number, a: number): Vector3 {
    const dv = 0.004;
    const da = 0.01;
    const pv = this.pt(Math.min(1, v + dv), a).sub(this.pt(Math.max(0, v - dv), a));
    const pa = this.pt(v, a + da).sub(this.pt(v, a - da));
    const n = pa.cross(pv);
    if (n.lengthSq() < 1e-12) {
      const p = this.pt(v, a);
      return p.sub(new Vector3(0, 0, -0.01)).normalize();
    }
    return n.normalize();
  }

  vAtY(y: number): number {
    const T = this.vTable;
    if (y <= T[0].y) return 0;
    if (y >= T[T.length - 1].y) return 1;
    for (let i = 1; i < T.length; i++) {
      if (T[i].y >= y) {
        const t = (y - T[i - 1].y) / (T[i].y - T[i - 1].y || 1);
        return lerp(T[i - 1].v, T[i].v, t);
      }
    }
    return 1;
  }

  /** Point on the face where the surface has lateral position x at height y (front half). */
  front(x: number, y: number): { p: Vector3; n: Vector3; v: number; a: number } {
    const v = this.vAtY(y);
    const r = this.ring(v);
    const ax = Math.abs(x);
    let lo = 0;
    let hi = Math.PI / 2;
    for (let i = 0; i < 30; i++) {
      const mid = (lo + hi) / 2;
      if (ringXZ(r, mid)[0] < ax) lo = mid;
      else hi = mid;
    }
    const a = (lo + hi) / 2 * Math.sign(x || 1);
    return { p: this.pt(v, a), n: this.nrm(v, a), v, a };
  }

  /** The head mesh itself. */
  mesh(cols = 24, rows = 18): BufferGeometry {
    return gridSurface(cols, rows, (u, v) => {
      const p = this.pt(v, u * Math.PI * 2);
      return [p.x, p.y, p.z];
    }, { closed: true, tile: 0.2 });
  }

  /** A surface following the head between two height curves (hair caps, beards, hats). */
  shell(s: ShellSpec): BufferGeometry {
    const a0 = s.a0 ?? -Math.PI;
    const a1 = s.a1 ?? Math.PI;
    const closed = Math.abs(a1 - a0 - Math.PI * 2) < 1e-6;
    return gridSurface(
      s.cols,
      s.rows,
      (u, k) => {
        const a = lerp(a0, a1, u);
        const vLo = this.vAtY(s.yLo(a));
        const vHi = s.yHi ? this.vAtY(s.yHi(a)) : 1;
        const v = lerp(vLo, vHi, k);
        const p = this.pt(v, a);
        const n = this.nrm(v, a);
        const out = s.map ? s.map(p, n, a, k, v) : p.addScaledVector(n, s.thick ? s.thick(a, k, v) : 0.004);
        return [out.x, out.y, out.z];
      },
      { closed, tile: s.tile ?? 0.2, uAnchor: 0.5 },
    );
  }
}

/** Wraps an angle to (-PI, PI]. */
export function wrapA(a: number) {
  let x = a % (Math.PI * 2);
  if (x > Math.PI) x -= Math.PI * 2;
  if (x <= -Math.PI) x += Math.PI * 2;
  return x;
}

/** Piecewise-smooth curve through (t, value) keys, t ascending. */
export function curve(keys: [number, number][], t: number): number {
  if (t <= keys[0][0]) return keys[0][1];
  for (let i = 1; i < keys.length; i++) {
    if (t <= keys[i][0]) {
      const [t0, v0] = keys[i - 1];
      const [t1, v1] = keys[i];
      const s = (t - t0) / (t1 - t0);
      return lerp(v0, v1, s * s * (3 - 2 * s));
    }
  }
  return keys[keys.length - 1][1];
}

/** Places a geometry at `pos`, turning its +z to `n`, then rolling it by `roll` around n. */
export function place(geo: BufferGeometry, pos: Vector3, n: Vector3, roll = 0): BufferGeometry {
  const q = new Quaternion().setFromUnitVectors(new Vector3(0, 0, 1), n.clone().normalize());
  if (roll) q.multiply(new Quaternion().setFromAxisAngle(new Vector3(0, 0, 1), roll));
  geo.applyQuaternion(q);
  geo.translate(pos.x, pos.y, pos.z);
  return geo;
}

/** Applies fn to every vertex position. */
export function deform(geo: BufferGeometry, fn: (p: Vector3) => void): BufferGeometry {
  const a = geo.getAttribute('position');
  const p = new Vector3();
  for (let i = 0; i < a.count; i++) {
    p.fromBufferAttribute(a, i);
    fn(p);
    a.setXYZ(i, p.x, p.y, p.z);
  }
  a.needsUpdate = true;
  geo.computeVertexNormals();
  return geo;
}

// ---------------------------------------------------------------------------------------------
// Face features
// ---------------------------------------------------------------------------------------------

export interface FaceParts {
  skin: BufferGeometry[];
  skinShade: BufferGeometry[];
  eyeWhite: BufferGeometry[];
  iris: BufferGeometry[];
  lash: BufferGeometry[];
  shine: BufferGeometry[];
  lip: BufferGeometry[];
  mouthDark: BufferGeometry[];
  teeth: BufferGeometry[];
  brow: BufferGeometry[];
}

const FWD = new Vector3(0, 0, 1);

function eyeDir(n: Vector3, side: number) {
  // Look straight ahead with a touch of the surface normal so the eye sits on the curve.
  return n.clone().lerp(FWD, 0.55).add(new Vector3(side * 0.04, 0, 0)).normalize();
}

export function buildFace(h: HeadSurface, o: { eyes: string; brows: string; nose: string; lips: string; mouth: string }): FaceParts {
  const F: FaceParts = { skin: [], skinShade: [], eyeWhite: [], iris: [], lash: [], shine: [], lip: [], mouthDark: [], teeth: [], brow: [] };
  const ys = h.ys;
  const fem = h.female;

  // ---- eyes
  const eye = {
    almond: { w: 0.0178, h: 0.0108, tilt: 0.12 },
    round: { w: 0.0162, h: 0.0132, tilt: 0.03 },
    hooded: { w: 0.0178, h: 0.011, tilt: 0.05 },
    wide: { w: 0.0194, h: 0.0126, tilt: 0.08 },
  }[o.eyes] ?? { w: 0.0178, h: 0.0108, tilt: 0.12 };
  const ew = eye.w * (fem ? 1.04 : 1);
  const eh = eye.h * (fem ? 1.06 : 1);
  for (const side of [1, -1]) {
    const s = h.front(side * FEATURE.eyeX, FEATURE.eyeY * ys);
    const n = eyeDir(s.n, side);
    const roll = side * eye.tilt;
    const c = s.p.clone().addScaledVector(n, -0.0015);
    const up = new Vector3(0, 1, 0).applyQuaternion(new Quaternion().setFromAxisAngle(n, roll));
    const out = new Vector3().crossVectors(up, n).multiplyScalar(side); // towards the outer corner
    F.eyeWhite.push(place(ellipsoid(ew, eh, 0.0068, {}, 12, 8), c, n, roll));
    const irisR = Math.min(eh * 0.9, 0.0102);
    F.iris.push(place(ellipsoid(irisR, irisR, 0.0034, {}, 10, 6), c.clone().addScaledVector(n, 0.0047).addScaledVector(up, -0.0006), n));
    F.shine.push(place(ellipsoid(0.0021, 0.0021, 0.001, {}, 6, 4), c.clone().addScaledVector(n, 0.0084).addScaledVector(up, 0.0034).addScaledVector(out, -0.0026), n));
    // upper lash line: a dark lid whose lower edge frames the top of the eye
    F.lash.push(place(ellipsoid(ew * 1.07, eh * 0.42, 0.0074, {}, 12, 6), c.clone().addScaledVector(up, eh * 0.64).addScaledVector(n, 0.0007).addScaledVector(out, ew * 0.04), n, roll));
    if (fem) {
      // a little flick at the outer corner
      F.lash.push(place(ellipsoid(0.005, 0.0016, 0.004, {}, 6, 4), c.clone().addScaledVector(up, eh * 0.62).addScaledVector(out, ew * 1.02).addScaledVector(n, -0.001), n, roll + side * 0.5));
    }
    if (o.eyes === 'hooded') {
      F.skinShade.push(place(ellipsoid(ew * 1.12, eh * 0.55, 0.0084, {}, 12, 6), c.clone().addScaledVector(up, eh * 0.55).addScaledVector(n, 0.0012), n, roll));
    }
    // lower lid crease (subtle)
    F.skinShade.push(place(ellipsoid(ew * 0.95, eh * 0.28, 0.0058, {}, 10, 4), c.clone().addScaledVector(up, -eh * 0.86).addScaledVector(n, -0.0006), n, roll));

    // ---- brows
    const br = {
      soft: { r: 0.0032, arch: 0.004, lift: 0, len: 1 },
      thick: { r: 0.0045, arch: 0.003, lift: 0, len: 1.04 },
      arched: { r: 0.0029, arch: 0.0085, lift: 0.002, len: 1 },
      straight: { r: 0.0036, arch: 0.0005, lift: -0.001, len: 1 },
      thin: { r: 0.0021, arch: 0.005, lift: 0.002, len: 0.95 },
    }[o.brows] ?? { r: 0.0032, arch: 0.004, lift: 0, len: 1 };
    const pts: V3[] = [];
    const radii: number[] = [];
    const N = 7;
    for (let i = 0; i < N; i++) {
      const t = i / (N - 1); // inner -> outer
      const x = side * (0.0095 + t * 0.041 * br.len);
      const y = (FEATURE.browY + br.lift) * ys + br.arch * Math.sin(Math.min(1, t * 1.25) * Math.PI) - t * 0.0035 + (fem ? 0.0015 : 0);
      const q = h.front(x, y);
      const p = q.p.addScaledVector(q.n.clone().lerp(FWD, 0.5).normalize(), 0.0022);
      pts.push([p.x, p.y, p.z]);
      radii.push(br.r * (t < 0.15 ? 1.05 : 1.15 - t * 0.55));
    }
    F.brow.push(tube(pts, radii, 4));
  }

  // ---- nose: one faceted wedge from the bridge to a broad base, embedded in the face
  const nose = {
    broad: { proj: 0.0158, ala: 0.0188, bridge: 0.0046, tip: 0.0105, top: 0.012 },
    button: { proj: 0.0128, ala: 0.0148, bridge: 0.0038, tip: 0.0095, top: 0.0 },
    straight: { proj: 0.0178, ala: 0.0138, bridge: 0.0058, tip: 0.0082, top: 0.014 },
    round: { proj: 0.0162, ala: 0.0166, bridge: 0.0045, tip: 0.0122, top: 0.01 },
  }[o.nose] ?? { proj: 0.0158, ala: 0.0188, bridge: 0.0046, tip: 0.0105, top: 0.012 };
  const k = fem ? 0.9 : 1;
  const ny = FEATURE.noseY * ys;
  const yTop = (FEATURE.eyeY + nose.top) * ys;
  const surfZ = (y: number) => h.front(0, y).p.z;
  const noseRings: Ring[] = [];
  const T = [0, 0.3, 0.6, 0.82, 0.94, 1];
  for (const t of T) {
    const y = lerp(yTop, ny, t);
    const p = nose.proj * k * Math.pow(t, 1.25);
    const w = lerp(nose.bridge, nose.ala, Math.pow(t, 2.4)) * k;
    const df = lerp(0.0035, nose.tip, Math.pow(t, 1.6)) * k;
    noseRings.push({ y, w, df, db: df + p + 0.008, z: surfZ(y) + p - df, n: 2.3 });
  }
  const last = noseRings[noseRings.length - 1];
  noseRings.push({ ...last, y: ny - 0.0055 * k, w: last.w * 0.88, df: last.df * 0.78, z: (last.z ?? 0) - 0.001 });
  noseRings.push({ ...last, y: ny - 0.0085 * k, w: last.w * 0.35, df: last.df * 0.3, db: last.db, z: (last.z ?? 0) - 0.004 });
  F.skin.push(loft(noseRings, { seg: 12 }));
  if (o.nose === 'round') {
    F.skin.push(ellipsoid(0.0085 * k, 0.0078 * k, 0.0075 * k, { p: [0, ny - 0.001, (last.z ?? 0) + last.df - 0.0045] }, 8, 6));
  }
  const tipFront = (last.z ?? 0) + last.df;
  for (const side of [1, -1]) {
    F.skinShade.push(ellipsoid(0.0046 * k, 0.0019, 0.0034, { p: [side * 0.0074 * k, ny - 0.0062 * k, tipFront - 0.0085] }, 6, 4));
    // a soft crease where each wing meets the cheek
    F.skinShade.push(ellipsoid(0.0018, 0.0058 * k, 0.003, { p: [side * (nose.ala * k + 0.0005), ny + 0.0005, surfZ(ny) + 0.0035], r: [0, side * 0.5, 0] }, 5, 5));
  }

  // ---- mouth
  const lip = { full: { u: 0.0062, l: 0.0078, d: 1.15 }, medium: { u: 0.0048, l: 0.0062, d: 1 }, thin: { u: 0.0032, l: 0.0044, d: 0.88 } }[o.lips]
    ?? { u: 0.0048, l: 0.0062, d: 1 };
  const lw = (fem ? 0.0225 : 0.0242) * (o.mouth === 'grin' ? 1.08 : 1);
  const my = FEATURE.mouthY * ys;
  const mc = h.front(0, my);
  const corner = h.front(lw, my);
  const curveZ = mc.p.z - corner.p.z; // how far the corners sit back
  const smile = { smile: 0.0042, neutral: 0.0006, grin: 0.0062, smirk: 0 }[o.mouth] ?? 0.004;
  const smirk = o.mouth === 'smirk';
  const shape = (zOff: number) => (p: Vector3) => {
    const t = clamp(Math.abs(p.x) / lw, 0, 1.2);
    p.z += zOff - curveZ * t * t;
    p.y += smile * t * t + (smirk ? (p.x > 0 ? 0.0055 : 0.0008) * t * t : 0);
  };
  const open = o.mouth === 'grin' ? 0.0042 : 0;
  F.lip.push(deform(ellipsoid(lw, lip.u, 0.0072 * lip.d, { p: [0, my + lip.u * 0.75 + open * 0.5, 0] }, 14, 6), shape(mc.p.z + 0.0012)));
  F.lip.push(deform(ellipsoid(lw * 0.9, lip.l, 0.0082 * lip.d, { p: [0, my - lip.l * 0.78 - open * 0.6, 0] }, 14, 6), shape(mc.p.z + 0.0016)));
  F.mouthDark.push(deform(ellipsoid(lw * 1.0, 0.0012 + open * 0.75, 0.0068, { p: [0, my - open * 0.1, 0] }, 12, 4), shape(mc.p.z + 0.002)));
  if (open) F.teeth.push(deform(ellipsoid(lw * 0.78, open * 0.62, 0.0052, { p: [0, my + open * 0.18, 0] }, 12, 4), shape(mc.p.z + 0.0032)));
  // philtrum / chin dimple shading
  F.skinShade.push(deform(ellipsoid(0.0042, 0.0028, 0.003, { p: [0, my - lip.l * 2.5 - 0.004, 0] }, 6, 4), (p) => { p.z += h.front(0, my - 0.016).p.z - 0.0012; }));

  // ---- ears
  for (const sd of [1, -1]) {
    const v = h.vAtY(FEATURE.earY * ys);
    const a = sd * 1.66;
    const p = h.pt(v, a);
    const n = h.nrm(v, a);
    const c = p.addScaledVector(n, 0.004);
    F.skin.push(ellipsoid(0.0105, 0.0255, 0.0168, { p: [c.x, c.y, c.z], r: [0, sd * 0.32, sd * 0.05] }, 8, 7));
    F.skinShade.push(ellipsoid(0.005, 0.016, 0.0095, { p: [c.x + sd * 0.0072, c.y + 0.001, c.z + 0.0012], r: [0, sd * 0.32, sd * 0.05] }, 6, 5));
  }
  return F;
}

// ---------------------------------------------------------------------------------------------
// Facial hair (men)
// ---------------------------------------------------------------------------------------------

export function buildFacialHair(h: HeadSurface, style: string): { hair: BufferGeometry[]; stubble: BufferGeometry[] } {
  const out = { hair: [] as BufferGeometry[], stubble: [] as BufferGeometry[] };
  if (style === 'none') return out;
  const ys = h.ys;
  const my = FEATURE.mouthY * ys;
  const ear = 1.42;
  // upper edge of the beard area, by angle
  const beardTop = (a: number) => {
    const t = Math.abs(wrapA(a));
    return curve([[0, my - 0.012], [0.3, my - 0.011], [0.5, my + 0.004], [0.8, my + 0.03], [1.2, 0.006 * ys], [ear, 0.02 * ys]], t);
  };
  const lo = () => -0.2;

  const moustache = (r: number) => {
    const pts: V3[] = [];
    const radii: number[] = [];
    for (let i = 0; i <= 8; i++) {
      const t = i / 8 * 2 - 1;
      const x = t * 0.027;
      const y = my + 0.0125 - 0.006 * t * t;
      const q = h.front(x, y);
      const p = q.p.addScaledVector(q.n, 0.0035);
      pts.push([p.x, p.y, p.z + 0.004 * (1 - t * t)]);
      radii.push(r * (1 - 0.5 * t * t));
    }
    return tube(pts, radii, 5);
  };

  if (style === 'stubble') {
    out.stubble.push(h.shell({ a0: -ear, a1: ear, cols: 24, rows: 8, yLo: lo, yHi: beardTop, thick: () => 0.0018 }));
    out.stubble.push(moustache(0.0032));
    return out;
  }
  if (style === 'moustache') {
    out.hair.push(moustache(0.0046));
    return out;
  }
  if (style === 'goatee') {
    out.hair.push(h.shell({
      a0: -0.55, a1: 0.55, cols: 10, rows: 7, yLo: lo, yHi: (a) => curve([[0, my - 0.012], [0.4, my - 0.02], [0.55, my - 0.045]], Math.abs(a)),
      thick: (a, k) => 0.0075 * (1 - smooth(0.35, 0.55, Math.abs(a)) * 0.8) * (1 - k * 0.5),
    }));
    out.hair.push(moustache(0.0042));
    return out;
  }
  if (style === 'chinstrap') {
    out.hair.push(h.shell({
      a0: -ear, a1: ear, cols: 26, rows: 4, yLo: lo,
      yHi: (a) => {
        const t = Math.abs(wrapA(a));
        return curve([[0, -0.098 * ys], [0.6, -0.085 * ys], [1.0, -0.05 * ys], [1.25, -0.005 * ys], [ear, 0.02 * ys]], t);
      },
      thick: (_a, k) => 0.0055 * (1 - k * 0.4),
    }));
    return out;
  }
  // full beard
  out.hair.push(h.shell({
    a0: -ear, a1: ear, cols: 26, rows: 9, yLo: lo, yHi: beardTop,
    thick: (a, k, v) => {
      const front = 1 - smooth(0.2, 1.3, Math.abs(a));
      const chin = 1 - smooth(0.0, 0.35, v);
      return (0.004 + 0.008 * front + 0.006 * chin) * (1 - 0.65 * k);
    },
  }));
  out.hair.push(moustache(0.0052));
  return out;
}

/** Joins the parts of one kind into a single geometry (or null). */
export function joined(list: BufferGeometry[]): BufferGeometry | null {
  if (!list.length) return null;
  return list.length === 1 ? list[0] : merge(list);
}
