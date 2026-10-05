// Low-poly furniture, built from boxes and cylinders into the shared HomeBuilder.
// Local frame per piece: origin = centre of the footprint on the floor, +z = the front (where you
// use it from), -z = the back (against a wall). Sizes match KINDS in ../model.ts.
import type { FurnitureItem } from '../model';
import type { HomeBuilder } from './build';

const WOOD = '#8a5a33';
const WOOD_DARK = '#5b3a24';
const WOOD_LIGHT = '#c49a6c';
const METAL = '#9aa3ab';
const METAL_DARK = '#59616b';
const WHITE = '#f4f2ee';
const SHEET = '#f6f3ec';
const ZINC = '#a7b0b6';
const ZINC_DARK = '#7f898f';
const BLACK = '#23262c';
const CHROME = '#c8ced4';

type B = HomeBuilder;

function legs4(b: B, w: number, d: number, h: number, t: number, color: string, inset = 0.04) {
  const x = w / 2 - inset - t / 2;
  const z = d / 2 - inset - t / 2;
  for (const sx of [-1, 1]) for (const sz of [-1, 1]) b.box(t, h, t, sx * x, 0, sz * z, color);
}

function bed(b: B, w: number, d: number, frame: string, blanket: string, top: number, opts: { head?: number; pillows?: number } = {}) {
  const base = top - 0.2;
  b.box(w, base - 0.08, d, 0, 0.08, 0, frame); // frame box
  legs4(b, w, d, 0.08, 0.07, WOOD_DARK, 0.02);
  b.box(w + 0.04, opts.head ?? 0.95, 0.07, 0, 0, -d / 2 + 0.035, frame); // headboard
  b.box(w + 0.04, 0.28, 0.06, 0, base - 0.05, d / 2 - 0.03, frame); // footboard
  b.box(w - 0.06, 0.2, d - 0.12, 0, base, 0.0, SHEET); // mattress
  b.box(w - 0.02, 0.06, d * 0.62, 0, top - 0.02, d * 0.17, blanket); // blanket
  b.box(w - 0.02, 0.2, 0.05, 0, top - 0.17, d * 0.17 + d * 0.31 - 0.02, blanket); // blanket fold over the end
  const n = opts.pillows ?? (w > 1.2 ? 2 : 1);
  for (let i = 0; i < n; i++) {
    const x = n === 1 ? 0 : (i - (n - 1) / 2) * (w / n);
    b.box(w / n - 0.12, 0.1, 0.34, x, top - 0.01, -d / 2 + 0.3, WHITE);
  }
}

function zincStall(b: B, w: number, d: number, h: number, door = true) {
  b.box(w, 0.06, d, 0, 0, 0, '#9c9790'); // slab
  b.box(w, h, 0.04, 0, 0, -d / 2 + 0.02, ZINC); // back
  b.box(0.04, h, d, -w / 2 + 0.02, 0, 0, ZINC_DARK); // left
  b.box(0.04, h, d, w / 2 - 0.02, 0, 0, ZINC); // right
  for (let i = -2; i <= 2; i++) b.box(0.02, h, 0.05, i * (w / 5), 0, -d / 2 + 0.05, ZINC_DARK); // corrugation ribs
  if (door) b.box(0.04, h * 0.85, d * 0.5, w / 2 - 0.02 + 0.2, 0.05, d / 2 - 0.05, ZINC_DARK, { ry: 0.9 }); // half-open door
}

