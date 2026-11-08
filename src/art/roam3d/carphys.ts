// Free roam: the player's own vehicle (pure TypeScript, no three.js). A kinematic bicycle model with the drive scene's feel (smooth
// speed, steering that tightens with speed, body roll and nose dip) and REAL collisions: the body is a set of circles along the car, moved in
// sub-steps of at most 7 cm (the smallest corner disc is 8 cm), pushed out of walls, poles, trunks, parked cars (statics) and other traffic (boxes). Pedestrians are a SOFT
// collider: the car is stopped 0.7 m before touching one (no damage, no contact), and they step aside long before that (peds.ts).
// Impacts are classified light / hard for the server's clamped damage report. scripts/roam-collide-check.mjs drives this at random.
import type { CollisionWorld, DynBox } from './collide';

export type CarKind = 'sedan' | 'suv' | 'pickup' | 'moto' | 'bike';

export interface CarSpec {
  len: number;
  wid: number;
  wheelbase: number;
  /** Top speed (m/s) forward / reverse. */
  vmax: number;
  vrev: number;
  /** Acceleration (m/s^2), brake and engine-brake deceleration. */
  accel: number;
  brake: number;
  /** Front wheel angle at a standstill (rad). */
  maxSteer: number;
}

export const CAR_SPECS: Record<CarKind, CarSpec> = {
  sedan: { len: 4.4, wid: 1.9, wheelbase: 2.7, vmax: 20, vrev: 4.5, accel: 4.6, brake: 9, maxSteer: 0.62 },
  suv: { len: 4.7, wid: 2.0, wheelbase: 2.9, vmax: 20.5, vrev: 4.5, accel: 4.2, brake: 9, maxSteer: 0.58 },
  pickup: { len: 5.1, wid: 2.0, wheelbase: 3.2, vmax: 19, vrev: 4.2, accel: 3.8, brake: 8.5, maxSteer: 0.55 },
  moto: { len: 2.2, wid: 0.8, wheelbase: 1.4, vmax: 22, vrev: 2.5, accel: 5.5, brake: 8, maxSteer: 0.7 },
  bike: { len: 1.8, wid: 0.6, wheelbase: 1.1, vmax: 6.5, vrev: 1.5, accel: 2.2, brake: 6, maxSteer: 0.75 },
};

export interface CarState {
  x: number;
  y: number;
  /** Heading (map-space angle of the nose). */
  h: number;
  /** Signed speed along the heading (m/s). */
  v: number;
  /** Front wheel angle (rad) and the yaw rate (rad/s). */
  steer: number;
  yaw: number;
  /** Visual body roll / nose dip (rad). */
  roll: number;
  pitch: number;
  /** Wheel spin phase (rad). */
  spin: number;
  /** Metres really covered since the last `takeDistance()`. */
  odo: number;
  /** Counts of hits since the last `takeHits()`. */
  light: number;
  hard: number;
  /** Last impact speed (m/s) and when (s of sim time) - the scene shakes the camera. */
  impact: number;
  impactAt: number;
  /** Stopped by a pedestrian's soft collider this step. */
  softStop: boolean;
  braking: boolean;
  reversing: boolean;
  offroad: boolean;
  t: number;
  /** The last hit of each class (cooldown). */
  lastLight: number;
  lastHard: number;
}

export interface CarInput {
  /** -1 left .. 1 right (as the stick: positive = right turn on screen). */
  steer: number;
  /** 0..1 */
  throttle: number;
  /** 0..1 */
  brake: number;
}

export interface CarEnv {
  /** The engine can run (fuel left and the car not wrecked). */
  engine: boolean;
  wet: boolean;
  /** Pedestrians (circles) - a soft collider. */
  people: readonly { x: number; y: number; r: number }[];
  /** Distance beyond the carriageway edge at a point (negative = on the road); null = unknown. */
  roadClear?: (x: number, y: number) => number;
}

