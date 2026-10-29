// M1 club radio, the audio side (docs/MUSIC.md). Plays a RadioPlaylist (src/lib/radio.ts) through the game's ONE
// AudioContext: two <audio> elements (A/B) -> MediaElementSource -> a deck gain -> the place bus (so the master
// limiter, mute, the Music setting and the hype ducking all apply). A 200 ms tick compares the schedule (server
// clock) with what the element is doing: it starts the right track at the right offset, swaps decks at track
// boundaries (the next track is preloaded in the spare deck), fades out / in across the boundary, and re-seeks when
// the element drifts more than 0.4 s. After a hidden tab / lock screen / stall the next tick resyncs by itself.
import { fadeGain, locate, type RadioPlaylist, type RadioSlot } from './radio';

const XF_MS = 900; // fade out / in around each track change
const PRELOAD_MS = 25_000; // start loading the next track this long before the boundary
const DRIFT_FIRST = 0.08; // s: first alignment after (re)starting a track
const DRIFT_LATER = 0.4; // s: later corrections (seeking too often stutters)
const TICK_MS = 200;
// 0-sample WAV: lets the gesture handler "unlock" the two elements on iOS (play() must start from a tap once per element)
const SILENT = 'data:audio/wav;base64,UklGRiQAAABXQVZFZm10IBAAAAABAAEAQB8AAEAfAAABAAgAZGF0YQAAAAA=';

interface Deck {
  el: HTMLAudioElement;
  gain: GainNode;
  trackId: string | null;
  url: string;
  synced: boolean;
  lastSeek: number;
  errAt: number;
  owner: ClubRadio | null;
}

let pool: Deck[] = [];
let poolCtx: AudioContext | null = null;

/** Create (once per context) and unlock the two decks. Call from a user gesture, after the context exists. */
export function primeRadioDecks(ctx: AudioContext) {
  if (poolCtx === ctx && pool.length) return;
  poolCtx = ctx;
  pool = [];
  for (let i = 0; i < 2; i++) {
    const el = new Audio();
    el.crossOrigin = 'anonymous'; // before any src: the bucket sends CORS headers, and WebAudio needs them
    el.preload = 'auto';
    el.setAttribute('playsinline', '');
    let gain: GainNode;
    try {
      const src = ctx.createMediaElementSource(el);
      gain = ctx.createGain();
      gain.gain.value = 0;
      src.connect(gain);
    } catch {
      pool = [];
      return;
    }
    pool.push({ el, gain, trackId: null, url: '', synced: false, lastSeek: 0, errAt: 0, owner: null });
    try {
      el.src = SILENT;
      void el.play().then(() => el.pause()).catch(() => {});
    } catch { /* unlock is best effort */ }
  }
}

/** Own-music mode: drop the two decks entirely (pause, empty the source, disconnect), so no media element stays
 *  alive holding audio focus. The next primeRadioDecks builds fresh ones. */
export function releaseRadioDecks() {
  for (const d of pool) {
    d.owner = null;
    try { d.el.pause(); d.el.removeAttribute('src'); d.el.load(); } catch { /* gone */ }
    try { d.gain.disconnect(); } catch { /* not connected */ }
  }
  pool = [];
  poolCtx = null;
}

export interface RadioInfo {
  playlist: string; playlistId: string; track: string; trackId: string; slot: number; cycle: number; index: number;
  expectedS: number; actualS: number; driftS: number; durationS: number; next: string; paused: boolean; playing: boolean; ready: number;
  order: string[];
}

export class ClubRadio {
  private timer: number | null = null;
  private cur: Deck | null = null;
  private curKey = -1;
  private paused = false;
  private dead = false;
  private lastLoc: RadioSlot | null = null;
  seeks = 0;
  swaps = 0;

  private ctx: AudioContext;
  private out: AudioNode;
  readonly playlist: RadioPlaylist;
  private now: () => number;
  private vol: number;

  constructor(ctx: AudioContext, out: AudioNode, playlist: RadioPlaylist, now: () => number, vol = 2.5) {
    this.ctx = ctx;
    this.out = out;
    this.playlist = playlist;
    this.now = now;
    this.vol = vol;
  }

  /** false when the decks could not be created (no MediaElementSource): the caller falls back. */
  start(): boolean {
    if (pool.length < 2 || poolCtx !== this.ctx) primeRadioDecks(this.ctx);
    if (pool.length < 2) return false;
    for (const d of pool) {
      d.owner = this;
      try { d.gain.disconnect(); } catch { /* not connected */ }
      d.gain.connect(this.out);
      d.gain.gain.cancelScheduledValues(this.ctx.currentTime);
      d.gain.gain.setValueAtTime(0, this.ctx.currentTime);
    }
    this.timer = window.setInterval(() => this.tick(), TICK_MS);
    this.tick();
    return true;
  }

  pause() {
    this.paused = true;
    for (const d of pool) if (d.owner === this) d.el.pause();
  }

  /** Back from hidden / yielded: the next tick resyncs to the club's current moment. */
  resume() {
    this.paused = false;
    for (const d of pool) if (d.owner === this) { d.synced = false; d.lastSeek = 0; }
    this.tick();
  }

