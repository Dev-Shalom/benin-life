// Free roam: pedestrians on the pavements (pure TypeScript). Walkers follow a road's pavement for a stretch, stop for a
// moment, turn round; sellers stand behind their market stalls; idlers wait near a door. All of them move through the
// same collision world as the player (they never enter a building) and wait for the player instead of pushing through.
import { at, rng } from '../map/mapGeo';
import { KERB } from '../city3d/engine/roadnet';
import type { CollisionWorld, DynCircle } from './collide';
import { districtAt } from '../drive3d/district';
import { inArea } from './area';
import type { RoamWorld } from './world';

export type PedKind = 'walker' | 'seller' | 'idler';

export interface Ped {
  id: number;
  kind: PedKind;
  x: number;
  y: number;
  /** Heading (map-space angle of the direction faced). */
  h: number;
  /** Metres moved in the last step (drives the walk cycle). */
  moved: number;
  /** Walk cycle phase and blend 0..1. */
  phase: number;
  gait: number;
  speed: number;
  v: number;
  // walkers
  road: number;
  s: number;
  dir: number;
  side: number;
  until: number;
  pause: number;
  wait: number;
  // sellers / idlers
  homeX: number;
  homeY: number;
  homeH: number;
  look: number;
  salt: number;
  /** Stall / door this seller or idler stands at (index into W.stalls / W.places), -1 none. */
  at: number;
}

/** How crowded the pavements are in a district (0..1): markets and the centre busy, GRA and the outskirts quiet. */
export const BUSY: Record<string, number> = { market: 1, core: 0.9, cramped: 0.7, campus: 0.55, res: 0.45, gra: 0.18, farm: 0.07 };

export interface CarObstacle {
  x: number;
  y: number;
  a: number;
  speed: number;
}

export class Peds {
  readonly list: Ped[] = [];
  readonly circles: DynCircle[] = [];
  private roads: number[] = [];
  private rnd: () => number;
  private W: RoamWorld;
  private t = 0;
  private around: { x: number; y: number } | null = null;
  private _p = { x: 0, y: 0 };

  constructor(W: RoamWorld, opt: { walkers: number; sellers: number; idlers: number; seed?: number; around?: { x: number; y: number } }) {
    this.W = W;
    this.around = opt.around ?? null;
    this.rnd = rng(opt.seed ?? 77);
    const L = W.L;
    // pavements worth walking: roads that run through the box for a good stretch
    this.roads = W.roadIdx.filter((ri) => {
      const r = L.roads[ri];
      if (r.kind === 'dirt' || r.kind === 'spur') return false;
      let inside = 0;
      for (const s of r.sp.samples) if (inArea(s.x, s.y, 4)) inside++;
      return inside > 6;
    });
    let id = 1;
    const push = (kind: PedKind): Ped => {
      const p: Ped = {
        id: id++, kind, x: 0, y: 0, h: 0, moved: 0, phase: this.rnd(), gait: 0, speed: 1.1 + this.rnd() * 0.35, v: 0,
        road: 0, s: 0, dir: 1, side: 1, until: 0, pause: 0, wait: 0, homeX: 0, homeY: 0, homeH: 0, look: id, salt: this.rnd() * 10, at: -1,
      };
      this.list.push(p);
      this.circles.push({ x: 0, y: 0, r: 0.3, id: p.id });
      return p;
    };
    for (let i = 0; i < opt.walkers && this.roads.length; i++) {
      const p = push('walker');
      this.spawnWalker(p);
    }
    const sellers = W.stalls.filter((s) => s.seller).sort((a, b) => this.around ? Math.hypot(a.x - this.around.x, a.y - this.around.y) - Math.hypot(b.x - this.around.x, b.y - this.around.y) : 0);
    for (let i = 0; i < Math.min(opt.sellers, sellers.length); i++) {
      const st = sellers[i];
      const p = push('seller');
      p.at = W.stalls.indexOf(st);
      p.homeX = st.x - st.fx * 0.95;
      p.homeY = st.y - st.fy * 0.95;
      p.homeH = Math.atan2(st.fy, st.fx);
      p.x = p.homeX; p.y = p.homeY; p.h = p.homeH;
    }
    const doors = W.places.filter((pl) => pl.door.kind === 'wall');
    for (let i = 0; i < Math.min(opt.idlers, doors.length); i++) {
      const d = doors[(i * 3 + 1) % doors.length].door;
      const p = push('idler');
      p.at = W.places.indexOf(doors[(i * 3 + 1) % doors.length]);
      // beside the door, not in front of it
      p.homeX = d.sx + d.ny * 3.6;
      p.homeY = d.sy - d.nx * 3.6;
      p.homeH = Math.atan2(-d.ny, -d.nx);
      if (!W.col.clear(p.homeX, p.homeY, 0.4, -1, false)) { p.homeX = d.sx - d.ny * 3.6; p.homeY = d.sy + d.nx * 3.6; }
      p.x = p.homeX; p.y = p.homeY; p.h = p.homeH;
    }
    this.syncCircles();
  }

