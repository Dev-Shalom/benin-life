// P2 place soundtracks: everything is synthesized here (no samples, no copyrighted music). Context-agnostic, so
// the same code plays live (sound.ts, one scheduler) and renders offline (OfflineAudioContext, for checks).
//   bank     drum / log drum / pluck / vocal-chop buffers computed once in JS per sample rate (no per-note synthesis)
//   tracks   club (amapiano groove, sections that change every 8–16 bars), buka radio (highlife <-> afrobeats),
//            market (hawker calls + bustle), stadium (chants + cheers), cinema (pad), lounge (jazz keys),
//            motor park (horns + conductor calls)
//   one-shots the "Doremi" stinger, a soft ticker cue, the crowd "ayyy"
// A hit = one AudioBufferSourceNode (+ a gain node only where the velocity / envelope needs one).

type Ctx = BaseAudioContext;
export const hz = (midi: number) => 440 * Math.pow(2, (midi - 69) / 12);

// ---------------------------------------------------------------- tiny DSP
function rng(seed: number) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

class Biquad {
  b0 = 0; b1 = 0; b2 = 0; a1 = 0; a2 = 0; x1 = 0; x2 = 0; y1 = 0; y2 = 0;
  constructor(type: 'lp' | 'hp' | 'bp', f: number, q: number, sr: number) {
    const w = (2 * Math.PI * f) / sr;
    const cs = Math.cos(w);
    const al = Math.sin(w) / (2 * q);
    const a0 = 1 + al;
    let b0: number, b1: number, b2: number;
    if (type === 'lp') { b0 = (1 - cs) / 2; b1 = 1 - cs; b2 = (1 - cs) / 2; }
    else if (type === 'hp') { b0 = (1 + cs) / 2; b1 = -(1 + cs); b2 = (1 + cs) / 2; }
    else { b0 = al; b1 = 0; b2 = -al; }
    this.b0 = b0 / a0; this.b1 = b1 / a0; this.b2 = b2 / a0; this.a1 = (-2 * cs) / a0; this.a2 = (1 - al) / a0;
  }
  run(x: number) {
    const y = this.b0 * x + this.b1 * this.x1 + this.b2 * this.x2 - this.a1 * this.y1 - this.a2 * this.y2;
    this.x2 = this.x1; this.x1 = x; this.y2 = this.y1; this.y1 = y;
    return y;
  }
}

function norm(d: Float32Array, peak: number) {
  let m = 0;
  for (let i = 0; i < d.length; i++) m = Math.max(m, Math.abs(d[i]));
  if (m > 0) for (let i = 0; i < d.length; i++) d[i] *= peak / m;
  return d;
}

// ---------------------------------------------------------------- the bank
export interface Bank {
  sr: number;
  kick: Float32Array; clap: Float32Array; rim: Float32Array; shaker: Float32Array; hat: Float32Array; ohat: Float32Array;
  /** log drum at C2 (MIDI 36) */ log: Float32Array;
  /** vocal-ish "ah" chop at A4 (MIDI 69) */ chop: Float32Array;
  /** plucked string (Karplus-Strong) at A3 (MIDI 57) */ pluck: Float32Array;
  /** crowd murmur / roar bed, loopable */ crowd: Float32Array;
  noise: Float32Array;
}
export const LOG_BASE = 36;
export const CHOP_BASE = 69;
export const PLUCK_BASE = 57;

