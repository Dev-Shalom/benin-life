// Live players: smoothing of a remote player's stream (pure TypeScript). docs/ROAM.md "Live players".
// Messages arrive sparsely (the sender sends only when the path leaves the receiver's prediction, see PosSender), so the track works in
// two parts: between two received snapshots it INTERPOLATES (drawn `buffer` ms in the past, so there is always a newer snapshot to glide
// towards), and beyond the newest it EXTRAPOLATES along the last heading and speed (dead reckoning) up to a cap, then stands. A snapshot
// that is far from the prediction (teleport, the player went through a door, joined) SNAPS the track instead of sliding across the city.
import { seqNewer, type Pose } from './protocol';

export interface Snap {
  t: number;
  x: number;
  y: number;
  h: number;
  v: number;
  car: boolean;
  run: boolean;
  brake: boolean;
  reverse: boolean;
}

/** Hold on after the last message when the sender may be silent: he is predicted to keep going this long (ms), then he stands. */
export const EXTRAPOLATE_MAX_MS = 5000;
/** A snapshot this far (m) from where the prediction put the player snaps the track. */
export const SNAP_M = 10;
/** No message for this long and the track starts again with a snap. */
const GAP_SNAP_MS = 12000;

const angleLerp = (a: number, b: number, u: number) => a + Math.atan2(Math.sin(b - a), Math.cos(b - a)) * u;

export class RemoteTrack {
  /** The rendered state (updated by sample()). */
  x = 0;
  y = 0;
  h = 0;
  /** Smoothed ground speed (m/s) from what was drawn (drives the walk cycle). */
  speed = 0;
  car = false;
  run = false;
  brake = false;
  reverse = false;
  /** Cumulative distance drawn (m): the walk phase and wheel spin follow it. */
  odo = 0;
  /** True once a snapshot has arrived. */
  has = false;
  /** Set when the track snapped on the last sample (no slide). */
  snapped = false;
  /** Emote now playing: id (1..6) and the time it started (ms), 0 = none. */
  emote = 0;
  emoteAt = 0;
  lastSeq = -1;
  lastAt = 0;
  /** When the last STREAM message arrived (ms): a long silence means the sender may have restarted his counter. */
  private lastStreamAt = -1e9;
  private snaps: Snap[] = [];
  private px = 0;
  private py = 0;
  private pInit = false;

  /** Feed one decoded message. `now` in ms. Returns false for a stale or duplicate one. */
  push(now: number, p: Pose & { seq: number }): boolean {
    if (now - this.lastStreamAt > 3000) this.lastSeq = -1;
    if (this.lastSeq >= 0 && !seqNewer(p.seq, this.lastSeq)) return false;
    this.lastSeq = p.seq;
    this.lastStreamAt = now;
    const last = this.snaps[this.snaps.length - 1];
    let snap = !last;
    if (last) {
      const dt = now - last.t;
      if (dt > GAP_SNAP_MS) snap = true;
      else {
        const pr = this.predict(last, Math.min(dt, EXTRAPOLATE_MAX_MS));
        if (Math.hypot(p.x - pr.x, p.y - pr.y) > SNAP_M) snap = true;
      }
    }
    const s: Snap = { t: Math.max(now, last ? last.t + 15 : now), x: p.x, y: p.y, h: p.h, v: p.v, car: p.car, run: p.run, brake: p.brake, reverse: p.reverse };
    if (snap) {
      this.snaps.length = 0;
      this.snapped = true;
    }
    this.snaps.push(s);
    if (this.snaps.length > 8) this.snaps.shift();
    this.has = true;
    this.lastAt = now;
    if (p.emote !== 0 && p.emote !== this.emote) {
      this.emote = p.emote;
      this.emoteAt = now;
    } else if (p.emote === 0 && this.emote !== 0 && now - this.emoteAt > 600) {
      this.emote = 0;
    }
    return true;
  }

  /** A position from the server's nearby list: used only when the stream has been silent for a long time or never started. */
  pushPresence(now: number, x: number, y: number, car: boolean) {
    if (this.has && now - this.lastAt < 10000) return;
    const last = this.snaps[this.snaps.length - 1];
    if (last && Math.hypot(last.x - x, last.y - y) < 1.5 && now - last.t < 10000) return;
    const h = last ? Math.atan2(y - last.y, x - last.x) : 0;
    if (!last || Math.hypot(last.x - x, last.y - y) > SNAP_M) {
      this.snaps.length = 0;
      this.snapped = true;
    }
    this.snaps.push({ t: Math.max(now, last ? last.t + 15 : now), x, y, h: last && !this.snapped ? h : last?.h ?? 0, v: 0, car, run: false, brake: false, reverse: false });
    if (this.snaps.length > 8) this.snaps.shift();
    this.has = true;
    this.lastAt = now;
  }

  private predict(s: Snap, ms: number): { x: number; y: number } {
    const t = ms / 1000;
    const k = s.reverse ? -1 : 1;
    return { x: s.x + Math.cos(s.h) * s.v * t * k, y: s.y + Math.sin(s.h) * s.v * t * k };
  }

  /** Is the player standing and quiet (no recent message)? Used to fade out ghosts. */
  silentFor(now: number): number {
    return now - this.lastAt;
  }

  /** Update the rendered state for `now` (ms), drawing `bufferMs` in the past. dt = seconds since the last sample. */
  sample(now: number, bufferMs: number, dt: number) {
    const n = this.snaps.length;
    if (!n) return;
    const T = now - bufferMs;
    let x: number, y: number, h: number;
    const newest = this.snaps[n - 1];
    let from = newest;
    if (T >= newest.t || n === 1) {
      const p = this.predict(newest, Math.min(Math.max(0, T - newest.t), EXTRAPOLATE_MAX_MS));
      x = p.x; y = p.y; h = newest.h;
    } else {
      let i = 0;
      while (i < n - 2 && this.snaps[i + 1].t <= T) i++;
      const a = this.snaps[i], b = this.snaps[i + 1];
      const u = Math.max(0, Math.min(1, (T - a.t) / Math.max(1, b.t - a.t)));
      x = a.x + (b.x - a.x) * u;
      y = a.y + (b.y - a.y) * u;
      h = angleLerp(a.h, b.h, u);
      from = u < 0.5 ? a : b;
    }
    // before the first snapshot has been reached: stand on it
    if (T < this.snaps[0].t) { x = this.snaps[0].x; y = this.snaps[0].y; h = this.snaps[0].h; from = this.snaps[0]; }
    // drop snapshots that are all in the past
    while (this.snaps.length > 2 && this.snaps[1].t <= T) this.snaps.shift();
    if (!this.pInit || this.snapped) {
      this.pInit = true;
      this.px = x; this.py = y;
      this.speed = 0;
      this.snapped = false;
      this.x = x; this.y = y; this.h = h;
    }
    const moved = Math.hypot(x - this.px, y - this.py);
    this.px = x; this.py = y;
    this.x = x; this.y = y;
    this.odo += moved;
    if (dt > 0) {
      const inst = Math.min(40, moved / dt);
      this.speed += (inst - this.speed) * Math.min(1, dt * 8);
    }
    // the heading is the sent one (interpolated): a walker faces where he goes, a car noses along its path
    this.h = h;
    this.car = from.car;
    this.run = from.run;
    this.brake = from.brake;
    this.reverse = from.reverse;
    // an emote ends by itself
    if (this.emote !== 0 && now - this.emoteAt > 6000) this.emote = 0;
  }
}