  private spawnWalker(p: Ped) {
    const L = this.W.L;
    for (let tries = 0; tries < 40; tries++) {
      const ri = this.roads[Math.floor(this.rnd() * this.roads.length)];
      const r = L.roads[ri];
      const s = this.rnd() * r.sp.length;
      p.road = ri;
      p.s = s;
      p.dir = this.rnd() < 0.5 ? 1 : -1;
      p.side = this.rnd() < 0.5 ? 1 : -1;
      const q = this.offsetAt(p, s);
      // the first walkers appear round the player (10 to 55 m), the rest anywhere
      if (this.around && tries < 30 && this.list.indexOf(p) < 14) {
        const dd = Math.hypot(q[0] - this.around.x, q[1] - this.around.y);
        if (dd < 8 || dd > 55) continue;
      }
      if (!inArea(q[0], q[1], 3) || !this.W.col.clear(q[0], q[1], 0.35, -1, false)) continue;
      if (this.around && tries < 30 && this.list.indexOf(p) < 14 && this.rnd() > (BUSY[districtAt(q[0], q[1])] ?? 0.4) + 0.25) continue;
      p.x = q[0];
      p.y = q[1];
      p.until = 20 + this.rnd() * 50;
      p.h = Math.atan2(Math.sin(r.sp.samples[0].a) * p.dir, Math.cos(r.sp.samples[0].a) * p.dir);
      return;
    }
    p.x = 500; p.y = 560;
  }

  private offsetAt(p: Ped, s: number): [number, number] {
    const r = this.W.L.roads[p.road];
    const q = at(r.sp, Math.max(0, Math.min(r.sp.length, s)));
    const off = r.hw + (KERB[r.kind] ?? 0.8) * 0.55 + 0.1;
    return [q.x - Math.sin(q.a) * off * p.side, q.y + Math.cos(q.a) * off * p.side];
  }

  private syncCircles() {
    for (let i = 0; i < this.list.length; i++) {
      this.circles[i].x = this.list[i].x;
      this.circles[i].y = this.list[i].y;
    }
  }

  /** Pedestrians as circles for the cars to brake for. */
  people(out: { x: number; y: number; r: number }[]) {
    out.length = this.list.length;
    for (let i = 0; i < this.list.length; i++) {
      const o = out[i] ?? (out[i] = { x: 0, y: 0, r: 0.3 });
      o.x = this.list[i].x; o.y = this.list[i].y; o.r = 0.3;
    }
  }