const banks = new Map<number, Bank>();
export function getBank(sr: number): Bank {
  const hit = banks.get(sr);
  if (hit) return hit;
  const r = rng(7);
  const mk = (s: number) => new Float32Array(Math.ceil(sr * s));
  // kick: soft sine thump with a pitch drop
  const kick = mk(0.42);
  {
    let ph = 0;
    for (let i = 0; i < kick.length; i++) {
      const t = i / sr;
      ph += (2 * Math.PI * (46 + 85 * Math.exp(-t * 30))) / sr;
      kick[i] = Math.sin(ph) * Math.exp(-t * 8.5) * Math.min(1, t / 0.002) + (t < 0.003 ? (r() * 2 - 1) * 0.15 * (1 - t / 0.003) : 0);
    }
    norm(kick, 0.9);
  }
  // clap: three quick noise bursts + a tail, bandpassed
  const clap = mk(0.3);
  {
    const bp = new Biquad('bp', 1350, 0.9, sr);
    for (let i = 0; i < clap.length; i++) {
      const t = i / sr;
      let e = 0;
      for (let k = 0; k < 3; k++) if (t >= k * 0.009) e += Math.exp(-(t - k * 0.009) * 170);
      if (t > 0.02) e += 0.55 * Math.exp(-(t - 0.02) * 20);
      clap[i] = bp.run((r() * 2 - 1) * e);
    }
    norm(clap, 0.75);
  }
  // rim: woody click
  const rim = mk(0.09);
  for (let i = 0; i < rim.length; i++) {
    const t = i / sr;
    rim[i] = Math.sin(2 * Math.PI * 1650 * t) * Math.exp(-t * 60) * 0.55 + Math.sin(2 * Math.PI * 820 * t) * Math.exp(-t * 45) * 0.4;
  }
  norm(rim, 0.6);
  const noisy = (secs: number, f: number, decay: number, attack: number, peak: number) => {
    const d = mk(secs);
    const hp = new Biquad('hp', f, 0.7, sr);
    for (let i = 0; i < d.length; i++) {
      const t = i / sr;
      d[i] = hp.run(r() * 2 - 1) * Math.min(1, t / attack) * Math.exp(-t * decay);
    }
    return norm(d, peak);
  };
  const shaker = noisy(0.12, 5200, 38, 0.006, 0.5);
  const hat = noisy(0.06, 7800, 75, 0.001, 0.45);
  const ohat = noisy(0.32, 7000, 11, 0.002, 0.4);
  // log drum: the amapiano bass hit: a hollow, slightly saturated pitched thump with a fast pitch drop
  const log = mk(0.8);
  {
    let ph = 0;
    const base = hz(LOG_BASE);
    const k = 1.9;
    const bp = new Biquad('bp', 900, 1.2, sr);
    for (let i = 0; i < log.length; i++) {
      const t = i / sr;
      ph += (2 * Math.PI * base * (1 + 0.8 * Math.exp(-t * 55))) / sr;
      const env = Math.min(1, t / 0.003) * Math.exp(-t * 5.2);
      const s = Math.sin(ph) + 0.35 * Math.sin(2 * ph) + 0.12 * Math.sin(3 * ph);
      log[i] = Math.tanh(k * s * env) / Math.tanh(k) + bp.run(r() * 2 - 1) * Math.exp(-t * 90) * 0.25;
    }
    norm(log, 0.9);
  }
  // vocal chop: a saw with vibrato through two "ah" formants
  const chop = mk(0.3);
  {
    const f1 = new Biquad('bp', 760, 5, sr);
    const f2 = new Biquad('bp', 1180, 6, sr);
    const f3 = new Biquad('bp', 2600, 8, sr);
    let ph = 0;
    const f0 = hz(CHOP_BASE);
    for (let i = 0; i < chop.length; i++) {
      const t = i / sr;
      const f = f0 * (1 + 0.006 * Math.sin(2 * Math.PI * 5.5 * t)) * (1 - 0.04 * Math.exp(-t * 30));
      ph = (ph + f / sr) % 1;
      const s = 2 * ph - 1;
      const env = Math.min(1, t / 0.015) * Math.exp(-t * 7);
      chop[i] = (f1.run(s) + 0.7 * f2.run(s) + 0.25 * f3.run(s)) * env;
    }
    norm(chop, 0.6);
  }
  // plucked string (guitar-ish), Karplus-Strong
  const pluck = mk(1.3);
  {
    const n = Math.round(sr / hz(PLUCK_BASE));
    const line = new Float32Array(n);
    for (let i = 0; i < n; i++) line[i] = r() * 2 - 1;
    let p = 0;
    let prev = 0;
    for (let i = 0; i < pluck.length; i++) {
      const cur = line[p];
      const nxt = 0.5 * (cur + prev) * 0.996;
      prev = cur;
      line[p] = nxt;
      p = (p + 1) % n;
      pluck[i] = cur;
    }
    const lp = new Biquad('lp', 3200, 0.7, sr);
    for (let i = 0; i < pluck.length; i++) pluck[i] = lp.run(pluck[i]);
    norm(pluck, 0.6);
  }
  // crowd bed: bandpassed noise with slow random swells, crossfaded so it loops
  const crowd = mk(4);
  {
    const a = new Biquad('bp', 520, 0.8, sr);
    const b = new Biquad('bp', 1150, 1.4, sr);
    let sw = 0.5;
    let tgt = 0.5;
    for (let i = 0; i < crowd.length; i++) {
      if (i % 2048 === 0) tgt = 0.35 + r() * 0.65;
      sw += (tgt - sw) * 0.0004;
      const x = r() * 2 - 1;
      crowd[i] = (a.run(x) + 0.5 * b.run(x)) * sw;
    }
    const xf = Math.floor(sr * 0.3);
    for (let i = 0; i < xf; i++) {
      const g = i / xf;
      crowd[i] = crowd[i] * g + crowd[crowd.length - xf + i] * (1 - g);
    }
    norm(crowd.subarray(0, crowd.length - xf), 0.5);
  }
  const noise = mk(2);
  for (let i = 0; i < noise.length; i++) noise[i] = r() * 2 - 1;
  const bank: Bank = { sr, kick, clap, rim, shaker, hat, ohat, log, chop, pluck, crowd: crowd.slice(0, crowd.length - Math.floor(sr * 0.3)), noise };
  banks.set(sr, bank);
  return bank;
}

