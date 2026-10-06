// Locomotion for one walker (M1): follows a path with eased speed (spring-smoothed, slows for
// corners and the stop), turns in place before walking off when the heading is far off, and turns
// to a final facing on arrival. Pure TypeScript, no three.js: the scene reads `pos`, `yaw`,
// `speed` and the returned distance (to drive the gait phase, so the feet never slide).
import { pathLength, type P2 } from './nav';

export interface Walker {
  pos: P2;
  yaw: number;
  /** Current ground speed (m/s). */
  speed: number;
  /** Speed's own rate of change (the spring's velocity), so starts and stops ease in and out. */
  accel: number;
  path: P2[];
  /** Index of the next path point. */
  seg: number;
  /** Facing to turn to after the last point (radians), or null. */
  faceTo: number | null;
  /** Turning on the spot (before walking off, or to `faceTo`). */
  turning: boolean;
}

export interface Gait {
  /** Cruise speed (m/s). */
  cruise: number;
  /** Comfortable braking (m/s²): sets where the slow-down before the stop begins. */
  brake: number;
  /** Max turn rate (rad/s). */
  turnRate: number;
}

// M2: a brisk default walk (the home passes the admin-tunable sim.walk_speed; see anim.gaitFor)
export const DEFAULT_GAIT: Gait = { cruise: 1.9, brake: 2.2, turnRate: 5 };

export function makeWalker(pos: P2 = [0, 0], yaw = 0): Walker {
  return { pos: [pos[0], pos[1]], yaw, speed: 0, accel: 0, path: [], seg: 0, faceTo: null, turning: false };
}

/** Shortest signed angle from a to b. */
export function angleTo(a: number, b: number): number {
  const d = b - a;
  return Math.atan2(Math.sin(d), Math.cos(d));
}

/** Start following `path` (its first point is where the walker stands). Keeps the current speed, so
 * re-targeting mid-walk does not stop and restart. */
export function walkPath(w: Walker, path: P2[], faceTo: number | null = null) {
  w.path = path.length ? path : [w.pos];
  w.seg = 1;
  w.faceTo = faceTo;
}

/** Stand still here at once (the scene blends the pose). */
export function place(w: Walker, pos: P2, yaw: number) {
  w.pos = [pos[0], pos[1]];
  w.yaw = yaw;
  w.speed = 0;
  w.accel = 0;
  w.path = [];
  w.seg = 0;
  w.faceTo = null;
  w.turning = false;
}

/** Stop walking as soon as an eased stop allows (M2: a cancelled walk to a task). Keeps the speed, so
 * stepWalker bleeds it off over a few frames instead of freezing mid-stride. */
export function stopWalk(w: Walker) {
  w.path = [w.pos];
  w.seg = 1;
  w.faceTo = null;
  w.turning = false;
}

export function isMoving(w: Walker): boolean {
  return w.path.length > 0 || w.speed > 0.01;
}

/** Metres left on the path. */
export function remaining(w: Walker): number {
  if (w.seg >= w.path.length) return 0;
  return Math.hypot(w.path[w.seg][0] - w.pos[0], w.path[w.seg][1] - w.pos[1]) + pathLength(w.path.slice(w.seg));
}

export interface StepResult {
  /** Metres moved this step (drive the walk-cycle phase with it). */
  moved: number;
  /** Radians turned this step (drive the shuffle of a turn on the spot). */
  turned: number;
  /** True on the step the walker arrives (path done and final facing reached). */
  arrived: boolean;
}

const TURN_FIRST = 0.75; // rad (~43°): a heading further off than this turns on the spot before stepping off

