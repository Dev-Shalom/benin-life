// Hairstyles and headwear. Everything is built on the HeadSurface (head-local coordinates), so caps,
// afros and hats hug every face shape. Long strands drape around the neck, shoulders and back.
import { BufferGeometry, Vector3 } from 'three';
import { bead, cone, ellipsoid, gridSurface, hash3, lerp, prng, ringAt, smooth, torus, tube, type Ring, type V3 } from './geo';
import { curve, HeadSurface, wrapA, place } from './head';
import { HAIR_HIDING_HATS } from '../catalog';

export interface HairResult {
  hair: BufferGeometry[];
  /** Headwear pieces by material slot. */
  hat: Partial<Record<HatMat, BufferGeometry[]>>;
  /** Long hair: limit head turning so strands do not cut through the shoulders. */
  long: boolean;
  /** Highest point (head-local y), for portrait framing. */
  top: number;
}

export type HatMat = 'accent' | 'accentDark' | 'accentFabric' | 'coral' | 'black' | 'gold' | 'white' | 'coralBead';

/** Body clearance for draped strands, in head-local coordinates. */
export interface Envelope {
  torso: Ring[];
  /** headCenter (model space). */
  hc: V3;
  neckR: number;
  neckBaseY: number;
  shoulderX: number;
  shoulderY: number;
  /** extra clearance (clothes). */
  margin: number;
}

function hairline(a: number, female: boolean, ys: number): number {
  const t = Math.abs(wrapA(a));
  const keys: [number, number][] = female
    ? [[0, 0.069], [0.55, 0.064], [1.0, 0.047], [1.28, 0.022], [1.42, 0.026], [1.8, 0.03], [2.15, -0.02], [2.6, -0.058], [Math.PI, -0.068]]
    : [[0, 0.07], [0.5, 0.066], [0.95, 0.052], [1.18, 0.028], [1.3, -0.004], [1.4, 0.004], [1.5, 0.03], [1.8, 0.034], [2.15, -0.016], [2.6, -0.048], [Math.PI, -0.056]];
  return curve(keys, t) * ys;
}

/** Distance along a ray from c (direction d) to a superellipsoid with radii r and exponents p (around), q (vertical). */
function rayShape(d: Vector3, r: V3, p = 2, q = 2): number {
  const F = (s: number) => {
    const x = Math.abs((d.x * s) / r[0]);
    const y = Math.abs((d.y * s) / r[1]);
    const z = Math.abs((d.z * s) / r[2]);
    return Math.pow(Math.pow(x, p) + Math.pow(z, p), q / p) + Math.pow(y, q);
  };
  let lo = 0;
  let hi = 0.6;
  for (let i = 0; i < 26; i++) {
    const m = (lo + hi) / 2;
    if (F(m) < 1) lo = m;
    else hi = m;
  }
  return (lo + hi) / 2;
}

