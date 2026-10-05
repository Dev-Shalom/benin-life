// Walking paths inside a home: a coarse occupancy grid built from walls and solid furniture,
// A* over it (8 neighbours, no corner cutting), then string-pulled into a few straight legs.
// Pure TypeScript (no three.js), cheap enough to rebuild whenever the layout changes.
import { KINDS, type FurnitureItem, type HomeLayout, type Seg } from './model';

export const CELL = 0.2;
/** Clearance from walls/furniture for the Sim's body. */
const PAD = 0.12;

export interface NavGrid {
  x0: number;
  z0: number;
  cols: number;
  rows: number;
  blocked: Uint8Array;
}

export type P2 = [number, number];

/** Rotated footprint rectangle [x0, z0, x1, z1] of a furniture piece in layout space. */
export function footprint(f: FurnitureItem): [number, number, number, number] {
  const k = KINDS[f.kind];
  const q = (((f.rot ?? 0) % 4) + 4) % 4;
  const w = q % 2 ? k.d : k.w;
  const d = q % 2 ? k.w : k.d;
  return [f.x - w / 2, f.z - d / 2, f.x + w / 2, f.z + d / 2];
}

/** Local [x, z] of a piece -> layout space (quarter-turn rotation around the piece centre). */
export function toLayout(f: FurnitureItem, lx: number, lz: number): P2 {
  const a = ((f.rot ?? 0) * Math.PI) / 2;
  const c = Math.cos(a);
  const s = Math.sin(a);
  return [f.x + lx * c + lz * s, f.z - lx * s + lz * c];
}

/** All wall segments (outer walls minus door gaps, plus partitions). */
export function wallSegments(L: HomeLayout): Seg[] {
  const segs: Seg[] = [[0, 0, L.w, 0], [0, 0, 0, L.d], ...L.partitions];
  const cut = (side: 's' | 'e', len: number): Seg[] => {
    const gaps = L.doors.filter((g) => g[0] === side).map((g) => [g[1], g[2]] as const).sort((a, b) => a[0] - b[0]);
    const out: Seg[] = [];
    let at = 0;
    for (const [a, b] of gaps) {
      if (a > at) out.push(side === 's' ? [at, L.d, a, L.d] : [L.w, at, L.w, a]);
      at = Math.max(at, b);
    }
    if (at < len) out.push(side === 's' ? [at, L.d, len, L.d] : [L.w, at, L.w, len]);
    return out;
  };
  return [...segs, ...cut('s', L.w), ...cut('e', L.d)];
}

export function buildGrid(L: HomeLayout): NavGrid {
  const [lx0, lz0, lx1, lz1] = L.lot;
  const cols = Math.ceil((lx1 - lx0) / CELL);
  const rows = Math.ceil((lz1 - lz0) / CELL);
  const blocked = new Uint8Array(cols * rows);
  const mark = (x0: number, z0: number, x1: number, z1: number) => {
    const c0 = Math.max(0, Math.floor((x0 - PAD - lx0) / CELL));
    const c1 = Math.min(cols - 1, Math.floor((x1 + PAD - lx0) / CELL));
    const r0 = Math.max(0, Math.floor((z0 - PAD - lz0) / CELL));
    const r1 = Math.min(rows - 1, Math.floor((z1 + PAD - lz0) / CELL));
    for (let r = r0; r <= r1; r++) for (let c = c0; c <= c1; c++) blocked[r * cols + c] = 1;
  };
  for (const [x1, z1, x2, z2] of wallSegments(L)) {
    mark(Math.min(x1, x2) - 0.04, Math.min(z1, z2) - 0.04, Math.max(x1, x2) + 0.04, Math.max(z1, z2) + 0.04);
  }
  for (const f of L.furniture) {
    if (!KINDS[f.kind].solid || (f.y ?? 0) > 0) continue;
    const [a, b, c, d] = footprint(f);
    mark(a, b, c, d);
  }
  // the lot border
  for (let c = 0; c < cols; c++) {
    blocked[c] = 1;
    blocked[(rows - 1) * cols + c] = 1;
  }
  for (let r = 0; r < rows; r++) {
    blocked[r * cols] = 1;
    blocked[r * cols + cols - 1] = 1;
  }
  return { x0: lx0, z0: lz0, cols, rows, blocked };
}

const cellOf = (g: NavGrid, p: P2): [number, number] => [
  Math.min(g.cols - 1, Math.max(0, Math.floor((p[0] - g.x0) / CELL))),
  Math.min(g.rows - 1, Math.max(0, Math.floor((p[1] - g.z0) / CELL))),
];
const centre = (g: NavGrid, c: number, r: number): P2 => [g.x0 + (c + 0.5) * CELL, g.z0 + (r + 0.5) * CELL];
const free = (g: NavGrid, c: number, r: number) => c >= 0 && r >= 0 && c < g.cols && r < g.rows && !g.blocked[r * g.cols + c];