// chords: electric-piano stabs and pads, computed once per chord / length (cached per sample rate)
const chordCache = new Map<string, Float32Array>();
function keysChord(sr: number, notes: number[]): Float32Array {
  const key = `k${sr}:${notes.join(',')}`;
  const hit = chordCache.get(key);
  if (hit) return hit;
  const d = new Float32Array(Math.ceil(sr * 1.4));
  for (const n of notes) {
    const f = hz(n);
    for (let i = 0; i < d.length; i++) {
      const t = i / sr;
      d[i] += Math.sin(2 * Math.PI * f * t) * Math.exp(-t * 2.6) + 0.35 * Math.sin(4 * Math.PI * f * t) * Math.exp(-t * 5)
        + 0.12 * Math.sin(2 * Math.PI * 3.98 * f * t) * Math.exp(-t * 16);
    }
  }
  for (let i = 0; i < d.length; i++) {
    const t = i / sr;
    d[i] *= Math.min(1, t / 0.004) * (1 + 0.07 * Math.sin(2 * Math.PI * 4.6 * t));
  }
  norm(d, 0.55);
  chordCache.set(key, d);
  return d;
}
function padChord(sr: number, notes: number[], secs: number, cutoff = 1100): Float32Array {
  const key = `p${sr}:${notes.join(',')}:${secs}:${cutoff}`;
  const hit = chordCache.get(key);
  if (hit) return hit;
  const d = new Float32Array(Math.ceil(sr * secs));
  const ph = new Float64Array(notes.length * 2);
  const lp = new Biquad('lp', cutoff, 0.6, sr);
  for (let i = 0; i < d.length; i++) {
    let s = 0;
    for (let k = 0; k < notes.length; k++) {
      const f = hz(notes[k]);
      ph[k * 2] = (ph[k * 2] + (f * 1.0012) / sr) % 1;
      ph[k * 2 + 1] = (ph[k * 2 + 1] + (f * 0.9988) / sr) % 1;
      s += ph[k * 2] + ph[k * 2 + 1] - 1;
    }
    const t = i / sr;
    const env = Math.min(1, t / 0.45) * Math.min(1, (secs - t) / 0.7);
    d[i] = lp.run(s) * env;
  }
  norm(d, 0.5);
  chordCache.set(key, d);
  return d;
}

// ---------------------------------------------------------------- engine
export class Engine {
  readonly c: Ctx;
  readonly out: GainNode;
  readonly bank: Bank;
  private bufs = new Map<Float32Array, AudioBuffer>();
  constructor(c: Ctx, dest: AudioNode) {
    this.c = c;
    this.out = c.createGain();
    this.out.connect(dest);
    this.bank = getBank(c.sampleRate);
  }
  buf(d: Float32Array): AudioBuffer {
    let b = this.bufs.get(d);
    if (!b) {
      b = this.c.createBuffer(1, d.length, this.c.sampleRate);
      b.getChannelData(0).set(d);
      this.bufs.set(d, b);
    }
    return b;
  }
  /** One hit. `gate` = cut the tail after this many seconds (a short release), `slide` = [rate, secs]. */
  hit(d: Float32Array, at: number, gain = 1, rate = 1, dest: AudioNode = this.out, gate = 0, slide?: [number, number]) {
    const s = this.c.createBufferSource();
    s.buffer = this.buf(d);
    s.playbackRate.setValueAtTime(rate, at);
    if (slide) s.playbackRate.exponentialRampToValueAtTime(Math.max(0.05, slide[0]), at + slide[1]);
    if (gain !== 1 || gate > 0) {
      const g = this.c.createGain();
      g.gain.setValueAtTime(gain, at);
      if (gate > 0) {
        g.gain.setValueAtTime(gain, at + gate);
        g.gain.exponentialRampToValueAtTime(0.0001, at + gate + 0.06);
      }
      s.connect(g).connect(dest);
      s.start(at);
      s.stop(at + (gate > 0 ? gate + 0.08 : (d.length / this.c.sampleRate) / rate + 0.05));
    } else {
      s.connect(dest);
      s.start(at);
    }
  }
  tone(freq: number, at: number, dur: number, o: { type?: OscillatorType; gain?: number; attack?: number; glide?: number; cutoff?: number; dest?: AudioNode } = {}) {
    const osc = this.c.createOscillator();
    const g = this.c.createGain();
    osc.type = o.type ?? 'sine';
    osc.frequency.setValueAtTime(freq, at);
    if (o.glide) osc.frequency.exponentialRampToValueAtTime(o.glide, at + dur);
    const a = o.attack ?? 0.005;
    g.gain.setValueAtTime(0.0001, at);
    g.gain.exponentialRampToValueAtTime(o.gain ?? 0.2, at + a);
    g.gain.exponentialRampToValueAtTime(0.0001, at + a + dur);
    let out: AudioNode = g;
    if (o.cutoff) {
      const f = this.c.createBiquadFilter();
      f.type = 'lowpass';
      f.frequency.value = o.cutoff;
      g.connect(f);
      out = f;
    }
    osc.connect(g);
    out.connect(o.dest ?? this.out);
    osc.start(at);
    osc.stop(at + a + dur + 0.05);
  }
}

export type TrackKind = 'club' | 'buka' | 'market' | 'stadium' | 'cinema' | 'lounge' | 'motorpark';

export interface Track {
  /** Beats per minute of the grid (visual beat clock), 0 = no grid. */
  bpm: number;
  /** Context time of beat 0. */
  t0: number;
  /** Schedule everything up to `until` (context seconds). */
  schedule(until: number): void;
  stop(): void;
}

