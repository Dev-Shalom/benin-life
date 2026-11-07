// Pure 2D geometry in map space for the city layout and for scripts/city-check.mjs (no three.js).
import type { Pt } from '../../map/mapGeo';

/** Corners of an oriented rectangle (centre, size along / across, yaw), in map space. */
export function rectCorners(x: number, y: number, w: number, d: number, a: number): Pt[] {
  const c = Math.cos(a);
  const s = Math.sin(a);
  const hw = w / 2;
  const hd = d / 2;
  return [
    [x - hw * c + hd * s, y - hw * s - hd * c],
    [x + hw * c + hd * s, y + hw * s - hd * c],
    [x + hw * c - hd * s, y + hw * s + hd * c],
    [x - hw * c - hd * s, y - hw * s + hd * c],
  ];
}

export function pointInPoly(x: number, y: number, poly: readonly Pt[]): boolean {
  let inside = false;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    const [xi, yi] = poly[i];
    const [xj, yj] = poly[j];
    if (yi > y !== yj > y && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) inside = !inside;
  }
  return inside;
}

export function polyBox(poly: readonly Pt[]): [number, number, number, number] {
  let a = Infinity, b = Infinity, c = -Infinity, d = -Infinity;
  for (const [x, y] of poly) {
    if (x < a) a = x;
    if (y < b) b = y;
    if (x > c) c = x;
    if (y > d) d = y;
  }
  return [a, b, c, d];
}

/** Distance from a point to a segment. */
export function segDist(px: number, py: number, ax: number, ay: number, bx: number, by: number): number {
  const dx = bx - ax;
  const dy = by - ay;
  const l2 = dx * dx + dy * dy;
  const t = l2 > 0 ? Math.max(0, Math.min(1, ((px - ax) * dx + (py - ay) * dy) / l2)) : 0;
  return Math.hypot(px - (ax + t * dx), py - (ay + t * dy));
}

/** Points along a polygon outline (every `step` units, corners included). */
export function outline(poly: readonly Pt[], step = 1): Pt[] {
  const out: Pt[] = [];
  for (let i = 0; i < poly.length; i++) {
    const a = poly[i];
    const b = poly[(i + 1) % poly.length];
    const n = Math.max(1, Math.ceil(Math.hypot(b[0] - a[0], b[1] - a[1]) / step));
    for (let k = 0; k < n; k++) out.push([a[0] + ((b[0] - a[0]) * k) / n, a[1] + ((b[1] - a[1]) * k) / n]);
  }
  return out;
}

/** Points covering a polygon: its outline plus an interior grid (so a thin road across a small footprint is still seen). */
export function cover(poly: readonly Pt[], step = 1.2): Pt[] {
  const pts = outline(poly, step);
  const [x0, y0, x1, y1] = polyBox(poly);
  for (let y = y0 + step / 2; y < y1; y += step * 1.5) for (let x = x0 + step / 2; x < x1; x += step * 1.5) if (pointInPoly(x, y, poly)) pts.push([x, y]);
  return pts;
}

function cross(ax: number, ay: number, bx: number, by: number, cx: number, cy: number) {
  return (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
}
function segCross(a: Pt, b: Pt, c: Pt, d: Pt, eps: number) {
  const d1 = cross(a[0], a[1], b[0], b[1], c[0], c[1]);
  const d2 = cross(a[0], a[1], b[0], b[1], d[0], d[1]);
  const d3 = cross(c[0], c[1], d[0], d[1], a[0], a[1]);
  const d4 = cross(c[0], c[1], d[0], d[1], b[0], b[1]);
  return ((d1 > eps && d2 < -eps) || (d1 < -eps && d2 > eps)) && ((d3 > eps && d4 < -eps) || (d3 < -eps && d4 > eps));
}

/** Distance from a point to a polygon's boundary. */
export function boundaryDist(x: number, y: number, poly: readonly Pt[]): number {
  let m = Infinity;
  for (let i = 0; i < poly.length; i++) {
    const a = poly[i];
    const b = poly[(i + 1) % poly.length];
    m = Math.min(m, segDist(x, y, a[0], a[1], b[0], b[1]));
  }
  return m;
}

/**
 * Do two simple polygons overlap by more than touching? True when an edge pair properly crosses, or one has a vertex
 * clearly inside the other. Shared walls and corners touching do not count.
 */
export function polysOverlap(p: readonly Pt[], q: readonly Pt[], eps = 1e-6): boolean {
  const bp = polyBox(p);
  const bq = polyBox(q);
  if (bp[2] <= bq[0] || bq[2] <= bp[0] || bp[3] <= bq[1] || bq[3] <= bp[1]) return false;
  for (let i = 0; i < p.length; i++) {
    const a = p[i];
    const b = p[(i + 1) % p.length];
    for (let j = 0; j < q.length; j++) if (segCross(a, b, q[j], q[(j + 1) % q.length], eps)) return true;
  }
  const inside = (pts: readonly Pt[], poly: readonly Pt[]) => {
    for (const [x, y] of pts) if (pointInPoly(x, y, poly) && boundaryDist(x, y, poly) > 0.02) return true;
    return false;
  };
  return inside(p, q) || inside(q, p);
}

/** Deepest penetration estimate of two overlapping polygons (largest depth of a vertex of one inside the other). */
export function overlapDepth(p: readonly Pt[], q: readonly Pt[]): number {
  let best = 0;
  const run = (pts: readonly Pt[], poly: readonly Pt[]) => {
    for (const [x, y] of pts) if (pointInPoly(x, y, poly)) best = Math.max(best, boundaryDist(x, y, poly));
  };
  run(p, q);
  run(q, p);
  return best;
}

export function polyArea(poly: readonly Pt[]): number {
  let s = 0;
  for (let i = 0; i < poly.length; i++) {
    const a = poly[i];
    const b = poly[(i + 1) % poly.length];
    s += a[0] * b[1] - b[0] * a[1];
  }
  return Math.abs(s) / 2;
}

/** Uniform spatial index of polygons by bounding box. */
export class PolyIndex<T> {
  private cells = new Map<number, number[]>();
  readonly items: { poly: readonly Pt[]; box: [number, number, number, number]; data: T }[] = [];
  private cell: number;
  constructor(cell = 24) {
    this.cell = cell;
  }
  private key(i: number, j: number) {
    return (i + 500) * 4096 + (j + 500);
  }
  add(poly: readonly Pt[], data: T): number {
    const box = polyBox(poly);
    const id = this.items.push({ poly, box, data }) - 1;
    for (let j = Math.floor(box[1] / this.cell); j <= Math.floor(box[3] / this.cell); j++)
      for (let i = Math.floor(box[0] / this.cell); i <= Math.floor(box[2] / this.cell); i++) {
        const k = this.key(i, j);
        const arr = this.cells.get(k);
        if (arr) arr.push(id);
        else this.cells.set(k, [id]);
      }
    return id;
  }
  /** ids whose box touches the query box */
  query(x0: number, y0: number, x1: number, y1: number): number[] {
    const out = new Set<number>();
    for (let j = Math.floor(y0 / this.cell); j <= Math.floor(y1 / this.cell); j++)
      for (let i = Math.floor(x0 / this.cell); i <= Math.floor(x1 / this.cell); i++) {
        const arr = this.cells.get(this.key(i, j));
        if (arr) for (const id of arr) out.add(id);
      }
    return [...out].filter((id) => {
      const b = this.items[id].box;
      return !(b[2] < x0 || b[0] > x1 || b[3] < y0 || b[1] > y1);
    });
  }
}
