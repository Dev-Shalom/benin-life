// S1 sound: everything is synthesized with WebAudio (no audio files, nothing to download).
//   SFX      click on buttons/taps (one delegated listener), cues: money in, action done, alert, error
//   music    a calm, gently upbeat highlife-flavoured pad + pluck groove; softer at night
//   ambience city bed (filtered noise) with distant horns by day, crickets at night
//   places   P2: each place's own soundtrack from src/lib/music.ts (club amapiano groove, buka radio, market,
//            stadium, cinema, hotel lounge, motor park), one scheduler; readBeat() = the beat clock for visuals;
//            playHype() = the "Doremi" stinger + crowd cheer for club announcements (soft cue for the ticker)
// Rules: nothing starts before the first user gesture (autoplay policy); SFX follow Settings "Sound
// effects", music + ambience follow "Music"; the HUD mute silences all. The context is suspended while
// the tab is hidden. Music/ambience only play inside the game (setSoundScene from Game.tsx).
// See docs/SOUND.md for the lifecycle rules (one context, one soundtrack, voice cap, limiter, tab ownership).
import { usePrefs } from './prefs';
import { serverNow } from './clock';
import { ClubRadio, primeRadioDecks } from './clubRadio';
import { radioClockInfo, radioNow, samePlaylist, type RadioPlaylist } from './radio';
import { CLUB_BPM, Engine, cheerOn, makeTrack, renderOffline, softCueOn, stingerOn, track, voiceStats, type Track, type TrackKind } from './music';

export type Cue = 'click' | 'money' | 'done' | 'alert' | 'error';

const VOL = { master: 0.6, sfx: 0.35, music: 0.11, amb: 0.07 };

/** Max simultaneous one-shot voices (cues, coins, stingers, cheers, ambience). Music is bounded by its look-ahead. */
const SFX_VOICE_CAP = 64;
const voiceFree = (n = 1) => voiceStats.sfx + n <= SFX_VOICE_CAP;

// dev-only counters (window.__blSound.stats()), used by scripts/sound-check.mjs
const dbg = { ctxCreated: 0, intervals: 0, buses: 0, engines: 0, hypeSkipped: 0 };
function setIv(fn: () => void, ms: number): number { dbg.intervals++; return window.setInterval(fn, ms); }
function clearIv(id: number) { dbg.intervals--; window.clearInterval(id); }

let ctx: AudioContext | null = null;
let master: GainNode;
let limiter: DynamicsCompressorNode;
let sfxBus: GainNode;
let musicBus: GainNode;
let ambBus: GainNode;
let noise: AudioBuffer;
let unlocked = false;
let scene = { inGame: false, night: false };

const prefs = () => usePrefs.getState();
const sfxOn = () => unlocked && !prefs().muted && prefs().sfx;
const musicOn = () => unlocked && !prefs().muted && prefs().music && scene.inGame;