  dispose() {
    if (this.dead) return;
    this.dead = true;
    if (this.timer !== null) window.clearInterval(this.timer);
    this.timer = null;
    const t = this.ctx.currentTime;
    for (const d of pool) {
      if (d.owner !== this) continue;
      d.gain.gain.cancelScheduledValues(t);
      d.gain.gain.setValueAtTime(d.gain.gain.value, t);
      d.gain.gain.linearRampToValueAtTime(0, t + 0.12);
      window.setTimeout(() => {
        if (d.owner !== this) return; // a newer radio took the deck over
        d.el.pause();
        try { d.gain.disconnect(); } catch { /* gone */ }
        d.owner = null;
        d.trackId = null;
      }, 220);
    }
    this.cur = null;
  }

  private load(d: Deck, url: string, trackId: string) {
    if (d.url === url && d.trackId === trackId) return;
    d.url = url;
    d.trackId = trackId;
    d.synced = false;
    d.errAt = 0;
    d.el.src = url;
    d.el.load();
  }

  private tick() {
    if (this.dead || this.paused || document.hidden || this.ctx.state !== 'running') return;
    const loc = locate(this.playlist, this.now());
    if (!loc) return;
    this.lastLoc = loc;
    if (!this.cur || this.curKey !== loc.key) this.switchTo(loc);
    else this.maintain(this.cur, loc);
    this.preload(loc);
  }

  private spare(): Deck {
    return pool.find((d) => d !== this.cur) ?? pool[0];
  }

  private switchTo(loc: RadioSlot) {
    const old = this.cur;
    // the spare may already hold this track (preloaded); otherwise load it now
    let d = pool.find((x) => x !== old && x.trackId === loc.track.id && x.url === loc.track.url);
    if (!d) d = this.spare();
    if (old && old !== d) {
      const t = this.ctx.currentTime;
      old.gain.gain.cancelScheduledValues(t);
      old.gain.gain.setValueAtTime(old.gain.gain.value, t);
      old.gain.gain.linearRampToValueAtTime(0, t + 0.08);
      window.setTimeout(() => { if (this.cur !== old) old.el.pause(); }, 120);
    }
    this.load(d, loc.track.url, loc.track.id);
    d.synced = false;
    this.cur = d;
    this.curKey = loc.key;
    this.swaps++;
    this.envelope(d, loc);
    this.maintain(d, loc);
  }

  /** Fade in over the first XF ms of the track, fade out over the last XF ms (the short crossfade). */
  private envelope(d: Deck, loc: RadioSlot) {
    const g = d.gain.gain;
    const t = this.ctx.currentTime;
    const dur = loc.track.duration_ms;
    g.cancelScheduledValues(t);
    g.setValueAtTime(fadeGain(loc.offsetMs, dur, XF_MS) * this.vol, t);
    let at = 0;
    if (loc.offsetMs < XF_MS) {
      at = (XF_MS - loc.offsetMs) / 1000;
      g.linearRampToValueAtTime(this.vol, t + at);
    }
    const rem = loc.remainingMs / 1000;
    const outAt = Math.max(at, rem - XF_MS / 1000);
    if (rem > 0.05) {
      g.setValueAtTime(this.vol * fadeGain(loc.offsetMs + outAt * 1000, dur, XF_MS), t + outAt);
      g.linearRampToValueAtTime(0, t + rem);
    }
  }

  private maintain(d: Deck, loc: RadioSlot) {
    const el = d.el;
    if (el.error) {
      // a bad file / network drop: try again in 5 s (the schedule keeps moving; the next track plays on time)
      if (Date.now() - d.errAt > 5000) { d.errAt = Date.now(); const u = d.url; d.url = ''; this.load(d, u, loc.track.id); }
      return;
    }
    if (el.readyState < 1) return; // still loading metadata
    const expected = loc.offsetMs / 1000;
    const dur = Number.isFinite(el.duration) ? el.duration : loc.track.duration_ms / 1000;
    if (expected >= dur - 0.05) return; // the file is shorter than its declared length: silence until the next slot
    const drift = el.currentTime - expected;
    const limit = d.synced ? DRIFT_LATER : DRIFT_FIRST;
    const canSeek = !el.seeking && (d.synced ? el.readyState >= 3 : true) && Date.now() - d.lastSeek > 1500;
    if (Math.abs(drift) > limit && canSeek) {
      el.currentTime = expected;
      d.lastSeek = Date.now();
      this.seeks++;
    }
    d.synced = true;
    if (el.paused || el.ended) void el.play().catch(() => { /* needs a tap: the next gesture retries */ });
  }

  private preload(loc: RadioSlot) {
    if (loc.remainingMs > PRELOAD_MS && this.spare().trackId !== null) return;
    const s = this.spare();
    if (s !== this.cur) this.load(s, loc.next.url, loc.next.id);
  }

  info(): RadioInfo | null {
    const loc = this.lastLoc ?? locate(this.playlist, this.now());
    const d = this.cur;
    if (!loc) return null;
    const live = locate(this.playlist, this.now()) ?? loc;
    return {
      playlist: this.playlist.name, playlistId: this.playlist.id, track: live.track.title, trackId: live.track.id, slot: live.key,
      cycle: live.cycle, index: live.index,
      expectedS: live.offsetMs / 1000, actualS: d ? d.el.currentTime : -1, driftS: d ? d.el.currentTime - live.offsetMs / 1000 : 0,
      durationS: live.track.duration_ms / 1000, next: live.next.title, paused: this.paused, playing: !!d && !d.el.paused && d.el.readyState >= 2,
      ready: d ? d.el.readyState : 0,
      order: this.playlist.shuffle ? [] : this.playlist.tracks.map((t) => t.title),
    };
  }
}
