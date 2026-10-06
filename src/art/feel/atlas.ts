// F1 real feel (docs/FEEL_PLAN.md): ONE procedural texture atlas shared by the home and every place.
// Drawn once into a canvas (no downloads): 4×4 tiles, each a seamless greyscale-ish detail map that the
// vertex colour tints (tiles + grout, wood grain, worn concrete with stains, plaster with cracks and
// peeling, rusty zinc, carpet, fabric, leather, brushed metal, tarp, cement blocks, laterite, asphalt,
// painted wall, grass). Values sit around 0.85 so the shader multiplies by FEEL_GAIN to keep the colour.

/** Atlas tile index per surface. */
export const MAT = {
  plain: 0,
  tiles: 1,
  wood: 2,
  concrete: 3,
  plaster: 4,
  zinc: 5,
  carpet: 6,
  fabric: 7,
  leather: 8,
  metal: 9,
  tarp: 10,
  block: 11,
  ground: 12,
  asphalt: 13,
  paint: 14,
  grass: 15,
} as const;
export type Mat = keyof typeof MAT;

/** Metres covered by one repeat of each tile (UV scale). */
export const MAT_SCALE: Record<Mat, number> = {
  plain: 2, tiles: 1.2, wood: 1.6, concrete: 2.6, plaster: 2.4, zinc: 1.2, carpet: 1.2, fabric: 0.6,
  leather: 0.8, metal: 1.2, tarp: 1.8, block: 1.8, ground: 3.2, asphalt: 3, paint: 2.4, grass: 2.4,
};

/** The shader multiplies the texel by this, so a mid texel (~0.85) keeps the vertex colour. */
export const FEEL_GAIN = 1.17;

