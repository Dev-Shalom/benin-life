// Exact road clearance queries in map space (pure; shared by the layout generator and scripts/city-check.mjs).
// A road is a centre line (spline samples) with a carriageway half-width `hw` and, on paved roads, a kerb / pavement
// strip `KERB[kind]` drawn beside it (build.ts). Buildings, trees, lamps and parked cars must stay out of that paved band.
import type { Spline } from '../../map/mapGeo';
import { segDist } from './geom';

/** Width of the kerb / pavement strip drawn outside the carriageway (build.ts roads use this). */
export const KERB: Record<string, number> = { express: 1.4, main: 1.3, ring: 1.5, minor: 0.9, spur: 0.7, dirt: 0 };

export interface NetRoad {
  id: string;
  kind: string;
  sp: Spline;
  hw: number;
  closed: boolean;
}

interface Seg {
  ax: number;
  ay: number;
  bx: number;
  by: number;
  hw: number;
  pw: number; // hw + kerb
  ri: number;
}

export class RoadNet {
  private cells = new Map<number, Seg[]>();
  readonly segs: Seg[] = [];
  private cell = 16;
  constructor(roads: readonly NetRoad[]) {
    roads.forEach((r, ri) => this.addRoad(r, ri));
  }
  private key(i: number, j: number) {
    return (i + 200) * 1000 + (j + 200);
  }
  private addSeg(s: Seg) {
    this.segs.push(s);
    for (let j = Math.floor(Math.min(s.ay, s.by) / this.cell); j <= Math.floor(Math.max(s.ay, s.by) / this.cell); j++)
      for (let i = Math.floor(Math.min(s.ax, s.bx) / this.cell); i <= Math.floor(Math.max(s.ax, s.bx) / this.cell); i++) {
        const k = this.key(i, j);
        const arr = this.cells.get(k);
        if (arr) arr.push(s);
        else this.cells.set(k, [s]);
      }
  }
  /** Add one road (index `ri` in the caller's list). Roads that leave the map run straight on for 600 units (as drawn). */
  addRoad(r: NetRoad, ri: number) {
    const S = r.sp.samples;
    const pw = r.hw + (KERB[r.kind] ?? 0);
    for (let i = 1; i < S.length; i++) this.addSeg({ ax: S[i - 1].x, ay: S[i - 1].y, bx: S[i].x, by: S[i].y, hw: r.hw, pw, ri });
    if (!r.closed && r.kind !== 'spur') {
      for (const end of [0, 1]) {
        const p = end ? S[S.length - 1] : S[0];
        const q = end ? S[S.length - 2] : S[1];
        if (!q || (p.x > 0 && p.x < 1000 && p.y > 0 && p.y < 1000)) continue;
        const a = Math.atan2(p.y - q.y, p.x - q.x);
        let px = p.x;
        let py = p.y;
        for (let k = 0; k < 30; k++) {
          const nx = px + Math.cos(a) * 20;
          const ny = py + Math.sin(a) * 20;
          this.addSeg({ ax: px, ay: py, bx: nx, by: ny, hw: r.hw, pw, ri });
          px = nx;
          py = ny;
        }
      }
    }
  }
  /**
   * Smallest (distance to a centre line − half-width) over roads near (x, y): negative means the point is on a carriageway
   * (`paved = false`) or on the carriageway or its kerb strip (`paved = true`). Capped at `lim`. `ignore` skips one road index.
   */
  clear(x: number, y: number, paved: boolean, lim = 6, ignore = -1): number {
    let best = lim;
    const reach = Math.ceil((lim + 12) / this.cell);
    const cx = Math.floor(x / this.cell);
    const cy = Math.floor(y / this.cell);
    for (let j = cy - reach; j <= cy + reach; j++)
      for (let i = cx - reach; i <= cx + reach; i++) {
        const arr = this.cells.get(this.key(i, j));
        if (!arr) continue;
        for (const s of arr) {
          if (s.ri === ignore) continue;
          const e = segDist(x, y, s.ax, s.ay, s.bx, s.by) - (paved ? s.pw : s.hw);
          if (e < best) best = e;
        }
      }
    return best;
  }
}
