// L2 interior geometry: the shell (floor, walls, entrance) and one low-poly prop per zone, all boxes and
// cylinders merged by the home's HomeBuilder into 4 meshes (solid / glow / glass / screen), so a whole
// interior costs ~4 draw calls whatever the number of zones. Local prop frame: origin = zone centre on
// the floor, +z = the zone's front (where the Sim stands), lw × ld = its footprint in that frame.
import type { BufferGeometry } from 'three';
import type { PlaceZone } from '../../../api/places';
import { HomeBuilder, type Layer } from '../../home3d/engine/build';
import type { Room } from '../model';
import type { Mat } from '../../feel/atlas';
import { buildClutter, buildOutside, buildPools, seeded, type ClutterKind, type Rect } from '../../feel/kit';
import { rigFor, type Rig } from '../../feel/rigs';

type B = HomeBuilder;

const WOOD = '#8a5a33';
const WOOD_D = '#5b3a24';
const WOOD_L = '#c49a6c';
const METAL = '#9aa3ab';
const METAL_D = '#59616b';
const WHITE = '#f4f2ee';
const BLACK = '#23262c';
const ZINC = '#a7b0b6';
const LEAF = '#3f8a3a';
const CORAL = '#d2342a';
const GOLD = '#d9a441';
const BRONZE = '#b0793a';
const FABRICS = ['#d2342a', '#1f7a3f', '#2f6fb3', '#d9a441', '#6d4aa0', '#e07a2e', '#0b625a', '#c74b8a'];
const FRUIT = ['#e0473a', '#f2a516', '#7dbb45', '#f3cf5e', '#b0202d'];

export interface BuiltPlace {
  layers: Record<Layer, BufferGeometry | null>;
  tris: number;
  /** F1: light rig for this place type, ceiling fan spot, steam spots (layout space). */
  rig: Rig;
  fan: [number, number, number] | null;
  steam: [number, number, number][];
}

/** F1: atlas surfaces per place type: [floor, walls]. */
const SURF: Record<string, [Mat, Mat]> = {
  club: ['tiles', 'paint'], lounge: ['tiles', 'paint'], buka: ['concrete', 'plaster'], restaurant: ['tiles', 'plaster'],
  bank: ['tiles', 'paint'], hospital: ['tiles', 'paint'], police: ['concrete', 'plaster'], campus: ['concrete', 'plaster'],
  museum: ['wood', 'paint'], office: ['carpet', 'paint'], tech: ['carpet', 'paint'], cyber: ['tiles', 'plaster'], shrine: ['ground', 'plaster'],
  salon: ['tiles', 'paint'], workshop: ['concrete', 'block'], airport: ['tiles', 'paint'], mall: ['tiles', 'paint'],
  cinema: ['carpet', 'paint'], hotel: ['tiles', 'paint'], car_dealer: ['tiles', 'paint'],
  market: ['ground', 'block'], motorpark: ['asphalt', 'block'], street: ['asphalt', 'block'], pos: ['concrete', 'block'],
  zoo: ['grass', 'block'], stadium: ['concrete', 'paint'], monument: ['tiles', 'block'], farm: ['ground', 'block'], palace: ['ground', 'plaster'],
};

const CLUTTER: Record<string, ClutterKind> = {
  club: 'club', lounge: 'club', buka: 'buka', restaurant: 'buka', bank: 'office', office: 'office', tech: 'office', cyber: 'office',
  police: 'office', airport: 'hall', hospital: 'clinic', campus: 'hall', market: 'market', motorpark: 'market', street: 'market', pos: 'market',
};

const WARM_PROPS = new Set(['tables', 'counter', 'bar', 'food_stall', 'grill', 'kiosk', 'checkout', 'desk', 'salon_chairs', 'stall']);
const PARTY_PROPS = new Set(['dance_floor', 'bar', 'dj_booth', 'vip', 'stage']);
const STEAM_PROPS = new Set(['food_stall', 'grill', 'counter', 'kiosk']);

function stool(b: B, x: number, z: number, c = WOOD) {
  b.cyl(0.16, 0.16, 0.06, x, 0.42, z, c, { seg: 8 });
  b.cyl(0.03, 0.03, 0.42, x, 0, z, METAL_D, { seg: 5 });
}
function chair(b: B, x: number, z: number, ry: number, c = '#2f6fb3') {
  b.box(0.42, 0.06, 0.42, x, 0.42, z, c, { ry });
  b.box(0.42, 0.45, 0.05, x - Math.sin(ry) * 0.19, 0.45, z - Math.cos(ry) * 0.19, c, { ry });
  b.box(0.36, 0.42, 0.36, x, 0, z, METAL_D, { ry, layer: 'solid' });
}
function table(b: B, x: number, z: number, w = 0.9, d = 0.9, c = WOOD_L) {
  b.box(w, 0.05, d, x, 0.72, z, c);
  b.cyl(0.05, 0.08, 0.72, x, 0, z, METAL_D, { seg: 6 });
}
function plant(b: B, x: number, z: number, s = 1) {
  b.cyl(0.18 * s, 0.14 * s, 0.35 * s, x, 0, z, '#b5552b', { seg: 8 });
  b.cyl(0.02, 0.4 * s, 0.9 * s, x, 0.35 * s, z, LEAF, { seg: 6 });
}
function tree(b: B, x: number, z: number, s = 1) {
  b.cyl(0.1 * s, 0.14 * s, 1.4 * s, x, 0, z, WOOD_D, { seg: 6 });
  b.cyl(0.05, 0.9 * s, 1.1 * s, x, 1.2 * s, z, '#4f9a3f', { seg: 7 });
  b.cyl(0.05, 0.7 * s, 0.9 * s, x, 1.8 * s, z, '#5aa84a', { seg: 7 });
}
function person(b: B, x: number, z: number, c: string, seated = false) {
  // a tiny static figure (posters, stands crowd, bus passengers)
  const y = seated ? 0.4 : 0;
  b.box(0.3, 0.55, 0.2, x, y + (seated ? 0 : 0.75), z, c);
  b.cyl(0.11, 0.11, 0.22, x, y + (seated ? 0.55 : 1.3), z, '#5a3a26', { seg: 6 });
  if (!seated) b.box(0.26, 0.75, 0.16, x, 0, z, '#2a2d3a');
}
function car(b: B, x: number, z: number, ry: number, c: string, s = 1) {
  b.setFrame(x, 0, z, ry);
  b.box(1.8 * s, 0.55 * s, 4.0 * s, 0, 0.25 * s, 0, c);
  b.box(1.6 * s, 0.5 * s, 2.0 * s, 0, 0.8 * s, -0.2 * s, c);
  b.box(1.62 * s, 0.38 * s, 1.85 * s, 0, 0.85 * s, -0.2 * s, '#bfe3f7', { layer: 'glass' });
  for (const sx of [-1, 1]) for (const sz of [-1, 1]) b.cyl(0.33 * s, 0.33 * s, 0.22 * s, sx * 0.86 * s, 0.33 * s, sz * 1.25 * s, BLACK, { seg: 10, rz: Math.PI / 2 });
  b.box(0.36 * s, 0.12 * s, 0.05, 0.6 * s, 0.45 * s, 2.0 * s, '#fff6c8', { layer: 'glow' });
  b.box(0.36 * s, 0.12 * s, 0.05, -0.6 * s, 0.45 * s, 2.0 * s, '#fff6c8', { layer: 'glow' });
}

