// Procedural animation on the rig: idle (breathing, sway, a look around) and a walk cycle for the 3D home.
// Both are pure functions of time, so any number of characters can share one clock.
import type { Character } from './character';
import { restPose } from './character';
import { BONE_PARENT, bonePositions } from './body';

const ease = (t: number) => (t <= 0 ? 0 : t >= 1 ? 1 : t * t * (3 - 2 * t));
function rnd(i: number, salt: number) {
  const s = Math.sin(i * 12.9898 + salt * 78.233) * 43758.5453;
  return s - Math.floor(s);
}

/** Head yaw/pitch target that changes every few seconds, smoothly. */
function look(t: number, salt: number, range: number): [number, number] {
  const seg = 3.6;
  const i = Math.floor(t / seg);
  const k = ease((t - i * seg) / 0.9);
  const target = (j: number): [number, number] => {
    const r = rnd(j, salt);
    // mostly straight ahead, sometimes left or right
    const yaw = r < 0.4 ? 0 : (r < 0.7 ? -1 : 1) * range * (0.55 + 0.45 * rnd(j, salt + 3));
    const pitch = (rnd(j, salt + 7) - 0.5) * 0.12;
    return [yaw, pitch];
  };
  const a = target(i - 1);
  const b = target(i);
  return [a[0] + (b[0] - a[0]) * k, a[1] + (b[1] - a[1]) * k];
}

export function poseIdle(c: Character, t: number, salt = 0) {
  const { rig, dims: d } = c;
  restPose(rig, d);
  const br = Math.sin(t * 1.7 + salt);
  const sw = Math.sin(t * 0.55 + salt * 2);
  // breathing: the chest (and everything above it) rises a touch
  rig.chest.position.y = d.shoulderY - d.hipY + 0.0022 * br;
  rig.chest.rotation.x = -0.006 * br;
  // weight shift
  rig.body.rotation.z = 0.012 * sw;
  rig.body.position.x = 0.005 * sw;
  rig.thighL.rotation.z -= 0.012 * sw;
  rig.thighR.rotation.z -= 0.012 * sw;
  rig.chest.rotation.z = -0.008 * sw;
  // arms hang and drift
  rig.armL.rotation.z += 0.012 * Math.sin(t * 1.7 + 0.6 + salt);
  rig.armR.rotation.z -= 0.012 * Math.sin(t * 1.7 + 0.9 + salt);
  rig.armL.rotation.x = 0.02 * Math.sin(t * 0.8 + salt);
  rig.armR.rotation.x = -0.02 * Math.sin(t * 0.8 + 1 + salt);
  rig.foreL.rotation.x += 0.025 * Math.sin(t * 1.1 + salt);
  rig.foreR.rotation.x += 0.025 * Math.sin(t * 1.1 + 2 + salt);
  // look around
  const [yaw, pitch] = look(t, salt, c.longHair ? 0.22 : 0.42);
  rig.neck.rotation.set(pitch * 0.4, yaw * 0.35, 0);
  rig.head.rotation.set(pitch * 0.6, yaw * 0.65, -yaw * 0.04);
}

/** Walk cycle (in place). `speed` 1 = a normal stroll (about 1.8 steps a second). */
export function poseWalk(c: Character, t: number, speed = 1) {
  const { rig, dims: d } = c;
  restPose(rig, d);
  const k = c.stride;
  const w = t * Math.PI * 2 * (0.9 + (1 - k) * 0.5) * speed;
  const s = Math.sin(w);
  const amp = 0.42 * k;
  rig.thighL.rotation.x = -amp * s;
  rig.thighR.rotation.x = amp * s;
  rig.shinL.rotation.x = 0.75 * k * Math.max(0, Math.sin(w - 1.2));
  rig.shinR.rotation.x = 0.75 * k * Math.max(0, Math.sin(w + Math.PI - 1.2));
  rig.footL.rotation.x = -0.25 * Math.max(0, -Math.sin(w + 0.4));
  rig.footR.rotation.x = -0.25 * Math.max(0, Math.sin(w + 0.4));
  rig.armL.rotation.x = 0.38 * s;
  rig.armR.rotation.x = -0.38 * s;
  rig.armL.rotation.z = d.armOut * (k < 1 ? 1 : 0.6);
  rig.armR.rotation.z = -d.armOut * (k < 1 ? 1 : 0.6);
  rig.foreL.rotation.x = -0.25 - 0.15 * Math.max(0, s);
  rig.foreR.rotation.x = -0.25 - 0.15 * Math.max(0, -s);
  rig.body.position.y = d.hipY + 0.012 * Math.abs(Math.cos(w)) - 0.008;
  rig.body.rotation.y = 0.06 * s;
  rig.chest.rotation.y = -0.1 * s;
  rig.chest.rotation.x = 0.03;
  rig.head.rotation.set(-0.02, 0.04 * s, 0);
}