function ensureCtx(): AudioContext | null {
  if (ctx) return ctx;
  try {
    const AC = window.AudioContext ?? (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
    if (!AC) return null;
    ctx = new AC();
    dbg.ctxCreated++;
    master = ctx.createGain();
    master.gain.value = prefs().muted ? 0 : VOL.master;
    // a master limiter: several stingers + cheers + groove stack up without clipping or pumping the whole mix
    limiter = ctx.createDynamicsCompressor();
    limiter.threshold.value = -12;
    limiter.knee.value = 10;
    limiter.ratio.value = 12;
    limiter.attack.value = 0.003;
    limiter.release.value = 0.2;
    master.connect(limiter).connect(ctx.destination);
    sfxBus = bus(prefs().sfx ? VOL.sfx : 0);
    ctx.addEventListener('statechange', onState);
    musicBus = bus(0);
    ambBus = bus(0);
    noise = ctx.createBuffer(1, ctx.sampleRate * 2, ctx.sampleRate);
    const d = noise.getChannelData(0);
    let last = 0;
    for (let i = 0; i < d.length; i++) {
      // brown-ish noise: softer than white, sounds like distant traffic
      last = (last + 0.02 * (Math.random() * 2 - 1)) / 1.02;
      d[i] = last * 3.5;
    }
  } catch {
    ctx = null;
  }
  return ctx;
}

function bus(v: number): GainNode {
  const g = ctx!.createGain();
  g.gain.value = v;
  g.connect(master);
  return g;
}

const hz = (midi: number) => 440 * Math.pow(2, (midi - 69) / 12);

interface ToneOpts { type?: OscillatorType; gain?: number; attack?: number; release?: number; dest?: AudioNode; glide?: number; cutoff?: number }
function tone(freq: number, at: number, dur: number, o: ToneOpts = {}) {
  if (!ctx) return;
  const cat = o.dest === musicBus ? 'music' : 'sfx';
  if (cat === 'sfx' && !voiceFree()) { voiceStats.dropped++; return; }
  const osc = ctx.createOscillator();
  const g = ctx.createGain();
  osc.type = o.type ?? 'sine';
  osc.frequency.setValueAtTime(freq, at);
  if (o.glide) osc.frequency.exponentialRampToValueAtTime(o.glide, at + dur);
  const peak = o.gain ?? 0.2;
  const a = o.attack ?? 0.005;
  const r = o.release ?? dur;
  g.gain.setValueAtTime(0.0001, at);
  g.gain.exponentialRampToValueAtTime(peak, at + a);
  g.gain.exponentialRampToValueAtTime(0.0001, at + a + r);
  let out: AudioNode = g;
  if (o.cutoff) {
    const f = ctx.createBiquadFilter();
    f.type = 'lowpass';
    f.frequency.value = o.cutoff;
    g.connect(f);
    out = f;
  }
  osc.connect(g);
  out.connect(o.dest ?? sfxBus);
  osc.start(at);
  osc.stop(at + a + r + 0.05);
  track(osc, ctx, cat);
}

// ---------- SFX ----------
const PRIORITY: Record<Cue, number> = { click: 0, alert: 1, done: 2, error: 3, money: 4 };
let lastCue = { p: -1, t: 0 };
let lastClick = 0;

/** Play a short cue (ignored when SFX are off, or a cue as important played a moment ago). */
export function playCue(c: Cue) {
  if (!sfxOn() || !ensureCtx() || ctx!.state !== 'running') return;
  const now = ctx!.currentTime;
  if (c === 'click') {
    if (now - lastClick < 0.04) return; // a finger drumming on the screen is one click, not a buzz
    lastClick = now;
  }
  const p = PRIORITY[c];
  if (c !== 'click' && now - lastCue.t < 0.7 && lastCue.p >= p) return;
  if (c !== 'click') lastCue = { p, t: now };
  const t = now + 0.01;
  switch (c) {
    case 'click':
      tone(1800, t, 0.03, { type: 'triangle', gain: 0.07, release: 0.03 });
      break;
    case 'money':
      tone(hz(88), t, 0.12, { type: 'triangle', gain: 0.16, release: 0.18 });
      tone(hz(95), t + 0.08, 0.3, { type: 'triangle', gain: 0.16, release: 0.35 });
      tone(hz(100), t + 0.16, 0.4, { type: 'sine', gain: 0.08, release: 0.45 });
      break;
    case 'done':
      tone(hz(72), t, 0.12, { type: 'sine', gain: 0.18, release: 0.16 });
      tone(hz(79), t + 0.09, 0.25, { type: 'sine', gain: 0.18, release: 0.3 });
      break;
    case 'alert':
      tone(hz(81), t, 0.15, { type: 'sine', gain: 0.14, release: 0.22 });
      tone(hz(76), t + 0.16, 0.25, { type: 'sine', gain: 0.12, release: 0.3 });
      break;
    case 'error':
      tone(220, t, 0.22, { type: 'square', gain: 0.05, release: 0.22, glide: 150, cutoff: 900 });
      break;
  }
}

/** SP2: a bright coin "ting" for each picked note (pitch steps up with the streak, never throttled). */
let coinStep = 0;
let coinAt = 0;
export function playCoin() {
  if (!sfxOn() || !ensureCtx() || ctx!.state !== 'running') return;
  const now = ctx!.currentTime;
  coinStep = now - coinAt < 0.6 ? Math.min(coinStep + 1, 7) : 0;
  coinAt = now;
  const base = 88 + [0, 2, 4, 5, 7, 9, 11, 12][coinStep];
  const t = now + 0.005;
  tone(hz(base), t, 0.05, { type: 'square', gain: 0.05, release: 0.06, cutoff: 5200 });
  tone(hz(base + 7), t + 0.045, 0.22, { type: 'triangle', gain: 0.13, release: 0.24 });
  tone(hz(base + 19), t + 0.05, 0.16, { type: 'sine', gain: 0.05, release: 0.18 });
}

/** The admin page's new-ad chime, on the shared context (it used to open a fresh AudioContext each time). */
export function playChime() {
  if (!sfxOn() || !ensureCtx() || ctx!.state !== 'running') return;
  const t = ctx!.currentTime + 0.01;
  tone(880, t, 0.35, { gain: 0.25, attack: 0.02, release: 0.35 });
  tone(1320, t + 0.16, 0.35, { gain: 0.25, attack: 0.02, release: 0.35 });
}

/**
 * Onboarding: a soft, warm chord swell for the "Welcome to Benin Life" intro (about 4 s, slow attack, long tail).
 * Silent when audio is not unlocked yet, when muted or when sound effects are off.
 */
export function playSwell() {
  if (!sfxOn() || !ensureCtx() || ctx!.state !== 'running') return;
  const t = ctx!.currentTime + 0.05;
  // C major 9 spread over two octaves; each voice blooms slowly then fades
  [48, 55, 60, 64, 67, 71].forEach((m, i) => {
    tone(hz(m), t + i * 0.07, 3.4, { type: 'sine', gain: 0.1 - i * 0.008, attack: 1.6, release: 2.0, cutoff: 1800 });
  });
  tone(hz(84), t + 1.4, 1.2, { type: 'triangle', gain: 0.05, attack: 0.05, release: 1.4, cutoff: 5200 });
}

// ---------- music ----------
const CHORDS_DAY = [[60, 64, 67, 71], [57, 60, 64, 67], [53, 57, 60, 64], [55, 59, 62, 65]];
const CHORDS_NIGHT = [[57, 60, 64, 67], [53, 57, 60, 64], [50, 53, 57, 60], [52, 55, 59, 62]];
const PLUCK_DAY = [0, 3, 6]; // 3-3-2 feel over 8 eighths
const PLUCK_NIGHT = [0, 6];
let musicTimer: number | null = null;
let step = 0;
let nextAt = 0;

function scheduleMusic() {
  if (!ctx) return;
  const night = scene.night;
  const bpm = night ? 76 : 96;
  const eighth = 60 / bpm / 2;
  const chords = night ? CHORDS_NIGHT : CHORDS_DAY;
  const pluck = night ? PLUCK_NIGHT : PLUCK_DAY;
  const cutoff = night ? 650 : 1100;
  // fell behind (main thread stalled, throttled timer): jump to the next bar line instead of dumping every missed note at once
  if (nextAt < ctx.currentTime - 0.25) {
    step = Math.ceil(step / 8) * 8;
    nextAt = ctx.currentTime + 0.05;
  }
  while (nextAt < ctx.currentTime + 0.5) {
    const bar = Math.floor(step / 8);
    const s = step % 8;
    const chord = chords[Math.floor(bar / 2) % chords.length];
    if (s === 0 && bar % 2 === 0) {
      for (const n of chord) {
        tone(hz(n), nextAt, eighth * 16, { type: 'triangle', gain: 0.05, attack: 0.9, release: eighth * 16, dest: musicBus, cutoff });
        tone(hz(n) * 1.004, nextAt, eighth * 16, { type: 'sine', gain: 0.04, attack: 1.1, release: eighth * 16, dest: musicBus });
      }
    }
    if (s === 0 || s === 4) tone(hz(chord[0] - 12), nextAt, eighth * 2, { type: 'sine', gain: night ? 0.095 : 0.12, release: eighth * 2.5, dest: musicBus });
    // A very quiet, synthesized shaker on the off-beats adds lift without turning the home bed into a club track.
    if (s === 2 || (!night && s === 6)) softShaker(nextAt, night ? 0.008 : 0.012);
    if (pluck.includes(s)) {
      const n = chord[(bar + s) % chord.length] + 12;
      tone(hz(n), nextAt, 0.3, { type: 'triangle', gain: 0.06, release: 0.35, dest: musicBus, cutoff: cutoff * 2 });
    }
    step++;
    nextAt += eighth;
  }
}

function softShaker(at: number, level: number) {
  if (!ctx || !noise) return;
  const src = ctx.createBufferSource();
  const filter = ctx.createBiquadFilter();
  const gain = ctx.createGain();
  src.buffer = noise;
  filter.type = 'highpass';
  filter.frequency.value = 6200;
  gain.gain.setValueAtTime(level, at);
  gain.gain.exponentialRampToValueAtTime(0.0001, at + 0.055);
  src.connect(filter);
  filter.connect(gain);
  gain.connect(musicBus);
  src.start(at);
  src.stop(at + 0.06);
  track(src, ctx, 'music');
}

// ---------- ambience ----------
let ambSrc: AudioBufferSourceNode | null = null;
let ambFilter: BiquadFilterNode | null = null;
let ambTimer: number | null = null;

function ambienceEvent() {
  if (!ctx || ctx.state !== 'running') return;
  const t = ctx.currentTime + 0.05;
  if (scene.night) {
    // crickets: a few quick high chirps
    const n = 3 + Math.floor(Math.random() * 3);
    for (let i = 0; i < n; i++) tone(4300 + Math.random() * 300, t + i * 0.07, 0.03, { gain: 0.05, release: 0.04, dest: ambBus });
  } else {
    // a distant horn (keke / car), soft and muffled
    const f = 360 + Math.random() * 140;
    tone(f, t, 0.14, { type: 'square', gain: 0.05, release: 0.14, cutoff: 700, dest: ambBus });
    if (Math.random() < 0.5) tone(f, t + 0.2, 0.18, { type: 'square', gain: 0.05, release: 0.18, cutoff: 700, dest: ambBus });
  }
}

function tuneAmbience() {
  if (!ambFilter || !ctx) return;
  const t = ctx.currentTime;
  ambFilter.type = scene.night ? 'lowpass' : 'bandpass';
  ambFilter.frequency.setTargetAtTime(scene.night ? 260 : 480, t, 1.5);
}

// ---------- F1 + P2: per-place soundtracks (follow the Music setting, like the city bed) ----------
// One scheduler (100 ms tick, ~0.3 s lookahead) drives the place's track from src/lib/music.ts: the club's
// amapiano groove, the buka radio, market hawkers, stadium chants, cinema pad, hotel-lounge keys, motor park.
// Bank / hospital hum and a neighbour's generator stay simple drones. Paused while the tab is hidden.
// 'dance' = Q1: the afrobeats loop while a shared "Dance together" runs at home (both players' clients)
export type PlaceSound = 'club' | 'buka' | 'bank' | 'market' | 'generator' | 'stadium' | 'cinema' | 'lounge' | 'motorpark' | 'dance' | null;
// bus levels, matched to the old background music (a groove peak of ~0.04 after the master): felt, not loud
const PLACE_LEVEL: Record<string, number> = { club: 0.12, buka: 0.1, market: 0.24, stadium: 0.2, cinema: 0.14, lounge: 0.09, motorpark: 0.28, dance: 0.14 };
let placeSound: PlaceSound = null;
let placeTimer: number | null = null;
let leaveTimer: number | null = null;
let lastStingerAt = -1e9;
let cheerUntil = 0;
let placeBus: GainNode | null = null;
let placeEngine: Engine | null = null;
let placeTrack: Track | null = null;
let placeTick = 0;
let placeDrone: { osc: OscillatorNode[]; g: GainNode } | null = null;
let duckUntil = 0;
// a licensed club track (admin: music.club_track_url) replaces the synth groove when set
let clubTrackUrl = '';
let fileAudio: HTMLAudioElement | null = null;
// M1: the resolved club playlist (src/lib/clubMusic.ts) plays as a server-clock radio through the shared context
let radioPl: RadioPlaylist | null = null;
let radio: ClubRadio | null = null;

function placeVoices() {
  // a murmur of talk: a few short low saw 'syllables' through a lowpass
  const t = ctx!.currentTime + 0.02 + Math.random() * 0.2;
  const base = 150 + Math.random() * 170;
  const n = 2 + Math.floor(Math.random() * 4);
  for (let i = 0; i < n; i++) tone(base * (0.9 + Math.random() * 0.3), t + i * 0.13, 0.1, { type: 'sawtooth', gain: 0.018, release: 0.1, cutoff: 700, dest: ambBus });
}

function schedulePlace() {
  if (!ctx || ctx.state !== 'running' || !placeSound || document.hidden) return;
  const now = ctx.currentTime;
  placeTrack?.schedule(now + 0.3);
  // the old F1 murmur + pots under the buka radio and the market calls
  if (++placeTick % 6 === 0 && (placeSound === 'buka' || placeSound === 'market')) {
    if (Math.random() < (placeSound === 'market' ? 0.75 : 0.5)) placeVoices();
    if (placeSound === 'buka' && Math.random() < 0.18) tone(1900 + Math.random() * 900, now + 0.05, 0.05, { type: 'triangle', gain: 0.03, release: 0.18, dest: ambBus });
  }
}

function startDrone(freqs: number[], type: OscillatorType, cutoff: number, gain: number) {
  const g = ctx!.createGain();
  g.gain.value = 0;
  const f = ctx!.createBiquadFilter();
  f.type = 'lowpass';
  f.frequency.value = cutoff;
  g.connect(f).connect(ambBus);
  const osc = freqs.map((fr) => {
    const o = ctx!.createOscillator();
    o.type = type;
    o.frequency.value = fr;
    o.connect(g);
    o.start();
    return o;
  });
  g.gain.setTargetAtTime(gain, ctx!.currentTime, 0.8);
  placeDrone = { osc, g };
}

function stopPlace() {
  if (placeTimer !== null) clearIv(placeTimer);
  placeTimer = null;
  placeTrack?.stop();
  placeTrack = null;
  if (placeBus && ctx) {
    const b = placeBus;
    const eng = placeEngine;
    const t = ctx.currentTime;
    b.gain.cancelScheduledValues(t);
    b.gain.setValueAtTime(b.gain.value, t);
    b.gain.setTargetAtTime(0, t, 0.25);
    // long tails (cinema pad ~4.6 s) are silent by now; cut the graph so nothing accumulates
    window.setTimeout(() => {
      try { eng?.out.disconnect(); b.disconnect(); } catch { /* gone */ }
      dbg.buses--;
      dbg.engines--;
    }, 2500);
  }
  placeBus = null;
  placeEngine = null;
  cheerUntil = 0;
  duckUntil = 0;
  if (fileAudio) {
    fileAudio.pause();
    fileAudio.src = '';
    fileAudio = null;
  }
  radio?.dispose();
  radio = null;
  if (placeDrone && ctx) {
    const d = placeDrone;
    d.g.gain.setTargetAtTime(0, ctx.currentTime, 0.3);
    window.setTimeout(() => { for (const o of d.osc) try { o.stop(); o.disconnect(); } catch { /* stopped */ } try { d.g.disconnect(); } catch { /* gone */ } }, 2000);
  }
  placeDrone = null;
}

function applyPlace() {
  stopPlace();
  if (!musicOn() || !ctx || !placeSound) {
    if (ctx && musicTimer !== null) fade(musicBus, musicOn() ? VOL.music : 0);
    return;
  }
  // the place's own soundtrack replaces most of the background music
  if (musicTimer !== null) fade(musicBus, placeSound in PLACE_LEVEL ? VOL.music * 0.15 : VOL.music * 0.7);
  if (placeSound === 'bank') startDrone([100, 50.3], 'sine', 400, 0.05); // AC + fluorescent hum
  if (placeSound === 'generator') startDrone([47, 94.5], 'sawtooth', 170, 0.06); // "I better pass my neighbour"
  const level = PLACE_LEVEL[placeSound];
  if (level) {
    placeBus = ctx.createGain();
    dbg.buses++;
    placeBus.gain.setValueAtTime(0, ctx.currentTime);
    placeBus.gain.linearRampToValueAtTime(level, ctx.currentTime + 1.5);
    placeBus.connect(master);
    if ((placeSound === 'club' || placeSound === 'lounge') && radioPl) {
      radio = new ClubRadio(ctx, placeBus, radioPl, () => radioNow(serverNow()));
      if (!radio.start()) radio = null;
      else if (yielded || document.hidden) radio.pause();
    }
    if (!radio && placeSound === 'club' && clubTrackUrl) {
      try {
        fileAudio = new Audio(clubTrackUrl);
        fileAudio.loop = true;
        fileAudio.volume = Math.min(1, level * 2.5 * VOL.master);
        if (!document.hidden && !yielded) void fileAudio.play().catch(() => {});
      } catch { fileAudio = null; }
    }
    if (!fileAudio && !radio) {
      placeEngine = new Engine(ctx, placeBus);
      dbg.engines++;
      placeTrack = makeTrack(placeSound === 'dance' ? 'afrobeats' : placeSound as TrackKind, placeEngine, ctx.currentTime + 0.15);
    }
  }
  placeTick = 0;
  placeTimer = setIv(schedulePlace, 100);
  schedulePlace();
}

/** Game.tsx: the soundtrack of the place you're in (null = just the city / home bed). */
export function setSoundPlace(k: PlaceSound) {
  cancelLeave();
  if (k === placeSound) return;
  placeSound = k;
  if (unlocked && ensureCtx()) applyPlace();
}

/** A licensed club track (music.club_track_url) replaces the synthesized groove; '' / null = the synth. */
export function setPlaceTrack(url: string | null) {
  const u = (url ?? '').trim();
  if (u === clubTrackUrl) return;
  clubTrackUrl = u;
  if (placeSound === 'club' && unlocked && ensureCtx()) applyPlace();
}

/** M1: the club's resolved playlist (null = none): it plays as a radio and replaces the synth groove / the single
 *  licensed file. The same playlist (id, anchor, tracks) again is a no-op, so polling never restarts the music. */
export function setPlaceRadio(pl: RadioPlaylist | null) {
  if (samePlaylist(pl, radioPl)) return;
  radioPl = pl;
  if ((placeSound === 'club' || placeSound === 'lounge') && unlocked && ensureCtx()) applyPlace();
}

// ---------- P2: the beat clock (visuals read it every frame, no allocation) ----------
let hypeAt = -1e9;
const beatState = { bpm: CLUB_BPM, phase: 0, n: 0, pulse: 0, audible: false, hypeAge: 1e9 };
export type BeatClock = Readonly<typeof beatState>;
/** Current beat: phase 0..1, beat count, a 1 -> 0 pulse on each beat, seconds since the last hype moment.
 *  Follows the playing groove; with audio off a silent clock runs at the club BPM. Mutates one object. */
export function readBeat(): BeatClock {
  const tr = placeTrack;
  let b: number;
  if (ctx && tr && tr.bpm > 0 && ctx.state === 'running') {
    const lat = (ctx as AudioContext & { outputLatency?: number }).outputLatency || 0;
    b = Math.max(0, ((ctx.currentTime - lat - tr.t0) * tr.bpm) / 60);
    beatState.bpm = tr.bpm;
    beatState.audible = true;
  } else {
    beatState.bpm = CLUB_BPM;
    beatState.audible = false;
    b = (performance.now() / 1000) * (CLUB_BPM / 60);
  }
  beatState.n = Math.floor(b);
  beatState.phase = b - beatState.n;
  beatState.pulse = Math.exp(-beatState.phase * 5);
  beatState.hypeAge = performance.now() / 1000 - hypeAt;
  return beatState;
}

/** P2: a club announcement: the Doremi stinger (Sound setting) + the crowd's "ayyy" (Music setting), and the
 *  visuals' hype moment (DJ / hype man / crowd react). 'global' = the soft cue for the app-wide strip.
 *  P3: 'big' = Shut down the club (a doubled, louder stinger and a longer double cheer); 'calm' = a VIP arrival
 *  (the soft bell and a gentle cheer, no stinger). */
export function playHype(kind: 'club' | 'global' | 'big' | 'calm') {
  if (kind !== 'global') hypeAt = performance.now() / 1000;
  if (!unlocked || !ensureCtx() || ctx!.state !== 'running') return;
  const t = ctx!.currentTime + 0.03;
  if (kind === 'global') {
    if (sfxOn() && voiceFree(2)) softCueOn(ctx!, sfxBus, t);
    return;
  }
  if (kind === 'calm') {
    if (sfxOn() && voiceFree(2)) softCueOn(ctx!, sfxBus, t);
    if (placeBus && musicOn() && t + 0.35 > cheerUntil && voiceFree(8)) { cheerOn(ctx!, placeBus, t + 0.35, 0.5); cheerUntil = t + 1.9; }
    return;
  }
  const big = kind === 'big';
  // hype spam: one stinger at a time (a new one inside 0.6 s of the last is folded into it), and never past the voice cap
  const stingerOk = t - lastStingerAt > 0.6 && voiceFree(big ? 34 : 17);
  if (sfxOn()) {
    if (stingerOk) {
      lastStingerAt = t;
      stingerOn(ctx!, sfxBus, t, big ? 1.9 : 1.5);
      if (big) stingerOn(ctx!, sfxBus, t + 0.42, 0.9);
    } else dbg.hypeSkipped++;
  }
  if (placeBus && musicOn() && placeSound === 'club') {
    // duck the groove under the stinger, then the crowd cheers
    const lvl = PLACE_LEVEL.club;
    const hold = big ? 2.4 : 1.3;
    if (t > duckUntil && stingerOk) {
      const cur = placeBus.gain.value; // may still be fading in: never jump
      placeBus.gain.cancelScheduledValues(t);
      placeBus.gain.setValueAtTime(cur, t);
      placeBus.gain.linearRampToValueAtTime(lvl * 0.45, t + 0.12);
      placeBus.gain.setValueAtTime(lvl * 0.45, t + hold);
      placeBus.gain.linearRampToValueAtTime(lvl, t + hold + 0.9);
      duckUntil = t + hold + 0.9;
    }
    // crowd: one cheer at a time (they last ~1.5 s), so a burst of announcements is one roar, not a pile of them
    if (stingerOk && t + 1.0 > cheerUntil && voiceFree(8)) {
      cheerOn(ctx!, placeBus, t + 1.0, big ? 1.35 : 1.1);
      cheerUntil = t + 2.5;
      if (big && voiceFree(8)) { cheerOn(ctx!, placeBus, t + 2.3, 1.1); cheerUntil = t + 3.8; }
    }
  }
}

// ---------- start / stop ----------
function fade(g: GainNode, v: number, secs = 1.2) {
  if (!ctx) return;
  const t = ctx.currentTime;
  g.gain.cancelScheduledValues(t);
  g.gain.setValueAtTime(g.gain.value, t);
  g.gain.linearRampToValueAtTime(v, t + secs);
}

function apply() {
  if (!unlocked || !ensureCtx()) return;
  // mute / Sound effects: ramp (a hard jump clicks) and cut stingers already in flight, not just future ones
  const now0 = ctx!.currentTime;
  master.gain.setTargetAtTime(prefs().muted ? 0 : VOL.master, now0, 0.03);
  sfxBus.gain.setTargetAtTime(prefs().sfx ? VOL.sfx : 0, now0, 0.03);
  if (musicOn()) {
    if (musicTimer === null) {
      step = 0;
      nextAt = ctx!.currentTime + 0.1;
      musicTimer = setIv(scheduleMusic, 150);
      scheduleMusic();
    }
    if (!ambSrc) {
      ambSrc = ctx!.createBufferSource();
      ambSrc.buffer = noise;
      ambSrc.loop = true;
      ambFilter = ctx!.createBiquadFilter();
      ambFilter.Q.value = 0.6;
      ambSrc.connect(ambFilter).connect(ambBus);
      ambSrc.start();
      tuneAmbience();
      ambTimer = setIv(() => { if (Math.random() < 0.35) ambienceEvent(); }, 2500);
    }
    fade(musicBus, VOL.music);
    fade(ambBus, VOL.amb);
    if (placeSound && placeTimer === null) applyPlace();
    else if (placeSound) fade(musicBus, placeSound in PLACE_LEVEL ? VOL.music * 0.15 : VOL.music * 0.7);
  } else if (musicTimer !== null || ambSrc) {
    fade(musicBus, 0, 0.6);
    fade(ambBus, 0, 0.6);
    const src = ambSrc;
    const flt = ambFilter;
    if (musicTimer !== null) clearIv(musicTimer);
    if (ambTimer !== null) clearIv(ambTimer);
    musicTimer = null;
    ambTimer = null;
    ambSrc = null;
    ambFilter = null;
    window.setTimeout(() => { try { src?.stop(); src?.disconnect(); flt?.disconnect(); } catch { /* already stopped */ } }, 900);
  }
  if (!musicOn()) stopPlace();
}

/** Game.tsx: music/ambience only inside the game; day/night picks the mood. */
export function setSoundScene(inGame: boolean, night: boolean) {
  cancelLeave();
  const changedNight = night !== scene.night;
  scene = { inGame, night };
  apply();
  if (changedNight) tuneAmbience();
}

// ---------- lifecycle: leaving the game, tab ownership, resume ----------
function cancelLeave() {
  if (leaveTimer !== null) { window.clearTimeout(leaveTimer); leaveTimer = null; }
}

/** Game.tsx unmount. Deferred a beat so a StrictMode remount (or a quick route change back) keeps the music
 *  playing instead of stopping and restarting it; any setSoundScene/setSoundPlace in between cancels it. */
export function leaveGameSound() {
  cancelLeave();
  leaveTimer = window.setTimeout(() => {
    leaveTimer = null;
    scene = { inGame: false, night: false };
    placeSound = null;
    apply();
  }, 150);
}

// Only one tab plays: a hidden tab suspends its context, and of two visible windows the one you touched last
// wins (BroadcastChannel); the other yields until its next tap.
const tabId = Math.random().toString(36).slice(2);
let yielded = false;
let chan: BroadcastChannel | null = null;

function pauseAudio() {
  if (!ctx) return;
  if (ctx.state !== 'suspended') void ctx.suspend().catch(() => {});
  fileAudio?.pause();
  radio?.pause();
}

function claimTab() {
  yielded = false;
  try { chan?.postMessage({ id: tabId }); } catch { /* closed */ }
  radio?.resume();
}

/** Bring the sound back if this tab should be playing (visible, not yielded). Safe to call any time. */
function wake() {
  if (!ctx || !unlocked || yielded || document.hidden) return;
  if (ctx.state !== 'running') void ctx.resume().then(apply).catch(() => {});
  if (fileAudio) void fileAudio.play().catch(() => {});
  radio?.resume(); // resync to the club's current moment
}

function onState() {
  if (!ctx || !unlocked) return;
  if (ctx.state === 'running') {
    if (document.hidden || yielded) pauseAudio();
    else apply();
  }
}

let installed = false;
/** Call once at startup: unlock on the first gesture, click SFX, pause while hidden. */
export function initSound() {
  if (installed || typeof window === 'undefined') return;
  installed = true;
  try {
    // iOS: play through the speaker even with the ringer switch on silent (Safari 16.4+)
    const as = (navigator as unknown as { audioSession?: { type: string } }).audioSession;
    if (as) as.type = 'playback';
  } catch { /* unsupported */ }
  try {
    chan = new BroadcastChannel('bl-sound');
    chan.onmessage = (e) => {
      if (e.data?.id === tabId || !ctx || !unlocked) return;
      yielded = true;
      pauseAudio();
    };
  } catch { chan = null; }
  // Every gesture: first one unlocks; later ones bring a suspended / iOS "interrupted" context back (after a call,
  // the lock screen, an app switch). iOS only honours resume() from touchend / click, so listen to those too.
  const gesture = () => {
    if (!ensureCtx()) return;
    const first = !unlocked;
    unlocked = true;
    if (first) primeRadioDecks(ctx!); // iOS: unlock the two radio <audio> elements from a tap
    if (first || yielded || ctx!.state !== 'running') {
      claimTab();
      void ctx!.resume().then(apply).catch(() => {});
    }
  };
  for (const ev of ['pointerdown', 'pointerup', 'touchend', 'click', 'keydown'] as const) window.addEventListener(ev, gesture, true);
  document.addEventListener('click', (e) => {
    const el = (e.target as Element | null)?.closest?.('button, [role="button"], a.bl-btn');
    if (!el || (el as HTMLButtonElement).disabled || el.getAttribute('aria-disabled') === 'true') return;
    playCue('click');
  }, true);
  document.addEventListener('visibilitychange', () => {
    if (!ctx || !unlocked) return;
    if (document.visibilityState === 'hidden') pauseAudio();
    else { claimTab(); wake(); }
  });
  window.addEventListener('pagehide', () => { if (ctx && unlocked) pauseAudio(); });
  window.addEventListener('pageshow', () => { if (ctx && unlocked && !document.hidden) { claimTab(); wake(); } });
  window.addEventListener('focus', () => wake());
  usePrefs.subscribe(apply);
  if (import.meta.env.DEV) {
    (window as unknown as { __blSound?: unknown }).__blSound = {
      render: renderOffline, playHype, readBeat, setPlaceTrack, setPlaceRadio,
      /** M1: what the club radio is doing (track, expected vs actual position) for the Playwright sync proof. */
      radio: () => (radio ? { ...radio.info(), seeks: radio.seeks, swaps: radio.swaps, ...radioClockInfo(), gameSkewMs: serverNow() - Date.now() } : null),
      /** Live counters for scripts/sound-check.mjs. */
      stats: () => ({
        ...voiceStats,
        ...dbg,
        state: ctx?.state ?? 'none',
        place: placeSound,
        trackActive: placeTrack ? 1 : 0,
        radioActive: radio ? 1 : 0,
        busActive: placeBus ? 1 : 0,
        musicTimer: musicTimer !== null,
        hidden: document.hidden,
        yielded,
        unlocked,
      }),
    };
  }
}
