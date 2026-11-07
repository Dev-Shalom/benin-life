// Free roam: the player's body (pure TypeScript). Third-person style movement: the stick gives a wanted direction in map
// space, the body accelerates towards it, turns smoothly to face it and slides along whatever it meets.
import { PLAYER_R, SPEED } from './area';
import type { CollisionWorld } from './collide';

export interface PlayerState {
  x: number;
  y: number;
  /** Velocity (m/s). */
  vx: number;
  vy: number;
  /** Heading: map-space angle of the direction faced. */
  h: number;
  /** Speed (m/s) and metres moved this step. */
  speed: number;
  moved: number;
  /** Walk-cycle phase (cycles) and blend 0..1. */
  phase: number;
  gait: number;
  /** The last step pushed into something. */
  bumped: boolean;
}

export function makePlayer(x: number, y: number, h = 0): PlayerState {
  return { x, y, vx: 0, vy: 0, h, speed: 0, moved: 0, phase: 0, gait: 0, bumped: false };
}

const _pos = { x: 0, y: 0 };

/**
 * One fixed step. (wx, wy) is the wanted direction in map space, length 0..1 (the stick). `run` doubles the pace.
 * Returns the metres really moved.
 */
export function stepPlayer(P: PlayerState, col: CollisionWorld, dt: number, wx: number, wy: number, run: boolean): number {
  const mag = Math.min(1, Math.hypot(wx, wy));
  const top = run ? SPEED.run : SPEED.walk;
  // a light touch walks slowly, a full push goes to the walk (or run) pace
  const want = mag < 0.08 ? 0 : top * Math.min(1, 0.35 + mag * 0.75);
  const dirx = mag > 0.001 ? wx / Math.hypot(wx, wy) : 0;
  const diry = mag > 0.001 ? wy / Math.hypot(wx, wy) : 0;
  // turning: face the wanted direction; slow down when the turn is sharp
  let slow = 1;
  if (want > 0) {
    let d = Math.atan2(diry, dirx) - P.h;
    d = Math.atan2(Math.sin(d), Math.cos(d));
    const step = Math.sign(d) * Math.min(Math.abs(d), SPEED.turn * dt);
    P.h += step;
    slow = Math.max(0.25, 1 - Math.abs(d) / 2.4);
  }
  const tvx = want > 0 ? dirx * want * slow : 0;
  const tvy = want > 0 ? diry * want * slow : 0;
  const a = SPEED.accel * dt * (want > 0 ? 1 : 1.6);
  const dx = tvx - P.vx, dy = tvy - P.vy;
  const dl = Math.hypot(dx, dy);
  if (dl <= a) { P.vx = tvx; P.vy = tvy; } else { P.vx += (dx / dl) * a; P.vy += (dy / dl) * a; }
  _pos.x = P.x;
  _pos.y = P.y;
  const wantMove = Math.hypot(P.vx, P.vy) * dt;
  const moved = col.move(_pos, P.vx * dt, P.vy * dt, PLAYER_R);
  P.x = _pos.x;
  P.y = _pos.y;
  P.bumped = wantMove > 1e-4 && moved < wantMove * 0.6;
  // what the body really did is what the legs show (no running on the spot against a wall)
  const real = dt > 0 ? moved / dt : 0;
  const sp = Math.hypot(P.vx, P.vy);
  if (P.bumped && sp > 0) {
    const k = Math.min(1, real / sp);
    P.vx *= k;
    P.vy *= k;
  }
  P.speed = Math.hypot(P.vx, P.vy);
  P.moved = moved;
  if (P.speed > 0.25 && !(want > 0)) {
    // coasting to a stop: keep facing where we were going
  }
  P.gait = Math.max(0, Math.min(1, P.gait + (P.speed > 0.3 ? 1 : -1) * dt * 6));
  return moved;
}

/** Put the player back on valid ground (spawn, teleport to a door). */
export function placePlayer(P: PlayerState, col: CollisionWorld, x: number, y: number, h?: number) {
  P.x = x;
  P.y = y;
  P.vx = P.vy = P.speed = P.moved = 0;
  if (h !== undefined) P.h = h;
  _pos.x = x;
  _pos.y = y;
  col.resolve(_pos, PLAYER_R);
  P.x = _pos.x;
  P.y = _pos.y;
}
