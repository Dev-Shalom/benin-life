// Procedural animation on the rig: idle (breathing, sway, a look around) and a walk cycle for the 3D home.
// Both are pure functions of time, so any number of characters can share one clock.
import type { Character } from './character';
import { restPose } from './character';

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
