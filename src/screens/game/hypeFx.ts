// P3 hype takeover: one capped canvas of naira notes, confetti and sparks (+ fireworks for a shutdown), and the
// aura pulsing on the beat (readBeat()). One rAF loop, preallocated typed arrays, no allocation per frame.
// About 120 particles on High, 40 on Low. Reduced motion never starts this (the takeover just fades).
import { readBeat } from '../../lib/sound';

export type HypeTier = 'gold' | 'bottles' | 'spray' | 'shout' | 'shutdown' | 'calm';

const NOTE_W = 120;
const NOTE_H = 58;
// a stylised green naira note (original art, no real bank marks)
const NOTE_SVG = `<svg xmlns='http://www.w3.org/2000/svg' width='${NOTE_W}' height='${NOTE_H}' viewBox='0 0 ${NOTE_W} ${NOTE_H}'>
<defs><linearGradient id='g' x1='0' y1='0' x2='1' y2='1'><stop offset='0' stop-color='#5fbf78'/><stop offset='.55' stop-color='#2f8f52'/><stop offset='1' stop-color='#1c6a3b'/></linearGradient>
<radialGradient id='s' cx='.72' cy='.5' r='.4'><stop offset='0' stop-color='#f6e7a8' stop-opacity='.55'/><stop offset='1' stop-color='#f6e7a8' stop-opacity='0'/></radialGradient></defs>
<rect x='1' y='1' width='118' height='56' rx='4' fill='url(#g)' stroke='#d8eebf' stroke-width='2'/>
<rect x='1' y='1' width='118' height='56' rx='4' fill='url(#s)'/>
<rect x='6' y='6' width='108' height='46' rx='2' fill='none' stroke='#eaf6d4' stroke-opacity='.55'/>
<path d='M8 40 Q30 30 52 40 T96 40' fill='none' stroke='#eaf6d4' stroke-opacity='.35'/>
<path d='M8 45 Q30 35 52 45 T96 45' fill='none' stroke='#eaf6d4' stroke-opacity='.25'/>
<circle cx='87' cy='28' r='17' fill='#103d22' fill-opacity='.28' stroke='#f3dc8a' stroke-opacity='.8' stroke-width='1.5'/>
<text x='87' y='36' font-family='Arial Black,Arial,sans-serif' font-weight='900' font-size='23' text-anchor='middle' fill='#f8eab0'>&#8358;</text>
<text x='12' y='22' font-family='Arial,sans-serif' font-weight='900' font-size='13' fill='#f8eab0'>1000</text>
<text x='112' y='52' font-family='Arial,sans-serif' font-weight='900' font-size='8' text-anchor='end' fill='#f8eab0' fill-opacity='.8'>1000</text>
</svg>`;

let noteImg: HTMLImageElement | null = null;
function note(): HTMLImageElement | null {
  if (typeof Image === 'undefined') return null;
  if (!noteImg) {
    noteImg = new Image();
    noteImg.decoding = 'async';
    noteImg.src = `data:image/svg+xml;charset=utf-8,${encodeURIComponent(NOTE_SVG)}`;
  }
  return noteImg.complete && noteImg.naturalWidth > 0 ? noteImg : null;
}
/** Start decoding the note early (the takeover mounts it on the first announcement). */
export function preloadHypeFx() { note(); }

const PALETTE: Record<HypeTier, string[]> = {
  gold: ['#f7d774', '#e8b04a', '#fff1c1', '#c98a2b', '#ffe49a'],
  bottles: ['#f7d774', '#fff1c1', '#e8b04a', '#ffd0e6', '#c98a2b'],
  spray: ['#3fbf6f', '#9be37a', '#f7d774', '#1f8a4c', '#e9f7b0'],
  shout: ['#a06bff', '#d7b8ff', '#f7d774', '#6b3fd1', '#ffe49a'],
  shutdown: ['#f7d774', '#ff5fa8', '#5fe0ff', '#ffffff', '#ffb547'],
  calm: ['#f7d774', '#fff1c1', '#e8b04a'],
};
// share of the pool: [notes, confetti, sparks]
const MIX: Record<HypeTier, [number, number, number]> = {
  gold: [0.14, 0.56, 0.3],
  bottles: [0.08, 0.42, 0.5],
  spray: [0.7, 0.2, 0.1],
  shout: [0.1, 0.5, 0.4],
  shutdown: [0.32, 0.3, 0.38],
  calm: [0, 0, 0.35],
};

const NOTE = 0;
const CONF = 1;
const SPARK = 2;

export interface HypeFxOptions {
  tier: HypeTier;
  /** Pool size (120 High / 40 Low). */
  count: number;
  /** Emit new particles until this many ms, then let them fall out. */
  emitMs: number;
}