// a 16th-step grid with swing; catches up (silently) after a stall instead of bursting
function grid(e: Engine, bpm: number, t0: number, swing: number, onStep: (step: number, at: number) => void, setBpm?: () => number) {
  let step = 0;
  let cur = bpm;
  let origin = t0;
  const tr: Track = {
    bpm, t0,
    schedule(until: number) {
      const s16 = 60 / cur / 4;
      const now = e.c.currentTime;
      // fell behind (timers throttled): skip ahead without playing the missed steps
      if (origin + step * s16 < now - 0.25) step = Math.ceil((now - origin) / s16);
      for (;;) {
        const at = origin + step * s16 + (step & 1 ? swing * s16 : 0);
        if (at >= until) break;
        onStep(step, at);
        step++;
        if (setBpm && step % 16 === 0) {
          const nb = setBpm();
          if (nb !== cur) {
            origin = origin + step * s16 + 0.6; // a short gap: the radio changes song
            step = 0;
            cur = nb;
            tr.bpm = nb;
            tr.t0 = origin;
            return;
          }
        }
      }
    },
    stop() {},
  };
  return tr;
}

// ---------------------------------------------------------------- club: amapiano
export const CLUB_BPM = 113;
const AMA_CHORDS = [[56, 60, 63, 67], [61, 65, 68, 72], [55, 58, 62, 65], [53, 56, 60, 63]]; // Fm9 Bbm9 Ebmaj9 Dbmaj9
const AMA_ROOTS = [41, 46, 39, 37];
// [step, semitones over the root, slide in semitones]
const LOGS: [number, number, number][][] = [
  [[0, 0, 0], [3, 0, 0], [6, 12, -12], [10, 0, 0], [13, 7, -7]],
  [[0, 0, 0], [2, 0, 0], [7, 0, 5], [10, 12, -5], [14, 0, 0]],
  [[3, 0, 0], [6, 0, 0], [8, 7, 0], [11, 5, -5], [14, 12, -12]],
  [[0, 0, -12], [8, 7, -7]],
];
const STABS = [[3, 6, 10], [0, 7, 10, 13], [2, 5, 11, 14], [6, 14]];
interface Section { bars: number; kick: boolean; clap: boolean; hat: boolean; log: number; keys: number; pad: boolean; chops: boolean; filt: number }
const ARRANGE: Section[] = [
  { bars: 16, kick: true, clap: true, hat: true, log: 0, keys: 0, pad: false, chops: false, filt: 18000 },
  { bars: 16, kick: true, clap: true, hat: true, log: 1, keys: 1, pad: true, chops: true, filt: 18000 },
  { bars: 8, kick: false, clap: false, hat: true, log: 3, keys: 3, pad: true, chops: true, filt: 1100 },
  { bars: 16, kick: true, clap: true, hat: true, log: 2, keys: 2, pad: false, chops: true, filt: 18000 },
  { bars: 16, kick: true, clap: true, hat: true, log: 0, keys: 1, pad: true, chops: false, filt: 18000 },
  { bars: 8, kick: false, clap: false, hat: true, log: 3, keys: 3, pad: true, chops: false, filt: 1400 },
];
const ARR_BARS = ARRANGE.reduce((n, s) => n + s.bars, 0);