/** Pushes a head-local point outside the head, neck and torso (plus margin). */
export function makePush(env: Envelope) {
  const [hx, hy, hz] = env.hc;
  return (p: Vector3): Vector3 => {
    // head (ellipsoid approximation, generous)
    const hr = new Vector3(0.088, 0.13, 0.108);
    const q = new Vector3(p.x / hr.x, p.y / hr.y, (p.z + 0.004) / hr.z);
    const L = q.length();
    if (L < 1.04) p.set(p.x * (1.04 / L), p.y * (1.04 / L), (p.z + 0.004) * (1.04 / L) - 0.004);
    // torso + neck in model space
    const my = p.y + hy;
    const mx = p.x + hx;
    const mz = p.z + hz;
    if (my < env.neckBaseY + 0.12 && my > env.neckBaseY - 0.02) {
      const r = Math.hypot(mx, mz + 0.004);
      const need = env.neckR + env.margin + 0.004;
      if (r < need) {
        const k = need / Math.max(r, 1e-4);
        p.x = mx * k - hx;
        p.z = (mz + 0.004) * k - 0.004 - hz;
      }
    }
    if (my < env.neckBaseY + 0.02) {
      const ring = ringAt(env.torso, my);
      const w = ring.w + env.margin;
      const df = ring.df + env.margin;
      const db = (ring.db ?? ring.df) + env.margin;
      const n = ring.n ?? 2;
      const x = p.x + hx;
      const z = p.z + hz;
      const F = Math.pow(Math.abs(x) / w, n) + Math.pow(Math.abs(z) / (z >= 0 ? df : db), n);
      if (F < 1) {
        const k = Math.pow(F, -1 / n);
        p.x = x * k - hx;
        p.z = z * k - hz;
      }
      // shoulders: the arm balls stick out past the torso rings
      for (const s of [1, -1]) {
        const ax = s * env.shoulderX;
        const dy = my - env.shoulderY;
        const dx = x - ax;
        const rr = 0.062 + env.margin;
        const dd = Math.hypot(dx, dy, z);
        if (dd < rr) {
          const k2 = rr / Math.max(dd, 1e-4);
          p.x = ax + dx * k2 - hx;
          p.z = z * k2 - hz;
          p.y = env.shoulderY + dy * k2 - hy;
        }
      }
    }
    return p;
  };
}

/** A strand hanging from `start`, pushed out of the body as it falls. */
function drape(start: Vector3, dir: Vector3, length: number, push: (p: Vector3) => Vector3, step = 0.02, stiff = 0.55): Vector3[] {
  const pts = [start.clone()];
  let p = start.clone();
  let d = dir.clone().normalize();
  const down = new Vector3(0, -1, 0);
  let len = 0;
  while (len < length - 1e-6) {
    const s = Math.min(step, length - len);
    d = d.multiplyScalar(stiff).addScaledVector(down, 1 - stiff).normalize();
    const next = p.clone().addScaledVector(d, s);
    push(next);
    d = next.clone().sub(p).normalize();
    p = next;
    pts.push(p.clone());
    len += s;
  }
  return pts;
}

const v3 = (p: Vector3): V3 => [p.x, p.y, p.z];

