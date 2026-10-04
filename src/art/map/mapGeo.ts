// P1-MAP — static geography of the Benin City map (map space 1000×1000, north up,
// Ring Road / King's Square at the centre). Pure data + small geometry helpers.

export type Pt = readonly [number, number];

export const MAP_W = 1000;
export const MAP_H = 1000;
export const RING = { x: 500, y: 500, r: 60, hw: 9 } as const;

/* ------------------------------------------------------------------ */
/* Helpers                                                              */
/* ------------------------------------------------------------------ */

/** Deterministic PRNG (mulberry32) so the procedural city is identical every load. */
export function rng(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export const r1 = (n: number) => Math.round(n * 10) / 10;

/** Fast 0.1-precision number -> string for path data (integer maths avoids V8's slow
 *  double->string path; the generator formats ~100k numbers). */
export function ft(n: number): string {
  return t10(Math.round(n * 10));
}
/** integer tenths -> decimal string (e.g. -32 -> "-3.2") */
export function t10(i: number): string {
  if (i % 10 === 0) return '' + i / 10;
  const a = i < 0 ? -i : i;
  return (i < 0 ? '-' : '') + ((a / 10) | 0) + '.' + (a % 10);
}

/**
 * Append-only SVG path writer over a byte buffer. The city generator emits ~100k
 * numbers; building them as JS strings created hundreds of thousands of short-lived
 * cons-strings (GC was the single biggest cost on a cold start). Here numbers are
 * written as ASCII digits straight into a Uint8Array and decoded once at the end.
 * All numbers are written at 0.1 precision.
 */
export class PathBuf {
  private b: Uint8Array;
  private n = 0;
  constructor(cap = 8192) {
    this.b = new Uint8Array(cap);
  }
  private room(k: number) {
    if (this.n + k > this.b.length) {
      const nb = new Uint8Array(Math.max(this.b.length * 2, this.n + k));
      nb.set(this.b);
      this.b = nb;
    }
  }
  /** raw char code (e.g. 77 'M', 108 'l') */
  ch(code: number): this {
    this.room(1);
    this.b[this.n++] = code;
    return this;
  }
  /** number at 0.1 precision */
  num(v: number): this {
    let i = Math.round(v * 10);
    this.room(10);
    const b = this.b;
    let n = this.n;
    if (i < 0) {
      b[n++] = 45;
      i = -i;
    }
    const ip = (i / 10) | 0;
    const fr = i - ip * 10;
    if (ip >= 10000) b[n++] = 48 + (((ip / 10000) | 0) % 10);
    if (ip >= 1000) b[n++] = 48 + (((ip / 1000) | 0) % 10);
    if (ip >= 100) b[n++] = 48 + (((ip / 100) | 0) % 10);
    if (ip >= 10) b[n++] = 48 + (((ip / 10) | 0) % 10);
    b[n++] = 48 + (ip % 10);
    if (fr) {
      b[n++] = 46;
      b[n++] = 48 + fr;
    }
    this.n = n;
    return this;
  }
  /** "x,y" */
  xy(x: number, y: number): this {
    return this.num(x).ch(44).num(y);
  }
  /** command letter followed by "x,y" */
  cxy(code: number, x: number, y: number): this {
    return this.ch(code).num(x).ch(44).num(y);
  }
  /** full circle as two relative arcs */
  circle(x: number, y: number, r: number): this {
    this.cxy(77, x - r, y);
    for (let k = 0; k < 2; k++) {
      this.cxy(97, r, r); // a r,r
      this.room(8);
      // " 0 1,0 "
      const b = this.b;
      b[this.n++] = 32; b[this.n++] = 48; b[this.n++] = 32; b[this.n++] = 49; b[this.n++] = 44; b[this.n++] = 48; b[this.n++] = 32;
      this.xy(k === 0 ? 2 * r : -2 * r, 0);
    }
    return this.ch(90);
  }
  /** closed polygon from flat [x0,y0,x1,y1,...] using relative 'l' segments */
  poly(c: ArrayLike<number>, count: number): this {
    // round absolute points first so relative steps don't accumulate rounding drift
    let px = Math.round(c[0] * 10) / 10;
    let py = Math.round(c[1] * 10) / 10;
    this.cxy(77, px, py);
    for (let i = 1; i < count; i++) {
      const x = Math.round(c[2 * i] * 10) / 10;
      const y = Math.round(c[2 * i + 1] * 10) / 10;
      this.cxy(108, x - px, y - py);
      px = x;
      py = y;
    }
    return this.ch(122);
  }
  get length() {
    return this.n;
  }
  toString(): string {
    return dec.decode(this.b.subarray(0, this.n));
  }
}
const dec = new TextDecoder();

export interface Sample {
  x: number;
  y: number;
  a: number; // tangent angle (rad)
  s: number; // cumulative length
}

export interface Spline {
  d: string;
  samples: Sample[];
  length: number;
}

/** Catmull-Rom spline through points → cubic-bezier path + dense samples. */
export function spline(pts: readonly Pt[], closed = false): Spline {
  const n = pts.length;
  const get = (i: number): Pt => (closed ? pts[((i % n) + n) % n] : pts[Math.max(0, Math.min(n - 1, i))]);
  const segs = closed ? n : n - 1;
  let d = `M${ft(pts[0][0])},${ft(pts[0][1])}`;
  const samples: Sample[] = [];
  let len = 0;
  let px = pts[0][0];
  let py = pts[0][1];
  for (let i = 0; i < segs; i++) {
    const p0 = get(i - 1);
    const p1 = get(i);
    const p2 = get(i + 1);
    const p3 = get(i + 2);
    const c1x = p1[0] + (p2[0] - p0[0]) / 6;
    const c1y = p1[1] + (p2[1] - p0[1]) / 6;
    const c2x = p2[0] - (p3[0] - p1[0]) / 6;
    const c2y = p2[1] - (p3[1] - p1[1]) / 6;
    d += `C${ft(c1x)},${ft(c1y)} ${ft(c2x)},${ft(c2y)} ${ft(p2[0])},${ft(p2[1])}`;
    const chord = Math.hypot(p2[0] - p1[0], p2[1] - p1[1]);
    const N = Math.max(3, Math.ceil(chord / 4));
    for (let k = i === 0 ? 0 : 1; k <= N; k++) {
      const t = k / N;
      const u = 1 - t;
      const x = u * u * u * p1[0] + 3 * u * u * t * c1x + 3 * u * t * t * c2x + t * t * t * p2[0];
      const y = u * u * u * p1[1] + 3 * u * u * t * c1y + 3 * u * t * t * c2y + t * t * t * p2[1];
      len += Math.sqrt((x - px) * (x - px) + (y - py) * (y - py));
      px = x;
      py = y;
      samples.push({ x, y, a: 0, s: len });
    }
  }
  for (let i = 0; i < samples.length; i++) {
    const a = samples[Math.max(0, i - 1)];
    const b = samples[Math.min(samples.length - 1, i + 1)];
    samples[i].a = Math.atan2(b.y - a.y, b.x - a.x);
  }
  if (closed) d += 'Z';
  return { d, samples, length: len };
}

/** Point at a given arc length along a spline. */
export function at(sp: Spline, s: number): Sample {
  const S = sp.samples;
  if (s <= 0) return S[0];
  if (s >= sp.length) return S[S.length - 1];
  let lo = 0;
  let hi = S.length - 1;
  while (hi - lo > 1) {
    const mid = (lo + hi) >> 1;
    if (S[mid].s < s) lo = mid;
    else hi = mid;
  }
  const a = S[lo];
  const b = S[hi];
  const t = (s - a.s) / Math.max(1e-6, b.s - a.s);
  return { x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t, a: a.a, s };
}

/** Polyline path for a stretch of a spline, flipped so text along it reads left→right. */
export function labelPath(sp: Spline, from: number, to: number): string {
  const pts: Sample[] = [];
  for (let s = from; s <= to; s += 3) pts.push(at(sp, s));
  pts.push(at(sp, to));
  if (pts[pts.length - 1].x < pts[0].x) pts.reverse();
  return 'M' + pts.map((p) => `${ft(p.x)},${ft(p.y)}`).join('L');
}

const bboxCache = new WeakMap<readonly Pt[], [number, number, number, number]>();

export function inPoly(x: number, y: number, poly: readonly Pt[]): boolean {
  let bb = bboxCache.get(poly);
  if (!bb) {
    bb = [Infinity, Infinity, -Infinity, -Infinity];
    for (const [px, py] of poly) {
      if (px < bb[0]) bb[0] = px;
      if (py < bb[1]) bb[1] = py;
      if (px > bb[2]) bb[2] = px;
      if (py > bb[3]) bb[3] = py;
    }
    bboxCache.set(poly, bb);
  }
  if (x < bb[0] || y < bb[1] || x > bb[2] || y > bb[3]) return false;
  let inside = false;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    const [xi, yi] = poly[i];
    const [xj, yj] = poly[j];
    if (yi > y !== yj > y && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) inside = !inside;
  }
  return inside;
}

