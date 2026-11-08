// Live players in free roam: the wire format and the sender's decision rule (pure TypeScript, no imports, so the load test script
// can use the very same code). docs/ROAM.md "Live players".
//
// A position message is ONE small array on the sender's own private topic `roam:u:<uid>`:
//     [x10, y10, h, v4, f, q]
//   x10, y10  position in map metres x 10 (0..10000, 10 cm steps)
//   h         heading 0..255 (full turn / 256)
//   v4        speed in m/s x 4 (0..255)
//   f         flags: bit0 car, bit1 run, bit2 braking, bits3..5 emote (0 none, 1..6), bit6 reversing
//   q         sequence number 0..255 (the receiver drops late or duplicated ones)
// About 28 bytes of JSON. The name, look and car are NEVER in a message: they come from the server (roam_live_tick).

export const EVT_POS = 'p';
export const EVT_BUBBLE = 'b';

export const EMOTES = ['', 'wave', 'nod', 'laugh', 'dance', 'thumbs', 'callover'] as const;
export type EmoteName = (typeof EMOTES)[number];
export const EMOTE_LABEL: Record<Exclude<EmoteName, ''>, string> = {
  wave: 'Wave', nod: 'Nod', laugh: 'Laugh', dance: 'Dance', thumbs: 'Thumbs up', callover: 'Come here',
};
/** How long an emote plays (ms). */
export const EMOTE_MS: Record<Exclude<EmoteName, ''>, number> = { wave: 2400, nod: 1500, laugh: 2400, dance: 4200, thumbs: 1900, callover: 2400 };

export interface Pose {
  /** Map metres. */
  x: number;
  y: number;
  /** Heading (rad, map space, the direction faced / driven). */
  h: number;
  /** Speed m/s. */
  v: number;
  car: boolean;
  run: boolean;
  brake: boolean;
  reverse: boolean;
  /** 0 none, 1..6 = EMOTES index. */
  emote: number;
}

export type Packet = [number, number, number, number, number, number];

const TAU = Math.PI * 2;

export function quantHeading(h: number): number {
  return Math.round((((h % TAU) + TAU) % TAU) / TAU * 256) & 255;
}
export function dequantHeading(q: number): number {
  const a = (q / 256) * TAU;
  return a > Math.PI ? a - TAU : a;
}

export function encodePose(p: Pose, seq: number): Packet {
  const f = (p.car ? 1 : 0) | (p.run ? 2 : 0) | (p.brake ? 4 : 0) | ((p.emote & 7) << 3) | (p.reverse ? 64 : 0);
  return [
    Math.max(0, Math.min(10000, Math.round(p.x * 10))),
    Math.max(0, Math.min(10000, Math.round(p.y * 10))),
    quantHeading(p.h),
    Math.max(0, Math.min(255, Math.round(Math.abs(p.v) * 4))),
    f,
    seq & 255,
  ];
}

/** Validate a received message (hostile input): anything odd returns null. */
export function decodePose(a: unknown): (Pose & { seq: number }) | null {
  if (!Array.isArray(a) || a.length < 6) return null;
  const [x, y, h, v, f, q] = a as number[];
  for (const n of [x, y, h, v, f, q]) if (typeof n !== 'number' || !Number.isFinite(n)) return null;
  if (x < 0 || x > 10000 || y < 0 || y > 10000 || h < 0 || h > 255 || v < 0 || v > 255 || f < 0 || f > 127 || q < 0 || q > 255) return null;
  const emote = (f >> 3) & 7;
  return {
    x: x / 10, y: y / 10, h: dequantHeading(Math.round(h)), v: v / 4,
    car: (f & 1) !== 0, run: (f & 2) !== 0, brake: (f & 4) !== 0, reverse: (f & 64) !== 0,
    emote: emote <= 6 ? emote : 0, seq: Math.round(q),
  };
}

/** Is sequence b newer than a (mod 256)? */
export const seqNewer = (b: number, a: number) => ((b - a) & 255) !== 0 && ((b - a) & 255) < 128;

export interface SendCfg {
  /** Most messages a second while moving. */
  moveHz: number;
  /** Seconds between keep-alives while standing still. */
  idleS: number;
  /** Longest gap while moving in a straight line (ms). */
  maxGapMs: number;
  /** Message budget: messages a second DELIVERED for this player (each position message is delivered to every listener, so it costs 1 + listeners). */
  budget: number;
}
export const DEFAULT_SEND: SendCfg = { moveHz: 3, idleS: 15, maxGapMs: 1200, budget: 6 };