/** Advance the walker by dt seconds. `speedScale` slows/hurries the gait (mood, a rushed action). */
export function stepWalker(w: Walker, dt: number, g: Gait = DEFAULT_GAIT, speedScale = 1): StepResult {
  const res: StepResult = { moved: 0, turned: 0, arrived: false };
  if (dt <= 0) return res;
  const cruise = g.cruise * speedScale;
  const onPath = w.seg < w.path.length;
  // skip points we are already on
  while (w.seg < w.path.length && Math.hypot(w.path[w.seg][0] - w.pos[0], w.path[w.seg][1] - w.pos[1]) < 1e-3) {
    w.pos = [w.path[w.seg][0], w.path[w.seg][1]];
    w.seg++;
  }

  let target = 0;
  let wantYaw: number | null = null;
  let rem = 0;
  if (w.seg < w.path.length) {
    const p = w.path[w.seg];
    const toX = p[0] - w.pos[0];
    const toZ = p[1] - w.pos[1];
    const toD = Math.hypot(toX, toZ);
    wantYaw = Math.atan2(toX, toZ);
    const err = Math.abs(angleTo(w.yaw, wantYaw));
    rem = remaining(w);
    // slow for the stop (v² = 2·a·d) ...
    target = Math.min(cruise, Math.sqrt(2 * g.brake * rem) + 0.05);
    // ... for the next corner (the sharper, the slower), planned ahead the same way ...
    if (w.seg < w.path.length - 1) {
      const q = w.path[w.seg + 1];
      const turn = Math.abs(angleTo(wantYaw, Math.atan2(q[0] - p[0], q[1] - p[1])));
      const vCorner = cruise * (1 - 0.5 * Math.min(1, turn / 1.4));
      target = Math.min(target, vCorner + Math.sqrt(2 * g.brake * Math.max(0, toD - w.speed * 0.3)));
    }
    // ... and while the body still faces off the path
    target *= 1 - 0.5 * Math.min(1, err / 1.4);
    // standing (or nearly) and facing well away: turn on the spot first (until nearly lined up)
    if (w.speed < 0.25 && err > TURN_FIRST) w.turning = true;
    else if (err < 0.3) w.turning = false;
    if (w.turning) target = 0;
  } else if (onPath || w.faceTo !== null) {
    wantYaw = w.faceTo;
    w.turning = wantYaw !== null && Math.abs(angleTo(w.yaw, wantYaw)) > 0.02;
  } else {
    w.turning = false;
  }

  // speed: critically damped spring towards the target (ease-in on start, ease-out on stop)
  const k = 30; // stiffness (ω ≈ 5.5/s)
  const c = 2 * Math.sqrt(k);
  w.accel += (k * (target - w.speed) - c * w.accel) * dt;
  w.speed = Math.max(0, w.speed + w.accel * dt);
  // never faster than a firm stop allows: lands on the last point at walking-stop speed
  if (w.seg < w.path.length) {
    const cap = Math.max(0.15, Math.sqrt(2 * g.brake * 1.25 * rem));
    if (w.speed > cap) {
      w.speed = cap;
      w.accel = Math.min(w.accel, 0);
    }
  }
  if (target === 0 && w.speed < 0.02) {
    w.speed = 0;
    w.accel = 0;
  }

  // heading: exponential ease towards the wanted yaw, capped by the turn rate (shortest way round)
  if (wantYaw !== null) {
    const d = angleTo(w.yaw, wantYaw);
    const rate = w.turning ? g.turnRate * 0.8 : g.turnRate;
    const stepYaw = Math.max(-rate * dt, Math.min(rate * dt, d * (1 - Math.exp(-dt * (w.turning ? 7 : 9)))));
    w.yaw += stepYaw;
    res.turned = Math.abs(stepYaw);
  }

  // move along the path
  let move = w.speed * dt;
  while (move > 0 && w.seg < w.path.length) {
    const p = w.path[w.seg];
    const dx = p[0] - w.pos[0];
    const dz = p[1] - w.pos[1];
    const dist = Math.hypot(dx, dz);
    if (dist <= move) {
      w.pos = [p[0], p[1]];
      move -= dist;
      res.moved += dist;
      w.seg++;
    } else {
      w.pos = [w.pos[0] + (dx / dist) * move, w.pos[1] + (dz / dist) * move];
      res.moved += move;
      move = 0;
    }
  }
  if (w.seg >= w.path.length && w.path.length) {
    // at the end: bleed off any speed left, then the final facing
    w.speed = Math.max(0, w.speed - 6 * dt);
    if (w.speed < 0.05) {
      w.speed = 0;
      w.accel = 0;
    }
    const facingDone = w.faceTo === null || Math.abs(angleTo(w.yaw, w.faceTo)) < 0.02;
    if (facingDone && w.speed === 0) {
      if (w.faceTo !== null) w.yaw = w.faceTo;
      w.path = [];
      w.seg = 0;
      w.faceTo = null;
      w.turning = false;
      res.arrived = true;
    }
  }
  return res;
}