export function buildPiece(b: B, f: FurnitureItem, wallH: number) {
  const c = f.color;
  switch (f.kind) {
    case 'bed_single':
      return bed(b, 1.0, 2.0, c ? WOOD : WOOD, c ?? '#2f6fb3', 0.5);
    case 'bed_double':
      return bed(b, 1.5, 2.0, WOOD, c ?? '#6d4aa0', 0.55);
    case 'bed_king':
      return bed(b, 1.9, 2.1, WOOD_DARK, c ?? '#efe9df', 0.58, { head: 1.2, pillows: 3 });
    case 'mattress': {
      b.box(1.3, 0.2, 1.9, 0, 0, 0, '#e9d9b0');
      b.box(1.32, 0.04, 1.92, 0, 0.08, 0, '#c74b3c');
      b.box(1.2, 0.05, 1.1, 0, 0.2, 0.3, c ?? '#3a6ea5');
      b.box(0.9, 0.1, 0.32, 0, 0.2, -0.65, WHITE);
      return;
    }
    case 'bunk': {
      const post = METAL_DARK;
      for (const sx of [-1, 1]) for (const sz of [-1, 1]) b.box(0.05, 1.75, 0.05, sx * 0.47, 0, sz * 0.97, post);
      for (const y of [0.28, 1.2]) {
        b.box(1.0, 0.06, 2.0, 0, y, 0, post);
        b.box(0.92, 0.14, 1.9, 0, y + 0.06, 0, SHEET);
        b.box(0.94, 0.05, 1.1, 0, y + 0.19, 0.38, y < 1 ? (c ?? '#2f6fb3') : '#c9a227');
        b.box(0.6, 0.09, 0.3, 0, y + 0.2, -0.72, WHITE);
      }
      b.box(1.0, 0.04, 0.04, 0, 1.55, 0.97, post); // top rail
      b.box(1.0, 0.04, 0.04, 0, 1.55, -0.97, post);
      for (let i = 0; i < 4; i++) b.box(0.32, 0.03, 0.03, 0.62, 0.35 + i * 0.28, 0.6, post); // ladder rungs (side)
      b.box(0.03, 1.3, 0.03, 0.62, 0.2, 0.44, post);
      b.box(0.03, 1.3, 0.03, 0.62, 0.2, 0.76, post);
      return;
    }
    case 'sofa':
    case 'sofa_l': {
      const w = f.kind === 'sofa' ? 1.9 : 2.8;
      const col = c ?? '#b0473c';
      b.box(w, 0.25, 0.85, 0, 0.08, 0, col);
      legs4(b, w, 0.85, 0.08, 0.06, WOOD_DARK, 0.06);
      b.box(w, 0.5, 0.2, 0, 0.3, -0.325, col); // back
      b.box(0.16, 0.32, 0.85, -w / 2 + 0.08, 0.3, 0, col); // arms
      b.box(0.16, 0.32, 0.85, w / 2 - 0.08, 0.3, 0, col);
      const n = f.kind === 'sofa' ? 2 : 3;
      for (let i = 0; i < n; i++) {
        const x = (i - (n - 1) / 2) * ((w - 0.34) / n);
        b.box((w - 0.36) / n - 0.03, 0.1, 0.62, x, 0.33, 0.06, shadeHex(col, 1.12)); // cushions
      }
      b.box(0.36, 0.3, 0.12, -w / 2 + 0.38, 0.42, -0.18, '#e2c46b', { rx: -0.2 }); // throw pillow
      if (f.kind === 'sofa_l') {
        b.box(0.8, 0.25, 0.9, w / 2 - 0.4, 0.08, 0.85, col); // chaise
        b.box(0.72, 0.1, 0.86, w / 2 - 0.42, 0.33, 0.85, shadeHex(col, 1.12));
      }
      return;
    }
    case 'armchair': {
      const col = c ?? '#7a1f2b';
      b.box(0.85, 0.25, 0.85, 0, 0.08, 0, col);
      legs4(b, 0.85, 0.85, 0.08, 0.06, WOOD_DARK, 0.06);
      b.box(0.85, 0.52, 0.2, 0, 0.3, -0.325, col);
      b.box(0.15, 0.3, 0.85, -0.35, 0.3, 0, col);
      b.box(0.15, 0.3, 0.85, 0.35, 0.3, 0, col);
      b.box(0.54, 0.1, 0.6, 0, 0.33, 0.06, shadeHex(col, 1.12));
      return;
    }
    case 'plastic_chair': {
      const col = c ?? '#e8e4dc';
      b.box(0.46, 0.04, 0.44, 0, 0.42, 0.01, col);
      b.box(0.44, 0.42, 0.04, 0, 0.46, -0.2, col, { rx: -0.12 });
      legs4(b, 0.46, 0.44, 0.42, 0.04, col, 0.01);
      return;
    }
    case 'stool':
      b.cyl(0.17, 0.15, 0.42, 0, 0, 0, c ?? WOOD_LIGHT, { seg: 8 });
      return;
    case 'bench':
      b.box(1.4, 0.06, 0.36, 0, 0.4, 0, c ?? WOOD);
      legs4(b, 1.4, 0.36, 0.4, 0.06, WOOD_DARK, 0.06);
      return;
    case 'table': {
      b.box(0.9, 0.04, 0.6, 0, 0.71, 0, c ?? WOOD_LIGHT);
      legs4(b, 0.9, 0.6, 0.71, 0.05, WOOD);
      b.cyl(0.11, 0.09, 0.03, 0.18, 0.75, 0.05, WHITE, { seg: 12 }); // plate
      b.cyl(0.04, 0.04, 0.12, -0.25, 0.75, -0.1, '#3d7bd9', { seg: 8 }); // water sachet cup
      return;
    }
    case 'dining': {
      b.box(1.4, 0.05, 0.9, 0, 0.71, 0, c ?? WOOD);
      legs4(b, 1.4, 0.9, 0.71, 0.06, WOOD_DARK);
      for (const sx of [-0.35, 0.35]) for (const sz of [-0.22, 0.22]) b.cyl(0.11, 0.09, 0.02, sx, 0.76, sz, WHITE, { seg: 12 });
      b.cyl(0.14, 0.1, 0.1, 0, 0.76, 0, '#d9a441', { seg: 10 }); // bowl of fruit
      b.cyl(0.05, 0.05, 0.05, 0.03, 0.86, 0.02, '#e2552c', { seg: 6 });
      return;
    }
    case 'centre_table': {
      b.box(1.0, 0.04, 0.55, 0, 0.4, 0, c ?? WOOD_DARK);
      b.box(0.9, 0.03, 0.45, 0, 0.12, 0, WOOD);
      legs4(b, 1.0, 0.55, 0.4, 0.05, WOOD_DARK);
      b.cyl(0.05, 0.07, 0.18, 0.25, 0.44, 0, '#2d8f6f', { seg: 8 }); // vase
      return;
    }
    case 'desk': {
      b.box(1.0, 0.04, 0.55, 0, 0.72, 0, c ?? WOOD_LIGHT);
      legs4(b, 1.0, 0.55, 0.72, 0.05, METAL_DARK);
      b.box(0.24, 0.05, 0.3, -0.3, 0.76, 0, '#c0392b'); // books
      b.box(0.22, 0.05, 0.28, -0.3, 0.81, 0, '#2c7be5');
      b.box(0.2, 0.04, 0.26, -0.3, 0.86, 0, '#f1c40f');
      b.box(0.3, 0.01, 0.22, 0.05, 0.76, 0.05, WHITE); // notebook
      return;
    }
    case 'wardrobe': {
      const col = c ?? WOOD;
      b.box(1.2, 1.95, 0.6, 0, 0.05, 0, col);
      b.box(1.24, 0.05, 0.64, 0, 2.0, 0, shadeHex(col, 0.8));
      b.box(0.02, 1.8, 0.01, 0, 0.12, 0.3, shadeHex(col, 0.7)); // door split
      b.box(0.03, 0.18, 0.03, -0.06, 1.0, 0.31, CHROME);
      b.box(0.03, 0.18, 0.03, 0.06, 1.0, 0.31, CHROME);
      b.box(0.36, 1.2, 0.01, 0.28, 0.45, 0.305, '#cfe3ef'); // mirror strip
      return;
    }
    case 'locker': {
      b.box(0.58, 1.8, 0.5, 0, 0, 0, c ?? '#6d8aa3');
      for (const y of [1.45, 1.52, 1.59]) b.box(0.3, 0.02, 0.01, 0, y, 0.25, '#4b6378');
      b.box(0.03, 0.12, 0.03, 0.2, 0.95, 0.26, CHROME);
      return;
    }
    case 'shelf': {
      b.box(0.9, 1.6, 0.35, 0, 0, 0, c ?? WOOD);
      for (const y of [0.4, 0.8, 1.2]) b.box(0.84, 0.03, 0.3, 0, y, 0.02, shadeHex(c ?? WOOD, 0.8));
      return;
    }
    case 'tv':
    case 'tv_big': {
      const w = f.kind === 'tv' ? 1.2 : 1.8;
      b.box(w, 0.45, 0.42, 0, 0, 0, c ?? WOOD_DARK); // stand
      b.box(w * 0.9, 0.02, 0.01, 0, 0.22, 0.211, shadeHex(c ?? WOOD_DARK, 0.7));
      const sw = w * 0.82;
      const sh = sw * 0.56;
      b.box(0.24, 0.05, 0.16, 0, 0.45, -0.02, BLACK); // foot
      b.box(0.05, 0.12, 0.04, 0, 0.5, -0.04, BLACK);
      b.box(sw, sh, 0.05, 0, 0.6, -0.06, BLACK); // bezel
      b.box(sw - 0.05, sh - 0.05, 0.01, 0, 0.625, -0.03, '#000', { layer: 'screen' });
      b.box(0.12, 0.3, 0.12, -w / 2 + 0.07, 0.45, 0, '#2b2e35'); // speakers
      b.box(0.12, 0.3, 0.12, w / 2 - 0.07, 0.45, 0, '#2b2e35');
      return;
    }
    case 'radio': {
      const y = f.y ?? 0;
      if (!y) b.cyl(0.17, 0.15, 0.42, 0, 0, 0, WOOD_LIGHT, { seg: 8 });
      const top = y ? 0 : 0.42;
      b.box(0.34, 0.18, 0.12, 0, top, 0, '#7a2f22');
      b.cyl(0.05, 0.05, 0.01, -0.08, top + 0.09, 0.06, '#2a2a2a', { rx: Math.PI / 2, seg: 10 });
      b.box(0.1, 0.05, 0.01, 0.08, top + 0.1, 0.061, '#e9c46a');
      b.box(0.01, 0.3, 0.01, 0.13, top + 0.18, -0.03, CHROME, { rz: -0.4 });
      return;
    }
    case 'fan': {
      b.cyl(0.18, 0.2, 0.04, 0, 0, 0, '#e9eef2', { seg: 12 });
      b.cyl(0.02, 0.02, 1.0, 0, 0.04, 0, METAL);
      b.box(0.12, 0.12, 0.16, 0, 1.0, -0.04, '#e9eef2');
      b.cyl(0.24, 0.24, 0.06, 0, 1.06, 0.06, '#cfd8de', { rx: Math.PI / 2, seg: 14 }); // cage
      for (let i = 0; i < 3; i++) b.box(0.07, 0.2, 0.01, 0, 1.06, 0.1, '#3d8fd1', { rz: (i * Math.PI * 2) / 3 });
      return;
    }
    case 'lamp': {
      b.cyl(0.13, 0.15, 0.03, 0, 0, 0, BLACK, { seg: 10 });
      b.cyl(0.015, 0.015, 1.35, 0, 0.03, 0, BLACK, { seg: 6 });
      b.cyl(0.12, 0.2, 0.26, 0, 1.3, 0, '#f6e7c4', { seg: 10, layer: 'glow' });
      return;
    }
    case 'plant': {
      b.cyl(0.17, 0.13, 0.32, 0, 0, 0, '#b5552b', { seg: 8 });
      b.cyl(0.16, 0.16, 0.02, 0, 0.3, 0, '#4a3324', { seg: 8 });
      const g = ['#2f8f4e', '#3fa45e', '#27773f'];
      for (let i = 0; i < 6; i++) {
        const a = (i / 6) * Math.PI * 2;
        b.box(0.08, 0.55, 0.02, Math.sin(a) * 0.05, 0.3, Math.cos(a) * 0.05, g[i % 3], { rx: Math.cos(a) * 0.45, rz: -Math.sin(a) * 0.45 });
      }
      return;
    }
    case 'rug': {
      const col = c ?? '#9c3b33';
      b.box(2.0, 0.012, 1.4, 0, 0.004, 0, '#e8c26a');
      b.box(1.8, 0.014, 1.2, 0, 0.004, 0, col);
      b.box(1.2, 0.016, 0.6, 0, 0.004, 0, '#e8c26a');
      b.box(1.0, 0.018, 0.42, 0, 0.004, 0, col);
      return;
    }
    case 'ac': {
      b.box(0.9, 0.28, 0.22, 0, 2.05, -0.02, WHITE);
      b.box(0.82, 0.02, 0.02, 0, 2.08, 0.1, '#c9d1d8');
      return;
    }
    case 'kerosene_stove':
    case 'hotplate': {
      const tw = f.kind === 'hotplate' ? 0.55 : 0.6;
      const td = f.kind === 'hotplate' ? 0.45 : 0.5;
      b.box(tw, 0.04, td, 0, 0.42, 0, WOOD_LIGHT);
      legs4(b, tw, td, 0.42, 0.04, WOOD, 0.02);
      if (f.kind === 'kerosene_stove') {
        b.cyl(0.13, 0.15, 0.16, 0, 0.46, 0, '#3f6f8f', { seg: 10 });
        b.cyl(0.12, 0.12, 0.02, 0, 0.62, 0, BLACK, { seg: 10 });
      } else {
        b.box(0.3, 0.06, 0.28, 0, 0.46, 0, '#dfe3e6');
        b.cyl(0.1, 0.1, 0.01, 0, 0.52, 0, '#2a2a2a', { seg: 12 });
      }
      b.cyl(0.14, 0.13, 0.15, 0, f.kind === 'hotplate' ? 0.53 : 0.64, 0, '#b9c0c6', { seg: 12 }); // pot
      b.box(0.1, 0.015, 0.02, 0.18, f.kind === 'hotplate' ? 0.65 : 0.76, 0, BLACK);
      b.box(0.24, 0.02, 0.2, -tw / 2 + 0.14, 0.46, 0.08, '#d9a441'); // tray of pepper
      return;
    }
    case 'kitchen': {
      const col = c ?? WHITE;
      b.box(2.2, 0.86, 0.6, 0, 0, 0, col); // cabinets
      for (let i = -1; i <= 1; i++) b.box(0.01, 0.7, 0.01, i * 0.55, 0.08, 0.301, shadeHex(col, 0.75));
      b.box(2.24, 0.05, 0.64, 0, 0.86, 0, '#3a3f47'); // counter top
      b.box(2.2, 0.5, 0.03, 0, 0.91, -0.3, '#d8e6ec'); // backsplash tiles
      // gas cooker on the left
      b.box(0.6, 0.02, 0.5, -0.6, 0.91, 0, '#1e2126');
      for (const sx of [-0.13, 0.13]) for (const sz of [-0.11, 0.11]) b.cyl(0.07, 0.07, 0.02, -0.6 + sx, 0.93, sz, '#55595f', { seg: 10 });
      b.cyl(0.13, 0.12, 0.16, -0.73, 0.95, 0.1, '#c0392b', { seg: 12 }); // pot of stew
      // sink on the right
      b.box(0.55, 0.03, 0.42, 0.55, 0.9, 0, '#c9d1d6');
      b.box(0.45, 0.02, 0.32, 0.55, 0.905, 0, '#8b979f');
      b.box(0.03, 0.22, 0.03, 0.55, 0.91, -0.2, CHROME);
      b.box(0.03, 0.03, 0.14, 0.55, 1.1, -0.14, CHROME);
      b.box(0.3, 0.32, 0.25, 0.0, 0.91, -0.12, '#efe9df'); // microwave/box
      b.box(0.2, 0.18, 0.01, -0.02, 0.98, 0.006, '#1b1e23', { layer: 'screen' });
      return;
    }
    case 'island': {
      const col = c ?? WHITE;
      b.box(1.6, 0.88, 0.8, 0, 0, 0, col);
      b.box(1.7, 0.05, 0.9, 0, 0.88, 0, '#2f3640');
      b.cyl(0.18, 0.14, 0.12, -0.4, 0.93, 0, '#d9a441', { seg: 10 });
      b.cyl(0.03, 0.03, 0.26, 0.4, 0.93, -0.1, '#2e7d32', { seg: 6 });
      for (const sx of [-0.45, 0.15]) {
        b.cyl(0.17, 0.17, 0.05, sx, 0.65, 0.65, BLACK, { seg: 10 });
        b.cyl(0.02, 0.02, 0.65, sx, 0, 0.65, CHROME, { seg: 6 });
      }
      return;
    }
    case 'fridge': {
      b.box(0.65, 1.65, 0.62, 0, 0, 0, c ?? '#e9edf0');
      b.box(0.63, 0.01, 0.01, 0, 1.1, 0.311, '#aeb7bf');
      b.box(0.03, 0.4, 0.03, 0.26, 1.15, 0.32, CHROME);
      b.box(0.03, 0.5, 0.03, 0.26, 0.5, 0.32, CHROME);
      b.box(0.14, 0.1, 0.01, -0.16, 1.4, 0.311, '#e2552c'); // fridge magnet
      return;
    }
    case 'gas': {
      b.cyl(0.14, 0.14, 0.5, 0, 0, 0, '#1f7a3f', { seg: 10 });
      b.cyl(0.08, 0.14, 0.08, 0, 0.5, 0, '#1f7a3f', { seg: 10 });
      b.cyl(0.03, 0.03, 0.07, 0, 0.58, 0, CHROME, { seg: 6 });
      return;
    }
    case 'bucket_bath': {
      zincStall(b, 1.1, 1.1, 1.75);
      b.cyl(0.17, 0.13, 0.32, -0.15, 0.06, -0.2, '#2c7be5', { seg: 10 });
      b.cyl(0.15, 0.15, 0.02, -0.15, 0.36, -0.2, '#5fa8ff', { seg: 10 });
      b.cyl(0.11, 0.07, 0.07, 0.2, 0.06, -0.25, '#f1c40f', { seg: 10 }); // small bowl
      b.box(0.1, 0.04, 0.06, 0.32, 0.06, 0.05, '#f6f3ec'); // soap
      return;
    }
    case 'pit_toilet': {
      zincStall(b, 1.1, 1.1, 1.75);
      b.box(0.5, 0.18, 0.55, 0, 0.06, -0.15, '#bdb7ae');
      b.box(0.18, 0.02, 0.22, 0, 0.24, -0.12, '#2b2b2b');
      b.cyl(0.08, 0.06, 0.18, 0.35, 0.06, -0.35, '#2e9e55', { seg: 8 }); // kettle
      return;
    }
    case 'shower': {
      b.box(0.95, 0.06, 0.95, 0, 0, 0, '#e8eef1');
      b.box(0.85, 0.02, 0.85, 0, 0.06, 0, '#c8d6dc');
      b.box(0.02, 1.9, 0.95, 0.47, 0.06, 0, '#bfe3f2', { layer: 'glass' });
      b.cyl(0.015, 0.015, 1.9, -0.36, 0.06, -0.42, CHROME, { seg: 6 });
      b.cyl(0.09, 0.07, 0.04, -0.3, 1.9, -0.36, CHROME, { seg: 10 });
      b.box(0.3, 0.3, 0.02, 0, 1.0, -0.47, '#2c7be5'); // towel on the wall
      return;
    }
    case 'bathtub': {
      b.box(0.8, 0.55, 1.7, 0, 0, 0, WHITE);
      b.box(0.62, 0.02, 1.5, 0, 0.53, 0, '#9fd3ea');
      b.box(0.04, 0.22, 0.04, 0, 0.55, -0.78, CHROME);
      b.box(0.5, 0.06, 0.3, 0, 0.55, 0.9, '#f7d7e2'); // bath mat
      return;
    }
    case 'toilet': {
      b.box(0.42, 0.38, 0.2, 0, 0.36, -0.25, WHITE); // tank
      b.cyl(0.17, 0.13, 0.4, 0, 0, 0.04, WHITE, { seg: 10 });
      b.cyl(0.19, 0.19, 0.04, 0, 0.4, 0.04, '#e9e9e4', { seg: 10 });
      b.box(0.05, 0.02, 0.03, 0.12, 0.72, -0.18, CHROME);
      return;
    }
    case 'sink': {
      b.cyl(0.06, 0.08, 0.72, 0, 0, -0.05, WHITE, { seg: 8 });
      b.box(0.5, 0.14, 0.4, 0, 0.72, 0, WHITE);
      b.box(0.4, 0.02, 0.28, 0, 0.85, 0.02, '#c5d3da');
      b.box(0.03, 0.12, 0.03, 0, 0.86, -0.15, CHROME);
      b.box(0.42, 0.55, 0.02, 0, 1.15, -0.2, '#cfe3ef', { layer: 'glass' }); // mirror
      return;
    }
    case 'generator': {
      b.box(0.8, 0.5, 0.55, 0, 0.08, 0, c ?? '#e2a21a');
      b.box(0.82, 0.05, 0.57, 0, 0.58, 0, '#2b2e35');
      b.box(0.5, 0.2, 0.01, 0, 0.25, 0.276, '#2b2e35');
      b.cyl(0.04, 0.04, 0.2, 0.3, 0.6, -0.15, METAL_DARK, { seg: 6 }); // exhaust
      for (const sx of [-0.33, 0.33]) b.cyl(0.08, 0.08, 0.05, sx, 0.08, 0.26, BLACK, { rx: Math.PI / 2, seg: 10 });
      b.box(0.72, 0.03, 0.03, 0, 0.62, 0.25, BLACK); // handle
      return;
    }
    case 'drum': {
      b.cyl(0.28, 0.28, 0.85, 0, 0, 0, c ?? '#2c6fd6', { seg: 12 });
      b.cyl(0.29, 0.29, 0.03, 0, 0.3, 0, '#1f55a8', { seg: 12 });
      b.cyl(0.29, 0.29, 0.03, 0, 0.6, 0, '#1f55a8', { seg: 12 });
      b.cyl(0.08, 0.08, 0.03, 0.12, 0.85, 0, '#1f55a8', { seg: 8 });
      return;
    }
    case 'clothesline': {
      b.box(0.04, 1.6, 0.04, -1.2, 0, 0, WOOD_DARK);
      b.box(0.04, 1.6, 0.04, 1.2, 0, 0, WOOD_DARK);
      b.box(2.4, 0.01, 0.01, 0, 1.55, 0, '#ddd');
      const cols = ['#e2552c', '#2c7be5', '#f1c40f', '#7d3c98'];
      for (let i = 0; i < 4; i++) b.box(0.32, 0.4 + (i % 2) * 0.12, 0.02, -0.8 + i * 0.52, 1.13 - (i % 2) * 0.12, 0, cols[i]);
      return;
    }
    case 'stall':
      zincStall(b, 1.2, 1.2, 1.8, false);
      return;
    default:
      void wallH;
  }
}

/** Darken (<1) or lighten (>1) a #rrggbb colour. */
export function shadeHex(hex: string, k: number): string {
  const n = parseInt(hex.slice(1), 16);
  const ch = (v: number) => Math.max(0, Math.min(255, Math.round(k > 1 ? v + (255 - v) * (k - 1) : v * k)));
  const r = ch((n >> 16) & 255);
  const g = ch((n >> 8) & 255);
  const bl = ch(n & 255);
  return `#${((1 << 24) | (r << 16) | (g << 8) | bl).toString(16).slice(1)}`;
}