// ---------- seeded, periodic value noise (tiles must wrap) ----------
function rng(seed: number) {
  let s = seed >>> 0;
  return () => {
    s = (s + 0x6d2b79f5) >>> 0;
    let t = s;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

class Noise {
  private v: Float32Array;
  private n: number;
  constructor(n: number, seed: number) {
    this.n = n;
    const r = rng(seed);
    this.v = new Float32Array(n * n);
    for (let i = 0; i < n * n; i++) this.v[i] = r();
  }
  /** Smooth value noise at (x, y) in [0, 1) tile space with `f` cells per tile (wraps). */
  at(x: number, y: number, f: number): number {
    const n = this.n;
    const fx = x * f, fy = y * f;
    const ix = Math.floor(fx), iy = Math.floor(fy);
    const tx = fx - ix, ty = fy - iy;
    const sx = tx * tx * (3 - 2 * tx), sy = ty * ty * (3 - 2 * ty);
    const m = (a: number) => ((a % f) + f) % f % n;
    const x0 = m(ix), x1 = m(ix + 1), y0 = m(iy), y1 = m(iy + 1);
    const v = this.v;
    const a = v[y0 * n + x0], b = v[y0 * n + x1], c = v[y1 * n + x0], d = v[y1 * n + x1];
    return a + (b - a) * sx + (c - a) * sy + (a - b - c + d) * sx * sy;
  }
  fbm(x: number, y: number, f: number, oct = 4): number {
    let s = 0, amp = 0.5, tot = 0;
    for (let o = 0; o < oct; o++) {
      s += this.at(x, y, f) * amp;
      tot += amp;
      amp *= 0.5;
      f *= 2;
    }
    return s / tot;
  }
}

type RGB = [number, number, number];
type Painter = (u: number, v: number, px: number, py: number) => RGB | number;

const clamp01 = (x: number) => (x < 0 ? 0 : x > 1 ? 1 : x);
const smooth = (a: number, b: number, x: number) => {
  const t = clamp01((x - a) / (b - a));
  return t * t * (3 - 2 * t);
};

function painters(T: number): Painter[] {
  const N = new Noise(256, 7);
  const M = new Noise(256, 19);
  const K = new Noise(256, 31);
  const r = rng(99);
  // crack paths for plaster (random walks, wrapped)
  const crack = new Float32Array(T * T);
  for (let c = 0; c < 5; c++) {
    let x = r() * T, y = r() * T, a = r() * Math.PI * 2;
    const len = T * (0.4 + r() * 0.6);
    for (let i = 0; i < len; i++) {
      a += (r() - 0.5) * 0.7;
      x += Math.cos(a);
      y += Math.sin(a);
      const ix = ((Math.round(x) % T) + T) % T, iy = ((Math.round(y) % T) + T) % T;
      crack[iy * T + ix] = 1;
      if (r() < 0.02) a += (r() - 0.5) * 2;
    }
  }
  // scratches for metal
  const scratch = new Float32Array(T * T);
  for (let c = 0; c < 26; c++) {
    let x = r() * T, y = r() * T;
    const a = (r() - 0.5) * 0.5, len = 10 + r() * T * 0.4;
    for (let i = 0; i < len; i++) {
      x += Math.cos(a);
      y += Math.sin(a);
      const ix = ((Math.round(x) % T) + T) % T, iy = ((Math.round(y) % T) + T) % T;
      scratch[iy * T + ix] = 1;
    }
  }
  const gray = (g: number): number => clamp01(g);
  return [
    // 0 plain: barely-there grain so no surface is perfectly flat
    (u, v) => gray(0.84 + (N.fbm(u, v, 8, 3) - 0.5) * 0.08 + (K.at(u, v, 64) - 0.5) * 0.03),
    // 1 tiles: 2×2 ceramic tiles, grout, per-tile tone, faint wear
    (u, v) => {
      const gu = (u * 2) % 1, gv = (v * 2) % 1;
      const g = Math.min(gu, 1 - gu, gv, 1 - gv);
      const grout = smooth(0.012, 0.03, g);
      const id = Math.floor(u * 2) + Math.floor(v * 2) * 2;
      const tone = 0.88 + ((id * 37) % 5) * 0.012 + (N.fbm(u, v, 6, 3) - 0.5) * 0.06;
      const bevel = 1 - (1 - smooth(0.03, 0.07, g)) * 0.05;
      return gray((tone * bevel) * grout + 0.52 * (1 - grout));
    },
    // 2 wood: planks along u with warped grain
    (u, v) => {
      const plank = Math.floor(v * 4);
      const pv = (v * 4) % 1;
      const seam = smooth(0.0, 0.05, Math.min(pv, 1 - pv));
      const warp = N.fbm(u, v, 3, 3) * 2;
      const grain = Math.sin((v * 4 * 9 + warp * 3 + plank * 1.7) * Math.PI * 2) * 0.5 + 0.5;
      const ring = Math.pow(grain, 3) * 0.12;
      const tone = 0.86 + ((plank * 53) % 7) * 0.012 - ring + (M.fbm(u * 0.5 + plank * 0.13, v, 12, 2) - 0.5) * 0.08;
      return gray(tone * (0.7 + 0.3 * seam));
    },
    // 3 concrete: mottled, stains, pits
    (u, v) => {
      const base = 0.84 + (N.fbm(u, v, 4, 5) - 0.5) * 0.2;
      const stain = smooth(0.62, 0.78, M.fbm(u + 0.3, v, 3, 4)) * 0.2;
      const pit = K.at(u, v, 96) > 0.93 ? 0.12 : 0;
      return gray(base - stain - pit);
    },
    // 4 plaster: soft paint, cracks, peeling patches
    (u, v, px, py) => {
      const base = 0.88 + (N.fbm(u, v, 5, 4) - 0.5) * 0.08;
      const peelN = M.fbm(u, v, 3, 4);
      const peel = smooth(0.66, 0.69, peelN);
      const edge = smooth(0.64, 0.66, peelN) - peel;
      const c = crack[py * T + px] ? 0.25 : 0;
      const dirt = smooth(0.45, 1, 1 - v) * 0; // (kept for tuning)
      const val = base * (1 - peel * 0.18) - edge * 0.12 - c - dirt;
      return peel > 0.5 ? [clamp01(val * 1.02), clamp01(val * 0.98), clamp01(val * 0.9)] : gray(val);
    },
    // 5 zinc: corrugation + rust streaks (coloured)
    (u, v) => {
      const corr = Math.sin(u * 12 * Math.PI * 2) * 0.5 + 0.5;
      const sh = 0.8 + corr * 0.14;
      const rust = smooth(0.55, 0.8, N.fbm(u * 2, v * 0.5, 3, 4) + (1 - v) * 0.15);
      const g = sh - (K.fbm(u, v, 16, 2) - 0.5) * 0.06;
      return [clamp01(g * (1 - rust * 0.05)), clamp01(g * (1 - rust * 0.3)), clamp01(g * (1 - rust * 0.55))];
    },
    // 6 carpet: fine pile + soft pattern
    (u, v) => gray(0.83 + (K.at(u, v, 128) - 0.5) * 0.12 + (N.fbm(u, v, 4, 3) - 0.5) * 0.08
      + (Math.sin((u + v) * 8 * Math.PI * 2) > 0.85 ? -0.05 : 0)),
    // 7 fabric: weave
    (u, v) => {
      const w = (Math.sin(u * 48 * Math.PI * 2) * Math.sin(v * 48 * Math.PI * 2)) * 0.05;
      return gray(0.85 + w + (N.fbm(u, v, 6, 3) - 0.5) * 0.06);
    },
    // 8 leather: pebbled, creases
    (u, v) => {
      const peb = Math.abs(K.at(u, v, 48) - 0.5) * 0.14;
      const crease = smooth(0.48, 0.5, M.fbm(u, v, 4, 3)) - smooth(0.5, 0.52, M.fbm(u, v, 4, 3));
      return gray(0.86 - peb - crease * 0.1 + (N.fbm(u, v, 3, 3) - 0.5) * 0.08);
    },
    // 9 metal: brushed streaks + scratches
    (u, v, px, py) => gray(0.84 + (N.at(u * 0.1, v, 128) - 0.5) * 0.1 + (M.fbm(u, v, 3, 3) - 0.5) * 0.08
      + (scratch[py * T + px] ? 0.08 : 0)),
    // 10 tarp: coarse weave + folds
    (u, v) => {
      const w = Math.sin(u * 32 * Math.PI * 2) * Math.sin(v * 32 * Math.PI * 2) * 0.04;
      const fold = Math.sin((u * 2 + N.fbm(u, v, 2, 2)) * Math.PI * 2) * 0.06;
      return gray(0.85 + w + fold);
    },
    // 11 cement blocks: 4 × 8 courses, running bond, mortar
    (u, v) => {
      const row = Math.floor(v * 8);
      const bu = (u * 4 + (row % 2) * 0.5) % 1;
      const bv = (v * 8) % 1;
      const m = smooth(0.02, 0.06, Math.min(bu, 1 - bu) * 2) * smooth(0.04, 0.12, Math.min(bv, 1 - bv));
      const id = Math.floor(u * 4 + (row % 2) * 0.5) * 13 + row * 7;
      const tone = 0.86 + ((id % 5) - 2) * 0.012 + (N.fbm(u, v, 8, 4) - 0.5) * 0.14;
      return gray(tone * m + 0.62 * (1 - m));
    },
    // 12 laterite ground: dirt + pebbles + tyre-ish streaks (slightly warm)
    (u, v) => {
      const g = 0.82 + (N.fbm(u, v, 4, 5) - 0.5) * 0.24;
      const peb = K.at(u, v, 80) > 0.9 ? 0.1 : 0;
      const val = g + peb;
      return [clamp01(val * 1.02), clamp01(val), clamp01(val * 0.96)];
    },
    // 13 asphalt: dark speckle + patches
    (u, v) => gray(0.8 + (K.at(u, v, 128) - 0.5) * 0.2 + (N.fbm(u, v, 3, 4) - 0.5) * 0.16
      - smooth(0.6, 0.75, M.fbm(u, v, 2, 3)) * 0.1),
    // 14 painted wall: roller texture, very soft
    (u, v) => gray(0.88 + (N.fbm(u, v * 0.4, 10, 3) - 0.5) * 0.05 + (K.at(u, v, 96) - 0.5) * 0.02),
    // 15 grass: blades + patches of soil
    (u, v) => {
      const blade = (K.at(u * 2, v * 0.6, 96) - 0.5) * 0.2;
      const soil = smooth(0.62, 0.72, M.fbm(u, v, 3, 4)) * 0.15;
      return gray(0.84 + blade - soil + (N.fbm(u, v, 5, 3) - 0.5) * 0.12);
    },
  ];
}

let cached: { canvas: HTMLCanvasElement; size: number } | null = null;

/** The atlas canvas (built on first use, then reused by every scene). `size` 1024 (High) or 512 (Low). */
export function atlasCanvas(size = 1024): HTMLCanvasElement {
  if (cached && cached.size >= size) return cached.canvas;
  const T = size / 4;
  const c = document.createElement('canvas');
  c.width = c.height = size;
  const g = c.getContext('2d')!;
  const img = g.createImageData(size, size);
  const d = img.data;
  const ps = painters(T);
  for (let t = 0; t < 16; t++) {
    const ox = (t % 4) * T, oy = Math.floor(t / 4) * T;
    const p = ps[t];
    for (let py = 0; py < T; py++)
      for (let px = 0; px < T; px++) {
        const out = p(px / T, py / T, px, py);
        const i = ((oy + py) * size + ox + px) * 4;
        if (typeof out === 'number') {
          const b = Math.round(out * 255);
          d[i] = d[i + 1] = d[i + 2] = b;
        } else {
          d[i] = Math.round(out[0] * 255);
          d[i + 1] = Math.round(out[1] * 255);
          d[i + 2] = Math.round(out[2] * 255);
        }
        d[i + 3] = 255;
      }
  }
  g.putImageData(img, 0, 0);
  cached = { canvas: c, size };
  return c;
}
