// Activity poses for the 3D home, on top of the avatar rig (see avatar3d/engine/anim.ts).
// The character root's origin is between the feet; +z is the way it faces.
import type { Character } from '../../avatar3d/engine/character';
import { restPose } from '../../avatar3d/engine/character';
import { poseIdle } from '../../avatar3d/engine/anim';

/** Seated: thighs forward, shins down, hands on the lap. Root must be lowered by `sitDrop`. */
export function poseSit(c: Character, t: number, salt = 0) {
  const { rig, dims: d } = c;
  poseIdle(c, t, salt);
  rig.body.rotation.set(0, 0, 0);
  rig.body.position.x = 0;
  rig.thighL.rotation.set(-1.5, 0, 0.06);
  rig.thighR.rotation.set(-1.5, 0, -0.06);
  rig.shinL.rotation.set(1.45, 0, 0);
  rig.shinR.rotation.set(1.45, 0, 0);
  rig.footL.rotation.set(0.05, 0.1, 0);
  rig.footR.rotation.set(0.05, -0.1, 0);
  rig.armL.rotation.set(-0.5, 0, d.armOut * 0.6);
  rig.armR.rotation.set(-0.5, 0, -d.armOut * 0.6);
  rig.foreL.rotation.set(-0.7, 0, 0);
  rig.foreR.rotation.set(-0.7, 0, 0);
}

/** How far the root drops (model units after scale) so the hips land on a seat at `seatY`. */
export function sitRootY(c: Character, seatY: number): number {
  return seatY - c.dims.hipY * c.dims.scale + 0.04;
}

/** Lying on the back, arms by the sides, slow breathing. The caller rotates the root -90° on x. */
export function poseLie(c: Character, t: number) {
  const { rig, dims: d } = c;
  restPose(rig, d);
  const br = Math.sin(t * 1.1);
  rig.chest.position.y = d.shoulderY - d.hipY + 0.003 * br;
  rig.armL.rotation.set(0.05, 0, d.armOut * 0.5);
  rig.armR.rotation.set(0.05, 0, -d.armOut * 0.5);
  rig.foreL.rotation.set(-0.3, 0, 0);
  rig.foreR.rotation.set(-0.3, 0, 0);
  rig.head.rotation.set(0.12, 0.25, 0);
  rig.neck.rotation.set(0.05, 0, 0);
  rig.footL.rotation.set(-0.4, 0.2, 0);
  rig.footR.rotation.set(-0.4, -0.2, 0);
}

/** Standing at the stove: one arm stirs, the other rests on the counter. */
export function poseCook(c: Character, t: number, salt = 0) {
  const { rig } = c;
  poseIdle(c, t, salt);
  const s = Math.sin(t * 4);
  rig.armR.rotation.set(-0.85 + 0.08 * s, 0.25 * Math.cos(t * 4), -0.25);
  rig.foreR.rotation.set(-1.0 + 0.1 * s, 0, 0);
  rig.armL.rotation.set(-0.55, 0, 0.18);
  rig.foreL.rotation.set(-0.8, 0, 0);
  rig.head.rotation.set(0.35, 0, 0);
  rig.neck.rotation.set(0.15, 0, 0);
}

/** Washing: arms scrub over the head and shoulders. */
export function poseScrub(c: Character, t: number, salt = 0) {
  const { rig } = c;
  poseIdle(c, t, salt);
  const s = Math.sin(t * 5);
  rig.armL.rotation.set(-2.3 + 0.2 * s, 0, 0.4);
  rig.armR.rotation.set(-1.4 - 0.25 * s, 0, -0.5);
  rig.foreL.rotation.set(-1.2, 0, 0);
  rig.foreR.rotation.set(-1.5 + 0.2 * s, 0, 0);
  rig.head.rotation.set(-0.15, 0.2 * s, 0);
}