export const polyD = (poly: readonly Pt[]) => 'M' + poly.map((p) => `${ft(p[0])},${ft(p[1])}`).join('L') + 'Z';

/** Smooth closed blob path through points. */
export const blobD = (poly: readonly Pt[]) => spline(poly, true).d;

export const circleD = (x: number, y: number, r: number) => {
  const rr = ft(r);
  const d = ft(2 * r);
  return `M${ft(x - r)},${ft(y)}a${rr},${rr} 0 1,0 ${d},0a${rr},${rr} 0 1,0 -${d},0Z`;
};

/* ------------------------------------------------------------------ */
/* Roads                                                                */
/* ------------------------------------------------------------------ */

export type RoadKind = 'express' | 'main' | 'minor' | 'dirt';
export const ROAD_HW: Record<RoadKind, number> = { express: 8, main: 6.5, minor: 3.2, dirt: 2.3 };

export interface RoadDef {
  id: string;
  kind: RoadKind;
  pts: Pt[];
  /** [label, centre position 0..1 along the road] */
  labels?: [string, number][];
  /** generate fishbone side-streets off this road */
  spurs?: boolean;
}

export const ROADS: RoadDef[] = [
  {
    id: 'ugbowo', kind: 'express', spurs: true,
    pts: [[467, 450], [430, 395], [385, 330], [345, 290], [305, 253], [255, 213], [205, 190], [165, 140], [130, 85], [85, 48], [30, 24], [-30, 8]],
    labels: [['Ugbowo–Lagos Rd', 0.355], ['Lagos Expressway', 0.87]],
  },
  {
    id: 'mission', kind: 'main', spurs: true,
    pts: [[514, 442], [518, 410], [538, 380], [585, 338], [612, 305], [612, 240], [602, 160], [592, 70], [588, -20]],
    labels: [['Upper Mission Rd', 0.68]],
  },
  {
    id: 'akpakpava', kind: 'main', spurs: true,
    pts: [[547, 463], [585, 430], [615, 393], [640, 372], [665, 371], [690, 373], [705, 375]],
    labels: [['Akpakpava Rd', 0.36]],
  },
  {
    id: 'auchi', kind: 'express', spurs: true,
    pts: [[705, 375], [760, 382], [820, 390], [880, 400], [940, 398], [1030, 390]],
    labels: [['Benin–Auchi Rd', 0.3]],
  },
  {
    id: 'agbor', kind: 'express', spurs: true,
    pts: [[705, 375], [722, 420], [745, 470], [790, 500], [850, 530], [920, 560], [1030, 595]],
    labels: [['Benin–Agbor Rd', 0.66]],
  },
  {
    id: 'sakponba', kind: 'main', spurs: true,
    pts: [[541, 544], [570, 575], [600, 606], [620, 630], [660, 672], [700, 712], [735, 745], [752, 764]],
    labels: [['Sakponba Rd', 0.66]],
  },
  {
    id: 'sapele', kind: 'express', spurs: true,
    pts: [[499, 560], [500, 610], [497, 650], [488, 690], [495, 720], [518, 745], [540, 765], [556, 800], [568, 860], [578, 940], [585, 1030]],
    labels: [['Sapele Rd', 0.66]],
  },
  {
    id: 'airport', kind: 'main', spurs: true,
    pts: [[440, 497], [400, 492], [350, 486], [300, 478], [258, 472], [238, 470]],
    labels: [['Airport Rd', 0.42]],
  },
  {
    id: 'siluko', kind: 'main', spurs: true,
    pts: [[466, 549], [445, 590], [425, 630], [400, 670], [368, 705], [330, 735], [285, 770], [240, 815], [190, 870], [140, 930], [100, 1030]],
    labels: [['Siluko Rd', 0.5]],
  },
  {
    id: 'ekenwan', kind: 'main', spurs: true,
    pts: [[444, 521], [400, 535], [350, 552], [300, 570], [250, 595], [205, 620], [160, 645], [110, 672], [60, 693], [0, 712], [-30, 720]],
    labels: [['Ekenwan Rd', 0.36]],
  },
  {
    id: 'thirdeast', kind: 'main', spurs: true,
    pts: [[612, 305], [632, 330], [645, 355], [648, 371], [655, 420], [668, 480], [680, 560], [678, 610], [662, 668], [645, 690], [618, 705], [570, 725], [518, 745]],
    labels: [['3rd East Circular', 0.3]],
  },
  { id: 'oluku-bypass', kind: 'main', pts: [[130, 85], [150, 40], [160, -20]] },
  { id: 'uselu-airport', kind: 'minor', pts: [[384, 333], [360, 350], [340, 366], [300, 392], [270, 425], [262, 472]] },
  { id: 'uselu-newbenin', kind: 'minor', pts: [[392, 322], [420, 297], [470, 284], [530, 298], [585, 336]] },
  { id: 'backgate', kind: 'dirt', pts: [[210, 188], [212, 160], [220, 110], [234, 50], [242, -10]] },
  { id: 'wifi', kind: 'minor', pts: [[306, 252], [308, 200], [310, 150], [318, 100], [330, 40]] },
  { id: 'aduwawa-link', kind: 'minor', pts: [[850, 530], [852, 505], [860, 450], [878, 400]] },
  { id: 'upper-sakponba', kind: 'dirt', pts: [[735, 745], [722, 800], [702, 860], [690, 930], [686, 1010]] },
  { id: 'gra-1', kind: 'minor', pts: [[452, 535], [415, 556], [380, 582], [352, 615], [338, 655], [350, 690]] },
  { id: 'gra-2', kind: 'minor', pts: [[300, 570], [318, 610], [345, 638], [395, 658], [425, 632]] },
  { id: 'farm-1', kind: 'dirt', pts: [[42, 700], [58, 760], [48, 840], [70, 930], [60, 1010]] },
  { id: 'farm-2', kind: 'dirt', pts: [[96, 678], [118, 620], [112, 575]] },
  { id: 'shrine', kind: 'dirt', pts: [[664, 662], [682, 666], [700, 652]] },
];