/**
 * Decides when to send. While moving it uses dead reckoning: the receiver extrapolates the last message (position + heading x speed),
 * so a new message is only needed when the real path leaves that prediction by more than a threshold, the heading turns, the speed
 * changes, the flags change, or the longest gap passed. Walking or driving straight therefore costs about 1 message a second, turning
 * up to `moveHz`. Standing still costs one message every `idleS` (twice that when nobody is near).
 */
export class PosSender {
  private lastAt = -1e9;
  private last: Pose | null = null;
  /** Starts anywhere: a phone that rejoins must not look like a replay of its own old messages. */
  private seq = Math.floor(Math.random() * 256);
  sent = 0;
  cfg: SendCfg;
  constructor(cfg: SendCfg = DEFAULT_SEND) {
    this.cfg = cfg;
  }

  /** Force the next call to send (emote started, joined a new channel). */
  poke() {
    this.lastAt = -1e9;
  }

  /** The gap this sender keeps between two messages while moving, given how many players listen. */
  gapMs(listeners: number): number {
    const byHz = 1000 / Math.max(0.5, this.cfg.moveHz);
    const byBudget = (Math.max(1, listeners) / Math.max(0.5, this.cfg.budget)) * 1000;
    return Math.min(4000, Math.max(byHz, byBudget));
  }

  /** `now` in ms. `listeners` = players near me (they listen to my topic). Returns the packet to send, or null. */
  next(now: number, p: Pose, listeners = 0): Packet | null {
    const L = this.last;
    const dt = now - this.lastAt;
    const lonely = listeners === 0;
    const minGap = this.gapMs(listeners);
    const maxGap = Math.max(this.cfg.maxGapMs, minGap * 1.5);
    let send = false;
    if (!L) send = true;
    else {
      const moving = p.v > 0.25 || L.v > 0.25;
      const flagsChanged = p.car !== L.car || p.run !== L.run || p.brake !== L.brake || p.emote !== L.emote || p.reverse !== L.reverse;
      if (flagsChanged && dt >= 120) send = true;
      else if (moving) {
        if (dt >= minGap) {
          // where the receiver thinks I am now
          const t = dt / 1000;
          const sg = L.reverse ? -1 : 1;
          const px = L.x + Math.cos(L.h) * L.v * t * sg;
          const py = L.y + Math.sin(L.h) * L.v * t * sg;
          const err = Math.hypot(p.x - px, p.y - py);
          let dh = p.h - L.h;
          dh = Math.atan2(Math.sin(dh), Math.cos(dh));
          const lim = p.car ? 0.9 : 0.45;
          const turn = p.car ? 0.07 : 0.15;
          if (err > lim || Math.abs(dh) > turn || Math.abs(p.v - L.v) > (p.car ? 2 : 0.8) || dt >= maxGap) send = true;
          // stopped: tell them at once so they do not walk on in place
          if (p.v <= 0.25 && L.v > 0.25) send = true;
        }
      } else if (dt >= this.cfg.idleS * 1000 * (lonely ? 2 : 1)) send = true;
    }
    if (!send) return null;
    this.last = { ...p };
    this.lastAt = now;
    this.seq = (this.seq + 1) & 255;
    this.sent++;
    return encodePose(p, this.seq);
  }
}

/** A chat bubble as the database sends it (trusted: only roam_say can write on the bubble topics). */
export interface BubbleMsg {
  i: number;
  /** Speaker id. */
  u: string;
  /** Speaker name (from profiles). */
  n: string;
  /** Text, already filtered. */
  t: string;
  x: number;
  y: number;
}
export function parseBubble(a: unknown): BubbleMsg | null {
  if (!a || typeof a !== 'object') return null;
  const o = a as Record<string, unknown>;
  if (typeof o.u !== 'string' || typeof o.t !== 'string' || typeof o.n !== 'string' || typeof o.x !== 'number' || typeof o.y !== 'number') return null;
  return { i: Number(o.i) || 0, u: o.u, n: o.n.slice(0, 40), t: o.t.slice(0, 200), x: o.x, y: o.y };
}

export const posTopic = (uid: string) => `roam:u:${uid}`;
/** A player's chat bubbles: written only by the database (roam_say), readable by the same players who may read his positions. */
export const textTopic = (uid: string) => `roam:t:${uid}`;

/** What `roam_live_tick` returns for each nearby player. Static fields (n, av, sc, t, c) only come the first time. */
export interface NearbyRow {
  id: string;
  m: 'walk' | 'car';
  v: string | null;
  x: number;
  y: number;
  n?: string;
  av?: unknown;
  sc?: number;
  t?: string | null;
  c?: { tag?: string; color?: string; emblem?: string; name?: string } | null;
}