function club(e: Engine, t0: number): Track {
  const b = e.bank;
  const r = rng(113);
  const filt = e.c.createBiquadFilter();
  filt.type = 'lowpass';
  filt.frequency.value = 18000;
  filt.Q.value = 0.7;
  const bus = e.c.createGain();
  bus.gain.value = 0.62; // headroom: kick + log + stabs stack up
  bus.connect(filt).connect(e.out);
  let lastSec = -1;
  const tr = grid(e, CLUB_BPM, t0, 0.16, (step, at) => {
    const bar = Math.floor(step / 16);
    const s = step % 16;
    const cycle = Math.floor(bar / ARR_BARS);
    let k = bar % ARR_BARS;
    let si = 0;
    while (k >= ARRANGE[si].bars) { k -= ARRANGE[si].bars; si++; }
    const sec = ARRANGE[si];
    // every pass through the arrangement picks other log / keys patterns, so it never loops exactly
    const logP = sec.log === 3 ? 3 : (sec.log + cycle) % 3;
    const keyP = sec.keys === 3 ? 3 : (sec.keys + cycle * 2) % 3;
    const ci = bar % 4;
    const chord = AMA_CHORDS[ci];
    if (s === 0 && si !== lastSec) {
      lastSec = si;
      filt.frequency.cancelScheduledValues(at);
      filt.frequency.setValueAtTime(filt.frequency.value || 18000, at);
      filt.frequency.exponentialRampToValueAtTime(sec.filt, at + (sec.filt < 5000 ? 0.8 : 2.5));
    }
    // last bar of a breakdown: snare-roll-ish rim build
    const lastBar = k === sec.bars - 1;
    if (sec.kick && s % 4 === 0) e.hit(b.kick, at, 0.8, 1, bus);
    if (sec.clap && (s === 4 || s === 12)) e.hit(b.clap, at, 0.42, 1, bus);
    if (!sec.kick && lastBar && s >= 8) e.hit(b.rim, at, 0.12 + (s - 8) * 0.03, 1, bus);
    if (sec.clap && (s === 7 || s === 15) && bar % 2 === 1) e.hit(b.rim, at, 0.22, 1, bus);
    // shakers on every 16th (accented), hats on the offbeat 8ths, an open hat now and then
    e.hit(b.shaker, at, s % 4 === 2 ? 0.34 : s % 2 ? 0.16 : 0.24, 1, bus);
    if (sec.hat && s % 4 === 2) e.hit(s === 14 && bar % 2 === 1 ? b.ohat : b.hat, at, 0.22, 1, bus);
    // log drum
    for (const [ls, semi, slide] of LOGS[logP]) {
      if (ls !== s) continue;
      const note = AMA_ROOTS[ci] + semi;
      const rate = Math.pow(2, (note - LOG_BASE) / 12);
      e.hit(b.log, at, 0.72, rate, bus, 0, slide ? [rate * Math.pow(2, slide / 12), 0.2] : undefined);
    }
    // jazzy piano stabs (7ths / 9ths), short and offbeat
    if (STABS[keyP].includes(s)) e.hit(keysChord(b.sr, chord), at, 0.26, 1, bus, 0.2);
    // pad under the chord
    if (sec.pad && s === 0) e.hit(padChord(b.sr, chord.map((n) => n - 12), 2.4), at, 0.2, 1, bus);
    // vocal-chop-like blips
    if (sec.chops && bar % 4 === 3 && (s === 10 || s === 12 || (s === 14 && r() < 0.6))) {
      const n = chord[(s / 2) % chord.length] + 12;
      e.hit(b.chop, at, 0.16, Math.pow(2, (n - CHOP_BASE) / 12), bus, 0.12);
    }
  });
  return tr;
}

// ---------------------------------------------------------------- buka: radio, highlife <-> afrobeats
function buka(e: Engine, t0: number): Track {
  const b = e.bank;
  const radio = e.c.createBiquadFilter();
  radio.type = 'bandpass';
  radio.frequency.value = 1500;
  radio.Q.value = 0.55;
  const bus = e.c.createGain();
  bus.gain.value = 1.4;
  bus.connect(radio).connect(e.out);
  let song = 0; // 0 highlife, 1 afrobeats; 24 bars each
  let barsIn = 0;
  const HL = [[60, 64, 67], [65, 69, 72], [67, 71, 74], [60, 64, 67]]; // C F G C
  const AF = [[57, 60, 64, 67], [62, 65, 69, 72], [55, 59, 62, 65], [60, 64, 67, 71]]; // Am7 Dm7 G7 Cmaj7
  const arp = [0, 2, 1, 2, 0, 2, 1, 2];
  const pr = (n: number) => Math.pow(2, (n - PLUCK_BASE) / 12);
  return grid(e, 118, t0, 0.08, (step, at) => {
    const bar = Math.floor(step / 16);
    const s = step % 16;
    if (s === 0 && step > 0) barsIn++;
    if (song === 0) {
      const ch = HL[bar % 4];
      if (s % 2 === 0) e.hit(b.pluck, at, 0.5, pr(ch[arp[(s / 2) % 8]]), bus);
      if (s === 3 || s === 11) e.hit(b.pluck, at, 0.32, pr(ch[2] + 12), bus);
      if (s === 0 || s === 6 || s === 8) e.hit(b.pluck, at, 0.6, pr(ch[0] - 24), bus);
      if ([0, 3, 6, 10, 12].includes(s)) e.hit(b.rim, at, 0.2, 1, bus);
      if (s % 2 === 0) e.hit(b.shaker, at, 0.18, 1, bus);
      if (s === 0 || s === 8) e.hit(b.kick, at, 0.35, 1, bus);
    } else {
      const ch = AF[bar % 4];
      if (s === 0 || s === 7 || s === 8) e.hit(b.kick, at, 0.66, 1, bus);
      if (s === 4 || s === 12) e.hit(b.clap, at, 0.32, 1, bus);
      e.hit(b.shaker, at, s % 2 ? 0.12 : 0.2, 1, bus);
      if (s === 3 || s === 6 || s === 11) e.hit(keysChord(b.sr, ch), at, 0.42, 1, bus, 0.18);
      if (s === 0 || s === 10) e.hit(b.pluck, at, 0.55, pr(ch[0] - 24), bus);
      if (bar % 2 === 1 && (s === 13 || s === 14)) e.hit(b.pluck, at, 0.3, pr(ch[3] + 12), bus);
    }
  }, () => {
    if (barsIn >= 24) {
      barsIn = 0;
      song = 1 - song;
      // "tuning" between songs: a short burst of static
      e.hit(b.noise, e.c.currentTime + 0.2, 0.05, 1, bus, 0.35);
    }
    return song === 0 ? 118 : 104;
  });
}