// ---------------------------------------------------------------------------------------------
// M1 "Sim life": a richer idle and a phase-driven walk for the 3D home (and later the L2 places),
// plus pose buffers to blend between any two poses. The two functions above stay as they are for
// the turntable and the cached portraits (changing them would change every cached image).

const BONES = ['body', 'chest', 'neck', 'head', 'armL', 'foreL', 'handL', 'armR', 'foreR', 'handR', 'thighL', 'shinL', 'footL', 'thighR', 'shinR', 'footR'] as const;
/** Floats per pose: position xyz + rotation xyz for each bone. */
export const POSE_SIZE = BONES.length * 6;
const bindPose = new WeakMap<Character, Float32Array>();

/** Copy the rig's bone transforms into `out` (POSE_SIZE floats). */
export function capturePose(c: Character, out: Float32Array = new Float32Array(POSE_SIZE)): Float32Array {
  let i = 0;
  for (const n of BONES) {
    const o = c.rig[n];
    out[i++] = o.position.x;
    out[i++] = o.position.y;
    out[i++] = o.position.z;
    out[i++] = o.rotation.x;
    out[i++] = o.rotation.y;
    out[i++] = o.rotation.z;
  }
  return out;
}

/** Write a pose buffer back into the rig. */
export function applyPose(c: Character, p: Float32Array) {
  let i = 0;
  for (const n of BONES) {
    const o = c.rig[n];
    o.position.set(p[i], p[i + 1], p[i + 2]);
    o.rotation.set(p[i + 3], p[i + 4], p[i + 5]);
    i += 6;
  }
}

/** out = a + (b - a)·t, angles the short way round. `out` may be `a` or `b`. */
export function mixPose(out: Float32Array, a: Float32Array, b: Float32Array, t: number): Float32Array {
  for (let i = 0; i < POSE_SIZE; i++) {
    const rot = i % 6 >= 3;
    const d = b[i] - a[i];
    out[i] = a[i] + (rot ? Math.atan2(Math.sin(d), Math.cos(d)) : d) * t;
  }
  return out;
}

/** Back to the bind pose (every bone at rest, no leftovers from the last pose), then restPose. */
export function resetRig(c: Character) {
  let bind = bindPose.get(c);
  if (!bind) {
    // the bind pose from the dims (not from the rig, which may already be posed)
    const pos = bonePositions(c.dims);
    bind = new Float32Array(POSE_SIZE);
    BONES.forEach((n, j) => {
      const par = BONE_PARENT[n];
      const pp = par ? pos[par] : [0, 0, 0];
      bind![j * 6] = pos[n][0] - pp[0];
      bind![j * 6 + 1] = pos[n][1] - pp[1];
      bind![j * 6 + 2] = pos[n][2] - pp[2];
    });
    bindPose.set(c, bind);
  }
  applyPose(c, bind);
  restPose(c.rig, c.dims);
}

export interface LifeOpts {
  /** 0..1: low energy / low mood. Slumped chest, head down, slower breathing and walk. */
  tired?: number;
  /** 0..1: good mood. Chest up, a small bounce. */
  happy?: number;
  /** prefers-reduced-motion: smaller idle motions, no fidgets. */
  reduced?: boolean;
  /** Seconds since the Sim last stood still. Fidgets and look-arounds fade in over ~1.5 s. */
  idleFor?: number;
}

const smooth = (a: number, b: number, x: number) => ease((x - a) / (b - a));

