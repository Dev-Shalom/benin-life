// P1 "people walk around" (docs/PLACES.md "P1 wandering"). Pure TypeScript, no three.js: one agent per drawn
// person, all on the place's one M1 nav grid, moved with the same locomotion as the Sim (eased speed, turn on
// the spot, eased final facing). Each agent pauses (doing its role motion), then walks somewhere that fits its
// role, then pauses again: roamers visit spots in their zone or a nearby one, dancers shuffle on the floor,
// bouncers / traders / cashiers take a few steps around their spot and come back, the waiter goes between
// the bar and the tables, the DJ and the hype man stay behind the booth, seated people stay seated.
// Deterministic per person (seeded by id) with staggered timers, so the room never looks chaotic. NPCs are
// never in the grid: the player's Sim is never blocked; NPCs wait for each other / the Sim (a simple
// separation check) and pick another spot if they wait too long.
import type { PlaceZone } from '../../../api/places';
import { freeAt, planPath, type NavGrid, type P2 } from '../../sim/nav';
import { makeWalker, stepWalker, type Gait, type Walker } from '../../sim/locomotion';
import { frontDir, propMeta, zoneSpot, type NpcPlan, type Room, type WanderKind } from '../model';

export interface Agent {
  id: string;
  kind: WanderKind;
  w: Walker;
  gaitCfg: Gait;
  /** 'pause' = standing (role motion), 'walk' = on a path. */
  mode: 'pause' | 'walk';
  /** Seconds (scene clock) when the pause ends. */
  until: number;
  home: P2;
  homeYaw: number;
  zone: string | null;
  /** Walk cycle phase (cycles) and blend weight 0..1 (0 = role motion, 1 = full walk). */
  phase: number;
  gait: number;
  /** Seconds spent blocked by someone in the way. */
  wait: number;
  /** Alternates for 'stay' (step out, come back) and 'waiter' (bar, table). */
  leg: number;
  /** Metres moved in the last step (drives the walk cycle). */
  moved: number;
  rnd: () => number;
}

function hash(s: string): number {
  let h = 2166136261;
  for (let i = 0; i < s.length; i++) h = Math.imul(h ^ s.charCodeAt(i), 16777619);
  return h >>> 0;
}
function rng(seed: number) {
  let s = seed % 2147483647 || 1;
  return () => (s = (s * 16807) % 2147483647) / 2147483647;
}

const CRUISE: Record<WanderKind, number> = { fixed: 0, seat: 0, stay: 0.95, dance: 0.55, waiter: 1.25, roam: 1.05 };
/** Pause lengths [min, max] seconds by kind. */
const PAUSE: Record<WanderKind, [number, number]> = { fixed: [1e9, 1e9], seat: [1e9, 1e9], stay: [7, 16], dance: [3, 7], waiter: [4, 8], roam: [6, 15] };

export function makeAgents(crowd: NpcPlan[], t0: number): Agent[] {
  return crowd.map((p) => {
    const r = rng(hash(p.id));
    const kind: WanderKind = p.wander ?? (p.seated ? 'seat' : 'roam');
    const cruise = CRUISE[kind] * (0.9 + r() * 0.2);
    const w = makeWalker(p.p, p.yaw);
    const [a, b] = PAUSE[kind];
    return {
      id: p.id, kind, w, gaitCfg: { cruise, brake: 1.6, turnRate: 4 }, mode: 'pause',
      // staggered: the first walks start 2-10 s after walking in, never all at once
      until: t0 + (a > 1e8 ? 1e9 : 2 + r() * 8 + r() * (b - a) * 0.3),
      home: [p.p[0], p.p[1]], homeYaw: p.yaw, zone: p.zone ?? null,
      phase: r(), gait: 0, wait: 0, leg: 0, moved: 0, rnd: r,
    } as Agent;
  });
}