// ---------------------------------------------------------------- event tracks (no grid)
function loopBed(e: Engine, d: Float32Array, gain: number, at: number, cutoff = 0) {
  const s = e.c.createBufferSource();
  s.buffer = e.buf(d);
  s.loop = true;
  const g = e.c.createGain();
  g.gain.setValueAtTime(0.0001, at);
  g.gain.exponentialRampToValueAtTime(gain, at + 1.5);
  let node: AudioNode = s;
  if (cutoff) {
    const f = e.c.createBiquadFilter();
    f.type = 'lowpass';
    f.frequency.value = cutoff;
    s.connect(f);
    node = f;
  }
  node.connect(g).connect(e.out);
  s.start(at);
  return () => {
    try {
      const t = e.c.currentTime;
      g.gain.cancelScheduledValues(t);
      g.gain.setTargetAtTime(0, t, 0.3);
      s.stop(t + 1.5);
    } catch { /* stopped */ }
  };
}

/** A voice-like call: 2–4 chop syllables with pitch moves ("Pure wa-ter!", "Ring road! Ring road!"). */
function call(e: Engine, at: number, base: number, sylls: number[], gain: number, gap = 0.17, dest?: AudioNode) {
  for (let i = 0; i < sylls.length; i++) {
    const rate = Math.pow(2, (base + sylls[i] - CHOP_BASE) / 12);
    e.hit(e.bank.chop, at + i * gap, gain, rate, dest ?? e.out, gap * 0.9, i === sylls.length - 1 ? [rate * 0.85, 0.25] : undefined);
  }
}

function events(e: Engine, t0: number, tickEvery: number, onTick: (at: number, r: () => number) => void, beds: (() => () => void)[]): Track {
  const r = rng(Math.floor(t0 * 1000) + 3);
  let next = t0;
  const stops = beds.map((f) => f());
  return {
    bpm: 0, t0,
    schedule(until: number) {
      if (next < e.c.currentTime - 1) next = e.c.currentTime;
      while (next < until) {
        onTick(next, r);
        next += tickEvery;
      }
    },
    stop() { for (const s of stops) s(); },
  };
}

function market(e: Engine, t0: number): Track {
  const calls = [[0, 3, -2], [0, 0, 5, 2], [7, 5, 0], [0, 4, 7, 4]];
  return events(e, t0, 0.5, (at, r) => {
    if (r() < 0.07) call(e, at + r() * 0.4, 62 + Math.floor(r() * 8), calls[Math.floor(r() * calls.length)], 0.12 + r() * 0.06, 0.15 + r() * 0.08);
    if (r() < 0.05) e.hit(e.bank.rim, at, 0.06, 0.6 + r() * 0.4); // a pan / a bowl
  }, [() => loopBed(e, e.bank.crowd, 0.22, t0, 1800)]);
}

function motorpark(e: Engine, t0: number): Track {
  return events(e, t0, 0.5, (at, r) => {
    if (r() < 0.06) {
      const f = 330 + r() * 160;
      e.tone(f, at, 0.16, { type: 'square', gain: 0.05, cutoff: 900 });
      if (r() < 0.6) e.tone(f, at + 0.24, 0.22, { type: 'square', gain: 0.05, cutoff: 900 });
    }
    if (r() < 0.05) {
      const base = 64 + Math.floor(r() * 5);
      call(e, at, base, [0, -3], 0.14, 0.14);
      call(e, at + 0.55, base, [0, -3], 0.12, 0.14);
    }
  }, [() => loopBed(e, e.bank.crowd, 0.16, t0, 1400)]);
}

function stadium(e: Engine, t0: number): Track {
  let chantAt = t0 + 3;
  return events(e, t0, 0.25, (at, r) => {
    if (at >= chantAt) {
      // clap clap, clap-clap-clap + "o-le, o-le" from a few voices
      const beat = 0.42;
      for (const k of [0, 1, 2, 2.5, 3]) for (let v = 0; v < 3; v++) e.hit(e.bank.clap, at + k * beat + v * 0.012, 0.18, 0.95 + v * 0.05);
      for (let v = 0; v < 3; v++) call(e, at + 4 * beat + v * 0.02, 60 + v * 0.3, [0, 4, 0, 4, 7, 4], 0.07, beat * 0.5);
      chantAt = at + 10 + r() * 8;
    }
    if (r() < 0.012) cheerOn(e.c, e.out, at, 0.55);
  }, [() => loopBed(e, e.bank.crowd, 0.3, t0, 2400)]);
}

function cinema(e: Engine, t0: number): Track {
  const CH = [[45, 52, 57, 60], [41, 48, 53, 57], [48, 55, 60, 64], [43, 50, 55, 59]];
  let n = 0;
  return events(e, t0, 4, (at) => {
    e.hit(padChord(e.bank.sr, CH[n % 4], 4.6, 700), at, 0.3);
    if (n % 4 === 0) e.hit(e.bank.kick, at, 0.25, 0.5);
    n++;
  }, []);
}

