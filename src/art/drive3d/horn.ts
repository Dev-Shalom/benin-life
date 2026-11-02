// A short two-tone car horn (Web Audio, no files). Respects the mute and sound-effects settings.
import { usePrefs } from '../../lib/prefs';

let ctx: AudioContext | null = null;

export function honk(): void {
  const p = usePrefs.getState();
  if (p.muted || !p.sfx) return;
  try {
    const AC = window.AudioContext ?? (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
    if (!AC) return;
    ctx ??= new AC();
    if (ctx.state === 'suspended') void ctx.resume();
    const t = ctx.currentTime;
    const g = ctx.createGain();
    g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(0.16, t + 0.03);
    g.gain.setValueAtTime(0.16, t + 0.28);
    g.gain.exponentialRampToValueAtTime(0.0001, t + 0.42);
    g.connect(ctx.destination);
    for (const f of [392, 494]) {
      const o = ctx.createOscillator();
      o.type = 'square';
      o.frequency.value = f;
      const lp = ctx.createBiquadFilter();
      lp.type = 'lowpass';
      lp.frequency.value = 1400;
      o.connect(lp).connect(g);
      o.start(t);
      o.stop(t + 0.45);
    }
  } catch {
    /* no audio: nothing to do */
  }
}