/** Weight shift: holds on one leg 4-9 s, then eases (1.1 s) to the other or back to centre. -1..1. */
function weightShift(t: number, salt: number): number {
  // variable-length segments from a hashed sequence
  const seg = (j: number) => 4 + 5 * rnd(j, salt + 11);
  const lean = (j: number) => {
    const r = rnd(j, salt + 13);
    return r < 0.2 ? 0 : (r < 0.6 ? -1 : 1) * (0.55 + 0.45 * rnd(j, salt + 17));
  };
  // find the segment containing t (segments average 6.5 s; start from a coarse guess)
  let j = Math.floor(t / 6.5) - 2;
  let at = j * 6.5;
  while (at + seg(j) < t) {
    at += seg(j);
    j++;
  }
  const k = ease((t - at) / 1.1);
  return lean(j - 1) + (lean(j) - lean(j - 1)) * k;
}

/** Fidget: every ~7-13 s a short gesture (1.6-2.4 s) eased in and out. kind -1 = none. */
function fidget(t: number, salt: number): { kind: number; k: number; u: number } {
  const slot = 9.5;
  const i = Math.floor(t / slot);
  const r = rnd(i, salt + 23);
  if (r < 0.25) return { kind: -1, k: 0, u: 0 }; // some slots stay calm
  const dur = 1.6 + 0.8 * rnd(i, salt + 29);
  const start = (slot - dur) * rnd(i, salt + 31);
  const u = (t - i * slot - start) / dur;
  if (u <= 0 || u >= 1) return { kind: -1, k: 0, u: 0 };
  const k = smooth(0, 0.25, u) * (1 - smooth(0.72, 1, u));
  return { kind: Math.floor(rnd(i, salt + 37) * 5), k, u };
}

/**
 * The home idle (M1): breathing every ~4 s (chest and shoulders rise), weight shifts from leg to
 * leg, look-arounds, small fidgets (scratch the head, check a hand, roll the shoulders, hands on
 * hips, tap a foot) and mood in the posture. A pure function of time, cheap (a few sin calls).
 */
