// S1 sound: everything is synthesized with WebAudio (no audio files, nothing to download).
//   SFX      click on buttons/taps (one delegated listener), cues: money in, action done, alert, error
//   music    a soft highlife-flavoured pad + pluck loop; slower, minor chords at night
//   ambience city bed (filtered noise) with distant horns by day, crickets at night
//   places   P2: each place's own soundtrack from src/lib/music.ts (club amapiano groove, buka radio, market,
//            stadium, cinema, hotel lounge, motor park), one scheduler; readBeat() = the beat clock for visuals;
//            playHype() = the "Doremi" stinger + crowd cheer for club announcements (soft cue for the ticker)
// Rules: nothing starts before the first user gesture (autoplay policy); SFX follow Settings "Sound
// effects", music + ambience follow "Music"; the HUD mute silences all. The context is suspended while
// the tab is hidden. Music/ambience only play inside the game (setSoundScene from Game.tsx).
import { usePrefs } from './prefs';
import { CLUB_BPM, Engine, cheerOn, makeTrack, renderOffline, softCueOn, stingerOn, type Track, type TrackKind } from './music';

export type Cue = 'click' | 'money' | 'done' | 'alert' | 'error';

const VOL = { master: 0.6, sfx: 0.35, music: 0.11, amb: 0.07 };

let ctx: AudioContext | null = null;
let master: GainNode;
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
    master = ctx.createGain();
    master.gain.value = VOL.master;
    master.connect(ctx.destination);
    sfxBus = bus(VOL.sfx);
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
}

// ---------- SFX ----------
const PRIORITY: Record<Cue, number> = { click: 0, alert: 1, done: 2, error: 3, money: 4 };
let lastCue = { p: -1, t: 0 };

/** Play a short cue (ignored when SFX are off, or a cue as important played a moment ago). */
export function playCue(c: Cue) {
  if (!sfxOn() || !ensureCtx() || ctx!.state !== 'running') return;
  const now = ctx!.currentTime;
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
  const bpm = night ? 70 : 92;
  const eighth = 60 / bpm / 2;
  const chords = night ? CHORDS_NIGHT : CHORDS_DAY;
  const pluck = night ? PLUCK_NIGHT : PLUCK_DAY;
  const cutoff = night ? 650 : 1100;
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
    if (s === 0 || (!night && s === 5)) tone(hz(chord[0] - 12), nextAt, eighth * 2, { type: 'sine', gain: 0.14, release: eighth * 2.5, dest: musicBus });
    if (pluck.includes(s)) {
      const n = chord[(bar + s) % chord.length] + 12;
      tone(hz(n), nextAt, 0.3, { type: 'triangle', gain: 0.06, release: 0.35, dest: musicBus, cutoff: cutoff * 2 });
    }
    step++;
    nextAt += eighth;
  }
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
export type PlaceSound = 'club' | 'buka' | 'bank' | 'market' | 'generator' | 'stadium' | 'cinema' | 'lounge' | 'motorpark' | null;
// bus levels, matched to the old background music (a groove peak of ~0.04 after the master): felt, not loud
const PLACE_LEVEL: Record<string, number> = { club: 0.12, buka: 0.1, market: 0.24, stadium: 0.2, cinema: 0.14, lounge: 0.09, motorpark: 0.28 };
let placeSound: PlaceSound = null;
let placeTimer: number | null = null;
let placeBus: GainNode | null = null;
let placeEngine: Engine | null = null;
let placeTrack: Track | null = null;
let placeTick = 0;
let placeDrone: { osc: OscillatorNode[]; g: GainNode } | null = null;
let duckUntil = 0;
// a licensed club track (admin: music.club_track_url) replaces the synth groove when set
let clubTrackUrl = '';
let fileAudio: HTMLAudioElement | null = null;

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
  if (placeTimer !== null) window.clearInterval(placeTimer);
  placeTimer = null;
  placeTrack?.stop();
  placeTrack = null;
  if (placeBus && ctx) {
    const b = placeBus;
    b.gain.cancelScheduledValues(ctx.currentTime);
    b.gain.setTargetAtTime(0, ctx.currentTime, 0.25);
    window.setTimeout(() => { try { b.disconnect(); } catch { /* gone */ } }, 1500);
  }
  placeBus = null;
  placeEngine = null;
  if (fileAudio) {
    fileAudio.pause();
    fileAudio.src = '';
    fileAudio = null;
  }
  if (placeDrone && ctx) {
    const d = placeDrone;
    d.g.gain.setTargetAtTime(0, ctx.currentTime, 0.3);
    window.setTimeout(() => { for (const o of d.osc) try { o.stop(); } catch { /* stopped */ } }, 1200);
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
    placeBus.gain.setValueAtTime(0, ctx.currentTime);
    placeBus.gain.linearRampToValueAtTime(level, ctx.currentTime + 1.5);
    placeBus.connect(master);
    if (placeSound === 'club' && clubTrackUrl) {
      try {
        fileAudio = new Audio(clubTrackUrl);
        fileAudio.loop = true;
        fileAudio.volume = Math.min(1, level * 2.5 * VOL.master);
        void fileAudio.play().catch(() => {});
      } catch { fileAudio = null; }
    }
    if (!fileAudio) {
      placeEngine = new Engine(ctx, placeBus);
      placeTrack = makeTrack(placeSound as TrackKind, placeEngine, ctx.currentTime + 0.15);
    }
  }
  placeTick = 0;
  placeTimer = window.setInterval(schedulePlace, 100);
  schedulePlace();
}

