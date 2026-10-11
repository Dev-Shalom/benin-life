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


/** Sofa archetype: w wide, d deep, `n` seat cushions, optional tufted (Chesterfield) back. */
function sofaShape(b: B, w: number, d: number, col: string, n: number, opts: { legs?: string; tuft?: boolean; armH?: number } = {}) {
  b.box(w, 0.25, d, 0, 0.08, 0, col);
  legs4(b, w, d, 0.08, 0.06, opts.legs ?? WOOD_DARK, 0.06);
  b.box(w, opts.tuft ? 0.56 : 0.5, 0.2, 0, 0.3, -d / 2 + 0.1, col);
  const ah = opts.armH ?? 0.32;
  b.box(0.16, ah, d, -w / 2 + 0.08, 0.3, 0, col);
  b.box(0.16, ah, d, w / 2 - 0.08, 0.3, 0, col);
  for (let i = 0; i < n; i++) {
    const x = (i - (n - 1) / 2) * ((w - 0.34) / n);
    b.box((w - 0.36) / n - 0.03, 0.1, d - 0.25, x, 0.33, 0.06, shadeHex(col, 1.12));
  }
  if (opts.tuft) for (let i = 0; i < 9; i++) for (const y of [0.55, 0.7]) b.box(0.03, 0.03, 0.01, -w / 2 + 0.3 + i * ((w - 0.6) / 8), y, -d / 2 + 0.205, shadeHex(col, 0.7));
}

/** TV on a low console: stand width `w`, screen width `sw`. */
function tvShape(b: B, w: number, sw: number, stand: string, legs = false) {
  const sh = sw * 0.56;
  if (legs) {
    b.box(w, 0.05, 0.4, 0, 0.4, 0, stand);
    legs4(b, w, 0.4, 0.4, 0.04, METAL_DARK, 0.03);
  } else {
    b.box(w, 0.45, 0.42, 0, 0, 0, stand);
    b.box(w * 0.9, 0.02, 0.01, 0, 0.22, 0.211, shadeHex(stand, 0.7));
  }
  const top = legs ? 0.45 : 0.45;
  b.box(0.24, 0.05, 0.16, 0, top, -0.02, BLACK);
  b.box(0.05, 0.12, 0.04, 0, top + 0.05, -0.04, BLACK);
  b.box(sw, sh, 0.05, 0, top + 0.15, -0.06, BLACK);
  b.box(sw - 0.05, sh - 0.05, 0.01, 0, top + 0.175, -0.03, '#000', { layer: 'screen' });
}

/** A box appliance (fridge, freezer, washer ...). */
function applianceBox(b: B, w: number, h: number, d: number, col: string) {
  b.box(w, h, d, 0, 0, 0, col);
  b.box(w + 0.01, 0.03, d + 0.01, 0, 0, 0, '#3a3f47'); // plinth
}

/** Something hung on the wall behind the piece (local -z), bottom at y. */
function onWall(b: B, w: number, h: number, y: number, col: string, d = 0.04, opt: { layer?: 'glow' | 'glass' | 'screen' } = {}) {
  b.box(w, h, d, 0, y, -0.02 + d / 2 - 0.02, col, { ...opt, noOcc: true });
}