/** One zone's prop. `lw`/`ld` = footprint in the zone's own frame (front = +z). */
function buildProp(b: B, z: PlaceZone, room: Room, seed: number) {
  const odd = ((z.rot % 4) + 4) % 2 === 1;
  const lw = odd ? z.d : z.w;
  const ld = odd ? z.w : z.d;
  const yaw = (z.rot * Math.PI) / 2;
  b.setFrame(z.x, 0, z.z, yaw);
  const k = room.kit;
  const hw = lw / 2;
  const hd = ld / 2;
  const pick = (arr: string[], i: number) => arr[(seed + i) % arr.length];
  switch (z.prop) {
    case 'stall':
    case 'food_stall': {
      // wooden table under a striped umbrella / zinc roof, goods on top
      b.box(lw, 0.8, ld * 0.6, 0, 0, -ld * 0.1, WOOD);
      for (const sx of [-1, 1]) for (const sz of [-1, 1]) b.box(0.08, 2.1, 0.08, sx * (hw - 0.1), 0, sz * (hd - 0.15), WOOD_D);
      const n = Math.max(3, Math.round(lw / 0.5));
      for (let i = 0; i < n; i++) b.box(lw / n, 0.06, ld + 0.3, -hw + (i + 0.5) * (lw / n), 2.1, 0, i % 2 ? WHITE : pick(FABRICS, 0), { rx: -0.12 });
      if (z.prop === 'food_stall') {
        b.cyl(0.32, 0.26, 0.4, -hw * 0.45, 0.8, -ld * 0.1, METAL, { seg: 10 });
        b.cyl(0.3, 0.24, 0.36, hw * 0.4, 0.8, -ld * 0.1, '#c74b3c', { seg: 10 });
        b.box(0.5, 0.06, 0.4, 0, 0.8, 0.05, WHITE);
      } else {
        for (let i = 0; i < 9; i++) b.cyl(0.13, 0.15, 0.18, -hw + 0.3 + (i % 5) * ((lw - 0.6) / 4), 0.8, -ld * 0.25 + Math.floor(i / 5) * 0.36, pick(FRUIT, i), { seg: 7 });
      }
      stool(b, hw * 0.6, -hd + 0.15, WOOD_D);
      return;
    }
    case 'crates': {
      for (let i = 0; i < 6; i++) b.box(0.6, 0.45, 0.45, -hw + 0.4 + (i % 3) * 0.7, Math.floor(i / 3) * 0.46, -0.2 + (i % 2) * 0.1, i % 2 ? WOOD : WOOD_L);
      b.box(0.9, 0.5, 0.6, hw - 0.6, 0, 0.1, '#c9b48a');
      b.box(0.8, 0.45, 0.55, hw - 0.6, 0.5, 0.1, '#e0c99a');
      return;
    }
    case 'restroom': {
      // a small cubicle: thin side + back panels, a coloured half-open door, the blue sign on top
      const wall = k.kind === 'outdoor' ? ZINC : '#e3e8ec';
      const h = 1.4;
      b.box(lw, 0.05, ld, 0, 0, 0, k.kind === 'outdoor' ? '#9c9790' : '#cfd8de');
      b.box(lw, h, 0.05, 0, 0, -hd + 0.025, wall);
      b.box(0.05, h, ld, -hw + 0.025, 0, 0, wall);
      b.box(0.05, h, ld, hw - 0.025, 0, 0, wall);
      b.box(lw * 0.5, h * 0.92, 0.04, -hw * 0.25, 0.05, hd - 0.02, k.kind === 'outdoor' ? METAL_D : '#2f7fd6', { ry: 0.5 });
      b.cyl(0.18, 0.2, 0.42, 0, 0, -hd + 0.3, WHITE, { seg: 10 }); // the WC
      b.box(0.36, 0.22, 0.04, 0, h + 0.02, hd - 0.02, '#2f7fd6', { layer: 'glow' });
      return;
    }
    case 'counter':
    case 'checkout':
    case 'bank_counter': {
      b.box(lw, 1.0, 0.7, 0, 0, -hd + 0.4, z.prop === 'bank_counter' ? '#f2efe8' : k.trim);
      b.box(lw + 0.06, 0.06, 0.8, 0, 1.0, -hd + 0.4, z.prop === 'bank_counter' ? '#13512a' : WOOD_L);
      if (z.prop === 'bank_counter') {
        b.box(lw, 0.9, 0.03, 0, 1.06, -hd + 0.45, '#cfe8f2', { layer: 'glass' });
        for (let i = 0; i < 3; i++) person(b, -hw + (i + 0.5) * (lw / 3), -hd - 0.15, '#13512a');
      } else if (z.prop === 'checkout') {
        for (let i = 0; i < 2; i++) b.box(0.4, 0.3, 0.3, -hw * 0.5 + i * hw, 1.06, -hd + 0.4, METAL_D);
      } else {
        for (let i = 0; i < 4; i++) b.cyl(0.18, 0.16, 0.22, -hw + 0.5 + i * ((lw - 1) / 3), 1.06, -hd + 0.35, i % 2 ? '#c74b3c' : METAL, { seg: 9 });
        person(b, 0, -hd - 0.1, CORAL);
      }
      return;
    }
    case 'tables':
    case 'vip': {
      const nx = Math.max(1, Math.round(lw / 1.8));
      const nz = Math.max(1, Math.round(ld / 1.6));
      for (let i = 0; i < nx; i++)
        for (let j = 0; j < nz; j++) {
          const x = -hw + (i + 0.5) * (lw / nx);
          const zz = -hd + (j + 0.5) * (ld / nz);
          if (z.prop === 'vip') {
            // velvet booth around a low table, bottle with a sparkler glow
            b.box(1.4, 0.45, 0.5, x, 0, zz - 0.5, '#5a1f3a');
            b.box(1.4, 0.6, 0.15, x, 0.45, zz - 0.72, '#5a1f3a');
            b.box(0.8, 0.4, 0.5, x, 0, zz + 0.1, BLACK);
            b.cyl(0.05, 0.06, 0.32, x, 0.4, zz + 0.1, '#1f5a2a', { seg: 6 });
            b.box(0.05, 0.12, 0.05, x, 0.72, zz + 0.1, '#ffd27a', { layer: 'glow' });
          } else {
            table(b, x, zz);
            chair(b, x - 0.55, zz, Math.PI / 2, pick(FABRICS, i + j));
            chair(b, x + 0.55, zz, -Math.PI / 2, pick(FABRICS, i + j + 1));
          }
        }
      if (z.prop === 'vip') {
        // rope + gold posts at the front
        for (const sx of [-1, 1]) b.cyl(0.04, 0.05, 0.9, sx * (hw - 0.1), 0, hd - 0.05, GOLD, { seg: 6 });
        b.box(lw - 0.2, 0.04, 0.04, 0, 0.8, hd - 0.05, '#9c1f19');
      }
      return;
    }
    case 'tv_screen': {
      b.box(lw * 0.9, 0.1, 0.4, 0, 0, -hd + 0.3, BLACK);
      b.box(0.1, 1.0, 0.1, 0, 0.1, -hd + 0.3, METAL_D);
      b.box(lw * 0.85, lw * 0.5, 0.08, 0, 1.0, -hd + 0.3, BLACK);
      b.box(lw * 0.8, lw * 0.45, 0.02, 0, 1.03, -hd + 0.35, '#7ec8ff', { layer: 'screen' });
      for (let i = 0; i < 3; i++) b.box(0.6, 0.42, 0.35, -hw + 0.4 + i * ((lw - 0.8) / 2), 0, hd - 0.3, pick(FABRICS, i)); // benches
      return;
    }
    case 'bar': {
      b.box(lw, 1.05, 0.6, 0, 0, -hd + 0.5, k.party ? '#1d1830' : WOOD);
      b.box(lw + 0.1, 0.06, 0.7, 0, 1.05, -hd + 0.5, k.party ? GOLD : WOOD_L);
      if (k.party) b.box(lw, 0.05, 0.04, 0, 0.95, -hd + 0.82, '#ff4fa3', { layer: 'glow' });
      // back shelf with bottles
      b.box(lw, 1.6, 0.25, 0, 0.3, -hd + 0.05, k.party ? '#2a2240' : WOOD_D);
      for (let i = 0; i < Math.round(lw * 3); i++) b.cyl(0.05, 0.06, 0.3, -hw + 0.15 + i * 0.33, 1.3 + (i % 2) * 0.45, -hd + 0.08, pick(['#1f5a2a', '#7a4f00', '#c8ced4', '#9c1f19'], i), { seg: 6, layer: k.party ? 'glow' : 'solid' });
      for (let i = 0; i < Math.round(lw / 0.8); i++) stool(b, -hw + 0.4 + i * 0.8, hd - 0.15, k.party ? GOLD : WOOD_D);
      person(b, 0, -hd + 0.25, k.party ? BLACK : CORAL);
      return;
    }
    case 'dance_floor': {
      // light-up tiles (screen layer = party colours at night)
      const n = Math.max(2, Math.round(lw / 0.8));
      const m = Math.max(2, Math.round(ld / 0.8));
      for (let i = 0; i < n; i++)
        for (let j = 0; j < m; j++)
          b.box(lw / n - 0.04, 0.03, ld / m - 0.04, -hw + (i + 0.5) * (lw / n), 0.01, -hd + (j + 0.5) * (ld / m), (i + j) % 2 ? '#f3d28a' : '#ff4fa3', { layer: (i + j) % 2 ? 'glow' : 'screen' });
      // disco ball + speakers
      b.cyl(0.02, 0.02, 0.6, 0, 2.6, 0, METAL_D, { seg: 4 });
      b.cyl(0.25, 0.25, 0.4, 0, 2.3, 0, '#e6eaf0', { seg: 10, layer: 'glow' });
      return;
    }
    case 'dj_booth': {
      b.box(lw, 1.0, ld * 0.7, 0, 0, -hd * 0.3, '#151832');
      b.box(lw, 0.06, 0.04, 0, 0.92, -hd * 0.3 + ld * 0.35, '#7ee0c5', { layer: 'glow' });
      b.box(0.5, 0.06, 0.35, -0.35, 1.0, -hd * 0.3, BLACK);
      b.box(0.5, 0.06, 0.35, 0.35, 1.0, -hd * 0.3, BLACK);
      for (const sx of [-1, 1]) {
        b.box(0.6, 1.7, 0.55, sx * (hw + 0.45), 0, -hd * 0.2, BLACK);
        b.cyl(0.2, 0.2, 0.04, sx * (hw + 0.45), 0.9, -hd * 0.2 + 0.28, METAL_D, { seg: 10, rx: Math.PI / 2 });
        b.cyl(0.12, 0.12, 0.04, sx * (hw + 0.45), 1.35, -hd * 0.2 + 0.28, METAL_D, { seg: 10, rx: Math.PI / 2 });
      }
      person(b, 0, -hd * 0.3 - 0.25, '#6d4aa0');
      return;
    }
    case 'atm': {
      for (let i = 0; i < Math.max(1, Math.round(lw / 0.9)); i++) {
        const x = -hw + 0.45 + i * 0.9;
        b.box(0.75, 1.6, 0.6, x, 0, -hd + 0.35, '#2c3540');
        b.box(0.5, 0.35, 0.02, x, 1.05, -hd + 0.66, '#7ee0c5', { layer: 'screen' });
        b.box(0.75, 0.15, 0.62, x, 1.6, -hd + 0.35, '#13512a');
      }
      return;
    }
    case 'seats': {
      const rows = Math.max(1, Math.round(ld / 1.0));
      for (let r = 0; r < rows; r++) {
        const zz = -hd + 0.4 + r * 1.0;
        b.box(lw, 0.05, 0.08, 0, 0.3, zz, METAL_D);
        for (let i = 0; i < Math.round(lw / 0.55); i++) chair(b, -hw + 0.3 + i * 0.55, zz, Math.PI, pick(['#2f6fb3', '#13512a', '#6d4aa0'], r));
      }
      return;
    }
    case 'shelves':
    case 'aisles': {
      const rows = z.prop === 'aisles' ? Math.max(2, Math.round(lw / 1.6)) : 1;
      for (let r = 0; r < rows; r++) {
        const x = z.prop === 'aisles' ? -hw + (r + 0.5) * (lw / rows) : 0;
        const w = z.prop === 'aisles' ? 0.6 : lw;
        const d = z.prop === 'aisles' ? ld * 0.85 : 0.5;
        const zz = z.prop === 'aisles' ? 0 : -hd + 0.3;
        b.box(w, 1.8, d, x, 0, zz, WHITE);
        for (let s = 0; s < 4; s++) {
          b.box(w + 0.04, 0.03, d + 0.04, x, 0.25 + s * 0.45, zz, METAL);
          const n = Math.round((z.prop === 'aisles' ? d : w) / 0.3);
          for (let i = 0; i < n; i++) {
            const t = -0.5 + (i + 0.5) / n;
            if (z.prop === 'aisles') b.box(w + 0.08, 0.28, 0.22, x, 0.28 + s * 0.45, zz + t * d, pick(FRUIT.concat(FABRICS), i + s + r));
            else b.box(0.22, 0.28, d * 0.8, x + t * w, 0.28 + s * 0.45, zz, pick(FRUIT.concat(['#2f7fd6', WHITE]), i + s));
          }
        }
      }
      if (z.prop === 'aisles') b.box(lw, 0.3, 0.05, 0, 2.3, -hd, CORAL, { layer: 'glow' });
      return;
    }
    case 'beds':
    case 'bed_lux': {
      const n = Math.max(1, Math.round(lw / 1.4));
      for (let i = 0; i < n; i++) {
        const x = -hw + (i + 0.5) * (lw / n);
        const lux = z.prop === 'bed_lux';
        b.box(lux ? 1.6 : 0.95, 0.45, 2.0, x, 0, 0, lux ? WOOD_D : METAL);
        b.box(lux ? 1.5 : 0.9, 0.15, 1.9, x, 0.45, 0, WHITE);
        b.box(lux ? 1.5 : 0.9, 0.06, 1.1, x, 0.6, 0.35, lux ? '#d9a441' : '#7fb4d9');
        b.box(lux ? 1.6 : 0.95, lux ? 1.2 : 0.8, 0.08, x, 0, -1.0, lux ? WOOD_D : METAL_D);
        if (!lux) b.cyl(0.02, 0.02, 1.6, x + 0.6, 0, -0.8, METAL, { seg: 4 });
      }
      return;
    }
    case 'desk': {
      b.box(Math.min(lw, 1.6), 0.75, 0.7, 0, 0, -0.1, WOOD);
      b.box(0.5, 0.35, 0.04, 0, 0.75, -0.3, BLACK);
      b.box(0.46, 0.3, 0.02, 0, 0.78, -0.27, '#7ec8ff', { layer: 'screen' });
      chair(b, 0, -0.75, 0, BLACK);
      b.box(0.5, 1.2, 0.4, hw - 0.3, 0, -hd + 0.25, '#7b8a99');
      return;
    }
    case 'lecture':
    case 'desks': {
      const nx = Math.max(1, Math.round(lw / 1.2));
      const nz = Math.max(1, Math.round(ld / 1.1));
      for (let i = 0; i < nx; i++)
        for (let j = 0; j < nz; j++) {
          const x = -hw + (i + 0.5) * (lw / nx);
          const zz = -hd + (j + 0.5) * (ld / nz);
          b.box(0.9, 0.05, 0.5, x, 0.72, zz, z.prop === 'desks' ? WHITE : WOOD_L);
          b.box(0.85, 0.7, 0.05, x, 0, zz - 0.22, METAL_D);
          if (z.prop === 'desks') {
            b.box(0.4, 0.28, 0.03, x, 0.77, zz - 0.12, BLACK);
            b.box(0.36, 0.24, 0.02, x, 0.79, zz - 0.1, '#9ad3ff', { layer: 'screen' });
          }
          chair(b, x, zz + 0.4, Math.PI, z.prop === 'desks' ? '#e07a2e' : WOOD);
        }
      if (z.prop === 'lecture') {
        b.box(Math.min(lw, 3.5), 1.2, 0.06, 0, 0.9, -hd - 0.5, '#1f3a2a');
        b.box(0.8, 1.0, 0.5, hw - 0.6, 0, -hd - 0.4, WOOD);
      }
      return;
    }
    case 'trees': {
      tree(b, -hw * 0.6, -hd * 0.5, 1.1);
      tree(b, hw * 0.65, -hd * 0.3, 0.95);
      b.box(1.6, 0.03, 1.2, 0, 0.01, hd * 0.2, pick(FABRICS, 2)); // mat
      b.box(0.4, 0.25, 0.3, 0.3, 0.03, hd * 0.2, '#c49a6c'); // basket
      return;
    }
    case 'bus': {
      // a yellow danfo-style bus + a second one behind
      b.setFrame(z.x, 0, z.z, yaw + Math.PI / 2);
      for (let i = 0; i < Math.max(1, Math.round(lw / 3)); i++) {
        const off = (i - (Math.round(lw / 3) - 1) / 2) * 1.9;
        b.box(1.7, 1.4, Math.min(4, ld * 2), off, 0.3, 0, i % 2 ? '#1f7a3f' : '#f2c230');
        b.box(1.72, 0.45, Math.min(3.6, ld * 1.8), off, 1.1, 0.1, '#bfe3f7', { layer: 'glass' });
        for (const sz of [-1, 1]) for (const sx of [-1, 1]) b.cyl(0.32, 0.32, 0.2, off + sx * 0.8, 0.32, sz * 1.3, BLACK, { seg: 10, rz: Math.PI / 2 });
        b.box(1.0, 0.1, 1.4, off, 1.75, 0, '#4a3a2a'); // luggage on the roof
      }
      return;
    }
    case 'keke': {
      for (let i = 0; i < Math.max(1, Math.round(lw / 1.2)); i++) {
        const x = -hw + 0.6 + i * 1.2;
        b.box(0.95, 0.9, 1.6, x, 0.25, 0, '#f2c230');
        b.box(1.0, 0.08, 1.7, x, 1.5, 0, '#1f7a3f');
        for (const sx of [-1, 1]) b.box(0.05, 0.4, 0.05, x + sx * 0.45, 1.15, 0.6, METAL_D);
        b.cyl(0.24, 0.24, 0.12, x, 0.24, 0.8, BLACK, { seg: 9, rz: Math.PI / 2 });
        for (const sx of [-1, 1]) b.cyl(0.24, 0.24, 0.12, x + sx * 0.45, 0.24, -0.55, BLACK, { seg: 9, rz: Math.PI / 2 });
      }
      return;
    }
    case 'grill': {
      b.box(lw * 0.7, 0.85, 0.5, 0, 0, -0.1, METAL_D);
      b.box(lw * 0.7, 0.04, 0.5, 0, 0.85, -0.1, '#ff7a2e', { layer: 'glow' });
      for (let i = 0; i < 6; i++) b.box(0.03, 0.03, 0.4, -lw * 0.3 + i * (lw * 0.12), 0.9, -0.1, '#7a3a1a');
      person(b, 0, -0.6, '#f3f0e8');
      b.cyl(0.02, 0.02, 2, hw - 0.1, 0, -0.4, WOOD_D, { seg: 4 });
      b.box(0.3, 0.3, 0.3, hw - 0.1, 2, -0.4, '#ffd27a', { layer: 'glow' }); // bulb
      return;
    }
    case 'kiosk': {
      b.box(lw * 0.85, 2.0, ld * 0.7, 0, 0, -0.1, k.kind === 'outdoor' ? '#2f6fb3' : WHITE);
      b.box(lw * 0.85 + 0.2, 0.08, ld * 0.7 + 0.5, 0, 2.0, 0.05, CORAL);
      b.box(lw * 0.6, 0.7, 0.03, 0, 0.95, ld * 0.25 + 0.01, '#3a3f6e');
      b.box(lw * 0.85, 0.06, 0.35, 0, 0.95, ld * 0.25 + 0.15, WOOD_L);
      b.box(lw * 0.6, 0.25, 0.02, 0, 1.7, ld * 0.25 + 0.02, GOLD, { layer: 'glow' });
      return;
    }
    case 'bench': {
      b.box(lw * 0.9, 0.06, 0.45, 0, 0.42, 0, WOOD);
      b.box(lw * 0.9, 0.4, 0.06, 0, 0.5, -0.2, WOOD);
      for (const sx of [-1, 1]) b.box(0.06, 0.42, 0.4, sx * lw * 0.42, 0, 0, METAL_D);
      if (k.kind === 'outdoor') tree(b, -hw - 0.3, -hd - 0.2, 0.9);
      return;
    }
    case 'board': {
      b.box(lw, 1.2, 0.06, 0, 0.6, 0, '#c49a6c');
      for (let i = 0; i < 6; i++) b.box(0.3, 0.38, 0.02, -hw + 0.3 + (i % 3) * (lw / 3), 0.75 + Math.floor(i / 3) * 0.5, 0.04, WHITE);
      return;
    }
    case 'gate': {
      for (const sx of [-1, 1]) b.box(0.6, 2.4, 0.6, sx * (hw - 0.3), 0, 0, '#b5552b');
      b.box(lw, 0.4, 0.7, 0, 2.4, 0, '#7c3216');
      b.box(lw - 1.3, 0.12, 0.08, 0, 2.2, 0.3, GOLD);
      b.box(0.5, 0.5, 0.06, 0, 2.5, 0.36, BRONZE);
      return;
    }
    case 'courtyard': {
      b.box(lw, 0.02, ld, 0, 0.005, 0, k.kind === 'outdoor' ? '#d8b98f' : '#b78a5c');
      for (const sx of [-1, 1]) plant(b, sx * (hw - 0.3), -hd + 0.3, 1.1);
      if (room.kit.signBg === '#7c3216') {
        // palace: a respectful row of red-capped chiefs' stools
        for (let i = 0; i < 4; i++) stool(b, -1.2 + i * 0.8, -hd + 0.6, CORAL);
      }
      return;
    }
    case 'display':
    case 'pedestals': {
      if (z.prop === 'display') {
        b.box(lw, 0.9, ld * 0.6, 0, 0, -hd * 0.3, WOOD_D);
        b.box(lw, 0.6, ld * 0.6, 0, 0.9, -hd * 0.3, '#dbeef6', { layer: 'glass' });
        for (let i = 0; i < Math.round(lw / 0.6); i++) b.cyl(0.1, 0.14, 0.38, -hw + 0.3 + i * 0.6, 0.92, -hd * 0.3, BRONZE, { seg: 8 });
      } else {
        for (let i = 0; i < 3; i++) {
          const x = -hw + (i + 0.5) * (lw / 3);
          b.box(0.5, 1.0, 0.5, x, 0, 0, WHITE);
          b.cyl(0.14, 0.18, 0.42, x, 1.0, 0, BRONZE, { seg: 8 });
          b.cyl(0.18, 0.1, 0.12, x, 1.4, 0, '#9c6a2e', { seg: 8 });
        }
      }
      return;
    }
    case 'stage': {
      b.box(lw, 0.5, ld, 0, 0, 0, '#1d1f2e');
      b.box(lw * 0.8, lw * 0.35, 0.08, 0, 0.9, -hd + 0.1, '#2f4fd6', { layer: 'screen' });
      b.cyl(0.02, 0.02, 1.1, 0, 0.5, 0.2, METAL_D, { seg: 4 });
      b.box(0.5, 1.0, 0.4, hw - 0.4, 0.5, 0.2, '#c8ced4');
      return;
    }
    case 'altar': {
      b.box(lw * 0.8, 0.7, ld * 0.6, 0, 0, -hd * 0.2, '#7a2a1a');
      b.box(lw * 0.85, 0.06, ld * 0.65, 0, 0.7, -hd * 0.2, WHITE);
      for (let i = 0; i < 5; i++) b.cyl(0.04, 0.04, 0.2, -0.6 + i * 0.3, 0.76, -hd * 0.2, '#f3d28a', { seg: 5 });
      for (let i = 0; i < 5; i++) b.box(0.04, 0.06, 0.04, -0.6 + i * 0.3, 0.98, -hd * 0.2, '#ffb347', { layer: 'glow' });
      b.cyl(0.18, 0.22, 0.5, -hw * 0.7, 0, -hd * 0.6, '#5a2a1a', { seg: 8 });
      b.box(lw, 1.6, 0.08, 0, 0.5, -hd + 0.05, '#fbf3e4');
      return;
    }
    case 'salon_chairs': {
      const n = Math.max(1, Math.round(lw / 1.4));
      for (let i = 0; i < n; i++) {
        const x = -hw + (i + 0.5) * (lw / n);
        b.box(0.6, 0.5, 0.6, x, 0, 0, BLACK);
        b.box(0.62, 0.7, 0.12, x, 0.5, -0.25, '#a02c68');
        b.box(0.8, 1.0, 0.04, x, 0.9, -hd + 0.02, '#cfe8f2', { layer: 'glass' });
      }
      return;
    }
    case 'furnace': {
      b.cyl(0.6, 0.75, 0.9, 0, 0, -0.2, '#6a4a3a', { seg: 10 });
      b.cyl(0.4, 0.4, 0.05, 0, 0.9, -0.2, '#ff7a2e', { seg: 10, layer: 'glow' });
      b.box(0.6, 0.06, 0.4, hw - 0.4, 0.75, 0.3, METAL_D);
      for (let i = 0; i < 3; i++) b.cyl(0.08, 0.11, 0.3, hw - 0.6 + i * 0.2, 0.81, 0.3, BRONZE, { seg: 7 });
      person(b, -hw + 0.4, 0.2, '#7a4e36');
      return;
    }
    case 'crops': {
      for (let r = 0; r < Math.round(ld / 0.8); r++)
        for (let i = 0; i < Math.round(lw / 0.6); i++) b.cyl(0.02, 0.22, 0.65, -hw + 0.3 + i * 0.6, 0, -hd + 0.4 + r * 0.8, i % 2 ? LEAF : '#5aa84a', { seg: 5 });
      return;
    }
    case 'shed': {
      b.box(lw * 0.9, 1.8, ld * 0.9, 0, 0, 0, WOOD);
      b.box(lw, 0.1, ld + 0.2, 0, 1.9, 0, ZINC, { rx: 0.15 });
      b.box(0.7, 1.4, 0.04, 0, 0, ld * 0.45 + 0.01, WOOD_D);
      return;
    }
    case 'cinema_door': {
      b.box(lw, 2.4, 0.3, 0, 0, -hd + 0.15, '#151832');
      b.box(lw * 0.5, 2.0, 0.04, 0, 0, -hd + 0.31, '#5a1f3a');
      b.box(lw * 0.9, 0.35, 0.05, 0, 2.0, -hd + 0.33, GOLD, { layer: 'glow' });
      for (const sx of [-1, 1]) b.box(0.6, 0.9, 0.04, sx * (hw - 0.4), 0.8, -hd + 0.32, pick(FABRICS, sx > 0 ? 1 : 4), { layer: 'glow' }); // posters
      return;
    }
    case 'planters': {
      for (let i = 0; i < Math.max(2, Math.round(lw / 1.4)); i++) {
        const x = -hw + 0.5 + i * 1.4;
        b.box(0.8, 0.45, 0.6, x, 0, 0, '#c8ced4');
        b.cyl(0.05, 0.45, 0.8, x, 0.45, 0, LEAF, { seg: 6 });
      }
      return;
    }
    case 'cinema_hall': {
      // big screen at the back, rows of red seats rising towards the front
      b.box(lw * 0.95, lw * 0.36, 0.08, 0, 0.8, -hd - 0.4, '#e9f1ff', { layer: 'screen' });
      b.box(lw, 0.1, 0.3, 0, 0.7, -hd - 0.4, BLACK);
      const rows = Math.max(2, Math.round(ld / 0.9));
      for (let r = 0; r < rows; r++) {
        const zz = -hd + 0.6 + r * 0.9;
        const y = r * 0.12;
        b.box(lw, y + 0.02, 0.9, 0, 0, zz, '#2a2230');
        for (let i = 0; i < Math.round(lw / 0.6); i++) {
          const x = -hw + 0.3 + i * 0.6;
          b.box(0.5, 0.42, 0.45, x, y, zz, '#9c1f19');
          b.box(0.5, 0.5, 0.1, x, y + 0.42, zz + 0.2, '#b0202d');
        }
      }
      return;
    }
    case 'arcade': {
      for (let i = 0; i < Math.max(1, Math.round(lw / 0.9)); i++) {
        const x = -hw + 0.45 + i * 0.9;
        b.box(0.7, 1.6, 0.6, x, 0, -0.1, pick(['#2f4fd6', '#d2342a', '#6d4aa0'], i));
        b.box(0.55, 0.42, 0.02, x, 1.0, 0.21, '#7ee0c5', { layer: 'screen' });
        b.box(0.6, 0.06, 0.3, x, 0.85, 0.3, BLACK);
      }
      return;
    }
    case 'pool': {
      b.box(lw + 0.4, 0.08, ld + 0.4, 0, 0, 0, '#f3eee6');
      b.box(lw, 0.04, ld, 0, 0.06, 0, '#3fb1d9', { layer: 'glass' });
      for (let i = 0; i < 3; i++) {
        const x = -hw + 0.6 + i * (lw / 3);
        b.box(0.6, 0.25, 1.6, x, 0, hd + 0.9, WHITE); // loungers
        b.box(0.6, 0.5, 0.1, x, 0.25, hd + 0.2, WHITE, { rx: -0.6 });
      }
      b.cyl(0.03, 0.03, 2.1, hw + 0.4, 0, -hd + 0.3, METAL, { seg: 4 });
      b.cyl(0.05, 0.9, 0.4, hw + 0.4, 2.0, -hd + 0.3, '#f2c230', { seg: 8 }); // umbrella
      return;
    }
    case 'cage': {
      b.box(lw, 0.05, ld, 0, 0.01, 0, '#a8875a');
      for (let i = 0; i <= Math.round(lw / 0.3); i++) b.box(0.03, 2.0, 0.03, -hw + i * 0.3, 0, hd - 0.05, METAL_D);
      b.box(lw, 0.05, 0.05, 0, 2.0, hd - 0.05, METAL_D);
      b.box(0.06, 2.0, ld, -hw, 0, 0, METAL_D);
      b.box(0.06, 2.0, ld, hw, 0, 0, METAL_D);
      // a lion (well, a low-poly one) on a rock
      b.box(1.4, 0.5, 0.6, -0.3, 0.2, -0.3, '#c99350');
      b.box(0.55, 0.55, 0.55, 0.45, 0.45, -0.3, '#8a5a2a');
      b.box(0.35, 0.35, 0.35, 0.62, 0.55, -0.3, '#c99350');
      for (const sx of [-0.8, 0.1]) for (const sz of [-0.5, -0.1]) b.box(0.15, 0.25, 0.15, sx, 0, sz, '#c99350');
      b.box(1.2, 0.4, 0.9, -hw + 0.8, 0, -hd + 0.6, '#8f8a84'); // rock
      tree(b, hw - 0.6, -hd + 0.5, 0.9);
      return;
    }
    case 'pen': {
      for (let i = 0; i <= Math.round(lw / 0.6); i++) b.box(0.06, 1.0, 0.06, -hw + i * 0.6, 0, hd - 0.05, WOOD);
      b.box(lw, 0.06, 0.04, 0, 0.6, hd - 0.05, WOOD);
      b.box(lw, 0.06, 0.04, 0, 0.95, hd - 0.05, WOOD);
      for (let i = 0; i < 2; i++) {
        const x = -0.6 + i * 1.2;
        b.box(0.5, 0.45, 0.7, x, 0.8, -0.2, '#2a2420'); // ostrich body
        b.box(0.08, 0.8, 0.08, x, 1.15, 0.1, '#d8b8a0'); // neck
        b.box(0.14, 0.12, 0.2, x, 1.9, 0.14, '#d8b8a0');
        for (const sx of [-1, 1]) b.box(0.06, 0.8, 0.06, x + sx * 0.12, 0, -0.2, '#d8b8a0');
      }
      return;
    }
    case 'stands': {
      const rows = 4;
      // the stand rises away from its front
      for (let r = 0; r < rows; r++) {
        b.box(lw, 0.3 + r * 0.35, ld / rows, 0, 0, hd - (r + 0.5) * (ld / rows), r % 2 ? '#d8d2c6' : '#c8c2b6');
        for (let i = 0; i < Math.round(lw / 0.7); i++)
          if ((i + r + seed) % 3 !== 0) person(b, -hw + 0.35 + i * 0.7, hd - (r + 0.5) * (ld / rows), pick(['#1f7a3f', '#f3f0e8', '#1f7a3f', '#d2342a'], i + r), true);
      }
      b.box(lw, 0.12, ld + 0.2, 0, 0.3 + rows * 0.35 + 0.6, 0, '#2c3540'); // roof
      for (const sx of [-1, 1]) b.box(0.12, 0.3 + rows * 0.35 + 0.6, 0.12, sx * (hw - 0.1), 0, -hd + 0.1, METAL_D);
      return;
    }
    case 'pitch': {
      b.box(lw, 0.02, ld, 0, 0.005, 0, '#3e9a4a');
      for (let i = 0; i < 6; i++) b.box(lw / 6, 0.004, ld, -hw + (i + 0.5) * (lw / 6), 0.026, 0, i % 2 ? '#469f52' : '#3a9145');
      b.box(lw, 0.006, 0.08, 0, 0.03, -hd + 0.05, WHITE);
      b.box(lw, 0.006, 0.08, 0, 0.03, hd - 0.05, WHITE);
      b.box(0.08, 0.006, ld, 0, 0.03, 0, WHITE);
      b.cyl(0.9, 0.9, 0.006, 0, 0.03, 0, WHITE, { seg: 20 });
      b.cyl(0.84, 0.84, 0.008, 0, 0.032, 0, '#3e9a4a', { seg: 20 });
      for (const sx of [-1, 1]) {
        b.box(0.08, 1.1, 0.08, sx * (hw - 0.1), 0, -0.7, WHITE);
        b.box(0.08, 1.1, 0.08, sx * (hw - 0.1), 0, 0.7, WHITE);
        b.box(0.08, 0.08, 1.48, sx * (hw - 0.1), 1.1, 0, WHITE);
      }
      // running track round the pitch
      b.box(lw + 1.2, 0.01, 0.5, 0, 0.002, -hd - 0.3, '#b5552b');
      b.box(lw + 1.2, 0.01, 0.5, 0, 0.002, hd + 0.3, '#b5552b');
      // floodlights
      for (const sx of [-1, 1]) {
        b.box(0.12, 4.2, 0.12, sx * (hw + 0.5), 0, -hd - 0.6, METAL_D);
        b.box(0.9, 0.4, 0.15, sx * (hw + 0.5), 4.2, -hd - 0.6, '#fff6c8', { layer: 'glow' });
      }
      return;
    }
    case 'statue': {
      // Emotan: a respectful bronze figure on a white plinth, under a small canopy, flowers at the base
      b.box(lw * 0.7, 0.4, ld * 0.7, 0, 0, 0, '#e8e2d6');
      b.box(lw * 0.45, 1.0, ld * 0.45, 0, 0.4, 0, '#f4f0e8');
      b.cyl(0.32, 0.42, 1.1, 0, 1.4, 0, '#8a5a2a', { seg: 10 }); // wrapper
      b.box(0.5, 0.55, 0.32, 0, 2.5, 0, '#9c6a2e');
      b.cyl(0.16, 0.16, 0.3, 0, 3.05, 0, '#8a5a2a', { seg: 8 });
      b.cyl(0.2, 0.18, 0.18, 0, 3.33, 0, '#b0793a', { seg: 8 }); // head tie
      b.box(0.12, 0.6, 0.12, 0.32, 2.3, 0.05, '#8a5a2a'); // arm
      for (let i = 0; i < 5; i++) b.cyl(0.08, 0.06, 0.12, -0.6 + i * 0.3, 0.4, ld * 0.25, pick(['#d2342a', '#f2a516', '#f3f0e8'], i), { seg: 6 });
      for (const sx of [-1, 1]) plant(b, sx * (hw - 0.2), hd - 0.2, 1.2);
      return;
    }
    case 'cars': {
      const n = Math.max(1, Math.floor(lw / 2.3));
      for (let i = 0; i < n; i++) {
        const x = -hw + (i + 0.5) * (lw / n);
        car(b, z.x + Math.cos(yaw) * x, z.z - Math.sin(yaw) * x, yaw + 0.25, pick(['#f4f2ee', BLACK, '#9c1f19', '#2f6fb3', '#c8ced4', '#d9a441'], i + seed), 0.62);
      }
      b.setFrame(z.x, 0, z.z, yaw);
      if (k.kind === 'indoor') b.box(lw, 0.02, ld, 0, 0.006, 0, '#cfd6dc');
      // price tags
      for (let i = 0; i < n; i++) b.box(0.4, 0.25, 0.03, -hw + (i + 0.5) * (lw / n) + 0.7, 0.9, hd - 0.2, '#f3cf5e', { layer: 'glow' });
      return;
    }
    case 'lane': {
      b.box(lw, 0.012, ld, 0, 0.004, 0, '#4a4f56');
      for (let i = 0; i < Math.round(ld / 0.8); i++) b.box(0.1, 0.006, 0.4, 0, 0.018, -hd + 0.4 + i * 0.8, WHITE);
      for (const sx of [-1, 1]) for (let i = 0; i < 3; i++) b.cyl(0.08, 0.12, 0.4, sx * (hw - 0.1), 0, -hd + 0.4 + i * (ld / 3), i % 2 ? WHITE : CORAL, { seg: 6 });
      return;
    }
    default:
      b.box(Math.min(1, lw), 0.4, Math.min(1, ld), 0, 0, 0, WOOD_L);
  }
}