export function poseLife(c: Character, t: number, salt = 0, o: LifeOpts = {}) {
  const { rig, dims: d } = c;
  resetRig(c);
  const m = o.reduced ? 0.45 : 1;
  const tired = Math.max(0, Math.min(1, o.tired ?? 0));
  const happy = Math.max(0, Math.min(1, o.happy ?? 0)) * (1 - tired);
  const settle = o.idleFor === undefined ? 1 : smooth(0.3, 1.8, o.idleFor);

  // ---- breathing (~4 s; slower and deeper when tired): chest lifts and opens, shoulders follow
  const period = 4 + tired * 0.9;
  const ph = ((t + salt * 3) / period) * Math.PI * 2;
  const br = Math.sin(ph) * 0.5 + 0.5 * Math.sin(ph) * Math.abs(Math.sin(ph)); // a softer exhale
  rig.chest.position.y = d.shoulderY - d.hipY + 0.0065 * br * m;
  rig.chest.rotation.x = -0.022 * br * m;
  rig.armL.rotation.z += 0.022 * br * m;
  rig.armR.rotation.z -= 0.022 * br * m;
  rig.neck.rotation.x = 0.012 * br * m;

  // ---- weight shift (contrapposto): hips slide over the standing leg, the other knee softens
  const ws = weightShift(t, salt) * m;
  const sw = Math.sin(t * 0.55 + salt * 2) * 0.25 * m; // a little drift on top
  const hip = ws + sw;
  rig.body.position.x = 0.016 * hip;
  rig.body.rotation.z = 0.03 * hip;
  rig.chest.rotation.z = -0.034 * hip;
  // keep the feet planted: undo the hip roll and the slide on the thighs
  rig.thighL.rotation.z -= 0.048 * hip;
  rig.thighR.rotation.z -= 0.048 * hip;
  // the free leg (the side the hips moved away from) bends a touch
  const free = Math.abs(ws);
  const bend = 0.09 * free;
  if (ws > 0) {
    rig.thighR.rotation.x = -bend * 0.6;
    rig.shinR.rotation.x = bend;
    rig.footR.rotation.x = -bend * 0.4;
  } else {
    rig.thighL.rotation.x = -bend * 0.6;
    rig.shinL.rotation.x = bend;
    rig.footL.rotation.x = -bend * 0.4;
  }
  rig.body.position.y = d.hipY - 0.004 * free;

  // ---- arms hang and drift
  rig.armL.rotation.x = 0.025 * Math.sin(t * 0.8 + salt) * m;
  rig.armR.rotation.x = -0.025 * Math.sin(t * 0.8 + 1 + salt) * m;
  rig.foreL.rotation.x += 0.03 * Math.sin(t * 1.1 + salt) * m;
  rig.foreR.rotation.x += 0.03 * Math.sin(t * 1.1 + 2 + salt) * m;

  // ---- look around (smaller with long hair, under reduced motion and right after walking)
  const [yaw, pitch] = look(t, salt, (c.longHair ? 0.24 : 0.48) * m * (0.35 + 0.65 * settle));
  rig.neck.rotation.y = yaw * 0.35;
  rig.neck.rotation.x += pitch * 0.4;
  rig.head.rotation.set(pitch * 0.6, yaw * 0.65, -yaw * 0.05);

  // ---- fidgets
  if (!o.reduced && settle > 0) {
    const f = fidget(t, salt);
    const k = f.k * settle;
    if (k > 0) {
      switch (f.kind) {
        case 0: // scratch the back of the head
          rig.armR.rotation.x -= 2.35 * k;
          rig.armR.rotation.z -= 0.55 * k;
          rig.foreR.rotation.x -= 1.55 * k + 0.12 * k * Math.sin(t * 18);
          rig.head.rotation.x += 0.12 * k;
          rig.head.rotation.z -= 0.08 * k;
          break;
        case 1: // look at the left hand (a watch, a phone)
          rig.armL.rotation.x -= 0.75 * k;
          rig.armL.rotation.y -= 0.35 * k;
          rig.foreL.rotation.x -= 1.25 * k;
          rig.head.rotation.x += 0.32 * k;
          rig.head.rotation.y = rig.head.rotation.y * (1 - k) + 0.22 * k;
          break;
        case 2: { // roll the shoulders
          const s = Math.sin(f.u * Math.PI * 4);
          rig.chest.rotation.x -= 0.06 * k * s;
          rig.chest.position.y += 0.012 * k * Math.max(0, s);
          rig.armL.rotation.z += 0.05 * k;
          rig.armR.rotation.z -= 0.05 * k;
          rig.head.rotation.z += 0.07 * k * Math.sin(f.u * Math.PI * 2);
          break;
        }
        case 3: // hands on hips
          rig.armL.rotation.z += 0.5 * k;
          rig.armR.rotation.z -= 0.5 * k;
          rig.armL.rotation.x += 0.15 * k;
          rig.armR.rotation.x += 0.15 * k;
          rig.foreL.rotation.x -= 1.15 * k;
          rig.foreR.rotation.x -= 1.15 * k;
          rig.foreL.rotation.y -= 0.6 * k;
          rig.foreR.rotation.y += 0.6 * k;
          rig.chest.rotation.x -= 0.03 * k;
          break;
        default: { // tap a foot (the free one)
          const tap = Math.max(0, Math.sin(t * 9)) * k;
          if (ws > 0) rig.footR.rotation.x -= 0.28 * tap;
          else rig.footL.rotation.x -= 0.28 * tap;
          rig.head.rotation.z += 0.03 * k * Math.sin(t * 4.5);
        }
      }
    }
  }

  // ---- mood in the posture
  if (tired > 0) {
    rig.chest.rotation.x += 0.11 * tired;
    rig.neck.rotation.x += 0.1 * tired;
    rig.head.rotation.x += 0.12 * tired;
    rig.armL.rotation.z -= d.armOut * 0.3 * tired;
    rig.armR.rotation.z += d.armOut * 0.3 * tired;
    rig.armL.rotation.x += 0.05 * tired;
    rig.armR.rotation.x += 0.05 * tired;
  }
  if (happy > 0) {
    const bounce = Math.pow(Math.max(0, Math.sin(t * Math.PI * 2 * 0.9 + salt)), 2);
    rig.body.position.y += 0.007 * happy * bounce * m;
    rig.footL.rotation.x += 0.05 * happy * bounce * m;
    rig.footR.rotation.x += 0.05 * happy * bounce * m;
    rig.chest.rotation.x -= 0.035 * happy;
    rig.head.rotation.x -= 0.05 * happy;
  }
}

/** Step length (m, world) of this character at gait weight w (0..1). */
export function stepLength(c: Character, w: number): number {
  const amp = 0.42 * c.stride * (0.35 + 0.65 * Math.max(0, Math.min(1, w)));
  return 2 * c.dims.hipY * c.dims.scale * Math.sin(amp);
}

