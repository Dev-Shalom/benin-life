// Walking paths on a flat floor (M1): a coarse occupancy grid, A* over it (8 neighbours, no corner
// cutting, binary heap), string pulling (line of sight) and optional corner rounding.
// Pure TypeScript with no imports (no three.js, no game data), so the home, the L2 place interiors
// and the node check in scripts/nav-check.mjs all share it. Build the grid with makeGrid + block*.

export type P2 = [number, number];

export interface NavGrid {
  x0: number;
  z0: number;
  cols: number;
  rows: number;
  /** Cell size in metres. */
  cell: number;
  /** 1 = blocked. Row-major: index = row * cols + col. */
  blocked: Uint8Array;
}

export interface PathPlan {
  /** [from, ...corners, end]. Always starts at `from`. */
  points: P2[];
  /** The exact target (or its nearest free cell, for a target inside an obstacle) can be reached. */
  reachable: boolean;
  /** Where the path ends (the target, or the nearest reachable point to it). */
  end: P2;
  /** Path length in metres. */
  length: number;
}

/** A grid over [x0, z0, x1, z1] with its border cells blocked. */
export function makeGrid(bounds: [number, number, number, number], cell: number): NavGrid {
  const [x0, z0, x1, z1] = bounds;
  const cols = Math.max(3, Math.ceil((x1 - x0) / cell));
  const rows = Math.max(3, Math.ceil((z1 - z0) / cell));
  const blocked = new Uint8Array(cols * rows);
  for (let c = 0; c < cols; c++) {
    blocked[c] = 1;
    blocked[(rows - 1) * cols + c] = 1;
  }
  for (let r = 0; r < rows; r++) {
    blocked[r * cols] = 1;
    blocked[r * cols + cols - 1] = 1;
  }
  return { x0, z0, cols, rows, cell, blocked };
}

/** Block every cell touched by the rectangle grown by `pad`. */
export function blockRect(g: NavGrid, x0: number, z0: number, x1: number, z1: number, pad = 0) {
  const c0 = Math.max(0, Math.floor((Math.min(x0, x1) - pad - g.x0) / g.cell));
  const c1 = Math.min(g.cols - 1, Math.floor((Math.max(x0, x1) + pad - g.x0) / g.cell));
  const r0 = Math.max(0, Math.floor((Math.min(z0, z1) - pad - g.z0) / g.cell));
  const r1 = Math.min(g.rows - 1, Math.floor((Math.max(z0, z1) + pad - g.z0) / g.cell));
  for (let r = r0; r <= r1; r++) for (let c = c0; c <= c1; c++) g.blocked[r * g.cols + c] = 1;
}

/** Block an axis-aligned wall segment of half-thickness `half` (plus `pad`). */
export function blockSegment(g: NavGrid, seg: [number, number, number, number], half: number, pad = 0) {
  const [x1, z1, x2, z2] = seg;
  blockRect(g, Math.min(x1, x2) - half, Math.min(z1, z2) - half, Math.max(x1, x2) + half, Math.max(z1, z2) + half, pad);
}

export function cellOf(g: NavGrid, p: P2): [number, number] {
  return [
    Math.min(g.cols - 1, Math.max(0, Math.floor((p[0] - g.x0) / g.cell))),
    Math.min(g.rows - 1, Math.max(0, Math.floor((p[1] - g.z0) / g.cell))),
  ];
}

export function centreOf(g: NavGrid, c: number, r: number): P2 {
  return [g.x0 + (c + 0.5) * g.cell, g.z0 + (r + 0.5) * g.cell];
}

export function isFree(g: NavGrid, c: number, r: number): boolean {
  return c >= 0 && r >= 0 && c < g.cols && r < g.rows && !g.blocked[r * g.cols + c];
}

export function freeAt(g: NavGrid, p: P2): boolean {
  const [c, r] = cellOf(g, p);
  return isFree(g, c, r);
}

/** Nearest free cell to (c, r) within `maxRad` rings (square spiral), or null. */
export function nearestFree(g: NavGrid, c: number, r: number, maxRad = 14): [number, number] | null {
  if (isFree(g, c, r)) return [c, r];
  let best: [number, number] | null = null;
  let bestD = Infinity;
  for (let rad = 1; rad <= maxRad; rad++) {
    for (let dr = -rad; dr <= rad; dr++)
      for (let dc = -rad; dc <= rad; dc++) {
        if (Math.max(Math.abs(dr), Math.abs(dc)) !== rad) continue;
        if (!isFree(g, c + dc, r + dr)) continue;
        const d = dc * dc + dr * dr;
        if (d < bestD) {
          bestD = d;
          best = [c + dc, r + dr];
        }
      }
    if (best) return best; // closest on the first ring that has one (Euclidean within the ring)
  }
  return null;
}

/** The straight line a-b only crosses free cells. */
export function lineClear(g: NavGrid, a: P2, b: P2): boolean {
  const len = Math.hypot(b[0] - a[0], b[1] - a[1]);
  const steps = Math.max(1, Math.ceil(len / (g.cell * 0.4)));
  for (let i = 0; i <= steps; i++) {
    const t = i / steps;
    const [c, r] = cellOf(g, [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t]);
    if (!isFree(g, c, r)) return false;
  }
  return true;
}

