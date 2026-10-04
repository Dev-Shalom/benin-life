// Body measurements + path helpers. Full-view space is 200 x 400, centre line x = 100.
import type { Gender } from '../../lib/types';

export type P = [number, number];
export interface Joint { x: number; y: number; w: number }

export const CX = 100;
export const r1 = (n: number) => Math.round(n * 10) / 10;
const pt = (p: P) => `${r1(p[0])} ${r1(p[1])}`;

/** Catmull-Rom spline through points, emitted as cubic Béziers (no leading M). */
export function smoothOpen(pts: P[], k = 1): string {
  let d = '';
  for (let i = 0; i < pts.length - 1; i++) {
    const p0 = pts[i - 1] ?? pts[i];
    const p1 = pts[i];
    const p2 = pts[i + 1];
    const p3 = pts[i + 2] ?? p2;
    const c1: P = [p1[0] + ((p2[0] - p0[0]) / 6) * k, p1[1] + ((p2[1] - p0[1]) / 6) * k];
    const c2: P = [p2[0] - ((p3[0] - p1[0]) / 6) * k, p2[1] - ((p3[1] - p1[1]) / 6) * k];
    d += ` C${pt(c1)} ${pt(c2)} ${pt(p2)}`;
  }
  return d;
}

/** Closed smooth shape through points. */
export function smoothClosed(pts: P[], k = 1): string {
  const n = pts.length;
  let d = `M${pt(pts[0])}`;
  for (let i = 0; i < n; i++) {
    const p0 = pts[(i - 1 + n) % n];
    const p1 = pts[i];
    const p2 = pts[(i + 1) % n];
    const p3 = pts[(i + 2) % n];
    const c1: P = [p1[0] + ((p2[0] - p0[0]) / 6) * k, p1[1] + ((p2[1] - p0[1]) / 6) * k];
    const c2: P = [p2[0] - ((p3[0] - p1[0]) / 6) * k, p2[1] - ((p3[1] - p1[1]) / 6) * k];
    d += ` C${pt(c1)} ${pt(c2)} ${pt(p2)}`;
  }
  return d + 'Z';
}

/** Polyline path (no smoothing). */
export function poly(pts: P[], close = true): string {
  return 'M' + pts.map(pt).join(' L') + (close ? 'Z' : '');
}

/** Mirror a list of left-side points (x < 100) to make a symmetric closed outline (left top → down → right up). */
export function mirrorPts(left: P[]): P[] {
  const right = left.map(([x, y]) => [200 - x, y] as P).reverse();
  return [...left, ...right];
}

export const mx = (x: number, side: number) => CX + (x - CX) * side; // side 1 = left as authored, -1 mirrored

// ---------- chain (limb) sampling ----------
function chainLen(c: Joint[]) {
  const segs: number[] = [];
  let total = 0;
  for (let i = 0; i < c.length - 1; i++) {
    const l = Math.hypot(c[i + 1].x - c[i].x, c[i + 1].y - c[i].y);
    segs.push(l);
    total += l;
  }
  return { segs, total };
}

export function chainAt(c: Joint[], t: number): Joint {
  const { segs, total } = chainLen(c);
  let d = Math.max(0, Math.min(1, t)) * total;
  for (let i = 0; i < segs.length; i++) {
    if (d <= segs[i] || i === segs.length - 1) {
      const u = segs[i] ? Math.min(1, d / segs[i]) : 0;
      const a = c[i];
      const b = c[i + 1];
      return { x: a.x + (b.x - a.x) * u, y: a.y + (b.y - a.y) * u, w: a.w + (b.w - a.w) * u };
    }
    d -= segs[i];
  }
  return c[c.length - 1];
}

function chainDir(c: Joint[], t: number): P {
  const a = chainAt(c, t - 0.05);
  const b = chainAt(c, t + 0.05);
  const l = Math.hypot(b.x - a.x, b.y - a.y) || 1;
  return [(b.x - a.x) / l, (b.y - a.y) / l];
}