  /**
   * Keep the crowd round the player in a city that is bigger than the screen: walkers that are far away reappear on a pavement near the
   * player (more where the district is busy, never in front of the camera close up), sellers and idlers move to a stall / door nearby.
   * Called a couple of times a second.
   */
  recycle(px: number, py: number, view: { dx: number; dy: number }) {
    const W = this.W;
    const L = W.L;
    this.recycleN++;
    for (const p of this.list) {
      const d2 = (p.x - px) ** 2 + (p.y - py) ** 2;
      if (p.kind === 'walker') {
        if (d2 < 110 * 110) continue;
        for (let tries = 0; tries < 36; tries++) {
          const ri = this.roads[Math.floor(this.rnd() * this.roads.length)];
          const r = L.roads[ri];
          // pick a point on the road, then test its distance to the player
          const s = this.rnd() * r.sp.length;
          p.road = ri;
          p.s = s;
          p.dir = this.rnd() < 0.5 ? 1 : -1;
          p.side = this.rnd() < 0.5 ? 1 : -1;
          const q = this.offsetAt(p, s);
          const dd = Math.hypot(q[0] - px, q[1] - py);
          if (dd < 28 || dd > 75) continue;
          const ahead = ((q[0] - px) * view.dx + (q[1] - py) * view.dy) / (dd || 1);
          if (dd < 50 && ahead > 0.3) continue;
          if (this.rnd() > (BUSY[districtAt(q[0], q[1])] ?? 0.4) + 0.1) continue;
          if (!inArea(q[0], q[1], 3) || !W.col.clear(q[0], q[1], 0.35, -1, false)) continue;
          p.x = q[0]; p.y = q[1]; p.until = this.t + 20 + this.rnd() * 50; p.pause = 0; p.wait = 0;
          p.h = Math.atan2(Math.sin(r.sp.samples[0].a) * p.dir, Math.cos(r.sp.samples[0].a) * p.dir);
          break;
        }
      } else if (d2 > 120 * 120) {
        // a seller / idler: a free stall or door within 20..70 m
        if (p.kind === 'seller') {
          const taken = new Set<number>();
          for (const q of this.list) if (q.kind === 'seller' && q.at >= 0) taken.add(q.at);
          let best = -1, bd = Infinity;
          for (let i = 0; i < W.stalls.length; i++) {
            const st = W.stalls[i];
            if (!st.seller || taken.has(i)) continue;
            const dd = Math.hypot(st.x - px, st.y - py);
            if (dd < 18 || dd > 90) continue;
            const ahead = ((st.x - px) * view.dx + (st.y - py) * view.dy) / (dd || 1);
            if (dd < 40 && ahead > 0.3) continue;
            if (dd < bd) { bd = dd; best = i; }
          }
          if (best >= 0) {
            const st = W.stalls[best];
            p.at = best;
            p.homeX = st.x - st.fx * 0.95; p.homeY = st.y - st.fy * 0.95; p.homeH = Math.atan2(st.fy, st.fx);
            p.x = p.homeX; p.y = p.homeY; p.h = p.homeH;
          }
        } else {
          const doors = W.places.filter((pl) => pl.door.kind === 'wall' && Math.hypot(pl.door.sx - px, pl.door.sy - py) > 25 && Math.hypot(pl.door.sx - px, pl.door.sy - py) < 80);
          if (doors.length) {
            const pl = doors[(this.recycleN * 7 + p.id) % doors.length];
            const d = pl.door;
            let hx = d.sx + d.ny * 3.6, hy = d.sy - d.nx * 3.6;
            if (!W.col.clear(hx, hy, 0.4, -1, false)) { hx = d.sx - d.ny * 3.6; hy = d.sy + d.nx * 3.6; }
            if (W.col.clear(hx, hy, 0.4, -1, false)) {
              p.at = W.places.indexOf(pl);
              p.homeX = hx; p.homeY = hy; p.homeH = Math.atan2(-d.ny, -d.nx);
              p.x = hx; p.y = hy; p.h = p.homeH;
            }
          }
        }
      }
    }
  }
  private recycleN = 0;

