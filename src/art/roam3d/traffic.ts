// Free roam: the city's traffic at street scale (pure TypeScript). Same vehicles, lanes and speeds as the 3D city map
// (layout.vehicles on layout.roads, positions exactly like vehicleAt), but each car keeps its own travelled distance so
// it can brake: for the car ahead in its lane, for the player and for pedestrians in front of it. A car never moves
// into a spot that overlaps a person. Cars within reach of the player are published to the collision world as boxes.
import { at } from '../map/mapGeo';
import { VEHICLE_SIZE, type CityLayout, type Vehicle } from '../city3d/engine/layout';
import type { CollisionWorld, DynBox } from './collide';

export interface Car {
  id: number;
  kind: Vehicle['kind'] | 'okada';
  color: string;
  road: number;
  lane: number;
  s0: number;
  s1: number;
  s: number;
  /** Distance travelled along the lane (the sim state). */
  run: number;
  /** Current speed (m/s) and the speed the lane wants. */
  v: number;
  cruise: number;
  len: number;
  wid: number;
  x: number;
  y: number;
  a: number;
  /** 0..1 fade at the ends of a lane stretch (not solid below 0.95). */
  k: number;
  braking: boolean;
  /** Fraction of the cruise speed this car may use (traffic is a little uneven). */
  jam: boolean;
}

export interface Person {
  x: number;
  y: number;
  r: number;
}

const SPEED_SCALE = 0.8;
export const OKADA_SIZE: readonly [number, number] = [2.0, 0.8];
const EXTRA_COL = ['#d9a441', '#2e7d5b', '#c0392b', '#3d5f80', '#e8e4da', '#5a4a8a'];
const DECEL = 7.5;
const ACCEL = 3.2;
const wrap = (v: number, len: number) => ((v % len) + len) % len;
const _s = { x: 0, y: 0, a: 0, s: 0 };

export class Traffic {
  readonly cars: Car[] = [];
  private L: CityLayout;
  /** dynamic boxes handed to the collision world (reused objects). */
  private boxes: DynBox[] = [];

  constructor(L: CityLayout, box: [number, number, number, number]) {
    this.L = L;
    let id = 0;
    for (const v of L.vehicles) {
      if (v.px !== undefined) continue;
      const rd = L.roads[v.road];
      const len = v.s1 - v.s0;
      let touch = false;
      for (let k = 0; k <= 24 && !touch; k++) {
        const p = at(rd.sp, v.s0 + (k / 24) * len, _s);
        if (p.x > box[0] - 20 && p.x < box[2] + 20 && p.y > box[1] - 20 && p.y < box[3] + 20) touch = true;
      }
      if (!touch) continue;
      const [vl, vw] = VEHICLE_SIZE[v.kind];
      this.cars.push({
        id: id++, kind: v.kind, color: v.color, road: v.road, lane: v.lane, s0: v.s0, s1: v.s1, s: v.s, run: 0,
        v: v.speed * SPEED_SCALE, cruise: v.speed * SPEED_SCALE * (v.jam ? 0.7 : 1), len: vl, wid: vw, x: 0, y: 0, a: 0, k: 1, braking: false, jam: v.jam,
      });
    }
    this.densify(id);
    for (const c of this.cars) this.pose(c);
  }

  /** Busy streets: put extra kekes, okadas and cars into the gaps of each lane (only where the gap is wide enough). */
  private densify(first: number) {
    let id = first;
    const groups = new Map<string, Car[]>();
    for (const c of this.cars) {
      if (c.jam) continue;
      const k = c.road + ':' + c.lane;
      (groups.get(k) ?? groups.set(k, []).get(k)!).push(c);
    }
    const extras = ['keke', 'okada', 'car', 'okada', 'keke'] as const;
    let n = 0;
    for (const list of groups.values()) {
      const c0 = list[0];
      const len = c0.s1 - c0.s0;
      const pos = list.map((c) => ((c.s - c.s0) % len + len) % len).sort((a, b) => a - b);
      for (let i = 0; i < pos.length; i++) {
        const a = pos[i], b = i + 1 < pos.length ? pos[i + 1] : pos[0] + len;
        const gap = b - a;
        if (gap < 34) continue;
        const kind = extras[n++ % extras.length];
        const [vl, vw] = kind === 'okada' ? OKADA_SIZE : VEHICLE_SIZE[kind];
        this.cars.push({
          id: id++, kind, color: EXTRA_COL[n % EXTRA_COL.length], road: c0.road, lane: c0.lane, s0: c0.s0, s1: c0.s1,
          s: c0.s0 + ((a + gap / 2) % len), run: 0, v: c0.cruise, cruise: c0.cruise * (kind === 'okada' ? 1.1 : 0.95), len: vl, wid: vw,
          x: 0, y: 0, a: 0, k: 1, braking: false, jam: false,
        });
      }
    }
  }

