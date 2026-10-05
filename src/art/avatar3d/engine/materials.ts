// Fabric textures (drawn at runtime on a canvas, no image files) and a shared material cache.
// Materials and textures are shared between every character on screen and every portrait render.
import {
  CanvasTexture,
  Color,
  DoubleSide,
  FrontSide,
  LinearMipmapLinearFilter,
  MeshBasicMaterial,
  MeshLambertMaterial,
  MeshPhongMaterial,
  RepeatWrapping,
  SRGBColorSpace,
  type Material,
  type Texture,
} from 'three';
import type { FabricId } from '../../../lib/types';

// ---------------------------------------------------------------------------------------------
// colour helpers (sRGB hex in, hex out)
// ---------------------------------------------------------------------------------------------

export function hexToRgb(hex: string): [number, number, number] {
  const n = parseInt(hex.slice(1), 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}
export function rgbToHex(r: number, g: number, b: number): string {
  const c = (x: number) => Math.max(0, Math.min(255, Math.round(x))).toString(16).padStart(2, '0');
  return '#' + c(r) + c(g) + c(b);
}
export function mix(a: string, b: string, t: number): string {
  const x = hexToRgb(a);
  const y = hexToRgb(b);
  return rgbToHex(x[0] + (y[0] - x[0]) * t, x[1] + (y[1] - x[1]) * t, x[2] + (y[2] - x[2]) * t);
}
export function shade(hex: string, k: number): string {
  return k < 0 ? mix(hex, '#000000', -k) : mix(hex, '#ffffff', k);
}
export function luma(hex: string): number {
  const [r, g, b] = hexToRgb(hex);
  return (0.299 * r + 0.587 * g + 0.114 * b) / 255;
}
function hsl(hex: string): [number, number, number] {
  const c = new Color(hex);
  const o = { h: 0, s: 0, l: 0 };
  c.getHSL(o, SRGBColorSpace);
  return [o.h, o.s, o.l];
}
function fromHsl(h: number, s: number, l: number): string {
  return '#' + new Color().setHSL(((h % 1) + 1) % 1, s, l, SRGBColorSpace).getHexString(SRGBColorSpace);
}

// ---------------------------------------------------------------------------------------------
// canvas textures
// ---------------------------------------------------------------------------------------------

const TEX = new Map<string, Texture>();
const S = 256;

function canvas(size = S): [HTMLCanvasElement, CanvasRenderingContext2D] {
  const c = document.createElement('canvas');
  c.width = size;
  c.height = size;
  return [c, c.getContext('2d')!];
}

function finish(c: HTMLCanvasElement, repeat = true): Texture {
  const t = new CanvasTexture(c);
  t.colorSpace = SRGBColorSpace;
  if (repeat) t.wrapS = t.wrapT = RepeatWrapping;
  t.minFilter = LinearMipmapLinearFilter;
  t.anisotropy = 4;
  return t;
}

/** Draws `fn` at the 9 wrapped offsets so motifs crossing an edge tile seamlessly. */
function wrapped(fn: (dx: number, dy: number) => void) {
  for (const dx of [-S, 0, S]) for (const dy of [-S, 0, S]) fn(dx, dy);
}

function noise(x: CanvasRenderingContext2D, amt: number, seed = 1, size = S) {
  const img = x.getImageData(0, 0, size, size);
  let s = seed * 9301 + 49297;
  for (let i = 0; i < img.data.length; i += 4) {
    s = (s * 9301 + 49297) % 233280;
    const n = (s / 233280 - 0.5) * amt * 255;
    img.data[i] += n;
    img.data[i + 1] += n;
    img.data[i + 2] += n;
  }
  x.putImageData(img, 0, 0);
}

function plain(base: string): HTMLCanvasElement {
  const [c, x] = canvas(64);
  x.fillStyle = base;
  x.fillRect(0, 0, 64, 64);
  noise(x, 0.035, 3, 64);
  return c;
}

function denim(base: string): HTMLCanvasElement {
  const [c, x] = canvas(64);
  x.fillStyle = base;
  x.fillRect(0, 0, 64, 64);
  x.strokeStyle = shade(base, 0.14);
  x.lineWidth = 1.2;
  for (let i = -64; i < 128; i += 5) {
    x.beginPath();
    x.moveTo(i, 0);
    x.lineTo(i + 64, 64);
    x.stroke();
  }
  noise(x, 0.05, 7, 64);
  return c;
}

/** Bold wax print: big concentric medallions, teardrops and dots in high-contrast colours. */
function ankara(base: string): HTMLCanvasElement {
  const [c, x] = canvas();
  const [h, s, l] = hsl(base);
  const dark = l < 0.25;
  const comp = fromHsl(h + 0.5, Math.max(0.55, s), dark ? 0.55 : 0.32);
  const pop = h > 0.08 && h < 0.2 ? '#c8261d' : '#f2bf2e';
  const cream = '#f7ecd2';
  const ink = dark ? '#f2bf2e' : '#17110d';
  x.fillStyle = base;
  x.fillRect(0, 0, S, S);
  // large medallions on a diagonal grid
  const centres: [number, number][] = [[64, 64], [192, 192]];
  wrapped((dx, dy) => {
    for (const [cx, cy] of centres) {
      const X = cx + dx;
      const Y = cy + dy;
      const rings: [number, string][] = [[54, ink], [48, cream], [40, comp], [27, pop], [19, ink], [12, cream], [6, comp]];
      for (const [r, col] of rings) {
        x.fillStyle = col;
        x.beginPath();
        x.arc(X, Y, r, 0, Math.PI * 2);
        x.fill();
      }
      // petals on the cream ring
      x.fillStyle = pop;
      for (let k = 0; k < 10; k++) {
        const a = (k / 10) * Math.PI * 2;
        x.beginPath();
        x.ellipse(X + Math.cos(a) * 44, Y + Math.sin(a) * 44, 5, 3, a, 0, Math.PI * 2);
        x.fill();
      }
    }
    // teardrops between the medallions
    for (const [cx, cy] of [[192, 64], [64, 192]] as [number, number][]) {
      const X = cx + dx;
      const Y = cy + dy;
      for (let k = 0; k < 4; k++) {
        const a = (k / 4) * Math.PI * 2 + Math.PI / 4;
        x.save();
        x.translate(X + Math.cos(a) * 22, Y + Math.sin(a) * 22);
        x.rotate(a + Math.PI / 2);
        x.fillStyle = ink;
        x.beginPath();
        x.ellipse(0, 0, 11, 20, 0, 0, Math.PI * 2);
        x.fill();
        x.fillStyle = k % 2 ? pop : cream;
        x.beginPath();
        x.ellipse(0, 2, 6, 12, 0, 0, Math.PI * 2);
        x.fill();
        x.restore();
      }
      x.fillStyle = cream;
      x.beginPath();
      x.arc(X, Y, 6, 0, Math.PI * 2);
      x.fill();
    }
  });
  // scattered dots
  x.fillStyle = ink;
  for (let i = 0; i < 26; i++) {
    const px = (i * 97) % S;
    const py = (i * 57 + 31) % S;
    x.beginPath();
    x.arc(px, py, 2.6, 0, Math.PI * 2);
    x.fill();
  }
  noise(x, 0.03, 5);
  return c;
}

/** Indigo-style resist dye: dark dyed ground, pale sunbursts and grid lines with soft, bleeding edges. */
function adire(base: string): HTMLCanvasElement {
  const [c, x] = canvas();
  const [h, s] = hsl(base);
  const ground = fromHsl(h, Math.min(0.75, s * 0.9 + 0.1), 0.2);
  const pale = fromHsl(h, Math.min(0.5, s), 0.82);
  const mid = fromHsl(h, Math.min(0.7, s), 0.45);
  x.fillStyle = ground;
  x.fillRect(0, 0, S, S);
  // mottled dye
  for (let i = 0; i < 70; i++) {
    x.fillStyle = `rgba(255,255,255,${0.02 + ((i * 13) % 7) * 0.006})`;
    x.beginPath();
    x.arc((i * 71) % S, (i * 113) % S, 8 + ((i * 17) % 22), 0, Math.PI * 2);
    x.fill();
  }
  x.shadowColor = pale;
  x.shadowBlur = 5;
  x.strokeStyle = pale;
  x.fillStyle = pale;
  // grid
  x.globalAlpha = 0.85;
  x.lineWidth = 3;
  for (const p of [0, 128]) {
    x.beginPath();
    x.moveTo(p, 0);
    x.lineTo(p, S);
    x.moveTo(0, p);
    x.lineTo(S, p);
    x.stroke();
  }
  // sunbursts (tie-dye circles) in two cells, dotted rings in the other two
  for (const [cx, cy] of [[64, 64], [192, 192]] as [number, number][]) {
    for (let r = 8; r <= 50; r += 10) {
      x.lineWidth = r < 20 ? 4 : 2.5;
      x.globalAlpha = 0.9 - r / 120;
      x.beginPath();
      x.arc(cx, cy, r, 0, Math.PI * 2);
      x.stroke();
    }
    x.globalAlpha = 0.6;
    x.lineWidth = 1.5;
    for (let k = 0; k < 16; k++) {
      const a = (k / 16) * Math.PI * 2;
      x.beginPath();
      x.moveTo(cx + Math.cos(a) * 12, cy + Math.sin(a) * 12);
      x.lineTo(cx + Math.cos(a) * 54, cy + Math.sin(a) * 54);
      x.stroke();
    }
  }
  x.globalAlpha = 0.9;
  for (const [cx, cy] of [[192, 64], [64, 192]] as [number, number][]) {
    for (let ring = 1; ring <= 3; ring++) {
      const n = ring * 8;
      for (let k = 0; k < n; k++) {
        const a = (k / n) * Math.PI * 2;
        x.beginPath();
        x.arc(cx + Math.cos(a) * ring * 15, cy + Math.sin(a) * ring * 15, 3.4 - ring * 0.5, 0, Math.PI * 2);
        x.fill();
      }
    }
    x.fillStyle = mid;
    x.beginPath();
    x.arc(cx, cy, 7, 0, Math.PI * 2);
    x.fill();
    x.fillStyle = pale;
  }
  x.globalAlpha = 1;
  x.shadowBlur = 0;
  noise(x, 0.05, 11);
  return c;
}

/** Hand-woven strips: base colour with thin metallic and contrast stripes plus a weave texture. */
function asooke(base: string): HTMLCanvasElement {
  const [c, x] = canvas();
  const [h, s, l] = hsl(base);
  const gold = '#e9c46a';
  const deep = fromHsl(h, s, Math.max(0.08, l * 0.55));
  const light = fromHsl(h, Math.min(1, s * 0.9), Math.min(0.85, l + 0.18));
  x.fillStyle = base;
  x.fillRect(0, 0, S, S);
  // vertical strips (u runs around the body)
  const bands: [number, number, string][] = [
    [0, 10, deep], [10, 3, gold], [13, 4, deep], [60, 18, light], [78, 3, gold], [118, 10, deep], [128, 3, gold],
    [131, 4, deep], [178, 18, light], [196, 3, gold], [240, 6, deep], [250, 3, gold],
  ];
  for (const [x0, w, col] of bands) {
    x.fillStyle = col;
    x.fillRect(x0, 0, w, S);
  }
  // weave: short horizontal ticks alternating per row
  for (let y = 0; y < S; y += 4) {
    x.fillStyle = y % 8 ? 'rgba(255,255,255,0.07)' : 'rgba(0,0,0,0.08)';
    x.fillRect(0, y, S, 2);
  }
  // gold supplementary-weft motifs (small diamonds) in the light bands
  x.fillStyle = gold;
  for (const bx of [69, 187]) {
    for (let y = 8; y < S; y += 32) {
      x.beginPath();
      x.moveTo(bx, y);
      x.lineTo(bx + 6, y + 6);
      x.lineTo(bx, y + 12);
      x.lineTo(bx - 6, y + 6);
      x.closePath();
      x.fill();
    }
  }
  noise(x, 0.05, 13);
  return c;
}

/** Tone-on-tone lace: pale floral outlines, eyelet holes and a fine net. */
function lace(base: string): HTMLCanvasElement {
  const [c, x] = canvas();
  const l = luma(base);
  const line = l > 0.75 ? shade(base, -0.16) : shade(base, 0.42);
  const hole = l > 0.75 ? shade(base, -0.3) : shade(base, -0.35);
  x.fillStyle = base;
  x.fillRect(0, 0, S, S);
  // net
  x.strokeStyle = line;
  x.globalAlpha = 0.28;
  x.lineWidth = 1;
  for (let i = -S; i < S * 2; i += 8) {
    x.beginPath();
    x.moveTo(i, 0);
    x.lineTo(i + S, S);
    x.moveTo(i, S);
    x.lineTo(i + S, 0);
    x.stroke();
  }
  x.globalAlpha = 1;
  // flowers
  x.lineWidth = 2.4;
  wrapped((dx, dy) => {
    for (const [cx, cy, r] of [[64, 64, 26], [192, 192, 26], [192, 64, 16], [64, 192, 16]] as [number, number, number][]) {
      const X = cx + dx;
      const Y = cy + dy;
      x.strokeStyle = line;
      for (let k = 0; k < 6; k++) {
        const a = (k / 6) * Math.PI * 2;
        x.beginPath();
        x.ellipse(X + Math.cos(a) * r * 0.6, Y + Math.sin(a) * r * 0.6, r * 0.45, r * 0.26, a, 0, Math.PI * 2);
        x.stroke();
      }
      x.fillStyle = hole;
      x.beginPath();
      x.arc(X, Y, r * 0.18, 0, Math.PI * 2);
      x.fill();
      // eyelets around
      for (let k = 0; k < 12; k++) {
        const a = (k / 12) * Math.PI * 2 + 0.2;
        x.beginPath();
        x.arc(X + Math.cos(a) * r * 1.35, Y + Math.sin(a) * r * 1.35, 2.2, 0, Math.PI * 2);
        x.fill();
      }
    }
  });
  noise(x, 0.025, 17);
  return c;
}

export const FABRIC_TILE: Record<FabricId | 'denim', number> = {
  plain: 0.3,
  denim: 0.12,
  ankara: 0.24,
  adire: 0.3,
  asooke: 0.2,
  lace: 0.16,
};

export function fabricTexture(f: FabricId | 'denim', base: string): Texture {
  const key = f + base;
  let t = TEX.get(key);
  if (!t) {
    const draw = { plain, denim, ankara, adire, asooke, lace }[f] ?? plain;
    t = finish(draw(base));
    TEX.set(key, t);
  }
  return t;
}

/** Coral bead mesh (coral cap, okuku crown). */
function coralBeads(): Texture {
  let t = TEX.get('coral');
  if (t) return t;
  const [c, x] = canvas(128);
  x.fillStyle = '#2a0e0b';
  x.fillRect(0, 0, 128, 128);
  for (let row = 0; row < 8; row++) {
    for (let col = 0; col < 8; col++) {
      const cx = col * 16 + (row % 2 ? 8 : 0) + 8;
      const cy = row * 16 + 8;
      for (const ox of [-128, 0, 128]) {
        const g = x.createRadialGradient(cx + ox - 2, cy - 2, 1, cx + ox, cy, 7.5);
        g.addColorStop(0, '#ff8a72');
        g.addColorStop(0.45, '#d8332a');
        g.addColorStop(1, '#8e1712');
        x.fillStyle = g;
        x.beginPath();
        x.arc(cx + ox, cy, 7, 0, Math.PI * 2);
        x.fill();
      }
    }
  }
  t = finish(c);
  TEX.set('coral', t);
  return t;
}

/** Big chest print for the designer tee (fictional brand). Transparent background. */
function graphic(col: string): Texture {
  const key = 'graphic' + col;
  let t = TEX.get(key);
  if (t) return t;
  const [c, x] = canvas(256);
  x.clearRect(0, 0, 256, 256);
  x.fillStyle = col;
  x.strokeStyle = col;
  x.textAlign = 'center';
  x.textBaseline = 'middle';
  x.lineWidth = 9;
  x.strokeRect(34, 40, 188, 176);
  x.font = '900 74px Arial Black, Impact, system-ui, sans-serif';
  x.fillText('B·C', 128, 112);
  x.font = '800 26px Arial, system-ui, sans-serif';
  x.fillText('BENIN CITY', 128, 168);
  x.font = '700 15px Arial, system-ui, sans-serif';
  x.fillText('EST. 1440', 128, 196);
  t = finish(c, false);
  TEX.set(key, t);
  return t;
}

/** Embroidery panel (senator / agbada / buba necklines). Transparent background. */
function embroidery(col: string): Texture {
  const key = 'emb' + col;
  let t = TEX.get(key);
  if (t) return t;
  const [c, x] = canvas(128);
  x.clearRect(0, 0, 128, 128);
  x.strokeStyle = col;
  x.fillStyle = col;
  x.lineCap = 'round';
  x.lineWidth = 3.2;
  // a centre spine with scrolls either side, mirrored
  x.beginPath();
  x.moveTo(64, 0);
  x.lineTo(64, 128);
  x.stroke();
  for (let y = 10; y < 128; y += 26) {
    for (const sgn of [-1, 1]) {
      x.beginPath();
      x.moveTo(64, y);
      x.bezierCurveTo(64 + sgn * 26, y - 6, 64 + sgn * 34, y + 14, 64 + sgn * 16, y + 16);
      x.stroke();
      x.beginPath();
      x.arc(64 + sgn * 22, y + 4, 3.4, 0, Math.PI * 2);
      x.fill();
    }
  }
  t = finish(c, false);
  TEX.set(key, t);
  return t;
}

function towel(col: string): Texture {
  const key = 'towel' + col;
  let t = TEX.get(key);
  if (t) return t;
  const [c, x] = canvas(64);
  x.fillStyle = '#f4f1ea';
  x.fillRect(0, 0, 64, 64);
  x.fillStyle = col;
  for (const y0 of [6, 14, 44, 52]) x.fillRect(0, y0, 64, 4);
  noise(x, 0.08, 23, 64);
  t = finish(c);
  TEX.set(key, t);
  return t;
}

// ---------------------------------------------------------------------------------------------
// material cache
// ---------------------------------------------------------------------------------------------

const MATS = new Map<string, Material>();

function cached<T extends Material>(key: string, make: () => T): T {
  let m = MATS.get(key) as T | undefined;
  if (!m) {
    m = make();
    m.name = key;
    MATS.set(key, m);
  }
  return m;
}

/** Flat-shaded matte colour. */
export function matte(hex: string, doubleSide = false): Material {
  return cached(`m|${hex}|${doubleSide}`, () => new MeshLambertMaterial({ color: hex, flatShading: true, side: doubleSide ? DoubleSide : FrontSide }));
}

/** Smooth-shaded matte (eyes, beads: small round things look better without facets). */
export function soft(hex: string): Material {
  return cached(`s|${hex}`, () => new MeshLambertMaterial({ color: hex }));
}

export function glossy(hex: string, shininess = 60, specular = '#ffffff'): Material {
  return cached(`g|${hex}|${shininess}|${specular}`, () => new MeshPhongMaterial({ color: hex, shininess, specular, flatShading: true }));
}

export function unlit(hex: string): Material {
  return cached(`u|${hex}`, () => new MeshBasicMaterial({ color: hex }));
}

export function fabric(f: FabricId | 'denim', base: string): Material {
  if (f === 'plain') return cached(`fp|${base}`, () => new MeshLambertMaterial({ color: '#ffffff', map: fabricTexture('plain', base), flatShading: true, side: DoubleSide }));
  return cached(`f|${f}|${base}`, () => new MeshLambertMaterial({ color: '#ffffff', map: fabricTexture(f, base), flatShading: true, side: DoubleSide }));
}

export function coralMat(): Material {
  return cached('coral-beads', () => new MeshPhongMaterial({ color: '#ffffff', map: coralBeads(), shininess: 40, specular: '#663333', flatShading: true }));
}

export function decalMat(kind: 'graphic' | 'embroidery', col: string): Material {
  return cached(`d|${kind}|${col}`, () =>
    new MeshLambertMaterial({
      color: '#ffffff',
      map: kind === 'graphic' ? graphic(col) : embroidery(col),
      transparent: true,
      alphaTest: 0.35,
      depthWrite: false,
      flatShading: true,
      polygonOffset: true,
      polygonOffsetFactor: -2,
    }),
  );
}

export function towelMat(col: string): Material {
  return cached(`towel|${col}`, () => new MeshLambertMaterial({ color: '#ffffff', map: towel(col), flatShading: true, side: DoubleSide }));
}

/** Number of distinct cached materials (for the dev gallery stats). */
export function materialCount() {
  return MATS.size;
}