function lounge(e: Engine, t0: number): Track {
  const b = e.bank;
  const CH = [[53, 57, 60, 64], [53, 59, 64, 65], [52, 55, 59, 62], [55, 58, 61, 64]]; // Dm9 G13 Cmaj9 A7b9
  const ROOT = [38, 43, 36, 45];
  const walk = [0, 3, 7, 5];
  const pr = (n: number) => Math.pow(2, (n - PLUCK_BASE) / 12);
  const lp = e.c.createBiquadFilter();
  lp.type = 'lowpass';
  lp.frequency.value = 2600;
  const bus = e.c.createGain();
  bus.connect(lp).connect(e.out);
  return grid(e, 84, t0, 0.33, (step, at) => {
    const bar = Math.floor(step / 16);
    const s = step % 16;
    const ci = bar % 4;
    if (s === 0 || s === 6) e.hit(keysChord(b.sr, CH[ci]), at, s === 0 ? 0.3 : 0.2, 1, bus, s === 0 ? 0.9 : 0.35);
    if (s % 4 === 0) e.hit(b.pluck, at, 0.5, pr(ROOT[ci] - 12 + walk[s / 4]), bus);
    if (s % 4 === 0 || s % 8 === 6) e.hit(b.hat, at, 0.1, 0.8, bus);
    if (s % 2 === 0) e.hit(b.shaker, at, 0.07, 0.7, bus);
  });
}

export function makeTrack(kind: TrackKind, e: Engine, t0: number): Track {
  switch (kind) {
    case 'club': return club(e, t0);
    case 'buka': return buka(e, t0);
    case 'market': return market(e, t0);
    case 'motorpark': return motorpark(e, t0);
    case 'stadium': return stadium(e, t0);
    case 'cinema': return cinema(e, t0);
    case 'lounge': return lounge(e, t0);
  }
}

// ---------------------------------------------------------------- one-shots
/** The "Doremi" stinger: a bright rising do-re-mi arpeggio over a whoosh + an air-horn-ish swell (~1.5 s). */
export function stingerOn(c: Ctx, dest: AudioNode, at: number, gain = 1) {
  const out = c.createGain();
  out.gain.value = gain;
  out.connect(dest);
  const notes = [72, 74, 76, 77, 79, 84]; // do re mi fa sol do'
  notes.forEach((n, i) => {
    const t = at + i * 0.085;
    for (const det of [-6, 6]) {
      const o = c.createOscillator();
      const g = c.createGain();
      o.type = 'sawtooth';
      o.frequency.value = hz(n);
      o.detune.value = det;
      const f = c.createBiquadFilter();
      f.type = 'lowpass';
      f.frequency.setValueAtTime(5200, t);
      f.frequency.exponentialRampToValueAtTime(1600, t + 0.3);
      const last = i === notes.length - 1;
      const len = last ? 0.55 : 0.16;
      g.gain.setValueAtTime(0.0001, t);
      g.gain.exponentialRampToValueAtTime(0.09, t + 0.008);
      g.gain.exponentialRampToValueAtTime(0.0001, t + len);
      o.connect(f).connect(g).connect(out);
      o.start(t);
      o.stop(t + len + 0.05);
    }
  });
  // whoosh: noise through a band rising 300 Hz -> 6 kHz
  const bank = getBank(c.sampleRate);
  const ns = c.createBufferSource();
  const nb = c.createBuffer(1, bank.noise.length, c.sampleRate);
  nb.getChannelData(0).set(bank.noise);
  ns.buffer = nb;
  const bp = c.createBiquadFilter();
  bp.type = 'bandpass';
  bp.Q.value = 1.6;
  bp.frequency.setValueAtTime(300, at);
  bp.frequency.exponentialRampToValueAtTime(6000, at + 1.1);
  const ng = c.createGain();
  ng.gain.setValueAtTime(0.0001, at);
  ng.gain.exponentialRampToValueAtTime(0.22, at + 0.9);
  ng.gain.exponentialRampToValueAtTime(0.0001, at + 1.35);
  ns.connect(bp).connect(ng).connect(out);
  ns.start(at);
  ns.stop(at + 1.4);
  // air-horn-ish swell: three detuned saws, the pitch leaning up, a filter opening
  const hs = at + 0.45;
  const hf = c.createBiquadFilter();
  hf.type = 'lowpass';
  hf.frequency.setValueAtTime(500, hs);
  hf.frequency.exponentialRampToValueAtTime(3800, hs + 0.6);
  const hg = c.createGain();
  hg.gain.setValueAtTime(0.0001, hs);
  hg.gain.exponentialRampToValueAtTime(0.07, hs + 0.35);
  hg.gain.setValueAtTime(0.07, hs + 0.8);
  hg.gain.exponentialRampToValueAtTime(0.0001, hs + 1.05);
  hf.connect(hg).connect(out);
  for (const det of [-12, 0, 9]) {
    const o = c.createOscillator();
    o.type = 'sawtooth';
    o.frequency.setValueAtTime(hz(70), hs);
    o.frequency.exponentialRampToValueAtTime(hz(70.6), hs + 0.8);
    o.detune.value = det;
    o.connect(hf);
    o.start(hs);
    o.stop(hs + 1.1);
  }
}