/** Off-map expressway exits (green road signs). */
export const EXITS: { text: string; sub?: string; x: number; y: number; arrow: 'l' | 'r' | 'd' | 'u' }[] = [
  { text: 'LAGOS', sub: 'via Oluku', x: 60, y: 46, arrow: 'l' },
  { text: 'AUCHI', sub: 'via Aduwawa', x: 952, y: 428, arrow: 'r' },
  { text: 'AGBOR', sub: 'Asaba', x: 948, y: 612, arrow: 'r' },
  { text: 'SAPELE', sub: 'Warri', x: 630, y: 968, arrow: 'd' },
];

/* ------------------------------------------------------------------ */
/* River, zones, landmarks                                              */
/* ------------------------------------------------------------------ */

export const RIVER: Pt[] = [
  [648, -20], [652, 60], [661, 150], [656, 240], [660, 310], [665, 371], [688, 430], [710, 505],
  [716, 580], [711, 650], [733, 712], [778, 765], [805, 850], [798, 930], [790, 1020],
];
export const BRIDGE = { x: 665, y: 371, a: Math.atan2(2, 50) };

export const CAMPUS: Pt[] = [[226, 182], [226, 130], [252, 102], [296, 100], [298, 150], [294, 200], [270, 206], [246, 196]];
export const UBTH: Pt[] = [[282, 266], [330, 280], [350, 300], [338, 322], [296, 312], [276, 290]];
export const AIRPORT: Pt[] = [[22, 530], [70, 476], [170, 420], [222, 430], [228, 498], [150, 540], [70, 580], [28, 582]];
export const RUNWAY = { x1: 48, y1: 552, x2: 196, y2: 462, w: 11 };
export const PALACE: Pt[] = [[520, 568], [548, 556], [574, 584], [560, 612], [530, 616], [512, 594]];
export const POLICE: Pt[] = [[364, 592], [396, 592], [396, 616], [364, 616]];
export const FARMLAND: Pt[] = [[0, 600], [60, 598], [120, 630], [152, 700], [142, 790], [160, 880], [140, 1000], [0, 1000]];
export const KINGS_SQUARE = { x: 500, y: 500, r: 49 };
export const RAMAT = { x: 705, y: 375 };