export function startHypeFx(canvas: HTMLCanvasElement, aura: HTMLElement | null, o: HypeFxOptions): () => void {
  const ctx = canvas.getContext('2d');
  const n = Math.max(0, Math.round(o.count));
  const pal = PALETTE[o.tier];
  const mix = MIX[o.tier];
  const dpr = Math.min(n > 60 ? 1.5 : 1, window.devicePixelRatio || 1);
  let W = 0;
  let H = 0;
  const resize = () => {
    W = canvas.clientWidth || window.innerWidth;
    H = canvas.clientHeight || window.innerHeight;
    canvas.width = Math.round(W * dpr);
    canvas.height = Math.round(H * dpr);
  };
  resize();
  window.addEventListener('resize', resize);

  const kind = new Uint8Array(n);
  const col = new Uint8Array(n);
  const x = new Float32Array(n);
  const y = new Float32Array(n);
  const vx = new Float32Array(n);
  const vy = new Float32Array(n);
  const g = new Float32Array(n); // gravity px/s²
  const term = new Float32Array(n); // terminal fall speed
  const rot = new Float32Array(n);
  const vr = new Float32Array(n);
  const flip = new Float32Array(n);
  const vf = new Float32Array(n);
  const size = new Float32Array(n);
  const life = new Float32Array(n); // seconds left (sparks), < 0 = dead
  const life0 = new Float32Array(n);
  const phase = new Float32Array(n);
  const nNotes = Math.round(n * mix[0]);
  const nConf = Math.round(n * mix[1]);
  const nSpark = Math.min(n - nNotes - nConf, Math.round(n * mix[2]));
  const used = nNotes + nConf + nSpark;
  const rnd = (a: number, b: number) => a + Math.random() * (b - a);
  const small = W < 600;

  function spawnFall(i: number, initial: boolean) {
    x[i] = rnd(-20, W + 20);
    y[i] = initial ? rnd(-H * 0.55, H * 0.3) : rnd(-80, -20);
    vx[i] = rnd(-30, 30);
    rot[i] = rnd(0, Math.PI * 2);
    flip[i] = rnd(0, Math.PI * 2);
    phase[i] = rnd(0, Math.PI * 2);
    col[i] = (Math.random() * pal.length) | 0;
    if (kind[i] === NOTE) {
      vy[i] = rnd(60, 140);
      g[i] = 120;
      term[i] = rnd(110, 170);
      vr[i] = rnd(-1.2, 1.2);
      vf[i] = rnd(1.5, 3.5);
      size[i] = rnd(0.32, 0.5) * (small ? 0.85 : 1);
    } else {
      vy[i] = rnd(80, 180);
      g[i] = 200;
      term[i] = rnd(140, 240);
      vr[i] = rnd(-4, 4);
      vf[i] = rnd(5, 11);
      size[i] = rnd(5, 9);
    }
    life[i] = 99;
    life0[i] = 99;
  }
  /** a confetti burst from the centre (start of the moment) */
  function spawnBurst(i: number) {
    spawnFall(i, true);
    x[i] = W / 2 + rnd(-40, 40);
    y[i] = H * 0.42 + rnd(-20, 20);
    const a = rnd(-Math.PI * 0.95, -Math.PI * 0.05);
    const sp = rnd(260, small ? 560 : 760);
    vx[i] = Math.cos(a) * sp;
    vy[i] = Math.sin(a) * sp;
    g[i] = 520;
  }
  function spawnSpark(i: number, cx?: number, cy?: number) {
    col[i] = (Math.random() * pal.length) | 0;
    phase[i] = rnd(0, Math.PI * 2);
    if (cx !== undefined && cy !== undefined) {
      // firework shell
      const a = rnd(0, Math.PI * 2);
      const sp = rnd(90, small ? 240 : 320);
      x[i] = cx; y[i] = cy;
      vx[i] = Math.cos(a) * sp; vy[i] = Math.sin(a) * sp;
      g[i] = 150; term[i] = 400; size[i] = rnd(1.6, 2.8);
      life0[i] = life[i] = rnd(0.9, 1.5);
    } else if (o.tier === 'bottles') {
      // sparklers rising from the bottom
      x[i] = rnd(W * 0.08, W * 0.92); y[i] = H + 10;
      vx[i] = rnd(-50, 50); vy[i] = rnd(-H * 0.95, -H * 0.6);
      g[i] = H * 0.55; term[i] = 600; size[i] = rnd(1.4, 2.6);
      life0[i] = life[i] = rnd(1.0, 1.6);
    } else {
      // gold dust drifting up
      x[i] = rnd(0, W); y[i] = rnd(H * 0.3, H + 10);
      vx[i] = rnd(-12, 12); vy[i] = rnd(-70, -25);
      g[i] = 0; term[i] = 400; size[i] = rnd(1.2, 2.6);
      life0[i] = life[i] = rnd(1.4, 2.8);
    }
  }

  for (let i = 0; i < used; i++) {
    kind[i] = i < nNotes ? NOTE : i < nNotes + nConf ? CONF : SPARK;
    if (kind[i] === SPARK) {
      if (o.tier === 'shutdown') life[i] = -1; // fireworks fill these
      else { spawnSpark(i); life[i] *= Math.random(); }
    } else if (kind[i] === CONF && o.tier !== 'spray' && Math.random() < 0.4) spawnBurst(i);
    else spawnFall(i, true);
  }

  const t0 = performance.now();
  let last = t0;
  let nextShell = 250;
  let raf = 0;
  const TAU = Math.PI * 2;

  const frame = (now: number) => {
    raf = requestAnimationFrame(frame);
    const dt = Math.min(0.05, (now - last) / 1000);
    last = now;
    const el = now - t0;
    const emitting = el < o.emitMs;
    // the aura breathes on the beat
    if (aura) {
      const b = readBeat();
      aura.style.transform = `translate(-50%, -50%) scale(${(1 + b.pulse * 0.07).toFixed(4)})`;
      aura.style.opacity = (0.72 + b.pulse * 0.28).toFixed(3);
    }
    // fireworks
    if (o.tier === 'shutdown' && emitting && el > nextShell) {
      nextShell = el + rnd(520, 820);
      const cx = rnd(W * 0.15, W * 0.85);
      const cy = rnd(H * 0.12, H * 0.42);
      let k = Math.round(nSpark / 3);
      for (let i = nNotes + nConf; i < used && k > 0; i++) if (life[i] <= 0) { spawnSpark(i, cx, cy); k--; }
    }
    if (!ctx) return;
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    const img = note();
    for (let i = 0; i < used; i++) {
      const k = kind[i];
      if (k === SPARK) {
        if (life[i] <= 0) {
          if (emitting && o.tier !== 'shutdown') spawnSpark(i);
          continue;
        }
        life[i] -= dt;
        vy[i] += g[i] * dt;
        vx[i] *= 1 - 1.2 * dt;
        x[i] += vx[i] * dt;
        y[i] += vy[i] * dt;
        const a = Math.max(0, life[i] / life0[i]);
        const tw = 0.65 + 0.35 * Math.sin(el * 0.02 + phase[i]);
        ctx.globalCompositeOperation = 'lighter';
        ctx.globalAlpha = a * tw;
        ctx.fillStyle = pal[col[i]];
        ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
        ctx.beginPath();
        ctx.arc(x[i], y[i], size[i] * (0.6 + a * 0.6), 0, TAU);
        ctx.fill();
        continue;
      }
      // notes + confetti: fall, sway, tumble
      vy[i] = Math.min(term[i], vy[i] + g[i] * dt);
      vx[i] += (Math.sin(el * 0.0016 + phase[i]) * 40 - vx[i]) * Math.min(1, 1.6 * dt);
      x[i] += vx[i] * dt;
      y[i] += vy[i] * dt;
      rot[i] += vr[i] * dt;
      flip[i] += vf[i] * dt;
      if (y[i] > H + 60) {
        if (emitting) spawnFall(i, false);
        else { y[i] = 1e6; continue; }
      }
      if (y[i] > 1e5) continue;
      const fy = Math.cos(flip[i]);
      const c = Math.cos(rot[i]);
      const s = Math.sin(rot[i]);
      ctx.globalCompositeOperation = 'source-over';
      ctx.globalAlpha = 1;
      if (k === NOTE) {
        const sc = size[i];
        ctx.setTransform(c * sc * dpr, s * sc * dpr, -s * sc * fy * dpr, c * sc * fy * dpr, x[i] * dpr, y[i] * dpr);
        if (img) ctx.drawImage(img, -NOTE_W / 2, -NOTE_H / 2);
        else { ctx.fillStyle = '#2f8f52'; ctx.fillRect(-NOTE_W / 2, -NOTE_H / 2, NOTE_W, NOTE_H); }
      } else {
        const sz = size[i];
        ctx.setTransform(c * dpr, s * dpr, -s * fy * dpr, c * fy * dpr, x[i] * dpr, y[i] * dpr);
        ctx.fillStyle = pal[col[i]];
        ctx.fillRect(-sz / 2, -sz * 0.3, sz, sz * 0.6);
      }
    }
    ctx.globalAlpha = 1;
    ctx.globalCompositeOperation = 'source-over';
  };
  raf = requestAnimationFrame(frame);
  return () => {
    cancelAnimationFrame(raf);
    window.removeEventListener('resize', resize);
  };
}
