// Walking paths inside a home: a coarse occupancy grid built from walls and solid furniture.
// Pure TypeScript (no three.js), cheap enough to rebuild whenever the layout changes.
// The grid/A*/smoothing live in ../sim/nav.ts (shared with the L2 place interiors); this file
// only knows how a HomeLayout turns into obstacles.
import { KINDS, type FurnitureItem, type HomeLayout, type Seg } from './model';
import { blockRect, blockSegment, lineClear, makeGrid, planPath, randomFree, type NavGrid, type P2, type PathPlan, type PlanOptions } from '../sim/nav';

export const CELL = 0.2;
/** Clearance from walls/furniture for the Sim's body. */
const PAD = 0.12;

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
  const g = makeGrid(L.lot, CELL);
  for (const seg of wallSegments(L)) blockSegment(g, seg, 0.04, PAD);
  for (const f of L.furniture) {
    if (!KINDS[f.kind].solid || (f.y ?? 0) > 0) continue;
    const [a, b, c, d] = footprint(f);
    blockRect(g, a, b, c, d, PAD);
  }
  return g;
}

/** Straight line between two points stays on free cells. */
export const clear = lineClear;

/**
 * Path from `from` to `to` in layout space: [from, ...corners, to]. The end points may sit inside
 * furniture (a bed's spot), so the search starts/ends at the nearest free cells and the exact
 * points are added back. An unreachable target ends at the nearest reachable point (see sim/nav).
 */
export function findPath(g: NavGrid, from: P2, to: P2, opts?: PlanOptions): P2[] {
  return planPath(g, from, to, { round: 0.22, ...opts }).points;
}

export { planPath, randomFree, type NavGrid, type P2, type PathPlan, type PlanOptions };