export function makeCarState(x: number, y: number, h: number): CarState {
  return { x, y, h, v: 0, steer: 0, yaw: 0, roll: 0, pitch: 0, spin: 0, odo: 0, light: 0, hard: 0, impact: 0, impactAt: -9, softStop: false, braking: false, reversing: false, offroad: false, t: 0, lastLight: -9, lastHard: -9 };
}

interface Disc {
  u: number;
  v: number;
  r: number;
}
const discCache = new Map<string, Disc[]>();
/** The body as circles: big ones down the middle, small ones in the four corners (so a corner cannot poke into a pole). */
export function discsFor(spec: CarSpec): Disc[] {
  const key = `${spec.len}x${spec.wid}`;
  let d = discCache.get(key);
  if (d) return d;
  d = [];
  const R = spec.wid / 2;
  const span = spec.len - 2 * R;
  const n = Math.max(1, Math.ceil(span / (R * 1.1)) + 1);
  for (let i = 0; i < n; i++) d.push({ u: n === 1 ? 0 : -span / 2 + (span * i) / (n - 1), v: 0, r: R });
  const cr = R * 0.55;
  for (const su of [-1, 1]) for (const sv of [-1, 1]) d.push({ u: su * (spec.len / 2 - cr), v: sv * (R - cr), r: cr });
  // and a row of small ones along the nose and the tail (and in the exact corners), so the real corners of the box cannot poke into a wall
  const tr = Math.min(0.09, R * 0.3);
  const nEnd = Math.max(2, Math.ceil((2 * (R - tr)) / 0.15) + 1);
  for (const su of [-1, 1]) for (let k = 0; k < nEnd; k++) d.push({ u: su * (spec.len / 2 - tr), v: -(R - tr) + ((2 * (R - tr)) * k) / (nEnd - 1), r: tr });
  discCache.set(key, d);
  return d;
}

const STEP_M = 0.05;
const SOFT = 0.7;
const HIT_COOLDOWN = 0.8;

let _depth = 0;
let _px = 0;
let _py = 0;
let _kind = 0; // 0 static, 1 soft (pedestrian), 2 box (a car)

/** Deepest overlap of one disc with everything; leaves the push-out in _px/_py and the kind in _kind. */
function probeDisc(col: CollisionWorld, x: number, y: number, r: number, env: CarEnv, boxes: readonly DynBox[]): number {
  _depth = 0;
  _kind = 0;
  let d = col.probe(x, y, r);
  if (d > _depth) { _depth = d; _px = col.push.x; _py = col.push.y; _kind = 0; }
  // pedestrians: a soft margin
  const pp = env.people;
  for (let i = 0; i < pp.length; i++) {
    const p = pp[i];
    const vx = x - p.x, vy = y - p.y;
    const rr = r + p.r + SOFT;
    if (vx > rr || vx < -rr || vy > rr || vy < -rr) continue;
    const dd = Math.hypot(vx, vy);
    d = rr - dd;
    if (d > _depth) {
      _depth = d;
      const k = dd > 1e-6 ? (d + 0.002) / dd : 0;
      _px = dd > 1e-6 ? vx * k : d;
      _py = dd > 1e-6 ? vy * k : 0;
      _kind = 1;
    }
  }
  // other cars
  for (let i = 0; i < boxes.length; i++) {
    const b = boxes[i];
    const reach = b.hl + b.hw + r;
    if (x - b.x > reach || b.x - x > reach || y - b.y > reach || b.y - y > reach) continue;
    const c = Math.cos(b.a), s = Math.sin(b.a);
    const wx = x - b.x, wy = y - b.y;
    const lx = wx * c + wy * s, ly = -wx * s + wy * c;
    const qx = Math.max(-b.hl, Math.min(b.hl, lx)), qy = Math.max(-b.hw, Math.min(b.hw, ly));
    const vx = lx - qx, vy = ly - qy;
    const dd = Math.hypot(vx, vy);
    if (dd >= r) continue;
    let ux: number, uy: number;
    if (dd > 1e-6) { d = r - dd; ux = vx / dd; uy = vy / dd; }
    else {
      const ex = b.hl - Math.abs(lx), ey = b.hw - Math.abs(ly);
      if (ey <= ex) { ux = 0; uy = ly >= 0 ? 1 : -1; d = r + ey; } else { ux = lx >= 0 ? 1 : -1; uy = 0; d = r + ex; }
    }
    if (d > _depth) {
      _depth = d;
      _px = (ux * c - uy * s) * (d + 0.002);
      _py = (ux * s + uy * c) * (d + 0.002);
      _kind = 2;
    }
  }
  return _depth;
}