  step(dt: number, col: CollisionWorld, player: { x: number; y: number }, car?: CarObstacle | null) {
    this.t += dt;
    for (const p of this.list) {
      p.moved = 0;
      // a car coming: step aside early, well before it is near (nobody is ever hit)
      if (car && car.speed > 1.2 && p.kind !== 'seller') {
        const wx = p.x - car.x, wy = p.y - car.y;
        if (Math.abs(wx) < 16 && Math.abs(wy) < 16) {
          const ch = Math.cos(car.a), sh = Math.sin(car.a);
          const lx = wx * ch + wy * sh, ly = -wx * sh + wy * ch;
          const reach = 4 + car.speed * 1.1;
          if (lx > -3 && lx < reach && Math.abs(ly) < 4.2) {
            const sg = ly >= 0 ? 1 : -1;
            const sp = Math.min(3.6, 1.6 + car.speed * 0.12) * dt;
            this._p.x = p.x;
            this._p.y = p.y;
            const m = col.move(this._p, -sh * sg * sp, ch * sg * sp, 0.28, p.id);
            p.x = this._p.x;
            p.y = this._p.y;
            p.moved = m;
            p.h = turnTo(p.h, Math.atan2(ch * sg, -sh * sg), 10 * dt);
            p.gait = Math.min(1, p.gait + dt * 6);
            p.pause = 0;
            continue;
          }
        }
      }
      if (p.kind !== 'walker') {
        // sellers and idlers stand; they turn to the player when he is close
        const dx = player.x - p.x, dy = player.y - p.y;
        const near = dx * dx + dy * dy < 36;
        const want = near ? Math.atan2(dy, dx) : p.homeH;
        p.h = turnTo(p.h, want, 3 * dt);
        p.gait = Math.max(0, p.gait - dt * 4);
        continue;
      }
      if (p.pause > 0) {
        p.pause -= dt;
        p.gait = Math.max(0, p.gait - dt * 4);
        continue;
      }
      const target = this.offsetAt(p, p.s + p.dir * 2.5);
      let dx = target[0] - p.x, dy = target[1] - p.y;
      const d = Math.hypot(dx, dy) || 1;
      dx /= d; dy /= d;
      // wait for the player in the way
      const px = player.x - p.x, py = player.y - p.y;
      const ahead = px * dx + py * dy;
      const blockedByPlayer = ahead > 0 && ahead < 1.6 && Math.abs(-px * dy + py * dx) < 0.9;
      if (blockedByPlayer) {
        p.wait += dt;
        p.gait = Math.max(0, p.gait - dt * 5);
        p.h = turnTo(p.h, Math.atan2(dy, dx), 6 * dt);
        if (p.wait > 3) { p.dir = -p.dir; p.wait = 0; }
        continue;
      }
      p.wait = 0;
      this._p.x = p.x;
      this._p.y = p.y;
      const sp = p.speed * dt;
      const moved = col.move(this._p, dx * sp, dy * sp, 0.28, p.id);
      p.x = this._p.x;
      p.y = this._p.y;
      p.moved = moved;
      p.h = turnTo(p.h, Math.atan2(dy, dx), 8 * dt);
      p.gait = Math.min(1, p.gait + dt * 4);
      if (moved < sp * 0.35) {
        // stuck on a tree / lamp / person: step round by turning back after a moment
        p.wait += dt;
        if (p.wait > 1.2) { p.dir = -p.dir; p.wait = 0; p.pause = 1 + this.rnd() * 2; }
      } else {
        p.s += p.dir * moved;
        const r = this.W.L.roads[p.road];
        if (p.s < 2 || p.s > r.sp.length - 2) p.dir = -p.dir;
      }
      if (!inArea(p.x, p.y, 2.5)) { p.dir = -p.dir; p.pause = 0.5; }
      if (this.t > p.until) {
        p.until = this.t + 20 + this.rnd() * 50;
        p.pause = 2 + this.rnd() * 5;
        if (this.rnd() < 0.6) p.dir = -p.dir;
      }
    }
    this.syncCircles();
    col.dynCircles = this.circles;
  }
}

function turnTo(h: number, want: number, k: number): number {
  let d = want - h;
  d = Math.atan2(Math.sin(d), Math.cos(d));
  return h + d * Math.min(1, k);
}