/** Market stall zones: [x, y, radius, location id]. */
export const MARKETS: [number, number, number, string][] = [
  [418, 445, 26, 'oba_market'],
  [596, 315, 17, 'new_benin_market'],
  [362, 318, 16, 'uselu_market'],
  [636, 612, 14, 'ekiosa_market'],
  [462, 716, 14, 'santana_market'],
  [764, 455, 15, 'oregbeni_market'],
];

/** Urban density cores: x, y, radius, weight. */
export const CORES: [number, number, number, number][] = [
  [500, 500, 150, 0.95],
  [590, 350, 105, 0.85],
  [385, 320, 95, 0.85],
  [300, 235, 95, 0.55],
  [760, 430, 105, 0.75],
  [870, 460, 95, 0.6],
  [640, 660, 115, 0.8],
  [720, 775, 85, 0.55],
  [520, 720, 115, 0.75],
  [320, 750, 105, 0.6],
  [220, 615, 95, 0.55],
  [320, 470, 80, 0.55],
  [375, 615, 85, 0.35],
  [130, 90, 60, 0.5],
  [420, 380, 80, 0.7],
  [600, 470, 70, 0.7],
];

export const GRA_ZONE = { x: 372, y: 620, r: 88 };

/** Soft district tint blobs: x, y, rx, ry, colour. */
export const DISTRICT_TINTS: [number, number, number, number, string][] = [
  [500, 500, 150, 140, '#f3c77d'], // Oredo
  [372, 625, 105, 95, '#6fae5a'], // GRA
  [265, 215, 115, 100, '#eaa868'], // Ugbowo
  [390, 320, 90, 80, '#f0b674'], // Uselu
  [590, 330, 95, 95, '#ec9f72'], // New Benin
  [770, 440, 95, 85, '#e0956a'], // Ikpoba Hill
  [880, 440, 90, 100, '#d9a46a'], // Aduwawa
  [620, 650, 85, 70, '#eaa676'], // Sakponba
  [720, 790, 80, 80, '#d48f60'], // Upper Sakponba
  [520, 760, 100, 110, '#f0b97f'], // Sapele Rd
  [320, 470, 90, 50, '#e4bd82'], // Airport Rd
  [310, 760, 90, 90, '#dc9f6e'], // Siluko
  [205, 615, 85, 70, '#d29c6c'], // Ekenwan
  [125, 95, 75, 60, '#d6a774'], // Oluku
];