/** A soft two-note bell for the app-wide ticker. */
export function softCueOn(c: Ctx, dest: AudioNode, at: number) {
  for (const [n, d] of [[84, 0], [88, 0.11]] as const) {
    const o = c.createOscillator();
    const g = c.createGain();
    o.frequency.value = hz(n);
    g.gain.setValueAtTime(0.0001, at + d);
    g.gain.exponentialRampToValueAtTime(0.06, at + d + 0.01);
    g.gain.exponentialRampToValueAtTime(0.0001, at + d + 0.5);
    o.connect(g).connect(dest);
    o.start(at + d);
    o.stop(at + d + 0.55);
  }
}

/** The crowd goes "ayyy": a formant-ish voice swell from several detuned voices + a noise roar. */
export function cheerOn(c: Ctx, dest: AudioNode, at: number, gain = 1) {
  const out = c.createGain();
  out.gain.setValueAtTime(0.0001, at);
  out.gain.exponentialRampToValueAtTime(0.5 * gain, at + 0.25);
  out.gain.setValueAtTime(0.5 * gain, at + 0.7);
  out.gain.exponentialRampToValueAtTime(0.0001, at + 1.5);
  out.connect(dest);
  const f1 = c.createBiquadFilter();
  f1.type = 'bandpass';
  f1.frequency.setValueAtTime(650, at);
  f1.frequency.linearRampToValueAtTime(900, at + 0.6);
  f1.Q.value = 3;
  const f2 = c.createBiquadFilter();
  f2.type = 'bandpass';
  f2.frequency.setValueAtTime(1500, at);
  f2.frequency.linearRampToValueAtTime(2100, at + 0.6);
  f2.Q.value = 4;
  const vg = c.createGain();
  vg.gain.value = 0.18;
  f1.connect(vg);
  f2.connect(vg);
  vg.connect(out);
  const r = rng(Math.floor(at * 100));
  for (let v = 0; v < 6; v++) {
    const o = c.createOscillator();
    o.type = 'sawtooth';
    const f = 170 + r() * 160;
    o.frequency.setValueAtTime(f, at);
    o.frequency.exponentialRampToValueAtTime(f * 1.25, at + 0.5);
    o.frequency.exponentialRampToValueAtTime(f * 1.1, at + 1.4);
    o.connect(f1);
    o.connect(f2);
    o.start(at + r() * 0.08);
    o.stop(at + 1.55);
  }
  const bank = getBank(c.sampleRate);
  const ns = c.createBufferSource();
  const nb = c.createBuffer(1, bank.crowd.length, c.sampleRate);
  nb.getChannelData(0).set(bank.crowd);
  ns.buffer = nb;
  const ng = c.createGain();
  ng.gain.value = 0.8;
  ns.connect(ng).connect(out);
  ns.start(at);
  ns.stop(at + 1.55);
}

// ---------------------------------------------------------------- offline render (checks)
export async function renderOffline(what: TrackKind | 'stinger' | 'cheer', secs: number, sr = 44100) {
  const OAC = (window as unknown as { OfflineAudioContext: typeof OfflineAudioContext }).OfflineAudioContext;
  const c = new OAC(1, Math.ceil(sr * secs), sr);
  const master = c.createGain();
  master.gain.value = 0.8;
  master.connect(c.destination);
  if (what === 'stinger') stingerOn(c, master, 0.05);
  else if (what === 'cheer') cheerOn(c, master, 0.05);
  else {
    const e = new Engine(c, master);
    // currentTime stays 0 before rendering, so schedule the whole span up front
    const tr = makeTrack(what, e, 0.05);
    for (let i = 0; i < 64; i++) tr.schedule(secs); // a grid track returns early when a radio changes song
  }
  const buf = await c.startRendering();
  const d = buf.getChannelData(0);
  let sum = 0;
  let peak = 0;
  for (let i = 0; i < d.length; i++) {
    sum += d[i] * d[i];
    peak = Math.max(peak, Math.abs(d[i]));
  }
  return { rms: Math.sqrt(sum / d.length), peak, wav: toWav(d, sr) };
}

function toWav(d: Float32Array, sr: number): string {
  const n = d.length;
  const ab = new ArrayBuffer(44 + n * 2);
  const v = new DataView(ab);
  const w = (o: number, s: string) => { for (let i = 0; i < s.length; i++) v.setUint8(o + i, s.charCodeAt(i)); };
  w(0, 'RIFF'); v.setUint32(4, 36 + n * 2, true); w(8, 'WAVE'); w(12, 'fmt ');
  v.setUint32(16, 16, true); v.setUint16(20, 1, true); v.setUint16(22, 1, true); v.setUint32(24, sr, true);
  v.setUint32(28, sr * 2, true); v.setUint16(32, 2, true); v.setUint16(34, 16, true); w(36, 'data'); v.setUint32(40, n * 2, true);
  for (let i = 0; i < n; i++) v.setInt16(44 + i * 2, Math.max(-1, Math.min(1, d[i])) * 0x7fff, true);
  let s = '';
  const u = new Uint8Array(ab);
  for (let i = 0; i < u.length; i += 0x8000) s += String.fromCharCode(...u.subarray(i, i + 0x8000));
  return btoa(s);
}