export function pathLength(pts: P2[]): number {
  let len = 0;
  for (let i = 1; i < pts.length; i++) len += Math.hypot(pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1]);
  return len;
}

// ---- binary min-heap of cell indices keyed by f-score
class Heap {
  private a: number[] = [];
  private f: Float32Array;
  constructor(f: Float32Array) {
    this.f = f;
  }
  get size() {
    return this.a.length;
  }
  push(i: number) {
    const a = this.a;
    a.push(i);
    let k = a.length - 1;
    while (k > 0) {
      const p = (k - 1) >> 1;
      if (this.f[a[p]] <= this.f[a[k]]) break;
      [a[p], a[k]] = [a[k], a[p]];
      k = p;
    }
  }
  pop(): number {
    const a = this.a;
    const top = a[0];
    const last = a.pop()!;
    if (a.length) {
      a[0] = last;
      let k = 0;
      for (;;) {
        const l = 2 * k + 1;
        const r = l + 1;
        let m = k;
        if (l < a.length && this.f[a[l]] < this.f[a[m]]) m = l;
        if (r < a.length && this.f[a[r]] < this.f[a[m]]) m = r;
        if (m === k) break;
        [a[m], a[k]] = [a[k], a[m]];
        k = m;
      }
    }
    return top;
  }
}

export interface PlanOptions {
  /** Target inside an obstacle: true = stop at the nearest free cell (a floor tap on a table);
   * false = end exactly on the target (a furniture spot just inside the clearance pad). Default false. */
  snapEnd?: boolean;
  /** Round corners with this radius (m) where the rounded curve stays clear. Default 0 (off). */
  round?: number;
}

/**
 * Plan a path from `from` to `to`. The end points may sit inside the clearance pad (a bed's spot),
 * so the search starts/ends at the nearest free cells and the exact points are added back. When the
 * target cannot be reached (a closed pocket, outside the walls), the path ends at the reachable cell
 * closest to it: the Sim never walks through walls and is never stranded.
 */