export const DISTRICT_LABELS: { t: string; x: number; y: number; size?: number }[] = [
  { t: 'OREDO', x: 432, y: 404, size: 17 },
  { t: 'G.R.A.', x: 300, y: 640, size: 20 },
  { t: 'UGBOWO', x: 168, y: 238 },
  { t: 'USELU', x: 455, y: 340 },
  { t: 'NEW BENIN', x: 555, y: 268 },
  { t: 'IKPOBA HILL', x: 806, y: 432, size: 16 },
  { t: 'RAMAT PARK', x: 760, y: 330, size: 13 },
  { t: 'ADUWAWA', x: 912, y: 300 },
  { t: 'SAKPONBA', x: 595, y: 680 },
  { t: 'UPPER SAKPONBA', x: 690, y: 828, size: 15 },
  { t: 'THIRD EAST', x: 612, y: 500, size: 13 },
  { t: 'SAPELE RD', x: 452, y: 880 },
  { t: 'AIRPORT RD', x: 318, y: 515, size: 14 },
  { t: 'SILUKO', x: 260, y: 735 },
  { t: 'EKENWAN', x: 116, y: 600, size: 15 },
  { t: 'OLUKU', x: 70, y: 125 },
];

/* ------------------------------------------------------------------ */
/* Pins: short labels, label tier (1 = landmark), preferred side        */
/* ------------------------------------------------------------------ */