/** Game.tsx: the soundtrack of the place you're in (null = just the city / home bed). */
export function setSoundPlace(k: PlaceSound) {
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
 *  visuals' hype moment (DJ / hype man / crowd react). 'global' = the soft cue for the app-wide ticker. */
export function playHype(kind: 'club' | 'global') {
  if (kind === 'club') hypeAt = performance.now() / 1000;
  if (!unlocked || !ensureCtx() || ctx!.state !== 'running') return;
  const t = ctx!.currentTime + 0.03;
  if (kind === 'global') {
    if (sfxOn()) softCueOn(ctx!, sfxBus, t);
    return;
  }
  if (sfxOn()) stingerOn(ctx!, sfxBus, t, 1.5);
  if (placeBus && musicOn() && placeSound === 'club') {
    // duck the groove under the stinger, then the crowd cheers
    const lvl = PLACE_LEVEL.club;
    if (t > duckUntil) {
      placeBus.gain.cancelScheduledValues(t);
      placeBus.gain.setValueAtTime(lvl, t);
      placeBus.gain.linearRampToValueAtTime(lvl * 0.45, t + 0.12);
      placeBus.gain.setValueAtTime(lvl * 0.45, t + 1.3);
      placeBus.gain.linearRampToValueAtTime(lvl, t + 2.2);
      duckUntil = t + 2.2;
    }
    cheerOn(ctx!, placeBus, t + 1.0, 1.1);
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
  sfxBus.gain.value = VOL.sfx;
  if (musicOn()) {
    if (musicTimer === null) {
      step = 0;
      nextAt = ctx!.currentTime + 0.1;
      musicTimer = window.setInterval(scheduleMusic, 150);
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
      ambTimer = window.setInterval(() => { if (Math.random() < 0.35) ambienceEvent(); }, 2500);
    }
    fade(musicBus, VOL.music);
    fade(ambBus, VOL.amb);
    if (placeSound && placeTimer === null) applyPlace();
    else if (placeSound) fade(musicBus, placeSound in PLACE_LEVEL ? VOL.music * 0.15 : VOL.music * 0.7);
  } else if (musicTimer !== null || ambSrc) {
    fade(musicBus, 0, 0.6);
    fade(ambBus, 0, 0.6);
    const src = ambSrc;
    if (musicTimer !== null) window.clearInterval(musicTimer);
    if (ambTimer !== null) window.clearInterval(ambTimer);
    musicTimer = null;
    ambTimer = null;
    ambSrc = null;
    ambFilter = null;
    window.setTimeout(() => { try { src?.stop(); } catch { /* already stopped */ } }, 700);
  }
  if (!musicOn()) stopPlace();
}

/** Game.tsx: music/ambience only inside the game; day/night picks the mood. */
export function setSoundScene(inGame: boolean, night: boolean) {
  const changedNight = night !== scene.night;
  scene = { inGame, night };
  apply();
  if (changedNight) tuneAmbience();
}

let installed = false;
/** Call once at startup: unlock on the first gesture, click SFX, pause while hidden. */
export function initSound() {
  if (installed || typeof window === 'undefined') return;
  installed = true;
  const unlock = () => {
    if (unlocked) return;
    if (!ensureCtx()) return;
    unlocked = true;
    void ctx!.resume().then(apply).catch(() => {});
    window.removeEventListener('pointerdown', unlock, true);
    window.removeEventListener('keydown', unlock, true);
  };
  window.addEventListener('pointerdown', unlock, true);
  window.addEventListener('keydown', unlock, true);
  document.addEventListener('click', (e) => {
    const el = (e.target as Element | null)?.closest?.('button, [role="button"], a.bl-btn');
    if (!el || (el as HTMLButtonElement).disabled || el.getAttribute('aria-disabled') === 'true') return;
    playCue('click');
  }, true);
  document.addEventListener('visibilitychange', () => {
    if (!ctx || !unlocked) return;
    if (document.visibilityState === 'hidden') {
      void ctx.suspend().catch(() => {});
      fileAudio?.pause();
    } else {
      void ctx.resume().catch(() => {});
      if (fileAudio) void fileAudio.play().catch(() => {});
    }
  });
  usePrefs.subscribe(apply);
  if (import.meta.env.DEV) (window as unknown as { __blSound?: unknown }).__blSound = { render: renderOffline, playHype, readBeat, setPlaceTrack };
}