export function buildHair(
  h: HeadSurface,
  o: { hair: string; hat: string; female: boolean; seed: number },
  env: Envelope,
): HairResult {
  const R: HairResult = { hair: [], hat: {}, long: false, top: 0.13 * h.ys };
  const ys = h.ys;
  const fem = o.female;
  const hl = (a: number) => hairline(a, fem, ys);
  const rand = prng(o.seed);
  const push = makePush(env);
  const hatAdd = (m: HatMat, ...g: BufferGeometry[]) => (R.hat[m] ??= []).push(...g);
  const hairHidden = HAIR_HIDING_HATS.has(o.hat);
  const underCap = o.hat === 'cap';
  const style = o.hair;

  /** Thin cap over the whole hairline. */
  const cap = (thick: number | ((a: number, k: number, v: number, p: Vector3) => number), cols = 32, rows = 10) =>
    h.shell({
      cols, rows, yLo: hl,
      map: (p, n, a, k, v) => {
        const t = typeof thick === 'number' ? thick : thick(a, k, v, p);
        return p.addScaledVector(n, t * (0.35 + 0.65 * smooth(0, 0.22, k)));
      },
    });

  /** Cap whose outside blends into a target shape (afro, high-top...). */
  const volume = (c: Vector3, r: V3, pe: number, qe: number, opts: { band?: number; fuzz?: number; minY?: number; cols?: number; rows?: number } = {}) =>
    h.shell({
      cols: opts.cols ?? 30, rows: opts.rows ?? 12, yLo: hl,
      map: (p, n, a, k) => {
        const base = p.clone().addScaledVector(n, 0.005);
        const d = p.clone().sub(c);
        const dist = d.length();
        d.normalize();
        let s = rayShape(d, r, pe, qe);
        s += (hash3(Math.round(a * 40), Math.round(k * 40), o.seed) * (opts.fuzz ?? 0.006));
        const target = c.clone().addScaledVector(d, Math.max(s, dist + 0.005));
        let w = smooth(0, opts.band ?? 0.3, k);
        if (opts.minY !== undefined) w *= smooth(opts.minY - 0.02, opts.minY + 0.02, p.y);
        const out = base.lerp(target, w);
        R.top = Math.max(R.top, out.y);
        return out;
      },
    });

  // ------------------------------------------------------------------ hair
  const buildStyle = () => {
    if (style === 'bald') return;
    if (hairHidden) {
      // Hair is under the headwear. Long styles still show below the back of a beanie/bucket hat.
      if (!['beanie', 'bucket'].includes(o.hat)) return;
    }
    const simple = hairHidden || underCap;
    switch (style) {
      case 'low_cut':
        R.hair.push(cap((_a, _k, _v, p) => 0.0055 + 0.001 * hash3(p.x * 300, p.y * 300, p.z * 300)));
        return;
      case 'waves':
        R.hair.push(h.shell({
          cols: 36, rows: 26, yLo: hl,
          map: (p, n, _a, k, v) => p.addScaledVector(n, (0.0052 + 0.0024 * Math.max(0, Math.sin(v * 95))) * (0.35 + 0.65 * smooth(0, 0.2, k))),
        }));
        return;
      case 'twa':
      case 'afro': {
        if (simple) {
          R.hair.push(cap(0.008));
          return;
        }
        if (style === 'twa') {
          R.hair.push(volume(new Vector3(0, 0.03 * ys, -0.01), [0.1, 0.122 * ys, 0.122], 2, 2, { band: 0.25, fuzz: 0.006 }));
          return;
        }
        const big = fem ? [0.152, 0.138, 0.152] : [0.126, 0.118, 0.13];
        R.hair.push(volume(new Vector3(0, (fem ? 0.05 : 0.045) * ys, -0.014), [big[0], big[1] * ys, big[2]], 2, 2, { band: 0.32, fuzz: 0.012, rows: 14, cols: 34 }));
        return;
      }
      case 'high_top':
        if (simple) {
          R.hair.push(cap(0.007));
          return;
        }
        R.hair.push(volume(new Vector3(0, 0.07 * ys, -0.012), [0.083, 0.1 * ys, 0.1], 3, 5, { band: 0.2, fuzz: 0.004, minY: 0.05 * ys, rows: 14, cols: 32 }));
        return;
      case 'cornrows': {
        R.hair.push(h.shell({
          cols: 56, rows: 16, yLo: hl,
          map: (p, n, _a, k) => {
            const ridge = Math.pow(Math.max(0, Math.cos((p.x / 0.0205) * Math.PI * 2)), 0.6);
            return p.addScaledVector(n, (0.0045 + 0.0042 * ridge) * (0.4 + 0.6 * smooth(0, 0.15, k)));
          },
        }));
        if (fem && !simple) {
          // a few loose braids at the nape
          for (let i = 0; i < 7; i++) {
            const x = (i - 3) * 0.0205;
            const start = new Vector3(x, -0.045 * ys, 0);
            const v = h.vAtY(-0.05 * ys);
            const a = Math.PI - x * 9;
            const sp = h.pt(v, a).addScaledVector(h.nrm(v, a), 0.006);
            start.copy(sp);
            const pts = drape(start, new Vector3(x * 4, -1, -0.5), 0.2, push);
            R.hair.push(tube(pts.map(v3), pts.map((_, j) => 0.0058 - j * 0.0002), 4));
          }
          R.long = true;
        }
        return;
      }
      case 'twists':
      case 'locs':
      case 'braids':
      case 'bantu_knots':
      case 'bone_straight':
      case 'bun':
      case 'ponytail':
        return strands();
      default:
        R.hair.push(cap(0.006));
    }
  };

  /** Styles made of strands, knots or a sheet. */
  const strands = () => {
    const simple = hairHidden || underCap;
    const sleek = (style === 'bun' || style === 'ponytail' || style === 'bone_straight');
    const capThick = style === 'twists' ? 0.011 : style === 'locs' ? 0.012 : sleek ? 0.0075 : 0.0068;
    if (!hairHidden) {
      if (style === 'braids' || style === 'bantu_knots') {
        // parted grid (box braids / knots)
        R.hair.push(h.shell({
          cols: 48, rows: 16, yLo: hl,
          map: (p, n, _a, k) => {
            const gx = Math.abs(Math.cos((p.x / 0.03) * Math.PI));
            const gz = Math.abs(Math.cos(((p.z + p.y * 0.6) / 0.03) * Math.PI));
            const bump = Math.min(gx, gz);
            return p.addScaledVector(n, (capThick + 0.003 * bump) * (0.4 + 0.6 * smooth(0, 0.15, k)));
          },
        }));
      } else if (style === 'bone_straight') {
        // middle parting
        R.hair.push(h.shell({
          cols: 36, rows: 12, yLo: hl,
          map: (p, n, _a, k) => {
            const part = 1 - 0.55 * Math.exp(-Math.pow(p.x / 0.004, 2)) * smooth(0.0, 0.06, p.z);
            const fall = 0.004 * smooth(0.02, 0.1, Math.abs(p.x)) * (1 - smooth(0.6, 1, k));
            return p.addScaledVector(n, (capThick + fall) * part * (0.4 + 0.6 * smooth(0, 0.15, k)));
          },
        }));
      } else {
        R.hair.push(cap((_a, _k, _v, p) => capThick + 0.0012 * hash3(p.x * 200, p.y * 200, p.z * 200)));
      }
    }
    if (simple && !['braids', 'locs', 'bone_straight', 'ponytail'].includes(style)) return;

    if (style === 'twists') {
      // short sponge twists all over the top
      const N = 78;
      for (let i = 0; i < N; i++) {
        const v = 0.56 + 0.44 * Math.sqrt(rand());
        const a = (rand() * 2 - 1) * Math.PI;
        const p = h.pt(v, a);
        if (p.y < hl(a) + 0.01) continue;
        const n = h.nrm(v, a).lerp(new Vector3(0, 1, 0), 0.3).normalize();
        const len = 0.018 + rand() * 0.012;
        const base = p.addScaledVector(n, 0.008);
        const g = cone(0.0105, len, {}, 5);
        g.translate(0, len / 2, 0);
        g.rotateX(Math.PI / 2);
        R.hair.push(place(g, base, n, rand() * 6));
        R.top = Math.max(R.top, base.y + len * n.y);
      }
      return;
    }

    if (style === 'bantu_knots') {
      const spots: [number, number][] = [[0.97, 0], [0.8, 0.45], [0.8, -0.45], [0.8, 1.45], [0.8, -1.45], [0.76, 2.5], [0.76, -2.5], [0.62, 2.0], [0.62, -2.0], [0.66, Math.PI]];
      for (const [v, a] of spots) {
        const p = h.pt(v, a);
        const n = h.nrm(v, a).lerp(new Vector3(0, 1, 0), 0.2).normalize();
        const base = p.addScaledVector(n, 0.006);
        R.hair.push(place(ellipsoid(0.019, 0.019, 0.013, {}, 8, 6), base.clone().addScaledVector(n, 0.008), n));
        R.hair.push(place(ellipsoid(0.012, 0.012, 0.011, {}, 7, 5), base.clone().addScaledVector(n, 0.02), n, 0.6));
        R.top = Math.max(R.top, base.y + 0.03 * n.y);
      }
      return;
    }

    if (style === 'bun') {
      const c = new Vector3(0, 0.138 * ys, -0.035);
      R.hair.push(ellipsoid(0.05, 0.042, 0.048, { p: v3(c), r: [-0.35, 0, 0] }, 10, 8));
      R.hair.push(torus(0.034, 0.0075, { p: [c.x, c.y - 0.03, c.z + 0.008], r: [Math.PI / 2 - 0.35, 0, 0] }, 4, 12));
      R.top = Math.max(R.top, c.y + 0.045);
      return;
    }

    if (style === 'ponytail') {
      const v = h.vAtY(0.06 * ys);
      const root = h.pt(v, Math.PI).addScaledVector(h.nrm(v, Math.PI), 0.008);
      R.hair.push(torus(0.017, 0.0065, { p: v3(root), r: [0.4, 0, 0] }, 4, 10));
      const pts = drape(root.clone().add(new Vector3(0, 0.004, -0.012)), new Vector3(0, 0.4, -1), 0.3, push, 0.03, 0.75);
      R.hair.push(tube(pts.map(v3), pts.map((_, j) => Math.max(0.006, 0.024 - j * 0.0018 + (j === 1 ? 0.004 : 0))), 7));
      R.long = true;
      return;
    }

    if (style === 'locs' || style === 'braids') {
      const isBraid = style === 'braids';
      const len = isBraid ? 0.42 : fem ? 0.32 : 0.17;
      const r0 = isBraid ? 0.0072 : 0.0105;
      const N = isBraid ? 50 : 38;
      R.long = len > 0.2;
      const startY = simple ? (o.hat === 'cap' ? 0.035 : 0.02) * ys : 0;
      for (let i = 0; i < N; i++) {
        // spread roots over the scalp, back and sides first; front roots fall back/sideways
        const a = wrapA(Math.PI + (i / N) * Math.PI * 2 + (rand() - 0.5) * 0.12);
        const front = Math.abs(a) < 1.1;
        const yMin = Math.max(hl(a) + 0.008, startY);
        const vLo = h.vAtY(yMin);
        const v = front ? lerp(Math.max(vLo, 0.82), 0.97, rand()) : lerp(vLo, Math.min(0.99, vLo + 0.18), rand());
        const p = h.pt(v, a);
        const n = h.nrm(v, a);
        const start = p.addScaledVector(n, 0.008);
        const outward = new Vector3(Math.sin(a), 0, Math.cos(a));
        const dir = front ? outward.clone().multiplyScalar(-0.2).add(new Vector3(Math.sign(Math.sin(a) || 1) * 0.9, 0.5, -0.6)) : outward.clone().multiplyScalar(0.7).add(new Vector3(0, 0.3, 0));
        const L = len * (0.85 + rand() * 0.3) * (front && !isBraid ? 0.75 : 1);
        const pts = drape(start, dir, L, push, isBraid ? 0.038 : 0.03, 0.5);
        const radii = pts.map((_, j) => r0 * (j === pts.length - 1 ? 0.7 : 1));
        R.hair.push(tube(pts.map(v3), radii, isBraid ? 4 : 5));
      }
      if (fem && isBraid && !simple) {
        // braids gathered into a light top volume
        R.hair.push(volume(new Vector3(0, 0.03 * ys, -0.012), [0.09, 0.124 * ys, 0.112], 2, 2, { band: 0.3, fuzz: 0.002, cols: 24, rows: 8 }));
      }
      return;
    }

    if (style === 'bone_straight') {
      // a sheet of straight hair from the sides and back, falling past the shoulders
      R.long = true;
      const cols = 26;
      const steps = 15;
      const len = 0.36;
      const a0 = 1.05;
      const a1 = Math.PI * 2 - 1.05;
      const lines: Vector3[][] = [];
      for (let i = 0; i <= cols; i++) {
        const a = wrapA(lerp(a0, a1, i / cols));
        const side = Math.abs(a) < 1.7;
        const y0 = side ? 0.045 * ys : 0.0;
        const v = h.vAtY(Math.max(y0, hl(a) + 0.01));
        const p = h.pt(v, a).addScaledVector(h.nrm(v, a), 0.011);
        const outward = new Vector3(Math.sin(a), 0, Math.cos(a));
        const pts = drape(p, outward.multiplyScalar(0.5).add(new Vector3(0, -0.5, 0)), len, push, len / steps, 0.35);
        while (pts.length < steps + 1) pts.push(pts[pts.length - 1].clone().add(new Vector3(0, -0.001, 0)));
        lines.push(pts.slice(0, steps + 1));
      }
      // jagged, slightly tapered ends
      R.hair.push(gridSurface(cols, steps, (u, v) => {
        const i = Math.round(u * cols);
        const j = Math.round(v * steps);
        const p = lines[i][j];
        const end = j === steps ? (i % 2 ? 0.015 : 0) : 0;
        return [p.x, p.y + end, p.z];
      }, { tile: 0.1 }));
      return;
    }
  };

  buildStyle();

  // ------------------------------------------------------------------ headwear
  const band = (front: number, side: number, back: number) => (a: number) =>
    curve([[0, front], [1.2, side], [1.9, side], [Math.PI, back]], Math.abs(wrapA(a))) * ys;

  switch (o.hat) {
    case 'cap': {
      const lo = band(0.058, 0.04, 0.03);
      hatAdd('accent', h.shell({ cols: 30, rows: 9, yLo: lo, map: (p, n, _a, k) => p.addScaledVector(n, 0.012 + 0.008 * Math.sin(k * Math.PI * 0.9)) }));
      // brim
      const v = (a: number) => h.vAtY(lo(a));
      const pts = (a: number, t: number) => {
        const p = h.pt(v(a), a).addScaledVector(h.nrm(v(a), a), 0.012);
        const len = 0.078 * Math.pow(Math.cos(a * 0.82), 0.7);
        return p.add(new Vector3(Math.sin(a) * 0.25, -0.12, 1).normalize().multiplyScalar(len * t));
      };
      hatAdd('accentDark', gridSurface(14, 3, (u, k) => {
        const a = lerp(-1.25, 1.25, u);
        const p = pts(a, k);
        return [p.x, p.y, p.z];
      }));
      const topV = h.pt(1, 0).addScaledVector(h.nrm(1, 0), 0.02);
      hatAdd('accentDark', ellipsoid(0.007, 0.004, 0.007, { p: v3(topV) }, 6, 4));
      R.top = Math.max(R.top, topV.y);
      break;
    }
    case 'beanie': {
      const lo = band(0.062, 0.032, 0.0);
      hatAdd('accent', h.shell({ cols: 30, rows: 10, yLo: lo, map: (p, n, _a, k) => p.addScaledVector(n, 0.014 + 0.016 * k * (1 - k * 0.4)) }));
      hatAdd('accentDark', h.shell({ cols: 30, rows: 2, yLo: (a) => lo(a) - 0.002, yHi: (a) => lo(a) + 0.026 * ys, thick: () => 0.019 }));
      R.top = Math.max(R.top, h.pt(1, 0).y + 0.026);
      break;
    }
    case 'bucket': {
      const lo = band(0.06, 0.036, 0.03);
      hatAdd('accent', h.shell({ cols: 30, rows: 9, yLo: lo, map: (p, n, _a, k) => p.addScaledVector(n, 0.013 + 0.01 * Math.sin(k * Math.PI * 0.8)) }));
      hatAdd('accent', gridSurface(30, 2, (u, k) => {
        const a = lerp(-Math.PI, Math.PI, u);
        const v = h.vAtY(lo(a));
        const p = h.pt(v, a).addScaledVector(h.nrm(v, a), 0.012);
        const out = new Vector3(Math.sin(a), -0.55, Math.cos(a)).normalize();
        return v3(p.addScaledVector(out, 0.055 * k));
      }, { closed: true }));
      R.top = Math.max(R.top, h.pt(1, 0).y + 0.03);
      break;
    }
    case 'fila': {
      const lo = band(0.062, 0.045, 0.034);
      const c = new Vector3(0, 0.075 * ys, -0.01);
      hatAdd('accentFabric', h.shell({
        cols: 30, rows: 10, yLo: lo,
        map: (p, n, _a, k) => {
          const d = p.clone().sub(c).normalize();
          const s = rayShape(d, [0.094, 0.085 * ys, 0.106], 2.4, 5);
          const out = p.clone().addScaledVector(n, 0.01).lerp(c.clone().addScaledVector(d, s), smooth(0, 0.35, k));
          // the classic slant: the top flops towards the left ear
          const lift = Math.max(0, out.y - 0.09 * ys);
          out.x += lift * 0.9;
          out.y -= lift * 0.35;
          R.top = Math.max(R.top, out.y);
          return out;
        },
      }));
      hatAdd('accentDark', h.shell({ cols: 30, rows: 1, yLo: (a) => lo(a) - 0.002, yHi: (a) => lo(a) + 0.014 * ys, thick: () => 0.0125 }));
      break;
    }
    case 'coral_cap': {
      const lo = band(0.064, 0.046, 0.036);
      hatAdd('coral', h.shell({ cols: 28, rows: 9, yLo: lo, map: (p, n, _a, k) => p.addScaledVector(n, 0.012 + 0.012 * Math.sin(k * Math.PI * 0.7)), tile: 0.05 }));
      // a rim of larger beads
      for (let i = 0; i < 30; i++) {
        const a = -Math.PI + (i / 30) * Math.PI * 2;
        const v = h.vAtY(lo(a));
        const p = h.pt(v, a).addScaledVector(h.nrm(v, a), 0.014);
        hatAdd('coralBead', bead(0.0075, { p: v3(p) }));
      }
      R.top = Math.max(R.top, h.pt(1, 0).y + 0.024);
      break;
    }
    case 'police_cap': {
      const lo = band(0.056, 0.05, 0.05);
      hatAdd('black', h.shell({ cols: 30, rows: 3, yLo: lo, yHi: (a) => lo(a) + 0.04 * ys, thick: () => 0.013 }));
      // crown: tilted oval top
      const topY = lo(0) + 0.05 * ys;
      hatAdd('accent', ellipsoid(0.112, 0.022, 0.122, { p: [0, topY, -0.006], r: [-0.12, 0, 0] }, 16, 6));
      const vv = h.vAtY(lo(0));
      const front = h.pt(vv, 0).addScaledVector(h.nrm(vv, 0), 0.013);
      hatAdd('black', ellipsoid(0.07, 0.006, 0.05, { p: [0, front.y - 0.004, front.z + 0.012], r: [0.32, 0, 0] }, 12, 4));
      hatAdd('gold', ellipsoid(0.011, 0.013, 0.004, { p: [0, front.y + 0.024, front.z + 0.002] }, 8, 6));
      R.top = Math.max(R.top, topY + 0.03);
      break;
    }
    case 'head_tie': {
      const lo = band(0.07, 0.034, -0.045);
      hatAdd('accentFabric', h.shell({ cols: 30, rows: 10, yLo: lo, map: (p, n, a, k) => p.addScaledVector(n, 0.014 + 0.016 * k + 0.006 * Math.abs(Math.sin(a * 3)) * k) }));
      const knot = h.pt(0.8, Math.PI).addScaledVector(h.nrm(0.8, Math.PI), 0.03);
      hatAdd('accentFabric', ellipsoid(0.028, 0.024, 0.022, { p: v3(knot) }, 8, 6));
      hatAdd('accentFabric', ellipsoid(0.034, 0.015, 0.008, { p: [knot.x + 0.022, knot.y + 0.012, knot.z - 0.018], r: [-0.5, 0.5, 0.5] }, 8, 5));
      hatAdd('accentFabric', ellipsoid(0.034, 0.015, 0.008, { p: [knot.x - 0.022, knot.y + 0.012, knot.z - 0.018], r: [-0.5, -0.5, -0.5] }, 8, 5));
      R.top = Math.max(R.top, h.pt(1, 0).y + 0.032);
      break;
    }
    case 'gele': {
      const lo = band(0.068, 0.03, -0.035);
      // wrapped base
      hatAdd('accentFabric', h.shell({ cols: 30, rows: 8, yLo: lo, map: (p, n, _a, k) => p.addScaledVector(n, 0.018 + 0.024 * k) }));
      // the fan: stiff pleats rising from the back of the head
      const hub = new Vector3(0, 0.12 * ys, -0.045);
      const K = 11;
      for (let i = 0; i < K; i++) {
        const t = i / (K - 1) * 2 - 1; // -1..1 left to right
        const ang = t * 1.25;
        const dir = new Vector3(Math.sin(ang) * 0.95, Math.cos(ang) * 0.75 + 0.25, -0.55 + Math.abs(t) * 0.2).normalize();
        const len = 0.1 - Math.abs(t) * 0.022;
        const c = hub.clone().addScaledVector(dir, len * 0.75);
        const g = ellipsoid(0.034, len, 0.008, {}, 8, 6);
        g.rotateZ(-ang);
        g.rotateX(-0.45 + Math.abs(t) * 0.25);
        g.translate(c.x, c.y, c.z);
        hatAdd('accentFabric', g);
        R.top = Math.max(R.top, c.y + len * dir.y);
      }
      // front swoop over the forehead
      hatAdd('accentFabric', ellipsoid(0.1, 0.03, 0.05, { p: [0, 0.098 * ys, 0.035], r: [0.35, 0, 0] }, 12, 6));
      // tucked tail at the back
      hatAdd('accentFabric', ellipsoid(0.04, 0.05, 0.014, { p: [0.035, 0.01, -0.105], r: [0.3, 0.3, 0.4] }, 8, 6));
      break;
    }
    case 'okuku': {
      const lo = band(0.07, 0.036, -0.03);
      const c = new Vector3(0, 0.05 * ys, -0.03);
      const tilt = 0.38;
      const ct = Math.cos(tilt);
      const st = Math.sin(tilt);
      hatAdd('coral', h.shell({
        cols: 30, rows: 14, yLo: lo, tile: 0.06,
        map: (p, n, _a, k) => {
          const d = p.clone().sub(c).normalize();
          // tilt the crown backwards: rotate the ray into the crown's frame
          const dl = new Vector3(d.x, d.y * ct - d.z * st, d.y * st + d.z * ct);
          const s = rayShape(dl, [0.1, 0.2 * ys, 0.105], 2, 1.6);
          const out = p.clone().addScaledVector(n, 0.012).lerp(c.clone().addScaledVector(d, s), smooth(0, 0.3, k));
          R.top = Math.max(R.top, out.y);
          return out;
        },
      }));
      // bead strands framing the face
      for (const sd of [1, -1]) {
        for (let i = 0; i < 6; i++) {
          const a = sd * 1.3;
          const v = h.vAtY(0.03 * ys);
          const p = h.pt(v, a).addScaledVector(h.nrm(v, a), 0.016);
          hatAdd('coralBead', bead(0.0062, { p: [p.x, p.y - i * 0.0125, p.z] }));
        }
      }
      // a band of bigger beads at the brow
      for (let i = 0; i < 26; i++) {
        const a = -Math.PI + (i / 26) * Math.PI * 2;
        const v = h.vAtY(lo(a));
        const p = h.pt(v, a).addScaledVector(h.nrm(v, a), 0.015);
        hatAdd('coralBead', bead(0.0082, { p: v3(p) }));
      }
      break;
    }
    default:
      break;
  }
  return R;
}

/** Tiny helpers for accessories that sit on the head (shades, earrings...). */
export function earPoint(h: HeadSurface, side: number): Vector3 {
  const v = h.vAtY(-0.028 * h.ys);
  const a = side * 1.66;
  return h.pt(v, a).addScaledVector(h.nrm(v, a), 0.008);
}