export type LabelSide = 'b' | 'r' | 'l' | 't';

export const PIN_META: Record<string, { short: string; tier: 1 | 2; side?: LabelSide }> = {
  national_museum: { short: 'National Museum', tier: 1, side: 'b' },
  oba_market: { short: 'Oba Market', tier: 1, side: 'l' },
  ring_road_pos: { short: 'Ring Rd PoS', tier: 2, side: 'r' },
  oba_palace: { short: "Oba's Palace", tier: 1, side: 'b' },
  igun_street: { short: 'Igun Street', tier: 2, side: 'r' },
  mama_osas_buka: { short: 'Mama Osas Buka', tier: 2, side: 'l' },
  new_benin_market: { short: 'New Benin Mkt', tier: 1, side: 'l' },
  new_benin_pos: { short: 'New Benin PoS', tier: 2, side: 't' },
  mercy_clinic: { short: 'Mercy Clinic', tier: 2, side: 'l' },
  mission_rd_flats: { short: 'Mission Rd Flats', tier: 2, side: 'l' },
  uselu_market: { short: 'Uselu Market', tier: 1, side: 'r' },
  fresh_cut_salon: { short: 'Fresh Cut Salon', tier: 2, side: 'r' },
  uselu_park: { short: 'Uselu Park', tier: 2, side: 'b' },
  uniben: { short: 'UNIBEN', tier: 1, side: 'r' },
  ubth: { short: 'UBTH', tier: 1, side: 'r' },
  back_gate_joint: { short: 'Back Gate Joint', tier: 2, side: 'l' },
  wifi_joint: { short: 'Wi-Fi Joint', tier: 2, side: 'r' },
  oluku_park: { short: 'Oluku Park', tier: 1, side: 'r' },
  ramat_park: { short: 'Ramat Park', tier: 1, side: 'b' },
  oregbeni_market: { short: 'Oregbeni Mkt', tier: 1, side: 'r' },
  aduwawa_park: { short: 'Aduwawa Park', tier: 1, side: 't' },
  aduwawa_room: { short: 'Aduwawa Room', tier: 2, side: 'b' },
  third_east: { short: 'Third East', tier: 2, side: 'r' },
  ekiosa_market: { short: 'Ekiosa Market', tier: 1, side: 'l' },
  baba_shrine: { short: 'Baba Osagie', tier: 2, side: 'r' },
  upper_sakponba: { short: 'Upper Sakponba', tier: 2, side: 'r' },
  santana_market: { short: 'Santana Mkt', tier: 1, side: 'l' },
  sapele_pos: { short: 'Sapele Rd PoS', tier: 2, side: 'r' },
  bronze_lounge: { short: 'Bronze Lounge', tier: 2, side: 'r' },
  police_hq: { short: 'Police HQ', tier: 1, side: 'b' },
  bronze_bank: { short: 'Bronze Bank', tier: 1, side: 'r' },
  gra_duplex: { short: 'GRA Duplex', tier: 2, side: 'b' },
  kingdom_lounge: { short: 'Kingdom Lounge', tier: 2, side: 'l' },
  benin_airport: { short: 'Benin Airport', tier: 1, side: 'b' },
  siluko_rd: { short: 'Siluko Road', tier: 2, side: 'r' },
  ekenwan_room: { short: 'Ekenwan Room', tier: 2, side: 'b' },
  iguobazuwa_farm: { short: 'Iguobazuwa Farm', tier: 1, side: 'r' },
  bronze_tech_hub: { short: 'Tech Hub', tier: 2, side: 'r' },
};

export function shortName(id: string, name: string): string {
  const m = PIN_META[id];
  if (m) return m.short;
  const cut = name.replace(/\s*\(.*\)\s*$/, '');
  return cut.length > 18 ? cut.slice(0, 17) + '…' : cut;
}