export function planPath(g: NavGrid, from: P2, to: P2, opts: PlanOptions = {}): PathPlan {
  const s0 = cellOf(g, from);
  const t0 = cellOf(g, to);
  const s = nearestFree(g, s0[0], s0[1]);
  const targetFree = isFree(g, t0[0], t0[1]);
  const t = nearestFree(g, t0[0], t0[1]);
  if (!s) return { points: [from], reachable: false, end: from, length: 0 };
  const cols = g.cols;
  const N = cols * g.rows;
  const start = s[1] * cols + s[0];
  const goal = t ? t[1] * cols + t[0] : -1;
  const gScore = new Float32Array(N).fill(Infinity);
  const fScore = new Float32Array(N).fill(Infinity);
  const came = new Int32Array(N).fill(-1);
  const closed = new Uint8Array(N);
  const hx = t ? t[0] : t0[0];
  const hz = t ? t[1] : t0[1];
  const h = (i: number) => {
    const dc = Math.abs((i % cols) - hx);
    const dr = Math.abs(((i / cols) | 0) - hz);
    return Math.max(dc, dr) + 0.41421356 * Math.min(dc, dr);
  };
  const heap = new Heap(fScore);
  gScore[start] = 0;
  fScore[start] = h(start);
  heap.push(start);
  let found = false;
  while (heap.size) {
    const cur = heap.pop();
    if (closed[cur]) continue;
    if (cur === goal) {
      found = true;
      break;
    }
    closed[cur] = 1;
    const cc = cur % cols;
    const cr = (cur / cols) | 0;
    for (let dr = -1; dr <= 1; dr++)
      for (let dc = -1; dc <= 1; dc++) {
        if (!dc && !dr) continue;
        const nc = cc + dc;
        const nr = cr + dr;
        if (!isFree(g, nc, nr)) continue;
        if (dc && dr && (!isFree(g, cc + dc, cr) || !isFree(g, cc, cr + dr))) continue; // no corner cutting
        const ni = nr * cols + nc;
        if (closed[ni]) continue;
        const tg = gScore[cur] + (dc && dr ? 1.41421356 : 1);
        if (tg < gScore[ni]) {
          gScore[ni] = tg;
          fScore[ni] = tg + h(ni);
          came[ni] = cur;
          heap.push(ni);
        }
      }
  }
  let endCell = goal;
  let reachable = found;
  if (!found) {
    // the open set ran dry: every cell reachable from the start is closed. Take the one nearest the target.
    let best = start;
    let bestD = Infinity;
    for (let i = 0; i < N; i++) {
      if (!closed[i]) continue;
      const [x, z] = centreOf(g, i % cols, (i / cols) | 0);
      const d = (x - to[0]) ** 2 + (z - to[1]) ** 2;
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    endCell = best;
    reachable = false;
  }
  const cells: P2[] = [];
  for (let i = endCell; i !== -1; i = came[i]) cells.push(centreOf(g, i % cols, (i / cols) | 0));
  cells.reverse();
  // exact end: the target itself when reachable (and free, or the caller wants the exact spot)
  const end: P2 = reachable && (targetFree || !opts.snapEnd) ? [to[0], to[1]] : cells[cells.length - 1];
  const raw: P2[] = [from, ...cells];
  if (end !== cells[cells.length - 1]) raw.push(end);
  let points = stringPull(g, raw);
  if (opts.round && opts.round > 0) points = roundCorners(g, points, opts.round);
  return { points, reachable, end, length: pathLength(points) };
}

/** Compatibility wrapper: just the points. */
export function findPath(g: NavGrid, from: P2, to: P2, opts?: PlanOptions): P2[] {
  return planPath(g, from, to, opts).points;
}

/** Greedy line-of-sight smoothing: keep a corner only where the straight line would leave free space. */
export function stringPull(g: NavGrid, pts: P2[]): P2[] {
  if (pts.length <= 2) return pts.slice();
  const out: P2[] = [pts[0]];
  let anchor = 0;
  for (let i = 2; i < pts.length; i++) {
    if (!lineClear(g, pts[anchor], pts[i])) {
      out.push(pts[i - 1]);
      anchor = i - 1;
    }
  }
  out.push(pts[pts.length - 1]);
  // drop exact duplicates (an end point in the same place as the last cell)
  return out.filter((p, i) => i === 0 || Math.hypot(p[0] - out[i - 1][0], p[1] - out[i - 1][1]) > 1e-4);
}

/** Replace sharp corners by short quadratic curves (4 segments), only where the curve stays clear. */
export function roundCorners(g: NavGrid, pts: P2[], radius: number): P2[] {
  if (pts.length < 3) return pts.slice();
  const out: P2[] = [pts[0]];
  for (let i = 1; i < pts.length - 1; i++) {
    const a = out[out.length - 1];
    const b = pts[i];
    const c = pts[i + 1];
    const ab = Math.hypot(b[0] - a[0], b[1] - a[1]);
    const bc = Math.hypot(c[0] - b[0], c[1] - b[1]);
    const r = Math.min(radius, ab * 0.45, bc * 0.45);
    if (r < 0.04) {
      out.push(b);
      continue;
    }
    const p0: P2 = [b[0] + ((a[0] - b[0]) / ab) * r, b[1] + ((a[1] - b[1]) / ab) * r];
    const p2: P2 = [b[0] + ((c[0] - b[0]) / bc) * r, b[1] + ((c[1] - b[1]) / bc) * r];
    const curve: P2[] = [];
    for (let k = 0; k <= 4; k++) {
      const t = k / 4;
      const u = 1 - t;
      curve.push([u * u * p0[0] + 2 * u * t * b[0] + t * t * p2[0], u * u * p0[1] + 2 * u * t * b[1] + t * t * p2[1]]);
    }
    let ok = true;
    for (let k = 1; k < curve.length && ok; k++) ok = lineClear(g, curve[k - 1], curve[k]);
    if (ok) out.push(...curve);
    else out.push(b);
  }
  out.push(pts[pts.length - 1]);
  return out;
}

/** A random free point with free neighbours (for idle wandering). */
export function randomFree(g: NavGrid, rnd: () => number, inside?: [number, number, number, number]): P2 | null {
  for (let i = 0; i < 40; i++) {
    const [x0, z0, x1, z1] = inside ?? [g.x0, g.z0, g.x0 + g.cols * g.cell, g.z0 + g.rows * g.cell];
    const p: P2 = [x0 + rnd() * (x1 - x0), z0 + rnd() * (z1 - z0)];
    const [c, r] = cellOf(g, p);
    if (isFree(g, c, r) && isFree(g, c + 1, r) && isFree(g, c - 1, r) && isFree(g, c, r + 1) && isFree(g, c, r - 1)) return p;
  }
  return null;
}

/** ASCII dump (# blocked, . free, * path) for debugging and the node check. */
export function dump(g: NavGrid, path: P2[] = []): string {
  const mark = new Set<number>();
  for (let i = 1; i < path.length; i++) {
    const a = path[i - 1];
    const b = path[i];
    const n = Math.max(1, Math.ceil(Math.hypot(b[0] - a[0], b[1] - a[1]) / (g.cell * 0.5)));
    for (let k = 0; k <= n; k++) {
      const [c, r] = cellOf(g, [a[0] + ((b[0] - a[0]) * k) / n, a[1] + ((b[1] - a[1]) * k) / n]);
      mark.add(r * g.cols + c);
    }
  }
  let s = '';
  for (let r = 0; r < g.rows; r++) {
    for (let c = 0; c < g.cols; c++) {
      const i = r * g.cols + c;
      s += mark.has(i) ? (g.blocked[i] ? '!' : '*') : g.blocked[i] ? '#' : '.';
    }
    s += '\n';
  }
  return s;
}
