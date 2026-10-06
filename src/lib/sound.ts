// S1 sound: everything is synthesized with WebAudio (no audio files, nothing to download).
//   SFX      click on buttons/taps (one delegated listener), cues: money in, action done, alert, error
//   music    a soft highlife-flavoured pad + pluck loop; slower, minor chords at night
//   ambience city bed (filtered noise) with distant horns by day, crickets at night
// Rules: nothing starts before the first user gesture (autoplay policy); SFX follow Settings "Sound
// effects", music + ambience follow "Music"; the HUD mute silences all. The context is suspended while
// the tab is hidden. Music/ambience only play inside the game (setSoundScene from Game.tsx).
import { usePrefs } from './prefs';

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
    if (document.visibilityState === 'hidden') void ctx.suspend().catch(() => {});
    else void ctx.resume().catch(() => {});
  });
  usePrefs.subscribe(apply);
}
