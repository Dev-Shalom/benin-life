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

/** [minX, minY, maxX, maxY] of a polygon. */
export function bbox(poly: readonly Pt[]): [number, number, number, number] {
  let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
  for (const [x, y] of poly) {
    if (x < x0) x0 = x;
    if (y < y0) y0 = y;
    if (x > x1) x1 = x;
    if (y > y1) y1 = y;
  }
  return [x0, y0, x1, y1];
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

// Geography follows docs/MAP_GEO.md (OSM road bearings out of King's Square, compressed
// radially). Each radial road starts on the Ring Road at its real bearing (clockwise from N):
// Lagos/Ugbowo 350, Mission 31, Akpakpava 52, Sakponba 125, Sapele 165, Airport 221,
// Ekenwan ~245 (passes south of the palace), Siluko ~300 (NW).
export const ROADS: RoadDef[] = [
  {
    // Uselu → Ugbowo (UBTH west, UNIBEN east) → Oluku, then the expressway towards Lagos
    id: 'ugbowo', kind: 'express', spurs: true,
    pts: [[490, 441], [486, 400], [478, 350], [470, 300], [465, 250], [460, 200], [455, 160], [446, 120], [430, 86], [410, 58], [390, 40], [370, 16], [352, -20]],
    labels: [['Ugbowo–Lagos Rd', 0.17]],
  },
  {
    id: 'mission', kind: 'main', spurs: true,
    pts: [[531, 449], [548, 418], [566, 388], [585, 360], [605, 330], [618, 290], [625, 230], [628, 150], [630, 60], [632, -20]],
    labels: [['Mission Rd', 0.12], ['Upper Mission Rd', 0.62]],
  },
  {
    // NE to the Ikpoba bridge, up Ikpoba Hill to Ramat Park
    id: 'akpakpava', kind: 'main', spurs: true,
    pts: [[547, 463], [578, 445], [610, 431], [636, 423], [656, 420], [686, 412]],
    labels: [['Akpakpava Rd', 0.62]],
  },
  {
    id: 'auchi', kind: 'express', spurs: true,
    pts: [[686, 412], [735, 388], [780, 360], [820, 338], [870, 322], [930, 306], [1030, 285]],
    labels: [['Benin–Auchi Rd', 0.66]],
  },
  {
    id: 'agbor', kind: 'express', spurs: true,
    pts: [[686, 412], [740, 420], [800, 430], [860, 446], [920, 466], [1030, 502]],
    labels: [['Benin–Agbor Rd', 0.5]],
  },
  {
    id: 'sakponba', kind: 'main', spurs: true,
    pts: [[549, 534], [582, 557], [615, 580], [650, 605], [685, 640], [712, 672], [740, 710]],
    labels: [['Sakponba Rd', 0.86]],
  },
  {
    id: 'sapele', kind: 'express', spurs: true,
    pts: [[516, 558], [524, 600], [532, 640], [542, 690], [546, 740], [545, 800], [552, 880], [560, 960], [564, 1030]],
    labels: [['Sapele Rd', 0.5]],
  },
  {
    id: 'airport', kind: 'main', spurs: true,
    pts: [[461, 545], [432, 563], [400, 580], [365, 598], [335, 612]],
    labels: [['Airport Rd', 0.5]],
  },
  {
    // NW: Siluko Rd becomes Upper Siluko Rd and runs on towards Iguobazuwa
    id: 'siluko', kind: 'main', spurs: true,
    pts: [[446, 474], [420, 450], [398, 415], [378, 385], [345, 355], [300, 326], [240, 302], [170, 284], [100, 273], [30, 266], [-30, 262]],
    labels: [['Siluko Rd', 0.14], ['Upper Siluko Rd', 0.5]],
  },
  {
    // WSW along the south side of the palace
    id: 'ekenwan', kind: 'main', spurs: true,
    pts: [[446, 525], [418, 541], [380, 551], [340, 560], [300, 577], [250, 592], [190, 606], [120, 620], [50, 635], [-30, 650]],
    labels: [['Ekenwan Rd', 0.7]],
  },
  {
    // Third East Circular: N–S east of the centre, between Akpakpava and Sakponba
    id: 'thirdeast', kind: 'main', spurs: true,
    pts: [[630, 425], [638, 470], [647, 520], [652, 568], [657, 610]],
    labels: [['3rd East Circular', 0.42]],
  },
  { id: 'oluku-bypass', kind: 'main', pts: [[390, 40], [440, 26], [520, 8], [590, -16]] },
  { id: 'second-east', kind: 'minor', pts: [[610, 431], [616, 480], [620, 535], [616, 584]] },
  { id: 'first-east', kind: 'minor', pts: [[585, 442], [596, 480], [600, 520], [596, 562]] },
  { id: 'uselu-siluko', kind: 'minor', pts: [[468, 290], [430, 302], [395, 322], [355, 350]] },
  { id: 'uselu-newbenin', kind: 'minor', pts: [[471, 312], [520, 324], [560, 340], [588, 356]] },
  { id: 'wifi', kind: 'minor', pts: [[452, 140], [420, 130], [380, 124], [330, 112], [280, 96]] },
  { id: 'backgate', kind: 'dirt', pts: [[495, 90], [486, 60], [479, 25], [475, -15]] },
  { id: 'aduwawa-link', kind: 'minor', pts: [[852, 444], [855, 400], [858, 360], [862, 325]] },
  { id: 'oregbeni', kind: 'minor', pts: [[742, 420], [730, 455], [724, 500], [718, 540]] },
  { id: 'upper-sakponba', kind: 'dirt', pts: [[740, 710], [752, 780], [760, 860], [765, 1010]] },
  { id: 'gra-1', kind: 'minor', pts: [[432, 563], [441, 600], [442, 640], [436, 690], [430, 735]] },
  { id: 'gra-2', kind: 'minor', pts: [[531, 636], [490, 648], [450, 662], [410, 676], [372, 700]] },
  { id: 'farm-1', kind: 'dirt', pts: [[80, 271], [62, 300], [52, 345], [60, 420]] },
  { id: 'farm-2', kind: 'dirt', pts: [[140, 279], [132, 230], [112, 185]] },
  { id: 'shrine', kind: 'dirt', pts: [[628, 597], [642, 622], [656, 640]] },
];

/** Off-map exits (green road signs). */
export const EXITS: { text: string; sub?: string; x: number; y: number; arrow: 'l' | 'r' | 'd' | 'u' }[] = [
  { text: 'LAGOS', sub: 'via Oluku', x: 300, y: 26, arrow: 'u' },
  { text: 'AUCHI', sub: 'via Aduwawa', x: 948, y: 345, arrow: 'r' },
  { text: 'AGBOR', sub: 'Asaba', x: 945, y: 515, arrow: 'r' },
  { text: 'SAPELE', sub: 'Warri', x: 620, y: 966, arrow: 'd' },
  { text: 'FARMS', sub: 'Iguobazuwa', x: 70, y: 232, arrow: 'l' },
];

/* ------------------------------------------------------------------ */
/* River, zones, landmarks                                              */
/* ------------------------------------------------------------------ */

/** Ikpoba River: N–S east of the centre, between the end of Akpakpava Rd and Ramat Park,
 *  then bending SE past Upper Sakponba. */
export const RIVER: Pt[] = [
  [725, -20], [718, 80], [705, 180], [690, 262], [674, 330], [666, 380], [656, 420], [670, 466],
  [695, 515], [726, 585], [762, 655], [798, 735], [826, 840], [836, 930], [840, 1020],
];
export const BRIDGE = { x: 656, y: 420, a: Math.atan2(-5, 40) };

export const CAMPUS: Pt[] = [[464, 98], [500, 86], [535, 100], [538, 150], [510, 168], [468, 160]];
export const UBTH: Pt[] = [[400, 148], [438, 145], [445, 160], [443, 192], [410, 196], [398, 175]];
export const AIRPORT: Pt[] = [[205, 625], [290, 610], [335, 640], [325, 700], [255, 732], [190, 700]];
export const RUNWAY = { x1: 214, y1: 702, x2: 306, y2: 640, w: 11 };
/** Airport terminal + apron (east end of the runway, at the end of Airport Rd). */
export const TERMINAL = { x: 312, y: 660 };
/** Oba's Palace: just W (slightly S) of King's Square, outside the ring, north of Ekenwan Rd. */
export const PALACE: Pt[] = [[385, 487], [412, 479], [428, 494], [426, 518], [404, 528], [384, 518]];
export const POLICE: Pt[] = [[486, 600], [508, 600], [508, 620], [486, 620]];
export const FARMLAND: Pt[] = [[0, 160], [80, 165], [150, 195], [185, 250], [175, 330], [140, 400], [70, 440], [0, 445]];
export const KINGS_SQUARE = { x: 500, y: 500, r: 49 };
/** Ramat Park roundabout (east bank of the Ikpoba, top of Ikpoba Hill). */
export const RAMAT = { x: 686, y: 412 };
export const GO_SLOW = { x: 728, y: 430 };
/** UNIBEN sports ground, UBTH hospital sign. */
export const STADIUM = { x: 514, y: 140 };
export const UBTH_SIGN = { x: 422, y: 182 };
/** Bronze Tech Hub plot (V1-3, fictional, Ugbowo near UNIBEN): kept clear of generated buildings. */
export const TECH_HUB = { x: 535, y: 190, r: 15 };
/** Sacred grove around the shrine. */
export const GROVE = { x: 655, y: 632, r: 22 };

/** Market stall zones: [x, y, radius, location id]. */
export const MARKETS: [number, number, number, string][] = [
  [445, 420, 22, 'oba_market'],
  [612, 368, 15, 'new_benin_market'],
  [500, 235, 16, 'uselu_market'],
  [600, 598, 13, 'ekiosa_market'],
  [580, 705, 14, 'santana_market'],
  [722, 492, 13, 'oregbeni_market'],
];

/** Warm night glows: [x, y, radius, opacity] (markets, Ramat, nightlife). */
export const NIGHT_GLOWS: [number, number, number, number][] = [
  [500, 500, 52, 1],
  [686, 412, 40, 1],
  [445, 425, 34, 0.8],
  [560, 770, 30, 0.8],
  [420, 650, 26, 0.7],
  [480, 235, 28, 0.6],
];

/** Urban density cores: x, y, radius, weight. */
export const CORES: [number, number, number, number][] = [
  [500, 500, 150, 0.95],
  [590, 345, 100, 0.85], // New Benin
  [470, 275, 95, 0.85], // Uselu
  [460, 150, 85, 0.55], // Ugbowo
  [390, 45, 60, 0.5], // Oluku
  [730, 450, 95, 0.75], // Ikpoba Hill
  [850, 365, 90, 0.6], // Aduwawa
  [635, 520, 80, 0.75], // Third East
  [640, 610, 110, 0.8], // Sakponba
  [725, 700, 85, 0.55], // Upper Sakponba
  [550, 740, 110, 0.75], // Sapele Rd
  [345, 355, 100, 0.6], // Siluko
  [270, 560, 90, 0.55], // Ekenwan
  [390, 590, 70, 0.45], // Airport Rd
  [465, 655, 85, 0.35], // GRA
  [555, 860, 90, 0.5], // Sapele Rd south
  [190, 600, 80, 0.4], // Ekenwan west
  [430, 400, 80, 0.7],
  [600, 470, 70, 0.7],
];

export const GRA_ZONE = { x: 462, y: 655, r: 80 };

/** Soft district tint blobs: x, y, rx, ry, colour. */
export const DISTRICT_TINTS: [number, number, number, number, string][] = [
  [500, 500, 150, 140, '#f3c77d'], // Oredo
  [462, 660, 100, 90, '#6fae5a'], // GRA
  [470, 140, 110, 90, '#eaa868'], // Ugbowo
  [470, 275, 95, 70, '#f0b674'], // Uselu
  [590, 330, 90, 95, '#ec9f72'], // New Benin
  [735, 455, 80, 80, '#e0956a'], // Ikpoba Hill
  [870, 380, 95, 90, '#d9a46a'], // Aduwawa
  [640, 520, 55, 70, '#e7ad78'], // Third East
  [630, 625, 85, 65, '#eaa676'], // Sakponba
  [725, 715, 80, 75, '#d48f60'], // Upper Sakponba
  [550, 780, 95, 120, '#f0b97f'], // Sapele Rd
  [350, 600, 70, 50, '#e4bd82'], // Airport Rd
  [320, 340, 100, 80, '#dc9f6e'], // Siluko
  [250, 575, 85, 60, '#d29c6c'], // Ekenwan
  [390, 50, 80, 50, '#d6a774'], // Oluku
];

export const DISTRICT_LABELS: { t: string; x: number; y: number; size?: number; rot?: number }[] = [
  { t: 'OREDO', x: 566, y: 531, size: 15 },
  { t: 'G.R.A.', x: 395, y: 728, size: 20 },
  { t: 'UGBOWO', x: 565, y: 60 },
  { t: 'USELU', x: 392, y: 236 },
  { t: 'NEW BENIN', x: 645, y: 232, size: 15 },
  { t: 'IKPOBA HILL', x: 810, y: 522, size: 15 },
  { t: 'RAMAT PARK', x: 790, y: 378, size: 12 },
  { t: 'ADUWAWA', x: 880, y: 270 },
  { t: 'SAKPONBA', x: 640, y: 692, size: 15 },
  { t: 'UPPER SAKPONBA', x: 772, y: 752, size: 13 },
  { t: 'THIRD EAST', x: 676, y: 568, size: 11, rot: 76 },
  { t: 'SAPELE RD', x: 470, y: 880 },
  { t: 'AIRPORT RD', x: 255, y: 762, size: 13 },
  { t: 'SILUKO', x: 300, y: 380 },
  { t: 'EKENWAN', x: 175, y: 560, size: 15 },
  { t: 'OLUKU', x: 300, y: 78, size: 15 },
];

/* ------------------------------------------------------------------ */
/* Pins: short labels, label tier (1 = landmark), preferred side        */
/* ------------------------------------------------------------------ */

export type LabelSide = 'b' | 'r' | 'l' | 't';

export const PIN_META: Record<string, { short: string; tier: 1 | 2; side?: LabelSide }> = {
  national_museum: { short: 'National Museum', tier: 1, side: 'b' },
  oba_market: { short: 'Oba Market', tier: 1, side: 'l' },
  ring_road_pos: { short: 'Ring Rd PoS', tier: 2, side: 'l' },
  oba_palace: { short: "Oba's Palace", tier: 1, side: 'b' },
  igun_street: { short: 'Igun Street', tier: 2, side: 'r' },
  mama_osas_buka: { short: 'Mama Osas Buka', tier: 2, side: 'l' },
  new_benin_market: { short: 'New Benin Mkt', tier: 1, side: 't' },
  new_benin_pos: { short: 'New Benin PoS', tier: 2, side: 'r' },
  mercy_clinic: { short: 'Mercy Clinic', tier: 2, side: 'l' },
  mission_rd_flats: { short: 'Mission Rd Flats', tier: 2, side: 'l' },
  uselu_market: { short: 'Uselu Market', tier: 1, side: 'r' },
  fresh_cut_salon: { short: 'Fresh Cut Salon', tier: 2, side: 'r' },
  uselu_park: { short: 'Uselu Park', tier: 2, side: 'b' },
  uniben: { short: 'UNIBEN', tier: 1, side: 'r' },
  ubth: { short: 'UBTH', tier: 1, side: 'r' },
  back_gate_joint: { short: 'Back Gate Joint', tier: 2, side: 'l' },
  wifi_joint: { short: 'Wi-Fi Joint', tier: 2, side: 'l' },
  oluku_park: { short: 'Oluku Park', tier: 1, side: 'r' },
  ramat_park: { short: 'Ramat Park', tier: 1, side: 'r' },
  oregbeni_market: { short: 'Oregbeni Mkt', tier: 1, side: 'r' },
  aduwawa_park: { short: 'Aduwawa Park', tier: 1, side: 't' },
  aduwawa_room: { short: 'Aduwawa Room', tier: 2, side: 'b' },
  third_east: { short: 'Third East', tier: 2, side: 'r' },
  ekiosa_market: { short: 'Ekiosa Market', tier: 1, side: 'r' },
  baba_shrine: { short: 'Baba Osagie', tier: 2, side: 'r' },
  upper_sakponba: { short: 'Upper Sakponba', tier: 2, side: 'r' },
  santana_market: { short: 'Santana Mkt', tier: 1, side: 'l' },
  sapele_pos: { short: 'Sapele Rd PoS', tier: 2, side: 'b' },
  bronze_lounge: { short: 'Bronze Lounge', tier: 2, side: 'r' },
  police_hq: { short: 'Police HQ', tier: 1, side: 'r' },
  bronze_bank: { short: 'Bronze Bank', tier: 1, side: 'l' },
  gra_duplex: { short: 'GRA Duplex', tier: 2, side: 'b' },
  kingdom_lounge: { short: 'Kingdom Lounge', tier: 2, side: 'l' },
  benin_airport: { short: 'Benin Airport', tier: 1, side: 'l' },
  siluko_rd: { short: 'Siluko Road', tier: 2, side: 'r' },
  ekenwan_room: { short: 'Ekenwan Room', tier: 2, side: 'l' },
  iguobazuwa_farm: { short: 'Iguobazuwa Farm', tier: 1, side: 'r' },
  bronze_tech_hub: { short: 'Tech Hub', tier: 1, side: 'r' },
  uniben_hostel: { short: 'UNIBEN Hostel', tier: 2, side: 'r' },
  uselu_selfcon: { short: 'Uselu Self-con', tier: 2, side: 'l' },
  // L2 landmarks (docs/LANDMARKS.md): the big ones label from far away, the clubs/dealers when zoomed in
  emotan_statue: { short: 'Emotan Statue', tier: 2, side: 'r' },
  kada_plaza: { short: 'Kada Plaza', tier: 2, side: 'r' },
  benin_city_mall: { short: 'Benin City Mall', tier: 1, side: 'r' },
  mama_ebo: { short: 'Mama Ebo', tier: 2, side: 'l' },
  protea_hotel: { short: 'Protea Hotel', tier: 2, side: 'b' },
  golden_tulip: { short: 'Golden Tulip', tier: 2, side: 'l' },
  ogba_zoo: { short: 'Ogba Zoo', tier: 1, side: 'b' },
  ogbemudia_stadium: { short: 'Ogbe Stadium', tier: 1, side: 'l' },
  club_360: { short: '360 Signature', tier: 2, side: 'b' },
  club_de_medici: { short: 'Club De Medici', tier: 2, side: 'l' },
  rome_club: { short: 'Rome Night Club', tier: 2, side: 'l' },
  cube_nightlife: { short: 'Cube Nightlife', tier: 2, side: 'l' },
  versus_lounge: { short: 'Versus Lounge', tier: 2, side: 'l' },
  owambe_republic: { short: 'Owambe Republic', tier: 2, side: 'r' },
  ighodalo_cars: { short: 'Ighodalo Cars', tier: 2, side: 'l' },
  sdd_motors: { short: 'SDD Motors', tier: 2, side: 'r' },
  tokunbo_lot: { short: 'Tokunbo Lot', tier: 2, side: 'r' },
};

export function shortName(id: string, name: string): string {
  const m = PIN_META[id];
  if (m) return m.short;
  const cut = name.replace(/\s*\(.*\)\s*$/, '');
  return cut.length > 18 ? cut.slice(0, 17) + '…' : cut;
}

/** Night danger zones: only the approved ones (Upper Sakponba 1.65, Third East 1.5) cross 1.4.
 *  Shared by the 2D map, the 3D city and the risk labels. */
export const isNightRisky = (l: { risk: number; night_risk_mult: number }) => l.risk * l.night_risk_mult >= 1.4;