  private pose(c: Car) {
    const rd = this.L.roads[c.road];
    const len = c.s1 - c.s0;
    const s = c.s0 + wrap(c.s - c.s0 + c.run * c.lane, len);
    const p = at(rd.sp, s, _s);
    const off = rd.hw * 0.48 * c.lane;
    c.x = p.x - Math.sin(p.a) * off;
    c.y = p.y + Math.cos(p.a) * off;
    c.a = p.a + (c.lane < 0 ? Math.PI : 0);
    const closed = rd.closed && !c.jam;
    const edge = Math.min(s - c.s0, c.s1 - s);
    c.k = closed ? 1 : Math.max(0.001, Math.min(1, edge / 4));
    return s;
  }

  /** Advance every car by dt. `people` = the player and pedestrians (circles). */
  step(dt: number, people: readonly Person[]) {
    const cars = this.cars;
    for (let i = 0; i < cars.length; i++) {
      const c = cars[i];
      let vmax = c.cruise;
      let braking = false;
      const ch = Math.cos(c.a), sh = Math.sin(c.a);
      // obstacles ahead: people, then the car in front in the same lane
      const look = c.v * c.v / (2 * DECEL) + 6;
      for (let j = 0; j < people.length; j++) {
        const p = people[j];
        const wx = p.x - c.x, wy = p.y - c.y;
        if (wx > look + 6 || wx < -look - 6 || wy > look + 6 || wy < -look - 6) continue;
        const lx = wx * ch + wy * sh;
        const ly = -wx * sh + wy * ch;
        if (lx < 0 || lx > look + c.len) continue;
        if (Math.abs(ly) > c.wid / 2 + p.r + 0.9) continue;
        const d = lx - c.len / 2 - p.r - 1.5;
        const vs = Math.sqrt(2 * DECEL * Math.max(0, d));
        if (vs < vmax) { vmax = vs; braking = true; }
      }
      for (let j = 0; j < cars.length; j++) {
        const o = cars[j];
        if (o === c || o.road !== c.road || o.lane !== c.lane) continue;
        const len = c.s1 - c.s0;
        const sc = wrap(c.s - c.s0 + c.run * c.lane, len);
        const so = wrap(o.s - o.s0 + o.run * o.lane, len);
        let ahead = (so - sc) * c.lane;
        ahead = wrap(ahead, len);
        const d = ahead - c.len / 2 - o.len / 2 - 2.2;
        if (ahead < look + 10) {
          const vs = Math.max(0, o.v) + Math.sqrt(2 * DECEL * Math.max(0, d));
          if (d < 0.2) { vmax = Math.min(vmax, 0); braking = true; }
          else if (vs < vmax) { vmax = vs; braking = true; }
        }
      }
      c.braking = braking;
      if (c.v > vmax) c.v = Math.max(vmax, c.v - DECEL * dt);
      else c.v = Math.min(vmax, c.v + ACCEL * dt);
      // never roll into a person this step
      const nx = c.v * dt;
      if (nx > 0) {
        let go = true;
        const steps = Math.ceil(nx / 0.1);
        for (let q = 1; q <= steps && go; q++) {
          const f = (q / steps) * nx;
          const fx = c.x + ch * f, fy = c.y + sh * f;
          for (let j = 0; j < people.length; j++) {
            const p = people[j];
            const wx = p.x - fx, wy = p.y - fy;
            if (wx > 6 || wx < -6 || wy > 6 || wy < -6) continue;
            const lx = wx * ch + wy * sh, ly = -wx * sh + wy * ch;
            if (Math.abs(lx) < c.len / 2 + p.r + 0.4 && Math.abs(ly) < c.wid / 2 + p.r + 0.3) { go = false; break; }
          }
        }
        if (!go) c.v = 0;
      }
      c.run += c.v * dt;
    }
    for (const c of cars) this.pose(c);
  }

  /** Publish the solid cars within `reach` m of (px, py) to the collision world. */
  publish(col: CollisionWorld, px: number, py: number, reach = 40) {
    let n = 0;
    for (const c of this.cars) {
      if (c.k < 0.95) continue;
      if (Math.abs(c.x - px) > reach || Math.abs(c.y - py) > reach) continue;
      let b = this.boxes[n];
      if (!b) b = this.boxes[n] = { x: 0, y: 0, hl: 0, hw: 0, a: 0, id: 0, v: 0 };
      b.x = c.x; b.y = c.y; b.hl = c.len / 2 + 0.05; b.hw = c.wid / 2 + 0.05; b.a = c.a; b.id = 10000 + c.id; b.v = c.v;
      n++;
    }
    this.boxes.length = n;
    col.dynBoxes = this.boxes;
  }
}