/** A small surface (stand or cart) to put a small appliance on. */
function smallStand(b: B, w: number, d: number, h: number, col = WOOD_LIGHT) {
  b.box(w, 0.04, d, 0, h - 0.04, 0, col);
  b.box(w - 0.06, 0.03, d - 0.06, 0, 0.12, 0, shadeHex(col, 0.85));
  legs4(b, w, d, h - 0.04, 0.04, shadeHex(col, 0.7), 0.02);
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
    case 'drum_bucket': {
      // blue water drum at the back-left, a bucket with a bowl in front-right, a wet patch on the floor
      b.box(0.95, 0.01, 0.58, 0, 0, 0, '#8d8a84');
      b.cyl(0.24, 0.24, 0.8, -0.24, 0, -0.04, c ?? '#2c6fd6', { seg: 12 });
      b.cyl(0.25, 0.25, 0.03, -0.24, 0.28, -0.04, '#1f55a8', { seg: 12 });
      b.cyl(0.25, 0.25, 0.03, -0.24, 0.56, -0.04, '#1f55a8', { seg: 12 });
      b.cyl(0.22, 0.22, 0.02, -0.24, 0.8, -0.04, '#1f55a8', { seg: 12 }); // lid
      b.cyl(0.16, 0.12, 0.3, 0.24, 0, 0.06, '#e2552c', { seg: 10 }); // bucket
      b.cyl(0.14, 0.14, 0.015, 0.24, 0.27, 0.06, '#5fa8ff', { seg: 10 }); // water
      b.box(0.24, 0.015, 0.02, 0.24, 0.31, 0.06, BLACK); // handle
      b.cyl(0.08, 0.05, 0.06, 0.38, 0, -0.18, '#f1c40f', { seg: 8 }); // small bowl
      b.box(0.09, 0.035, 0.05, 0.06, 0, 0.18, '#f6f3ec'); // soap
      return;
    }
    case 'gas_cooker': {
      // standing cooker (0.6 wide) with an oven, plus the cylinder on the right
      const col = c ?? '#e9ecef';
      b.box(0.6, 0.85, 0.58, -0.17, 0, 0, col);
      b.box(0.5, 0.36, 0.01, -0.17, 0.2, 0.291, '#2b2f36'); // oven door
      b.box(0.36, 0.03, 0.03, -0.17, 0.62, 0.3, CHROME); // handle
      b.box(0.6, 0.02, 0.58, -0.17, 0.85, 0, '#1e2126'); // hob
      for (const sx of [-0.13, 0.13]) for (const sz of [-0.12, 0.12]) b.cyl(0.065, 0.065, 0.02, -0.17 + sx, 0.87, sz, '#55595f', { seg: 10 });
      for (let i = 0; i < 4; i++) b.box(0.04, 0.04, 0.02, -0.38 + i * 0.14, 0.76, 0.3, BLACK); // knobs
      b.cyl(0.13, 0.12, 0.16, -0.3, 0.89, 0.12, '#c0392b', { seg: 12 }); // pot of stew
      b.cyl(0.13, 0.13, 0.48, 0.32, 0, 0, '#1f7a3f', { seg: 10 }); // gas cylinder
      b.cyl(0.07, 0.13, 0.08, 0.32, 0.48, 0, '#1f7a3f', { seg: 10 });
      b.cyl(0.03, 0.03, 0.07, 0.32, 0.56, 0, CHROME, { seg: 6 });
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

    // ---------------- B1 catalogue
    case 'plastic_table': {
      const col = c ?? '#2e86c1';
      b.cyl(0.4, 0.4, 0.04, 0, 0.7, 0, col, { seg: 14 });
      for (const [sx, sz] of [[-0.25, -0.25], [0.25, -0.25], [-0.25, 0.25], [0.25, 0.25]]) b.box(0.05, 0.7, 0.05, sx, 0, sz, col, { rx: sz * 0.25, rz: -sx * 0.25 });
      return;
    }
    case 'sofa_2':
      return sofaShape(b, 1.4, 0.85, c ?? '#2f6f8f', 2);
    case 'sofa_lux': {
      const col = c ?? '#f1e9da';
      sofaShape(b, 2.4, 0.95, col, 3, { legs: '#c9a227', tuft: true, armH: 0.42 });
      b.box(0.4, 0.32, 0.12, -0.75, 0.42, -0.25, '#c9a227', { rx: -0.2 });
      b.box(0.4, 0.32, 0.12, 0.75, 0.42, -0.25, '#7b4f2e', { rx: -0.2 });
      return;
    }
    case 'recliner': {
      const col = c ?? '#3b2a20';
      b.box(0.95, 0.3, 0.95, 0, 0.05, 0, col);
      b.box(0.95, 0.62, 0.22, 0, 0.3, -0.36, col, { rx: -0.18 });
      b.box(0.17, 0.36, 0.95, -0.39, 0.3, 0, col);
      b.box(0.17, 0.36, 0.95, 0.39, 0.3, 0, col);
      b.box(0.6, 0.12, 0.6, 0, 0.35, 0.05, shadeHex(col, 1.18));
      b.box(0.6, 0.08, 0.3, 0, 0.22, 0.58, col, { rx: 0.5 }); // footrest
      return;
    }
    case 'centre_glass': {
      for (const [sx, sz] of [[-0.5, -0.24], [0.5, -0.24], [-0.5, 0.24], [0.5, 0.24]]) b.box(0.04, 0.42, 0.04, sx, 0, sz, '#c9a227');
      b.box(1.2, 0.03, 0.65, 0, 0.42, 0, '#bfe3f2', { layer: 'glass' });
      b.box(1.1, 0.02, 0.55, 0, 0.12, 0, '#c9a227');
      b.cyl(0.08, 0.06, 0.1, 0.3, 0.45, 0, '#2c3e50', { seg: 10 });
      return;
    }
    case 'office_chair': {
      const col = c ?? '#23262c';
      b.cyl(0.28, 0.28, 0.04, 0, 0.05, 0, METAL_DARK, { seg: 5 });
      b.cyl(0.03, 0.03, 0.38, 0, 0.08, 0, CHROME, { seg: 6 });
      b.box(0.5, 0.08, 0.48, 0, 0.44, 0, col);
      b.box(0.46, 0.55, 0.06, 0, 0.55, -0.22, col, { rx: -0.1 });
      return;
    }
    case 'garden_set': {
      b.cyl(0.35, 0.35, 0.04, 0, 0.7, 0, WHITE, { seg: 14 });
      b.cyl(0.03, 0.03, 0.7, 0, 0, 0, METAL_DARK, { seg: 6 });
      b.cyl(0.02, 0.02, 1.4, 0, 0.7, 0, METAL_DARK, { seg: 6 });
      b.cyl(0.04, 0.78, 0.3, 0, 1.9, 0, '#c0392b', { seg: 8 }); // umbrella
      for (const sx of [-0.6, 0.6]) {
        b.box(0.45, 0.04, 0.45, sx, 0.4, 0, WHITE);
        b.box(0.04, 0.4, 0.45, sx + Math.sign(sx) * 0.22, 0.4, 0, WHITE, { rz: Math.sign(sx) * 0.15 });
        legs4(b, 0.45, 0.45, 0.4, 0.04, WHITE, 0.02);
      }
      return;
    }
    case 'tv_small': {
      smallStand(b, 0.8, 0.4, 0.5, c ?? WOOD);
      b.box(0.56, 0.34, 0.05, 0, 0.55, -0.04, BLACK);
      b.box(0.52, 0.3, 0.01, 0, 0.57, -0.01, '#000', { layer: 'screen' });
      b.box(0.18, 0.05, 0.12, 0, 0.5, -0.04, BLACK);
      return;
    }
    case 'tv_43':
      return tvShape(b, 1.3, 0.98, c ?? WOOD_DARK);
    case 'tv_55':
      return tvShape(b, 1.5, 1.24, c ?? '#2b2e35');
    case 'tv_75':
      tvShape(b, 2.2, 1.7, c ?? '#efe9df');
      b.box(0.9, 0.08, 0.1, 0, 0.45, 0.12, BLACK); // soundbar
      return;
    case 'speaker_small':
      b.cyl(0.08, 0.08, 0.22, 0, 0.42, 0, '#1b1e23', { seg: 10 });
      b.cyl(0.15, 0.13, 0.42, 0, 0, 0, WOOD_LIGHT, { seg: 8 }); // on a stool
      return;
    case 'home_theatre': {
      b.box(1.0, 0.1, 0.12, 0, 0.0, 0.12, BLACK); // soundbar on the floor in front
      b.box(0.34, 0.42, 0.36, -0.6, 0, -0.02, '#2b2e35'); // woofer
      b.cyl(0.11, 0.11, 0.02, -0.6, 0.21, 0.16, '#555', { rx: Math.PI / 2, seg: 12 });
      for (const sx of [0.35, 0.68]) b.box(0.16, 0.9, 0.16, sx, 0, -0.05, '#2b2e35');
      return;
    }
    case 'speaker_tower': {
      b.box(0.3, 1.1, 0.3, 0, 0.02, 0, c ?? '#1b1e23');
      for (const y of [0.3, 0.6, 0.9]) b.cyl(0.08, 0.08, 0.01, 0, y, 0.15, '#4a4f57', { rx: Math.PI / 2, seg: 12 });
      return;
    }
    case 'mat_raffia': {
      b.box(1.6, 0.012, 1.0, 0, 0.004, 0, '#d8b06a');
      for (let i = 0; i < 6; i++) b.box(1.5, 0.014, 0.04, 0, 0.004, -0.4 + i * 0.16, i % 2 ? '#b5813f' : '#9b2c2c');
      return;
    }
    case 'rug_big': {
      const col = c ?? '#efe6d6';
      b.box(2.6, 0.02, 1.8, 0, 0.004, 0, col);
      b.box(2.3, 0.022, 1.5, 0, 0.004, 0, shadeHex(col, 0.92));
      return;
    }
    case 'curtain':
    case 'curtain_lux': {
      const w = f.kind === 'curtain' ? 1.4 : 1.8;
      const col = c ?? '#d35400';
      b.box(w + 0.1, 0.03, 0.03, 0, 2.15, -0.04, f.kind === 'curtain' ? WOOD_DARK : '#c9a227'); // rod
      for (const sx of [-1, 1]) {
        for (let i = 0; i < 3; i++) b.box(w * 0.12, 1.9, 0.05, sx * (w / 2 - w * 0.06 - i * w * 0.11), 0.25, -0.03 + (i % 2) * 0.03, i % 2 ? shadeHex(col, 0.85) : col, { noOcc: true });
      }
      if (f.kind === 'curtain_lux') b.box(w - 0.1, 0.25, 0.06, 0, 1.9, -0.01, shadeHex(col, 0.7), { noOcc: true }); // pelmet
      return;
    }
    case 'fan_table': {
      b.box(0.3, 0.04, 0.24, 0, 0, 0, '#e9eef2');
      b.cyl(0.02, 0.02, 0.3, 0, 0.04, 0, METAL);
      b.cyl(0.15, 0.15, 0.05, 0, 0.42, 0.03, '#cfd8de', { rx: Math.PI / 2, seg: 14 });
      for (let i = 0; i < 3; i++) b.box(0.05, 0.13, 0.01, 0, 0.42, 0.06, '#e2552c', { rz: (i * Math.PI * 2) / 3 });
      return;
    }
    case 'fan_ceiling': {
      const top = wallH - 0.02;
      b.cyl(0.015, 0.015, 0.4, 0, top - 0.4, 0, METAL_DARK, { seg: 6 });
      b.cyl(0.1, 0.12, 0.12, 0, top - 0.5, 0, '#e9eef2', { seg: 10 });
      for (let i = 0; i < 3; i++) {
        const a = (i * Math.PI * 2) / 3;
        b.box(0.55, 0.015, 0.12, Math.cos(a) * 0.32, top - 0.46, Math.sin(a) * 0.32, WOOD, { ry: -a });
      }
      return;
    }
    case 'ac_big': {
      b.box(1.1, 0.32, 0.25, 0, 2.0, -0.02, WHITE);
      b.box(1.0, 0.02, 0.02, 0, 2.04, 0.11, '#c9d1d8');
      b.box(0.12, 0.03, 0.01, 0.4, 2.25, 0.105, '#2ecc71', { layer: 'glow' });
      return;
    }
    case 'ac_standing': {
      b.box(0.45, 1.75, 0.35, 0, 0, 0, WHITE);
      b.box(0.36, 0.5, 0.01, 0, 1.1, 0.176, '#c9d1d8');
      b.box(0.14, 0.05, 0.01, 0, 0.9, 0.176, '#2c7be5', { layer: 'glow' });
      return;
    }
    case 'bookshelf': {
      const col = c ?? WOOD;
      b.box(1.0, 1.8, 0.36, 0, 0, 0, col);
      const books = ['#c0392b', '#2c7be5', '#f1c40f', '#27ae60', '#8e44ad', '#e67e22'];
      for (const [j, y] of [0.1, 0.55, 1.0, 1.45].entries()) {
        b.box(0.94, 0.03, 0.32, 0, y, 0.03, shadeHex(col, 0.8));
        for (let i = 0; i < 7; i++) b.box(0.08, 0.3 - ((i + j) % 3) * 0.04, 0.24, -0.38 + i * 0.12, y + 0.03, 0.04, books[(i + j) % books.length]);
      }
      return;
    }
    case 'mattress_thick': {
      b.box(1.4, 0.3, 1.95, 0, 0, 0, '#f2ead6');
      b.box(1.42, 0.05, 1.97, 0, 0.12, 0, c ?? '#2e7d6b');
      b.box(1.3, 0.05, 1.1, 0, 0.3, 0.3, '#d9a441');
      b.box(1.0, 0.1, 0.32, 0, 0.3, -0.68, WHITE);
      return;
    }
    case 'bed_6':
      return bed(b, 1.8, 2.05, WOOD, c ?? '#1f618d', 0.6, { head: 1.05 });
    case 'bed_lux': {
      bed(b, 2.1, 2.25, c ?? '#c9b79c', '#f4ecdf', 0.66, { head: 0.3, pillows: 3 });
      const col = c ?? '#c9b79c';
      b.box(2.3, 1.3, 0.14, 0, 0, -1.08, col); // tall upholstered headboard
      for (let i = 0; i < 7; i++) for (const y of [0.8, 1.0, 1.2]) b.box(0.03, 0.03, 0.01, -0.9 + i * 0.3, y, -1.005, shadeHex(col, 0.7));
      b.box(2.1, 0.06, 0.5, 0, 0.66, 0.75, '#c9a227'); // runner
      return;
    }
    case 'clothes_rack': {
      for (const sx of [-0.48, 0.48]) b.box(0.03, 1.6, 0.03, sx, 0, 0, CHROME);
      b.box(1.0, 0.03, 0.03, 0, 1.58, 0, CHROME);
      for (const sx of [-0.48, 0.48]) b.box(0.05, 0.03, 0.42, sx, 0, 0, CHROME);
      const cl = ['#e2552c', '#2c7be5', '#f1c40f', '#27ae60', '#ecf0f1'];
      for (let i = 0; i < 5; i++) b.box(0.14, 0.75, 0.32, -0.34 + i * 0.17, 0.8, 0, cl[i]);
      return;
    }
    case 'wardrobe_big': {
      const col = c ?? WOOD_DARK;
      b.box(1.9, 2.1, 0.62, 0, 0.05, 0, col);
      b.box(1.94, 0.05, 0.66, 0, 2.15, 0, shadeHex(col, 0.8));
      for (const x of [-0.32, 0.32]) b.box(0.02, 1.95, 0.01, x, 0.12, 0.31, shadeHex(col, 0.7));
      for (const x of [-0.38, -0.26, 0.26, 0.38]) b.box(0.03, 0.2, 0.03, x, 1.0, 0.32, '#c9a227');
      b.box(0.5, 1.6, 0.01, 0, 0.3, 0.315, '#cfe3ef');
      return;
    }
    case 'dressing': {
      const col = c ?? WOOD_LIGHT;
      b.box(1.0, 0.75, 0.45, 0, 0, 0, col);
      b.box(0.02, 0.6, 0.01, 0, 0.08, 0.226, shadeHex(col, 0.7));
      b.box(0.6, 0.8, 0.03, 0, 0.75, -0.18, shadeHex(col, 0.8));
      b.box(0.52, 0.72, 0.01, 0, 0.79, -0.16, '#cfe3ef', { layer: 'glass' });
      b.cyl(0.03, 0.03, 0.12, 0.35, 0.75, 0.05, '#8e44ad', { seg: 6 });
      b.cyl(0.03, 0.03, 0.09, 0.28, 0.75, 0.08, '#e84393', { seg: 6 });
      return;
    }
    case 'mirror_stand': {
      b.box(0.46, 1.6, 0.04, 0, 0.05, -0.05, WOOD_DARK, { rx: -0.1 });
      b.box(0.38, 1.5, 0.01, 0, 0.1, -0.02, '#cfe3ef', { rx: -0.1, layer: 'glass' });
      b.box(0.04, 0.9, 0.04, 0, 0, -0.15, WOOD_DARK, { rx: 0.35 });
      return;
    }
    case 'bedside': {
      const col = c ?? WOOD;
      b.box(0.45, 0.55, 0.4, 0, 0, 0, col);
      b.box(0.39, 0.01, 0.01, 0, 0.35, 0.2, shadeHex(col, 0.7));
      b.box(0.06, 0.02, 0.02, 0, 0.42, 0.21, CHROME);
      b.box(0.12, 0.02, 0.07, 0.1, 0.55, 0.05, BLACK); // phone
      return;
    }
    case 'lamp_small': {
      b.cyl(0.08, 0.1, 0.05, 0, 0, 0, '#c9a227', { seg: 10 });
      b.cyl(0.015, 0.015, 0.35, 0, 0.05, 0, '#c9a227', { seg: 6 });
      b.cyl(0.08, 0.14, 0.18, 0, 0.38, 0, '#f6e7c4', { seg: 10, layer: 'glow' });
      return;
    }
    case 'chandelier': {
      const top = wallH - 0.02;
      b.cyl(0.01, 0.01, 0.45, 0, top - 0.45, 0, '#c9a227', { seg: 6 });
      b.cyl(0.32, 0.18, 0.08, 0, top - 0.55, 0, '#c9a227', { seg: 12 });
      for (let i = 0; i < 10; i++) {
        const a = (i / 10) * Math.PI * 2;
        b.cyl(0.03, 0.01, 0.22 + (i % 2) * 0.1, Math.cos(a) * 0.3, top - 0.85 - (i % 2) * 0.1, Math.sin(a) * 0.3, '#fff7d6', { seg: 6, layer: 'glow' });
      }
      b.cyl(0.05, 0.02, 0.35, 0, top - 0.95, 0, '#fff7d6', { seg: 6, layer: 'glow' });
      return;
    }
    case 'gas_table': {
      smallStand(b, 0.7, 0.5, 0.75, WOOD_LIGHT);
      b.box(0.55, 0.08, 0.32, 0, 0.75, 0, '#2b2f36');
      for (const sx of [-0.13, 0.13]) b.cyl(0.07, 0.07, 0.02, sx, 0.83, 0, '#55595f', { seg: 10 });
      b.cyl(0.12, 0.11, 0.14, -0.13, 0.85, 0, '#c0392b', { seg: 12 });
      b.cyl(0.1, 0.1, 0.32, 0.22, 0, 0.1, '#1f7a3f', { seg: 10 }); // 3 kg cylinder underneath
      return;
    }
    case 'cooker_big': {
      b.box(0.92, 0.88, 0.6, 0, 0, 0, '#c8ced4');
      b.box(0.8, 0.42, 0.01, 0, 0.18, 0.301, '#1b1e23');
      b.box(0.6, 0.03, 0.03, 0, 0.66, 0.31, CHROME);
      b.box(0.92, 0.02, 0.6, 0, 0.88, 0, '#1e2126');
      for (const [sx, sz] of [[-0.28, -0.14], [0.28, -0.14], [-0.28, 0.14], [0.28, 0.14], [0, 0]]) b.cyl(0.07, 0.07, 0.02, sx, 0.9, sz, '#55595f', { seg: 10 });
      for (let i = 0; i < 5; i++) b.box(0.05, 0.05, 0.02, -0.3 + i * 0.15, 0.78, 0.31, BLACK);
      b.box(0.96, 0.4, 0.03, 0, 0.9, -0.3, '#c8ced4'); // splash back
      b.cyl(0.14, 0.13, 0.18, 0.28, 0.92, 0.14, '#c0392b', { seg: 12 });
      return;
    }
    case 'fridge_small': {
      applianceBox(b, 0.5, 0.85, 0.5, c ?? '#e9edf0');
      b.box(0.03, 0.25, 0.03, 0.19, 0.45, 0.26, CHROME);
      return;
    }
    case 'fridge_sbs': {
      applianceBox(b, 0.92, 1.8, 0.72, c ?? '#b8c0c8');
      b.box(0.01, 1.75, 0.01, 0, 0.03, 0.361, '#7f898f');
      for (const sx of [-0.05, 0.05]) b.box(0.03, 0.7, 0.03, sx, 0.7, 0.37, CHROME);
      b.box(0.18, 0.28, 0.01, -0.22, 1.1, 0.361, '#2b2f36'); // water / ice tap
      return;
    }
    case 'freezer': {
      applianceBox(b, 1.0, 0.85, 0.6, c ?? WHITE);
      b.box(1.02, 0.06, 0.62, 0, 0.85, 0, '#dfe5ea');
      b.box(0.3, 0.03, 0.03, 0, 0.78, 0.31, '#9aa3ab');
      b.box(0.08, 0.03, 0.01, 0.4, 0.6, 0.301, '#2ecc71', { layer: 'glow' });
      return;
    }
    case 'microwave': {
      smallStand(b, 0.55, 0.45, 0.8, WOOD_LIGHT);
      b.box(0.48, 0.28, 0.36, 0, 0.8, 0, '#2b2f36');
      b.box(0.3, 0.2, 0.01, -0.06, 0.84, 0.181, '#111', { layer: 'screen' });
      b.box(0.08, 0.2, 0.01, 0.17, 0.84, 0.181, '#c8ced4');
      return;
    }
    case 'blender': {
      smallStand(b, 0.4, 0.4, 0.75, WOOD_LIGHT);
      b.box(0.16, 0.12, 0.16, 0, 0.75, 0, '#e9eef2');
      b.cyl(0.07, 0.05, 0.26, 0, 0.87, 0, '#bfe3f2', { seg: 10, layer: 'glass' });
      b.cyl(0.075, 0.075, 0.03, 0, 1.13, 0, '#2c7be5', { seg: 10 });
      return;
    }
    case 'pots': {
      b.box(0.7, 0.04, 0.38, 0, 0.45, 0, WOOD);
      legs4(b, 0.7, 0.38, 0.45, 0.04, WOOD_DARK, 0.02);
      b.cyl(0.13, 0.12, 0.16, -0.18, 0.49, 0, '#b9c0c6', { seg: 12 });
      b.cyl(0.1, 0.1, 0.12, 0.12, 0.49, 0, '#c0392b', { seg: 12 });
      b.cyl(0.14, 0.1, 0.3, 0.22, 0, 0.05, WOOD_DARK, { seg: 10 }); // mortar on the floor
      b.cyl(0.025, 0.025, 0.5, 0.22, 0.25, 0.05, WOOD_LIGHT, { seg: 6, rz: 0.2 }); // pestle
      return;
    }
    case 'dispenser': {
      b.box(0.34, 0.95, 0.34, 0, 0, 0, '#e9eef2');
      b.box(0.2, 0.18, 0.02, 0, 0.55, 0.17, '#cfd8de');
      b.box(0.03, 0.04, 0.03, -0.05, 0.62, 0.18, '#e74c3c');
      b.box(0.03, 0.04, 0.03, 0.05, 0.62, 0.18, '#2c7be5');
      b.cyl(0.14, 0.14, 0.38, 0, 0.95, 0, '#7ec8ff', { seg: 12, layer: 'glass' });
      return;
    }
    case 'dining4':
    case 'dining6': {
      const big = f.kind === 'dining6';
      const tw = big ? 1.7 : 1.1, td = big ? 0.95 : 0.8;
      if (big) {
        b.box(tw, 0.03, td, 0, 0.74, 0, '#bfe3f2', { layer: 'glass' });
        b.box(0.2, 0.72, 0.6, -0.5, 0, 0, '#c9a227');
        b.box(0.2, 0.72, 0.6, 0.5, 0, 0, '#c9a227');
      } else {
        b.box(tw, 0.05, td, 0, 0.71, 0, c ?? WOOD);
        legs4(b, tw, td, 0.71, 0.06, WOOD_DARK);
      }
      for (const sx of big ? [-0.55, 0, 0.55] : [-0.28, 0.28]) {
        b.cyl(0.11, 0.09, 0.02, sx, big ? 0.77 : 0.76, -td / 4, WHITE, { seg: 12 });
        for (const side of [-1, 1]) {
          const z = side * (td / 2 + 0.25);
          const col = big ? '#f1e9da' : WOOD;
          b.box(0.42, 0.06, 0.42, sx, 0.44, z, col);
          legs4(b, 0.42, 0.42, 0.44, 0.04, big ? '#c9a227' : WOOD_DARK, 0.02);
          b.box(0.42, 0.5, 0.05, sx, 0.48, z + side * 0.19, col);
        }
      }
      return;
    }
    case 'kitchen_cab': {
      const col = c ?? '#f4f1ea';
      b.box(1.2, 0.86, 0.55, 0, 0, 0, col);
      b.box(0.01, 0.7, 0.01, 0, 0.08, 0.276, shadeHex(col, 0.75));
      b.box(1.24, 0.05, 0.58, 0, 0.86, 0, '#3a3f47');
      b.cyl(0.1, 0.08, 0.2, 0.35, 0.91, 0, '#d9a441', { seg: 10 }); // bread bin
      b.box(0.3, 0.02, 0.2, -0.3, 0.91, 0.05, WOOD_LIGHT); // chopping board
      return;
    }
    case 'bucket_bowl': {
      b.cyl(0.16, 0.12, 0.3, -0.1, 0, 0, c ?? '#2c7be5', { seg: 10 });
      b.cyl(0.14, 0.14, 0.015, -0.1, 0.27, 0, '#5fa8ff', { seg: 10 });
      b.box(0.24, 0.015, 0.02, -0.1, 0.31, 0, BLACK);
      b.cyl(0.12, 0.07, 0.08, 0.18, 0, 0.05, '#f1c40f', { seg: 10 });
      b.box(0.09, 0.035, 0.05, 0.18, 0, -0.14, '#f6f3ec');
      return;
    }
    case 'water_heater': {
      b.cyl(0.18, 0.18, 0.6, 0, 1.5, -0.01, WHITE, { seg: 12 });
      b.box(0.1, 0.1, 0.02, 0, 1.75, 0.17, '#e74c3c', { layer: 'glow' });
      b.cyl(0.015, 0.015, 0.3, -0.08, 1.2, -0.01, CHROME, { seg: 6 });
      b.cyl(0.015, 0.015, 0.3, 0.08, 1.2, -0.01, CHROME, { seg: 6 });
      return;
    }
    case 'mirror_wall':
      onWall(b, 0.6, 0.8, 1.1, WOOD_DARK, 0.03);
      onWall(b, 0.52, 0.72, 1.14, '#cfe3ef', 0.04, { layer: 'glass' });
      return;
    case 'towel_rack': {
      for (const sx of [-0.28, 0.28]) b.box(0.03, 1.0, 0.03, sx, 0, 0, CHROME);
      for (const y of [0.55, 0.85]) b.box(0.6, 0.025, 0.025, 0, y, 0, CHROME);
      b.box(0.4, 0.5, 0.04, -0.05, 0.4, 0.02, '#2c7be5');
      b.box(0.3, 0.35, 0.04, 0.1, 0.55, -0.02, '#f7d7e2');
      return;
    }
    case 'washer': {
      applianceBox(b, 0.6, 0.85, 0.6, c ?? WHITE);
      b.cyl(0.2, 0.2, 0.02, 0, 0.42, 0.3, '#9aa3ab', { rx: Math.PI / 2, seg: 16 });
      b.cyl(0.16, 0.16, 0.02, 0, 0.42, 0.31, '#7ec8ff', { rx: Math.PI / 2, seg: 16, layer: 'glass' });
      b.box(0.5, 0.08, 0.01, 0, 0.72, 0.301, '#2b2f36');
      return;
    }
    case 'gen_small': {
      const col = c ?? '#d4232b';
      b.box(0.5, 0.36, 0.34, 0, 0.04, 0, col);
      b.box(0.52, 0.04, 0.36, 0, 0.4, 0, BLACK);
      b.box(0.04, 0.12, 0.3, -0.24, 0.4, 0, BLACK); // handle frame
      b.box(0.04, 0.12, 0.3, 0.24, 0.4, 0, BLACK);
      b.box(0.5, 0.03, 0.03, 0, 0.5, 0, BLACK);
      b.cyl(0.03, 0.03, 0.12, 0.18, 0.4, -0.1, METAL_DARK, { seg: 6 });
      b.box(0.2, 0.08, 0.01, 0, 0.2, 0.171, '#f1c40f');
      return;
    }
    case 'gen_big': {
      b.box(1.8, 0.12, 0.9, 0, 0, 0, '#3a3f47');
      b.box(1.7, 1.05, 0.85, 0, 0.12, 0, c ?? '#1f6f43'); // canopy
      for (let i = 0; i < 6; i++) b.box(0.4, 0.02, 0.01, -0.5, 0.4 + i * 0.1, 0.426, '#174f31');
      b.box(0.36, 0.26, 0.01, 0.45, 0.6, 0.426, '#2b2f36');
      b.box(0.12, 0.06, 0.01, 0.45, 0.78, 0.427, '#2ecc71', { layer: 'glow' });
      b.cyl(0.05, 0.05, 0.25, 0.6, 1.17, -0.25, METAL_DARK, { seg: 8 });
      return;
    }
    case 'inverter':
    case 'inverter_small': {
      const big = f.kind === 'inverter';
      const w = big ? 0.8 : 0.5, d = big ? 0.5 : 0.4;
      b.box(w, 0.04, d, 0, 0.05, 0, METAL_DARK);
      legs4(b, w, d, 0.05, 0.04, METAL_DARK, 0.02);
      const nb = big ? 4 : 1;
      for (let i = 0; i < nb; i++) b.box(big ? 0.17 : 0.3, 0.3, d - 0.1, -w / 2 + 0.11 + i * 0.19 + (big ? 0 : 0.04), 0.09, 0, big ? '#2c3e50' : '#1b1e23');
      b.box(w * 0.7, 0.32, 0.18, 0, 0.42, -d / 2 + 0.1, '#ecf0f1'); // inverter box
      b.box(0.14, 0.06, 0.01, 0, 0.6, -d / 2 + 0.191, '#2c7be5', { layer: 'glow' });
      return;
    }
    case 'solar': {
      for (const sx of [-0.85, 0.85]) {
        b.box(0.06, 0.6, 0.06, sx, 0, 0.4, METAL);
        b.box(0.06, 1.2, 0.06, sx, 0, -0.4, METAL);
      }
      b.box(2.0, 0.05, 1.1, 0, 0.88, 0, '#1b2a4a', { rx: 0.5 });
      for (let i = -3; i <= 3; i++) b.box(0.01, 0.06, 1.05, i * 0.28, 0.9, 0, '#8fa7c9', { rx: 0.5 });
      return;
    }
    case 'water_tank': {
      for (const [sx, sz] of [[-0.45, -0.45], [0.45, -0.45], [-0.45, 0.45], [0.45, 0.45]]) b.box(0.07, 1.2, 0.07, sx, 0, sz, METAL_DARK);
      b.box(1.1, 0.06, 1.1, 0, 1.2, 0, METAL_DARK);
      b.cyl(0.52, 0.55, 1.1, 0, 1.26, 0, c ?? '#2c3e50', { seg: 14 });
      b.cyl(0.2, 0.2, 0.08, 0, 2.36, 0, '#1b2631', { seg: 10 });
      return;
    }
    case 'gate_light': {
      b.cyl(0.12, 0.15, 0.1, 0, 0, 0, '#7f8c8d', { seg: 8 });
      b.cyl(0.04, 0.05, 2.6, 0, 0.1, 0, '#2b2f36', { seg: 8 });
      b.box(0.36, 0.2, 0.1, 0, 2.6, 0.08, '#2b2f36', { rx: 0.5 });
      b.box(0.3, 0.14, 0.02, 0, 2.6, 0.14, '#fff7d6', { rx: 0.5, layer: 'glow' });
      return;
    }
    case 'car_shade': {
      for (const [sx, sz] of [[-1.3, -2.0], [1.3, -2.0], [-1.3, 2.0], [1.3, 2.0]]) b.box(0.08, 2.3, 0.08, sx, 0, sz, METAL_DARK);
      b.box(2.8, 0.06, 4.2, 0, 2.3, 0, c ?? '#2471a3', { rx: 0.05 });
      for (let i = -3; i <= 3; i++) b.box(0.03, 0.08, 4.2, i * 0.4, 2.29, 0, '#1a5276', { rx: 0.05 });
      return;
    }
    case 'plant_big': {
      b.cyl(0.24, 0.18, 0.45, 0, 0, 0, '#e9e4dc', { seg: 10 });
      b.cyl(0.03, 0.04, 1.2, 0, 0.4, 0, '#6b4f3a', { seg: 6 });
      const g = ['#2f8f4e', '#3fa45e', '#27773f'];
      for (let i = 0; i < 8; i++) {
        const a = (i / 8) * Math.PI * 2;
        b.box(0.12, 0.75, 0.02, Math.sin(a) * 0.1, 1.35, Math.cos(a) * 0.1, g[i % 3], { rx: Math.cos(a) * 1.0, rz: -Math.sin(a) * 1.0 });
      }
      return;
    }
    case 'wall_art': {
      const col = c ?? '#e67e22';
      onWall(b, 0.9, 0.62, 1.3, WOOD_DARK, 0.03);
      onWall(b, 0.82, 0.54, 1.34, col, 0.04);
      for (let i = 0; i < 4; i++) b.box(0.12, 0.12, 0.01, -0.3 + i * 0.2, 1.45 + (i % 2) * 0.15, 0.03, i % 2 ? '#1abc9c' : '#8e44ad', { ry: 0.785, noOcc: true });
      return;
    }
    case 'plaque':
      onWall(b, 0.42, 0.58, 1.3, '#8a5a2b', 0.05);
      b.box(0.12, 0.3, 0.04, 0, 1.42, 0.03, '#a0703c', { noOcc: true }); // the figure
      b.box(0.16, 0.08, 0.04, 0, 1.68, 0.03, '#a0703c', { noOcc: true });
      return;
    case 'bronze_head': {
      b.box(0.4, 0.8, 0.4, 0, 0, 0, '#2b2f36'); // plinth
      b.cyl(0.11, 0.13, 0.2, 0, 0.8, 0, '#8a5a2b', { seg: 10 }); // neck rings
      b.cyl(0.12, 0.1, 0.22, 0, 1.0, 0, '#a0703c', { seg: 10 }); // head
      b.cyl(0.05, 0.13, 0.25, 0, 1.2, -0.04, '#8a5a2b', { seg: 10, rx: -0.4 }); // Idia crown
      return;
    }
    case 'wall_clock':
      b.cyl(0.18, 0.18, 0.04, 0, 1.8, -0.01, WHITE, { rx: Math.PI / 2, seg: 16 });
      b.box(0.02, 0.12, 0.01, 0, 1.8, 0.02, BLACK, { noOcc: true });
      b.box(0.09, 0.02, 0.01, 0.04, 1.8, 0.02, BLACK, { noOcc: true });
      return;
    case 'photo_frame':
      onWall(b, 0.5, 0.4, 1.5, '#c9a227', 0.03);
      onWall(b, 0.42, 0.32, 1.54, '#7f8c8d', 0.04);
      for (let i = 0; i < 3; i++) b.cyl(0.04, 0.04, 0.12, -0.12 + i * 0.12, 1.56, 0.02, ['#5b3a24', '#3b2a20', '#6b4f3a'][i], { seg: 6 });
      return;
    case 'aquarium': {
      b.box(1.0, 0.75, 0.42, 0, 0, 0, '#2b2f36');
      b.box(0.96, 0.5, 0.38, 0, 0.75, 0, '#7ec8ff', { layer: 'glass' });
      b.box(1.0, 0.05, 0.42, 0, 1.25, 0, '#2b2f36');
      b.box(0.08, 0.04, 0.02, -0.2, 1.0, 0.19, '#f39c12', { noOcc: true });
      b.box(0.08, 0.04, 0.02, 0.15, 0.9, 0.19, '#e74c3c', { noOcc: true });
      return;
    }
    case 'vase': {
      b.cyl(0.08, 0.12, 0.35, 0, 0, 0, '#2d8f6f', { seg: 10 });
      const fl = ['#e84393', '#f1c40f', '#e74c3c'];
      for (let i = 0; i < 5; i++) {
        const a = (i / 5) * Math.PI * 2;
        b.box(0.015, 0.3, 0.015, Math.cos(a) * 0.03, 0.35, Math.sin(a) * 0.03, '#27ae60', { rx: Math.sin(a) * 0.3, rz: -Math.cos(a) * 0.3 });
        b.box(0.08, 0.08, 0.08, Math.cos(a) * 0.1, 0.64, Math.sin(a) * 0.1, fl[i % 3]);
      }
      return;
    }
    case 'stairs': {
      // H1 duplex staircase: tiled treads climbing towards the back wall, a dark wood stringer and a
      // steel + wood handrail on the open (west) side. The upper floor itself is cut away.
      const n = 10;
      const run = 2.6 / n;
      const rise = Math.min(0.29, (wallH - 0.1) / n);
      for (let i = 0; i < n; i++) {
        const z = 1.3 - (i + 0.5) * run;
        b.box(1.0, rise * (i + 1) - 0.03, run, 0, 0, z, '#d9d3c7', { mat: 'concrete' });
        b.box(1.02, 0.03, run + 0.02, 0, rise * (i + 1) - 0.03, z, '#efe9de', { mat: 'tiles' });
      }
      b.box(0.06, rise * n, 2.6, 0.5, 0, 0, WOOD_DARK, { mat: 'wood' });
      for (let i = 0; i <= n; i += 2) {
        const z = 1.3 - (i + 0.5) * run;
        b.box(0.03, 0.9, 0.03, -0.47, rise * Math.min(n, i + 1), z, CHROME, { mat: 'metal' });
      }
      b.box(0.06, 0.05, 2.75, -0.47, rise * n * 0.5 + 0.92, 0, WOOD_DARK, { mat: 'wood', rx: Math.atan2(rise * n, 2.6) });
      return;
    }
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