/** Cruise speed that keeps the cadence natural for this stride (short steps in a wrapper walk slower). */
export function cruiseSpeed(c: Character, base = 1.15): number {
  return Math.min(base, stepLength(c, 1) * 2.25);
}

/**
 * Walk cycle driven by the gait phase (in cycles; one cycle = two steps). The scene advances the
 * phase by distance / (2 · stepLength), so the feet keep pace with the ground. `w` (0..1) is the
 * gait weight: short, soft steps while speeding up or slowing down. Legs and arms swing in
 * opposition, the hips bob (lowest when both feet are down) and sway over the standing leg, the
 * chest counter-twists, soles stay flat on the floor through the stance.
 */
export function poseGait(c: Character, phase: number, w = 1, o: LifeOpts = {}) {
  const { rig, dims: d } = c;
  resetRig(c);
  const k = c.stride;
  const ww = Math.max(0, Math.min(1, w));
  const tired = Math.max(0, Math.min(1, o.tired ?? 0));
  const happy = Math.max(0, Math.min(1, o.happy ?? 0)) * (1 - tired);
  const p = phase * Math.PI * 2;
  const s = Math.sin(p);
  const cp = Math.cos(p);
  const A = 0.42 * k * (0.35 + 0.65 * ww);
  // legs: left thigh forward while sin p > 0; a leg swings forward while its thigh angle grows
  rig.thighL.rotation.x = -A * s;
  rig.thighR.rotation.x = A * s;
  const swingL = Math.max(0, cp);
  const swingR = Math.max(0, -cp);
  const knee = (0.95 * k + 0.1) * (0.45 + 0.55 * ww);
  rig.shinL.rotation.x = knee * Math.pow(swingL, 1.4) + 0.05;
  rig.shinR.rotation.x = knee * Math.pow(swingR, 1.4) + 0.05;
  // soles flat while the foot is down, toes drop a little in the swing
  rig.footL.rotation.x = -(rig.thighL.rotation.x + rig.shinL.rotation.x) * (1 - 0.65 * swingL);
  rig.footR.rotation.x = -(rig.thighR.rotation.x + rig.shinR.rotation.x) * (1 - 0.65 * swingR);
  // hips: drop by the standing leg's angle (inverted pendulum), sway over the standing leg
  const drop = d.hipY * (1 - Math.cos(A * s)) + 0.006 * ww;
  rig.body.position.y = d.hipY - drop + (happy ? 0.008 * happy * Math.abs(s) * ww : 0);
  rig.body.position.x = -0.012 * ww * cp;
  rig.body.rotation.z = -0.022 * ww * cp; // the swing side's hip drops a touch
  rig.thighL.rotation.z += 0.022 * ww * cp + (0.012 * ww * cp) / d.hipY;
  rig.thighR.rotation.z += 0.022 * ww * cp + (0.012 * ww * cp) / d.hipY;
  rig.body.rotation.y = 0.07 * ww * s;
  // chest counter-twists and leans into the walk
  rig.chest.rotation.y = -0.11 * ww * s;
  rig.chest.rotation.z = 0.018 * ww * cp;
  rig.chest.rotation.x = 0.035 * ww + 0.1 * tired - 0.03 * happy;
  // arms: opposite to the legs, elbows bend more on the forward swing
  const armA = (0.3 + 0.12 * k) * ww * (1 - 0.35 * tired);
  rig.armL.rotation.x = armA * s;
  rig.armR.rotation.x = -armA * s;
  rig.armL.rotation.z = d.armOut * 0.85;
  rig.armR.rotation.z = -d.armOut * 0.85;
  rig.foreL.rotation.x = -0.2 - 0.3 * ww * Math.max(0, -s);
  rig.foreR.rotation.x = -0.2 - 0.3 * ww * Math.max(0, s);
  // head stays steady: undo most of the twist, a small nod with each step
  rig.neck.rotation.set(0.02 + 0.1 * tired, 0.06 * ww * s, 0);
  rig.head.rotation.set(-0.02 + 0.012 * ww * Math.abs(cp) + 0.08 * tired - 0.04 * happy, 0.04 * ww * s, 0);
}