export interface LimbOpts {
  from?: number;
  to?: number;
  pad?: number;
  /** extra width added linearly toward the end (sleeve/trouser flare) */
  flare?: number;
  start?: 'round' | 'flat';
  end?: 'round' | 'flat' | 'curve';
  samples?: number;
}

/** Outline of a tapered limb (or sleeve / trouser leg) following a joint chain. */
export function limb(c: Joint[], o: LimbOpts = {}): string {
  const from = o.from ?? 0;
  const to = o.to ?? 1;
  const pad = o.pad ?? 0;
  const flare = o.flare ?? 0;
  const n = o.samples ?? 9;
  const L: P[] = [];
  const R: P[] = [];
  let endW = 0;
  let endP: Joint = c[0];
  let endD: P = [0, 1];
  let startW = 0;
  let startD: P = [0, 1];
  for (let i = 0; i <= n; i++) {
    const u = i / n;
    const t = from + (to - from) * u;
    const j = chainAt(c, t);
    const [dx, dy] = chainDir(c, t);
    const w = j.w + pad + flare * u;
    const nx = -dy;
    const ny = dx;
    L.push([j.x + nx * w, j.y + ny * w]);
    R.push([j.x - nx * w, j.y - ny * w]);
    if (i === n) { endW = w; endP = j; endD = [dx, dy]; }
    if (i === 0) { startW = w; startD = [dx, dy]; }
  }
  let d = `M${pt(L[0])}` + smoothOpen(L);
  const re = R[n];
  if ((o.end ?? 'round') === 'round') {
    d += ` A${r1(endW)} ${r1(endW)} 0 0 0 ${pt(re)}`;
  } else if (o.end === 'curve') {
    const cx = endP.x + endD[0] * endW * 0.45;
    const cy = endP.y + endD[1] * endW * 0.45;
    d += ` Q${r1(cx)} ${r1(cy)} ${pt(re)}`;
  } else {
    d += ` L${pt(re)}`;
  }
  const Rr = [...R].reverse();
  d += smoothOpen(Rr);
  if ((o.start ?? 'round') === 'round') {
    d += ` A${r1(startW)} ${r1(startW)} 0 0 0 ${pt(L[0])}`;
  }
  void startD;
  return d + 'Z';
}

// ---------- body measurements ----------
export type BodyKind = 'slim' | 'average' | 'thick';

export interface Body {
  female: boolean;
  kind: BodyKind;
  t: number; // 0 slim, 1 average, 2 thick
  nw: number; // neck half width
  sh: number; // shoulder half width
  ch: number; // chest half width
  wa: number; // waist half width
  hi: number; // hip half width
  bust: number;
  belly: number;
  shoulderY: number;
  waistY: number;
  hipY: number;
  crotchY: number;
  arm: Joint[]; // left arm (viewer's left), shoulder → wrist
  leg: Joint[]; // left leg, hip → ankle
  handLen: number;
  handW: number;
}

const pick = (t: number, a: [number, number, number]) => a[t];