export interface WanderCtx {
  grid: NavGrid;
  room: Room;
  zones: PlaceZone[];
  zoneByKey: Map<string, PlaceZone>;
  /** The player's Sim (NPCs give way). */
  sim: P2;
  /** Path plans allowed this frame (spreads A* over frames). */
  budget: number;
}

const inRoom = (room: Room, p: P2) => p[0] > 0.45 && p[1] > 0.45 && p[0] < room.W - 0.45 && p[1] < room.D - 0.45;

/** A free standing spot in / at a zone (inside walk-on zones, along the front of solid ones). */
function spotIn(z: PlaceZone, room: Room, grid: NavGrid, r: () => number): { p: P2; yaw: number } | null {
  const m = propMeta(z.prop);
  for (let k = 0; k < 8; k++) {
    let p: P2;
    let yaw: number;
    if (m.spot === 'centre') {
      p = [z.x + (r() - 0.5) * z.w * 0.75, z.z + (r() - 0.5) * z.d * 0.75];
      yaw = Math.PI + (r() - 0.5) * 1.6;
    } else {
      const s = zoneSpot(z, room);
      const [dx, dz] = frontDir(z.rot);
      const side = (r() - 0.5) * (dx !== 0 ? z.d : z.w) * 0.85;
      const out = 0.1 + r() * 0.5;
      p = [s.p[0] + (dx === 0 ? side : dx * out), s.p[1] + (dz === 0 ? side : dz * out)];
      yaw = s.yaw + (r() - 0.5) * 0.7;
    }
    if (inRoom(room, p) && freeAt(grid, p)) return { p, yaw };
  }
  return null;
}

/** Pick where an agent goes next (null = stay paused a bit longer). */
function pickTarget(a: Agent, ctx: WanderCtx): { p: P2; yaw: number } | null {
  const { room, grid, zones, zoneByKey } = ctx;
  const r = a.rnd;
  const own = a.zone ? zoneByKey.get(a.zone) ?? null : null;
  switch (a.kind) {
    case 'dance': {
      const z = own ?? zones.find((zz) => propMeta(zz.prop).pose === 'dance');
      if (!z) return null;
      // a short shuffle: within ~1.4 m, inside the floor
      for (let k = 0; k < 6; k++) {
        const p: P2 = [a.w.pos[0] + (r() - 0.5) * 2.4, a.w.pos[1] + (r() - 0.5) * 2.4];
        if (Math.abs(p[0] - z.x) < z.w / 2 - 0.3 && Math.abs(p[1] - z.z) < z.d / 2 - 0.3 && freeAt(grid, p)) return { p, yaw: r() * Math.PI * 2 };
      }
      return null;
    }
    case 'stay': {
      a.leg++;
      if (a.leg % 2 === 0) return { p: [a.home[0], a.home[1]], yaw: a.homeYaw };
      for (let k = 0; k < 6; k++) {
        const ang = r() * Math.PI * 2;
        const d = 0.5 + r() * 0.8;
        const p: P2 = [a.home[0] + Math.cos(ang) * d, a.home[1] + Math.sin(ang) * d];
        if (inRoom(room, p) && freeAt(grid, p)) return { p, yaw: a.homeYaw + (r() - 0.5) * 1.2 };
      }
      return null;
    }
    case 'waiter': {
      a.leg++;
      if (a.leg % 2 === 0) {
        const bar = own ?? zones.find((z) => z.prop === 'bar' || z.prop === 'counter');
        return bar ? spotIn(bar, room, grid, r) ?? { p: [a.home[0], a.home[1]], yaw: a.homeYaw } : { p: [a.home[0], a.home[1]], yaw: a.homeYaw };
      }
      const tables = zones.filter((z) => z.prop === 'tables' || z.prop === 'vip' || z.prop === 'seats');
      const t = tables.length ? tables[Math.floor(r() * tables.length)] : null;
      if (!t) return null;
      // stand at the edge of the tables, facing them
      const s = spotIn(t, room, grid, r);
      return s;
    }
    case 'roam': {
      // mostly their own zone, sometimes a nearby one (closest few by distance)
      let z = own;
      if (!z || r() < 0.4) {
        const near = zones
          .filter((zz) => zz.prop !== 'restroom')
          .map((zz) => ({ zz, d: Math.hypot(zz.x - a.w.pos[0], zz.z - a.w.pos[1]) }))
          .sort((x, y) => x.d - y.d)
          .slice(0, 4);
        if (near.length) z = near[Math.floor(r() * near.length)].zz;
      }
      return z ? spotIn(z, room, grid, r) : null;
    }
    default:
      return null;
  }
}