/** The shell: floor (checker), back + left walls full height (cut away at the front/right like the home),
 * entrance mat, a few plants / lamps. Outdoor kits: a ground island with a low fence and trees. */
function buildShell(b: B, room: Room, scene: string, seed: number, density: number) {
  const { W, D, kit } = room;
  b.resetFrame();
  const outdoor = kit.kind === 'outdoor';
  const [floorMat, wallMat] = SURF[scene] ?? (outdoor ? ['ground', 'block'] : ['tiles', 'paint']);
  // F1: the world outside instead of a floating island
  buildOutside(b, {
    x0: 0, z0: 0, x1: W, z1: D, seed,
    style: outdoor ? (scene === 'market' || scene === 'farm' || scene === 'motorpark' ? 'compound' : 'city') : ['hotel', 'bank', 'car_dealer', 'mall', 'airport'].includes(scene) ? 'estate' : 'city',
    density,
  });
  // floor: one slab with the atlas (tiles, worn cement, laterite...), tinted by the kit
  b.box(W, 0.04, D, W / 2, -0.04, D / 2, kit.floorAlt ? mixCol(kit.floor, kit.floorAlt) : kit.floor, { mat: floorMat, uv: floorMat === 'tiles' && kit.tile ? kit.tile * 2 : undefined });
  const T = 0.14;
  b.mat = wallMat;
  if (outdoor) {
    // low block fence on the back and left, posts on the right; trees in the corners
    b.box(W, kit.wallH, T, W / 2, 0, -T / 2, kit.wall);
    b.box(T, kit.wallH, D, -T / 2, 0, D / 2, kit.wall);
    for (let z = 0.5; z < D; z += 1.5) b.box(0.1, 0.5, 0.1, W + 0.05, 0, z, kit.trim);
    b.box(0.06, 0.06, D, W + 0.05, 0.45, D / 2, kit.trim);
    for (const [x, z] of [[-0.9, -0.9], [W + 0.9, -0.6], [-0.8, D + 0.6]] as [number, number][]) tree(b, x, z, 1.15);
    // sign on two posts at the back
    for (const sx of [W / 2 - 1.8, W / 2 + 1.8]) b.box(0.1, 2.6, 0.1, sx, 0, -0.35, kit.trim, { mat: 'metal' });
    b.mat = null;
    // market / park: coloured tarps over the back half (shade), on poles
    if (scene === 'market' || scene === 'motorpark') {
      const r = seeded(seed + 5);
      const tarps = ['#2f6fb3', '#d2342a', '#1f7a3f', '#e2b33b', '#3e5f9e'];
      for (let x = 1.6; x < W - 1; x += 3 + r()) {
        const c = tarps[Math.floor(r() * tarps.length)];
        b.box(2.6, 0.03, 2.2, x, 2.3, 1.4 + r() * 0.5, c, { mat: 'tarp', rx: 0.12, noOcc: true });
        for (const dx of [-1.2, 1.2]) b.box(0.05, 2.3, 0.05, x + dx, 0, 0.4, '#6b5338', { mat: 'wood' });
      }
    }
    return;
  }
  const H = kit.wallH;
  b.mat = wallMat;
  b.box(W + T, H, T, W / 2, 0, -T / 2, kit.wall); // back
  b.box(T, H, D + T, -T / 2, 0, D / 2, kit.wall); // left
  if (kit.wallTop) {
    b.box(W + T, 0.25, T + 0.02, W / 2, H - 0.25, -T / 2, kit.wallTop);
    b.box(T + 0.02, 0.25, D + T, -T / 2, H - 0.25, D / 2, kit.wallTop);
  }
  b.mat = null;
  // skirting in the trim colour
  b.box(W, 0.12, 0.02, W / 2, 0, 0.01, kit.trim, { mat: 'wood' });
  b.box(0.02, 0.12, D, 0.01, 0, D / 2, kit.trim, { mat: 'wood' });
  b.mat = wallMat;
  // cut-away right + front walls (low, so the camera sees in), with the entrance gap in the front
  const LOW = 0.35;
  b.box(T, LOW, D + T, W + T / 2, 0, D / 2, kit.wall);
  const gap = 1.6;
  b.box(W / 2 - gap / 2, LOW, T, (W / 2 - gap / 2) / 2, 0, D + T / 2, kit.wall);
  b.box(W / 2 - gap / 2, LOW, T, W - (W / 2 - gap / 2) / 2, 0, D + T / 2, kit.wall);
  b.mat = null;
  b.box(gap, 0.02, 0.9, W / 2, 0.001, D - 0.3, '#7a4f2a'); // door mat
  // windows on the back wall (glass), wall lamps (glow)
  for (let x = 2; x < W - 1; x += 3.2) {
    if (!kit.party) b.box(1.3, 0.9, 0.04, x, 1.2, 0.02, '#bfe3f7', { layer: 'glass' });
    b.box(0.3, 0.12, 0.12, x + 1.4, H - 0.5, 0.08, kit.party ? '#ff4fa3' : '#ffe2a8', { layer: 'glow' });
  }
  for (let z = 2; z < D - 1; z += 3.5) b.box(0.12, 0.12, 0.3, 0.08, H - 0.5, z, kit.party ? '#7ee0c5' : '#ffe2a8', { layer: 'glow' });
  if (kit.party) {
    // LED strips along the top of the walls and the skirting (they cycle colours with the club rig)
    b.box(W, 0.05, 0.05, W / 2, H - 0.1, 0.05, '#ff3fa0', { layer: 'glow' });
    b.box(0.05, 0.05, D, 0.05, H - 0.1, D / 2, '#36d6ff', { layer: 'glow' });
    b.box(W, 0.03, 0.03, W / 2, 0.13, 0.04, '#9b5cff', { layer: 'glow' });
    b.box(0.03, 0.03, D, 0.04, 0.13, D / 2, '#ff3fa0', { layer: 'glow' });
  }
  plant(b, 0.45, D - 0.6, 1);
}