export function makeBody(gender: Gender, kind: BodyKind): Body {
  const F = gender === 'female';
  const t = kind === 'slim' ? 0 : kind === 'thick' ? 2 : 1;
  const sh = F ? pick(t, [27, 29, 32]) : pick(t, [30, 33, 36]);
  const ch = F ? pick(t, [24, 27, 31]) : pick(t, [26, 29.5, 33.5]);
  const wa = F ? pick(t, [17.5, 20.5, 27]) : pick(t, [21, 24.5, 31]);
  const hi = F ? pick(t, [25.5, 30, 36.5]) : pick(t, [22.5, 26, 30.5]);
  const nw = F ? pick(t, [7.2, 7.6, 8.4]) : pick(t, [8.6, 9.6, 10.8]);
  const aTop = F ? pick(t, [7, 8.2, 10.2]) : pick(t, [8, 9.6, 11.6]);
  const aMid = F ? pick(t, [6, 7, 9]) : pick(t, [7, 8.4, 10.2]);
  const aElb = F ? pick(t, [4.8, 5.4, 6.8]) : pick(t, [5.4, 6.2, 7.4]);
  const aFore = F ? pick(t, [5.2, 5.9, 7.2]) : pick(t, [6, 7, 8.2]);
  const aWr = F ? pick(t, [3.8, 4.2, 5]) : pick(t, [4.3, 4.8, 5.5]);
  const thigh = F ? pick(t, [12.6, 15, 18.4]) : pick(t, [11.8, 13.4, 15.8]);
  const knee = F ? pick(t, [7.4, 8.4, 10.2]) : pick(t, [7.6, 8.6, 9.8]);
  const calf = F ? pick(t, [8, 9.2, 11.2]) : pick(t, [8.2, 9.4, 10.8]);
  const ankle = F ? pick(t, [4.4, 4.8, 5.6]) : pick(t, [4.8, 5.2, 5.8]);

  const hj = hi - thigh + 0.5; // hip joint x-offset
  const kx = Math.max(knee + 1.5, hj * 0.8 + 2);
  const ax = kx + 1.5;

  const elbX = Math.max(sh + 1.5, wa + aElb + 4);
  const wrX = Math.max(sh + 5, hi + aWr + 2.5);
  const shX = sh - aTop * 0.75;

  const arm: Joint[] = [
    { x: CX - shX, y: 117, w: aTop },
    { x: CX - (shX + elbX) / 2 - 0.5, y: 143, w: aMid },
    { x: CX - elbX, y: 170, w: aElb },
    { x: CX - elbX - (wrX - elbX) * 0.35, y: 186, w: aFore },
    { x: CX - wrX, y: 219, w: aWr },
  ];
  const leg: Joint[] = [
    { x: CX - hj, y: 222, w: thigh },
    { x: CX - (hj + kx) / 2, y: 262, w: (thigh + knee) / 2 + 1.2 },
    { x: CX - kx, y: 300, w: knee },
    { x: CX - kx - 0.6, y: 322, w: calf },
    { x: CX - ax, y: 369, w: ankle },
  ];

  return {
    female: F, kind, t, nw, sh, ch, wa, hi,
    bust: F ? pick(t, [3, 4.5, 6]) : 0,
    belly: F ? pick(t, [0, 0, 2]) : pick(t, [0, 0, 4]),
    shoulderY: 113, waistY: 177, hipY: 207, crotchY: 230,
    arm, leg,
    handLen: F ? 19 : 21,
    handW: F ? pick(t, [4.6, 5, 5.6]) : pick(t, [5.4, 5.8, 6.3]),
  };
}

/** Body half-width at height y (skin silhouette). */
export function sideAt(b: Body, y: number): number {
  const keys: P[] = [
    [100, b.nw + 1.5],
    [108, b.sh - 5],
    [114, b.sh],
    [130, b.sh - 2],
    [143, b.ch],
    [b.waistY, b.wa],
    [b.hipY, b.hi],
    [b.crotchY, b.hi - 1.5],
    [260, b.hi - 1.5],
  ];
  if (y <= keys[0][0]) return keys[0][1];
  for (let i = 0; i < keys.length - 1; i++) {
    const [y0, w0] = keys[i];
    const [y1, w1] = keys[i + 1];
    if (y <= y1) {
      const u = (y - y0) / (y1 - y0);
      const s = u * u * (3 - 2 * u); // smoothstep
      return w0 + (w1 - w0) * s;
    }
  }
  return keys[keys.length - 1][1];
}

export function mirrorJoints(c: Joint[]): Joint[] {
  return c.map((j) => ({ ...j, x: 200 - j.x }));
}

/** Hand outline + wrist point for a side (1 = viewer's left, -1 = right). */
export function handGeom(b: Body, side: number) {
  const arm = side === 1 ? b.arm : mirrorJoints(b.arm);
  const w = arm[arm.length - 1];
  const e = arm[arm.length - 2];
  const l = Math.hypot(w.x - e.x, w.y - e.y);
  const d: P = [(w.x - e.x) / l, (w.y - e.y) / l];
  return { wrist: w, dir: d };
}
