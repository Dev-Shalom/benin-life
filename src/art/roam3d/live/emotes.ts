// Live players: the emote poses (wave, nod, laugh, dance, thumbs up, come here). Each is a pure function of the time since it started and
// is applied ON TOP of the idle pose (poseIdle has just been written to the rig), so it only touches the bones it needs.
import type { Character } from '../../avatar3d/engine/character';
import { EMOTES, EMOTE_MS, type EmoteName } from './protocol';

const sm = (x: number) => (x <= 0 ? 0 : x >= 1 ? 1 : x * x * (3 - 2 * x));

/** 0..1 envelope: in over 0.28 s, out over the last 0.35 s. */
function env(t: number, dur: number): number {
  return sm(t / 0.28) * (1 - sm((t - (dur - 0.35)) / 0.35));
}

/**
 * Apply emote `id` (1..6, see EMOTES) `t` seconds after it started. Returns false once it is over (the caller then stops asking).
 * Angles: arm.z is out to the side (left arm +, right arm -), arm.x forward is negative, fore.x bends the elbow.
 */
export function poseEmote(c: Character, id: number, t: number): boolean {
  const name = EMOTES[id] as EmoteName;
  if (!name) return false;
  const dur = EMOTE_MS[name as Exclude<EmoteName, ''>] / 1000;
  if (t > dur) return false;
  const e = env(t, dur);
  const r = c.rig;
  switch (name) {
    case 'wave': {
      // right arm up beside the head, the forearm swings side to side
      r.armR.rotation.z = -2.55 * e;
      r.armR.rotation.x = -0.15 * e;
      r.foreR.rotation.x = -0.35 * e;
      r.foreR.rotation.z = Math.sin(t * 11) * 0.5 * e;
      r.handR.rotation.z = Math.sin(t * 11 + 0.6) * 0.25 * e;
      r.head.rotation.z += 0.08 * e;
      r.head.rotation.x -= 0.05 * e;
      break;
    }
    case 'nod': {
      r.head.rotation.x += Math.sin(t * 8.5) * 0.3 * e;
      r.neck.rotation.x += Math.sin(t * 8.5 - 0.4) * 0.12 * e;
      r.chest.rotation.x += 0.04 * e;
      break;
    }
    case 'laugh': {
      // head back, shoulders shaking, a hand on the belly
      const sh = Math.sin(t * 19);
      r.head.rotation.x += (-0.32 + sh * 0.05) * e;
      r.chest.rotation.x += (-0.1 + sh * 0.05) * e;
      r.chest.position.y += sh * 0.006 * e;
      r.body.position.y += Math.abs(sh) * 0.01 * e;
      r.armL.rotation.x = -0.5 * e;
      r.foreL.rotation.x = -1.2 * e;
      r.armR.rotation.x = -0.3 * e;
      r.foreR.rotation.x = -0.6 * e;
      break;
    }
    case 'dance': {
      // bounce on the beat (about 2 per second), hips and arms swinging
      const b = Math.sin(t * 12.5);
      const s = Math.sin(t * 6.25);
      r.body.position.y += (Math.abs(b) * 0.045 - 0.02) * e;
      r.body.rotation.y += s * 0.35 * e;
      r.chest.rotation.y -= s * 0.3 * e;
      r.chest.rotation.z += s * 0.08 * e;
      r.armL.rotation.z = (0.5 + (s > 0 ? 1.7 : 0.2) * (0.5 + 0.5 * s)) * e + r.armL.rotation.z * (1 - e);
      r.armR.rotation.z = -(0.5 + (s < 0 ? 1.7 : 0.2) * (0.5 - 0.5 * s)) * e + r.armR.rotation.z * (1 - e);
      r.foreL.rotation.x = -0.7 * e;
      r.foreR.rotation.x = -0.7 * e;
      r.thighL.rotation.x += Math.max(0, b) * -0.35 * e;
      r.thighR.rotation.x += Math.max(0, -b) * -0.35 * e;
      r.shinL.rotation.x += Math.max(0, b) * 0.5 * e;
      r.shinR.rotation.x += Math.max(0, -b) * 0.5 * e;
      r.head.rotation.z += s * 0.1 * e;
      break;
    }
    case 'thumbs': {
      r.armR.rotation.x = -1.15 * e;
      r.armR.rotation.z = -0.35 * e;
      r.foreR.rotation.x = -1.35 * e;
      r.handR.rotation.x = -0.4 * e;
      r.head.rotation.x += Math.sin(t * 7) * 0.08 * e;
      r.chest.rotation.x += 0.05 * e;
      break;
    }
    case 'callover': {
      // arm out front, the hand beckons
      r.armR.rotation.x = -1.2 * e;
      r.armR.rotation.z = -0.5 * e;
      r.foreR.rotation.x = (-0.5 - (0.5 + 0.5 * Math.sin(t * 9)) * 0.85) * e;
      r.handR.rotation.x = (-0.1 - 0.5 * Math.max(0, Math.sin(t * 9 + 0.5))) * e;
      r.head.rotation.x += 0.06 * e;
      break;
    }
  }
  return true;
}