function mixCol(a: string, c: string): string {
  const pa = parseInt(a.slice(1), 16), pc = parseInt(c.slice(1), 16);
  const ch = (s: number) => Math.round((((pa >> s) & 255) + ((pc >> s) & 255)) / 2);
  return `#${((1 << 24) | (ch(16) << 16) | (ch(8) << 8) | ch(0)).toString(16).slice(1)}`;
}

export function buildPlace(room: Room, zones: PlaceZone[], opts: { scene?: string; seed?: number; density?: number } = {}): BuiltPlace {
  const scene = opts.scene ?? '';
  const seed = opts.seed ?? 1;
  const density = opts.density ?? 1;
  const outdoor = room.kit.kind === 'outdoor';
  const rig = rigFor(scene, outdoor);
  const b = new HomeBuilder();
  buildShell(b, room, scene, seed, density);
  zones.forEach((z, i) => buildProp(b, z, room, i * 3 + z.key.length));
  b.resetFrame();
  // F1: clutter along the walls, keeping every zone (and the entrance) clear
  const avoid: Rect[] = zones.map((z) => [z.x - z.w / 2 - 0.35, z.z - z.d / 2 - 0.35, z.x + z.w / 2 + 0.35, z.z + z.d / 2 + 0.6] as Rect);
  avoid.push([room.W / 2 - 1.3, room.D - 2, room.W / 2 + 1.3, room.D]);
  avoid.push([0, room.D - 1.2, 1, room.D]); // the plant by the door
  const kind = CLUTTER[scene] ?? (outdoor ? 'market' : 'hall');
  const windowsN: [number, number][] = [];
  if (!outdoor && !room.kit.party) for (let x = 2; x < room.W - 1; x += 3.2) windowsN.push([x - 0.8, x + 0.8]);
  buildClutter(b, { W: room.W, D: room.D, H: room.kit.wallH, kind, seed, density, avoid, windowsN, outdoor });
  // light pools: club colours over the party zones, lamp pools over tables / counters, a grid otherwise
  const spots: [number, number][] = [];
  for (const z of zones) if ((room.kit.party ? PARTY_PROPS : WARM_PROPS).has(z.prop)) spots.push([z.x, z.z + (room.kit.party ? 0 : z.d / 2 + 0.3)]);
  if (!room.kit.party && spots.length < 2) for (let x = room.W / 4; x < room.W; x += room.W / 2) spots.push([x, room.D / 2]);
  buildPools(b, { W: room.W, D: room.D, H: room.kit.wallH, kind: room.kit.party ? 'club' : scene, seed, spots: spots.slice(0, room.kit.party ? 4 : 6) });
  const layers = b.finish();
  const fan: [number, number, number] | null = rig.fan && !outdoor ? [room.W * 0.45, room.kit.wallH - 0.1, room.D * 0.45] : null;
  const steam: [number, number, number][] = rig.steam ? zones.filter((z) => STEAM_PROPS.has(z.prop)).slice(0, 3).map((z) => [z.x, 1.05, z.z]) : [];
  return { layers, tris: b.tris, rig, fan, steam };
}