/** Deepest overlap of the whole body at a pose (used by spawn / get-in checks); true when clear of every static. */
export function bodyClear(col: CollisionWorld, spec: CarSpec, x: number, y: number, h: number, pad = 0): boolean {
  const c = Math.cos(h), s = Math.sin(h);
  for (const d of discsFor(spec)) {
    const px = x + d.u * c - d.v * s, py = y + d.u * s + d.v * c;
    if (col.probe(px, py, d.r + pad) > 0.003) return false;
  }
  return true;
}

/**
 * One fixed step. Returns the metres moved. The body can never end a step inside a static collider (it is pushed out in sub-steps).
 */
export function stepCar(c: CarState, spec: CarSpec, col: CollisionWorld, dt: number, inp: CarInput, env: CarEnv): number {
  c.t += dt;
  c.softStop = false;
  const wet = env.wet;
  // ---- longitudinal
  let a = 0;
  const speedAbs = Math.abs(c.v);
  const roadClear = env.roadClear ? env.roadClear(c.x, c.y) : 0;
  c.offroad = roadClear > 3.2;
  const vmaxHere = c.offroad ? spec.vmax * 0.55 : spec.vmax;
  c.braking = false;
  c.reversing = false;
  const thr = env.engine ? inp.throttle : 0;
  if (inp.brake > 0.05) {
    if (c.v > 0.4) { a = -spec.brake * inp.brake * (wet ? 0.85 : 1); c.braking = true; }
    else if (env.engine && inp.brake > 0.5) { a = -spec.accel * 0.55 * (1 + c.v / spec.vrev); c.reversing = true; }
    else if (c.v < -0.1) { a = spec.brake * 0.6; c.braking = true; }
    else c.v = 0;
  } else if (thr > 0.02) {
    if (c.v < -0.2) { a = spec.brake * 0.8; c.braking = true; }
    else a = thr * spec.accel * Math.max(0, 1 - (Math.max(0, c.v) / vmaxHere) ** 2);
  } else if (speedAbs > 0.05) {
    // engine braking / rolling resistance
    a = -Math.sign(c.v) * (0.9 + (c.offroad ? 2.2 : 0)) - c.v * 0.05;
  }
  if (c.offroad && c.v > vmaxHere) a -= 5;
  const v0 = c.v;
  c.v += a * dt;
  // do not reverse through zero when only braking / coasting
  if ((v0 > 0 && c.v < 0 && !c.reversing) || (v0 < 0 && c.v > 0 && thr < 0.02)) c.v = 0;
  if (c.v < -spec.vrev) c.v = -spec.vrev;
  // ---- steering: the wheel angle follows the stick, tighter at speed
  const lim = spec.maxSteer / (1 + (speedAbs / 9) ** 2) * (wet ? 0.88 : 1);
  const want = Math.max(-1, Math.min(1, inp.steer)) * lim;
  c.steer += (want - c.steer) * Math.min(1, dt * 9);
  const targetYaw = (c.v / spec.wheelbase) * Math.tan(c.steer);
  c.yaw += (targetYaw - c.yaw) * Math.min(1, dt * 7);
  const h0 = c.h;
  c.h += c.yaw * dt;
  // ---- move in sub-steps through the collision
  const dist = c.v * dt;
  const hx = Math.cos(c.h), hy = Math.sin(c.h);
  const n = Math.max(1, Math.ceil(Math.abs(dist) / STEP_M));
  const sx = (hx * dist) / n, sy = (hy * dist) / n;
  const x0 = c.x, y0 = c.y;
  const discs = discsFor(spec);
  const boxes = col.dynBoxes;
  let hitN = 0, hitX = 0, hitY = 0, hitKind = 0;
  for (let i = 0; i < n; i++) {
    const lx0 = c.x, ly0 = c.y;
    c.x += sx;
    c.y += sy;
    let resolved = false;
    for (let it = 0; it < 10; it++) {
      const ch = Math.cos(c.h), sh = Math.sin(c.h);
      let best = 0, bx = 0, by = 0, bk = 0;
      for (let k = 0; k < discs.length; k++) {
        const d = discs[k];
        const dep = probeDisc(col, c.x + d.u * ch - d.v * sh, c.y + d.u * sh + d.v * ch, d.r, env, boxes);
        if (dep > best) { best = dep; bx = _px; by = _py; bk = _kind; }
      }
      if (best <= 0.003) { resolved = true; break; }
      c.x += bx;
      c.y += by;
      hitN++;
      const l = Math.hypot(bx, by) || 1;
      hitX = bx / l;
      hitY = by / l;
      hitKind = bk;
    }
    if (!resolved) {
      // wedged between two things: stay where the last sub-step was valid and lose the speed
      c.x = lx0;
      c.y = ly0;
      c.h = h0;
      c.yaw = 0;
      hitN++;
      hitX = -Math.cos(c.h) * Math.sign(c.v || 1);
      hitY = -Math.sin(c.h) * Math.sign(c.v || 1);
      hitKind = 0;
      break;
    }
  }
  const moved = Math.hypot(c.x - x0, c.y - y0);
  // ---- what the impact does to the speed
  if (hitN > 0) {
    const vx = hx * c.v, vy = hy * c.v;
    const vn = vx * hitX + vy * hitY;
    if (vn < 0) {
      const imp = -vn;
      if (hitKind === 1) {
        // a pedestrian's soft margin: just stop, no bounce, no damage
        c.v -= (vx * hitX + vy * hitY) * (hx * hitX + hy * hitY);
        c.v *= 0.2;
        c.softStop = true;
      } else {
        const e = hitKind === 2 ? 0.1 : 0.22;
        const nvx = vx - (1 + e) * vn * hitX, nvy = vy - (1 + e) * vn * hitY;
        // keep sliding a little along the wall, scrub the speed
        c.v = (nvx * hx + nvy * hy) * 0.88;
        // the nose swings away from the wall a touch
        const side = hx * hitY - hy * hitX;
        c.h += Math.max(-0.06, Math.min(0.06, side * imp * 0.01)) * (c.v >= 0 ? 1 : -1);
        if (imp >= 1.6) {
          c.impact = imp;
          c.impactAt = c.t;
          if (imp >= 6.5) {
            if (c.t - c.lastHard > HIT_COOLDOWN) { c.hard++; c.lastHard = c.t; c.lastLight = c.t; }
          } else if (c.t - c.lastLight > HIT_COOLDOWN) { c.light++; c.lastLight = c.t; }
        }
      }
    }
  }
  c.odo += moved;
  // ---- visuals: roll into the turn, nose dips under braking
  const lat = c.yaw * c.v;
  c.roll += (Math.max(-0.07, Math.min(0.07, lat * 0.0065)) - c.roll) * Math.min(1, dt * 8);
  c.pitch += (Math.max(-0.05, Math.min(0.04, -a * 0.0045)) - c.pitch) * Math.min(1, dt * 7);
  c.spin += (moved / 0.34) * Math.sign(c.v || 1);
  return moved;
}

/** Take the distance driven and the hits counted since the last call (what the server checkpoint reports). */
export function takeReport(c: CarState): { dist: number; light: number; hard: number } {
  const r = { dist: c.odo, light: c.light, hard: c.hard };
  c.odo = 0;
  c.light = 0;
  c.hard = 0;
  return r;
}

/** Legal to leave the car here: not in the middle of the carriageway (within about a metre of its edge, or off the road). */
export function parkLegal(roadClear: number): boolean {
  return roadClear > -1.15;
}