/** Nearest free cell to a point (spiral search). */
function nearestFree(g: NavGrid, c: number, r: number): [number, number] | null {
  if (free(g, c, r)) return [c, r];
  for (let rad = 1; rad < 12; rad++) {
    for (let dr = -rad; dr <= rad; dr++)
      for (let dc = -rad; dc <= rad; dc++) {
        if (Math.max(Math.abs(dr), Math.abs(dc)) !== rad) continue;
        if (free(g, c + dc, r + dr)) return [c + dc, r + dr];
      }
  }
  return null;
}

/** Straight line between two points stays on free cells. */
export function clear(g: NavGrid, a: P2, b: P2): boolean {
  const len = Math.hypot(b[0] - a[0], b[1] - a[1]);
  const steps = Math.max(1, Math.ceil(len / (CELL * 0.4)));
  for (let i = 0; i <= steps; i++) {
    const t = i / steps;
    const [c, r] = cellOf(g, [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t]);
    if (!free(g, c, r)) return false;
  }
  return true;
}

/**
 * Path from `from` to `to` in layout space: [from, ...corners, to]. The end points may sit inside
 * furniture (a bed's spot), so the search starts/ends at the nearest free cells and the exact
 * points are added back. Returns a direct line when no path exists (never strands the Sim).
 */
export function findPath(g: NavGrid, from: P2, to: P2): P2[] {
  const s0 = cellOf(g, from);
  const t0 = cellOf(g, to);
  const s = nearestFree(g, s0[0], s0[1]);
  const t = nearestFree(g, t0[0], t0[1]);
  if (!s || !t) return [from, to];
  const N = g.cols * g.rows;
  const start = s[1] * g.cols + s[0];
  const goal = t[1] * g.cols + t[0];
  const gScore = new Float32Array(N).fill(Infinity);
  const came = new Int32Array(N).fill(-1);
  const closed = new Uint8Array(N);
  const open: number[] = [start];
  const fScore = new Float32Array(N).fill(Infinity);
  const h = (i: number) => {
    const dc = Math.abs((i % g.cols) - t[0]);
    const dr = Math.abs(Math.floor(i / g.cols) - t[1]);
    return Math.max(dc, dr) + 0.414 * Math.min(dc, dr);
  };
  gScore[start] = 0;
  fScore[start] = h(start);
  let found = start === goal;
  let guard = 0;
  while (open.length && !found && guard++ < N * 4) {
    let bi = 0;
    for (let i = 1; i < open.length; i++) if (fScore[open[i]] < fScore[open[bi]]) bi = i;
    const cur = open[bi];
    open.splice(bi, 1);
    if (cur === goal) {
      found = true;
      break;
    }
    closed[cur] = 1;
    const cc = cur % g.cols;
    const cr = Math.floor(cur / g.cols);
    for (let dr = -1; dr <= 1; dr++)
      for (let dc = -1; dc <= 1; dc++) {
        if (!dc && !dr) continue;
        const nc = cc + dc;
        const nr = cr + dr;
        if (!free(g, nc, nr)) continue;
        if (dc && dr && (!free(g, cc + dc, cr) || !free(g, cc, cr + dr))) continue; // no corner cutting
        const ni = nr * g.cols + nc;
        if (closed[ni]) continue;
        const tg = gScore[cur] + (dc && dr ? 1.414 : 1);
        if (tg < gScore[ni]) {
          gScore[ni] = tg;
          fScore[ni] = tg + h(ni);
          came[ni] = cur;
          if (!open.includes(ni)) open.push(ni);
        }
      }
  }
  if (!found) return [from, to];
  const cells: P2[] = [];
  for (let i = goal; i !== -1; i = came[i]) cells.push(centre(g, i % g.cols, Math.floor(i / g.cols)));
  cells.reverse();
  // string pulling
  const pts: P2[] = [from, ...cells, to];
  const out: P2[] = [pts[0]];
  let anchor = 0;
  for (let i = 2; i < pts.length; i++) {
    if (!clear(g, pts[anchor], pts[i])) {
      out.push(pts[i - 1]);
      anchor = i - 1;
    }
  }
  out.push(pts[pts.length - 1]);
  return out;
}

/** A random free point (for idle wandering). */
export function randomFree(g: NavGrid, rnd: () => number, inside?: [number, number, number, number]): P2 | null {
  for (let i = 0; i < 40; i++) {
    const [x0, z0, x1, z1] = inside ?? [g.x0, g.z0, g.x0 + g.cols * CELL, g.z0 + g.rows * CELL];
    const p: P2 = [x0 + rnd() * (x1 - x0), z0 + rnd() * (z1 - z0)];
    const [c, r] = cellOf(g, p);
    if (free(g, c, r) && free(g, c + 1, r) && free(g, c - 1, r) && free(g, c, r + 1) && free(g, c, r - 1)) return p;
  }
  return null;
}