/** Advance every agent by dt (scene seconds) at time t. Allocation-light; returns how many are walking. */
export function stepAgents(agents: Agent[], dt: number, t: number, ctx: WanderCtx, reduced: boolean): number {
  let walking = 0;
  for (let i = 0; i < agents.length; i++) {
    const a = agents[i];
    a.moved = 0;
    if (a.kind === 'fixed' || a.kind === 'seat') continue;
    if (a.mode === 'pause') {
      a.gait = Math.max(0, a.gait - dt * 4);
      if (reduced || t < a.until) continue;
      if (ctx.budget <= 0) continue; // plan next frame
      const tgt = pickTarget(a, ctx);
      const [mn, mx] = PAUSE[a.kind];
      if (!tgt || Math.hypot(tgt.p[0] - a.w.pos[0], tgt.p[1] - a.w.pos[1]) < 0.25) {
        a.until = t + mn * 0.5 + a.rnd() * (mx - mn) * 0.5;
        continue;
      }
      ctx.budget--;
      const plan = planPath(ctx.grid, a.w.pos, tgt.p, { snapEnd: true, round: 0.2 });
      if (plan.points.length < 2 || plan.length > 14) {
        a.until = t + 2 + a.rnd() * 3;
        continue;
      }
      a.w.path = plan.points;
      a.w.seg = 1;
      a.w.faceTo = tgt.yaw;
      a.mode = 'walk';
      a.wait = 0;
    }
    // walking: give way to someone close in front (another person or the Sim)
    let blocked = false;
    const seg = a.w.seg < a.w.path.length ? a.w.path[a.w.seg] : null;
    if (seg) {
      const hx = Math.sin(a.w.yaw);
      const hz = Math.cos(a.w.yaw);
      const check = (px: number, pz: number, r: number) => {
        const dx = px - a.w.pos[0];
        const dz = pz - a.w.pos[1];
        const d = Math.hypot(dx, dz);
        return d < r && d > 1e-3 && (dx * hx + dz * hz) / d > 0.35;
      };
      if (check(ctx.sim[0], ctx.sim[1], 0.8)) blocked = true;
      else
        for (let j = 0; j < agents.length && !blocked; j++) {
          if (j === i) continue;
          const b = agents[j];
          // the one with the lower index has right of way when both walk (no dead-locks)
          if (b.mode === 'walk' && j > i) continue;
          if (check(b.w.pos[0], b.w.pos[1], 0.6)) blocked = true;
        }
    }
    if (blocked) {
      a.wait += dt;
      if (a.wait > 2.4) {
        // give up: stop here and think again in a moment
        a.w.path = [a.w.pos];
        a.w.seg = 1;
        a.w.faceTo = null;
      }
    } else a.wait = Math.max(0, a.wait - dt);
    const res = stepWalker(a.w, dt, a.gaitCfg, blocked ? 0 : 1);
    a.moved = res.moved;
    const gt = Math.max(Math.min(1, a.w.speed / Math.max(0.2, a.gaitCfg.cruise)), a.w.turning ? 0.3 : 0);
    a.gait += (gt - a.gait) * (1 - Math.exp(-dt * 8));
    if (res.arrived || (a.w.path.length === 0 && a.w.speed === 0)) {
      a.mode = 'pause';
      a.w.path = [];
      const [mn, mx] = PAUSE[a.kind];
      a.until = t + mn + a.rnd() * (mx - mn);
    } else walking++;
  }
  return walking;
}
