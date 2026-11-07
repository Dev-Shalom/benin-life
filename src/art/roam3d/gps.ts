// Free roam: the GPS line. A* over the world's walking grid with the carriageways closed except at crossings and junctions,
// so the route follows the pavements and crosses roads where people would; falls back to the plain grid when needed.
import { lineClear, pathLength, planPath, type P2 } from '../sim/nav';
import type { RoamWorld } from './world';

export interface GpsRoute {
  pts: P2[];
  length: number;
  reachable: boolean;
}

export function planRoute(W: RoamWorld, from: P2, to: P2): GpsRoute {
  let plan = planPath(W.gps, from, to, { round: 0 });
  if (!plan.reachable) plan = planPath(W.walk, from, to, { round: 0 });
  return { pts: plan.points, length: plan.length || pathLength(plan.points), reachable: plan.reachable };
}

/** Distance left along the route and the index of the segment the player is on. */
export function routeProgress(pts: readonly P2[], x: number, y: number): { left: number; seg: number; off: number } {
  let best = Infinity, seg = 0;
  for (let i = 0; i + 1 < pts.length; i++) {
    const a = pts[i], b = pts[i + 1];
    const dx = b[0] - a[0], dy = b[1] - a[1];
    const l2 = dx * dx + dy * dy || 1;
    const t = Math.max(0, Math.min(1, ((x - a[0]) * dx + (y - a[1]) * dy) / l2));
    const d = Math.hypot(x - (a[0] + dx * t), y - (a[1] + dy * t));
    if (d < best) { best = d; seg = i; }
  }
  let left = 0;
  if (pts.length > 1) {
    const a = pts[seg], b = pts[seg + 1];
    left += Math.hypot(b[0] - x, b[1] - y);
    for (let i = seg + 1; i + 1 < pts.length; i++) left += Math.hypot(pts[i + 1][0] - pts[i][0], pts[i + 1][1] - pts[i][1]);
    void a;
  }
  return { left, seg, off: best };
}

export { lineClear };
