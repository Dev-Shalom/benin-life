// L3: what a nearby background person does with the full rig. All procedural, built on the M1 idle life
// (poseLife) and walk cycle (poseGait); a pure function of time + a per-person salt, so any number share a clock.
import type { NpcMotion } from '../../../api/places';
import { poseGait, poseLife, resetRig } from '../../avatar3d/engine/anim';
import type { Character } from '../../avatar3d/engine/character';
import { poseSit, sitRootY } from '../../home3d/engine/poses';

/** Poses `ch` for `motion` at time t. Returns the root lift (jumps) in metres. */
export function poseCrowd(ch: Character, motion: NpcMotion | undefined, t: number, salt: number, reduced: boolean): number {
  const r = ch.rig;
  const root = ch.root;
  root.position.y = 0;
  const amp = reduced ? 0.4 : 1;
  const life = { reduced, idleFor: 10 };
  switch (motion) {
    case 'sit': {
      resetRig(ch);
      poseSit(ch, t, salt);
      root.position.y = sitRootY(ch, 0.45);
      return 0;
    }
    case 'dance': {
      const ph = t * 1.5 + salt;
      resetRig(ch);
      poseGait(ch, ph, 0.75, { ...life, strideScale: 0.6 });
      r.armL.rotation.x = -1.2 + Math.sin(t * 6 + salt) * 0.5 * amp;
      r.armR.rotation.x = -1.2 - Math.sin(t * 6 + salt) * 0.5 * amp;
      root.position.y = Math.abs(Math.sin(ph * Math.PI * 2)) * 0.05 * amp;
      r.body.rotation.y = Math.sin(t * 0.9 + salt) * 0.5 * amp;
      return root.position.y;
    }
    case 'hype': {
      // the hype man: one arm pumping high, the other sweeping the crowd, little jumps on the beat
      resetRig(ch);
      poseLife(ch, t, salt, life);
      const beat = Math.abs(Math.sin(t * 4.2 + salt));
      r.armR.rotation.x = -2.7 + beat * 0.45 * amp;
      r.armR.rotation.z = -0.25;
      r.foreR.rotation.x = -0.3;
      r.armL.rotation.x = -1.3 + Math.sin(t * 1.3 + salt) * 0.25 * amp;
      r.armL.rotation.z = 0.5 + Math.sin(t * 1.3 + salt) * 0.4 * amp;
      r.chest.rotation.y = Math.sin(t * 1.3 + salt) * 0.25 * amp;
      r.head.rotation.x = -0.15 + beat * 0.1;
      root.position.y = beat * 0.07 * amp;
      return root.position.y;
    }
    case 'dj': {
      // hands on the decks, head nodding; every few seconds one hand to the headphones
      resetRig(ch);
      poseLife(ch, t, salt, life);
      const nod = Math.sin(t * 8.4 + salt);
      r.head.rotation.x = 0.1 + nod * 0.12 * amp;
      r.chest.rotation.x = 0.12;
      r.armL.rotation.x = -0.75;
      r.foreL.rotation.x = -0.9 + Math.sin(t * 2.1) * 0.15 * amp;
      const ear = (t + salt) % 7 < 2.2;
      r.armR.rotation.x = ear ? -2.0 : -0.75;
      r.armR.rotation.z = ear ? -0.6 : 0;
      r.foreR.rotation.x = ear ? -2.0 : -0.9 + Math.cos(t * 2.6) * 0.18 * amp;
      root.position.y = Math.max(0, nod) * 0.015;
      return 0;
    }
    case 'cheer': {
      resetRig(ch);
      poseLife(ch, t, salt, life);
      const up = Math.max(0, Math.sin(t * 2.4 + salt));
      r.armL.rotation.x = -0.4 - up * 2.4 * amp;
      r.armR.rotation.x = -0.4 - up * 2.4 * amp;
      r.armL.rotation.z = 0.2 + up * 0.3;
      r.armR.rotation.z = -0.2 - up * 0.3;
      root.position.y = up * 0.06 * amp;
      return root.position.y;
    }
    case 'trade': {
      // a trader calling customers: a beckoning arm, leaning in now and then
      resetRig(ch);
      poseLife(ch, t, salt, life);
      const call = (t + salt) % 5 < 2.4;
      const w = Math.sin(t * 5 + salt);
      r.armR.rotation.x = call ? -1.35 + w * 0.2 * amp : r.armR.rotation.x;
      r.foreR.rotation.x = call ? -0.7 + w * 0.5 * amp : r.foreR.rotation.x;
      r.chest.rotation.x = call ? 0.12 : r.chest.rotation.x;
      r.head.rotation.y = Math.sin(t * 0.7 + salt) * 0.4 * amp;
      return 0;
    }
    case 'serve': {
      // holding a tray / working the counter
      resetRig(ch);
      poseLife(ch, t, salt, life);
      r.armL.rotation.x = -0.35;
      r.foreL.rotation.x = -1.35;
      r.foreL.rotation.z = 0.25;
      r.armR.rotation.x = -0.5 + Math.sin(t * 1.9 + salt) * 0.25 * amp;
      r.foreR.rotation.x = -0.9;
      return 0;
    }
    case 'guard': {
      // arms folded, slow look around
      resetRig(ch);
      poseLife(ch, t, salt, life);
      r.armL.rotation.set(-0.55, 0, 0.18);
      r.armR.rotation.set(-0.55, 0, -0.18);
      r.foreL.rotation.set(-1.75, -0.85, 0);
      r.foreR.rotation.set(-1.75, 0.85, 0);
      r.head.rotation.y = Math.sin(t * 0.35 + salt) * 0.55 * amp;
      return 0;
    }
    case 'work': {
      // bent over a load / furnace / crops
      resetRig(ch);
      poseLife(ch, t, salt, life);
      const b = Math.sin(t * 1.6 + salt);
      r.chest.rotation.x = 0.45 + b * 0.12 * amp;
      r.armL.rotation.x = -0.9 + b * 0.25 * amp;
      r.armR.rotation.x = -0.9 - b * 0.25 * amp;
      r.foreL.rotation.x = -0.5;
      r.foreR.rotation.x = -0.5;
      return 0;
    }
    case 'phone': {
      resetRig(ch);
      poseLife(ch, t, salt, life);
      r.armR.rotation.x = -0.55;
      r.foreR.rotation.x = -1.55;
      r.foreR.rotation.z = -0.35;
      r.head.rotation.x = 0.32;
      return 0;
    }
    default: {
      resetRig(ch);
      poseLife(ch, t, salt, life);
      return 0;
    }
  }
}
