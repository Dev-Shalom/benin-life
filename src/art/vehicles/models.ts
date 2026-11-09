// Shared vehicle library: the models. Each builder draws into a Kit (see kit.ts), nose -z, wheels on y = 0.
import { BoxGeometry, type BufferGeometry } from 'three';
import { buildCar, plate } from './car';
import { HATCH, MINIBUS, PICKUP, SEDAN, SEDAN2, SUV, SUVLUX } from './designs';
import { Kit, type Role } from './kit';
import { cylX, cylZ, ell, loft, mirrorRing, rbox, rod, smoothPoly, type Ring } from './prim';
import { wheelParts } from './wheels';

export type VehicleModel = 'sedan' | 'sedan2' | 'hatch' | 'suv' | 'suvlux' | 'pickup' | 'minibus' | 'moto' | 'okada2' | 'bike' | 'keke' | 'bus';

/** Footprint half-length used to keep traffic apart (unchanged from the first drive scene). */
export const VEH_LEN: Record<VehicleModel, number> = { sedan: 4.4, sedan2: 4.8, hatch: 3.9, suv: 4.7, suvlux: 4.9, pickup: 5.1, minibus: 5.3, moto: 2.2, okada2: 2.2, bike: 1.8, keke: 3.4, bus: 9.8 };

/* ------------------------------------------------------------------------------------------------ people on two wheels */

/** A seated rider on a motorcycle or bicycle: torso, head with a helmet, arms to the bars and legs to the pegs. */
function rider(K: Kit, o: { x?: number; y: number; z: number; lean: number; shirt: number; skin: number; helmet?: number; bars: [number, number]; peg: [number, number]; legW?: number }) {
  if (!K.rider) return;
  const x = o.x ?? 0;
  const lod = K.lod;
  const tz = o.z - 0.06 - o.lean * 0.1;
  K.put(rbox(0.38, 0.52, 0.22, 0.08, lod === 0 ? 2 : 1), 'cloth', x, o.y + 0.3, tz, { rx: o.lean, hex: o.shirt });
  K.put(ell(0.14, 0.15, 0.15, lod === 0 ? 9 : 6, lod === 0 ? 6 : 4), 'skin', x, o.y + 0.7, tz - o.lean * 0.22, { hex: o.skin });
  if (o.helmet !== undefined) K.put(ell(0.15, 0.13, 0.16, lod === 0 ? 9 : 6, lod === 0 ? 5 : 4), 'accent', x, o.y + 0.74, tz - o.lean * 0.22 - 0.01, { hex: o.helmet });
  if (lod >= 2) return;
  for (const s of [-1, 1]) {
    // arms: shoulder to the grip
    K.add(rod([x + s * 0.2, o.y + 0.5, tz - o.lean * 0.12], [x + s * 0.24, o.bars[0], o.bars[1]], 0.045, 4), 'cloth', o.shirt);
    // legs: hip to knee to the peg
    const hipx = x + s * 0.11;
    const knee: [number, number, number] = [x + s * (o.legW ?? 0.2), o.y + 0.05, o.z - 0.34];
    K.add(rod([hipx, o.y + 0.08, o.z + 0.02], knee, 0.07, 4), 'cloth', 0x2f3646);
    K.add(rod(knee, [x + s * 0.16, o.peg[0], o.peg[1]], 0.06, 4), 'cloth', 0x2f3646);
  }
}

/* ------------------------------------------------------------------------------------------------ motorcycle */

function moto(K: Kit, passenger: boolean) {
  const lod = K.lod;
  const W = { r: 0.34, wid: 0.12 };
  const zf = -0.78;
  const zr = 0.82;
  for (const z of [zf, zr]) {
    if (K.separateWheels) K.wheels.push({ x: 0, z, r: W.r, wid: W.wid, front: z < 0, style: 'spoke' });
    else for (const p of wheelParts(0, z, W.r, W.wid, 'spoke', lod)) K.parts.push(p);
  }
  // frame, engine, tank, seat
  K.put(rbox(0.22, 0.3, 0.42, 0.06, 1), 'metal', 0, 0.5, 0.06, { hex: 0x4a4f57 });
  K.put(ell(0.16, 0.14, 0.34, lod === 0 ? 10 : 7, lod === 0 ? 6 : 4), 'body', 0, 0.93, -0.18);
  K.put(rbox(0.28, 0.09, 0.78, 0.04, lod === 0 ? 2 : 1), 'seat', 0, 0.87, 0.42);
  K.put(rbox(0.2, 0.1, 0.34, 0.04, 1), 'body', 0, 0.78, 0.9); // tail cowl
  K.add(rod([0, 0.74, -0.36], [0, 0.48, 0.1], 0.025, 4), 'trim');
  // front fork and the steering head
  for (const s of [-1, 1]) {
    K.add(rod([s * 0.075, 0.36, zf], [s * 0.06, 1.0, zf + 0.16], 0.02, 5), 'chrome');
    if (lod === 0) K.add(rod([s * 0.075, 0.36, zf], [s * 0.075, 0.62, zf + 0.04], 0.03, 5), 'metal');
  }
  K.put(cylX(0.012, 0.6, 5), 'trim', 0, 1.06, zf + 0.2); // handlebar
  if (lod === 0) for (const s of [-1, 1]) {
    K.put(cylX(0.022, 0.1, 6), 'trim', s * 0.3, 1.06, zf + 0.2);
    K.add(rod([s * 0.26, 1.06, zf + 0.2], [s * 0.3, 1.2, zf + 0.26], 0.008, 4), 'trim'); // mirror stalks
    K.put(ell(0.055, 0.04, 0.02, 6, 4), 'chrome', s * 0.3, 1.22, zf + 0.26);
  }
  K.put(ell(0.095, 0.095, 0.07, lod === 0 ? 9 : 6, lod === 0 ? 6 : 4), 'head', 0, 1.0, zf - 0.08); // headlamp
  K.put(rbox(0.12, 0.03, 0.55, 0.012, 1), 'body', 0, 0.74, zf + 0.04); // front mudguard
  K.put(rbox(0.12, 0.03, 0.5, 0.012, 1), 'body', 0, 0.74, zr - 0.02); // rear mudguard
  K.put(rbox(0.1, 0.06, 0.05, 0.02, 1), 'tail', 0, 0.8, 1.08);
  if (lod < 2) {
    K.add(rod([0.1, 0.34, 0.0], [0.14, 0.38, 1.12], 0.035, 6), 'chrome'); // exhaust
    K.put(cylZ(0.04, 0.12, 6), 'chrome', 0.14, 0.38, 1.16);
    K.add(rod([0, 0.34, 0.1], [0, 0.4, zr], 0.022, 4), 'metal'); // swing arm
    K.put(rbox(0.2, 0.03, 0.4, 0.01, 1), 'metal', 0, 0.84, 1.0, { hex: 0x2a2d33 }); // rear rack
    K.put(rbox(0.04, 0.1, 0.14, 0.015, 1), 'plate', 0, 0.7, 1.12);
  }
  // rider (and a passenger on the okada2 variant)
  rider(K, { y: 0.82, z: 0.3, lean: 0.4, shirt: passenger ? 0x8a5a44 : 0x4d6a8f, skin: 0x7a5236, helmet: 0xe6e2d6, bars: [1.08, zf + 0.22], peg: [0.32, 0.18] });
  if (passenger) rider(K, { y: 0.82, z: 0.78, lean: 0.12, shirt: 0xc9b9a0, skin: 0x6a4630, bars: [0.9, 0.5], peg: [0.32, 0.7], legW: 0.22 });
}

/* ------------------------------------------------------------------------------------------------ bicycle */

function bike(K: Kit) {
  const lod = K.lod;
  const zf = -0.55;
  const zr = 0.55;
  const r = 0.34;
  for (const z of [zf, zr]) {
    if (K.separateWheels) K.wheels.push({ x: 0, z, r, wid: 0.05, front: z < 0, style: 'spoke' });
    else for (const p of wheelParts(0, z, r, 0.05, 'spoke', lod)) K.parts.push(p);
  }
  const FR = 0x2f6f54;
  const t = (a: [number, number, number], b: [number, number, number], rad = 0.022) => K.add(rod(a, b, rad, lod === 0 ? 5 : 4), 'accent', FR);
  const bb: [number, number, number] = [0, 0.34, 0.12];
  const seat: [number, number, number] = [0, 0.86, 0.22];
  const head: [number, number, number] = [0, 0.84, -0.4];
  t(seat, head); // top tube
  t(head, bb); // down tube
  t(bb, seat); // seat tube
  t(bb, [0, r, zr], 0.016); // chain stay
  t(seat, [0, r, zr], 0.016); // seat stay
  K.add(rod([0, 0.88, -0.42], [0, r, zf], 0.02, 5), 'chrome'); // fork
  K.put(cylX(0.012, 0.48, 5), 'trim', 0, 0.98, -0.44); // bars
  K.put(rbox(0.12, 0.05, 0.26, 0.02, 1), 'seat', 0, 0.9, 0.22); // saddle
  K.add(rod([0, 0.88, 0.22], [0, 0.86, 0.22], 0.015, 4), 'trim');
  if (lod === 0) {
    K.put(cylX(0.05, 0.03, 8), 'chrome', 0.03, 0.34, 0.12); // chainring
    K.add(rod([0.08, 0.3, 0.12], [0.08, 0.4, 0.12], 0.012, 4), 'trim');
    K.put(rbox(0.1, 0.03, 0.14, 0.01, 1), 'trim', 0.1, 0.26, 0.12);
    K.put(ell(0.045, 0.045, 0.03, 6, 4), 'head', 0, 0.94, -0.5);
  }
  rider(K, { y: 0.86, z: 0.24, lean: 0.55, shirt: 0x6f8a6a, skin: 0x7a5236, bars: [0.98, -0.42], peg: [0.3, 0.12], legW: 0.17 });
}

/* ------------------------------------------------------------------------------------------------ keke (tricycle taxi) */

function keke(K: Kit) {
  const lod = K.lod;
  const N = lod === 0 ? 12 : lod === 1 ? 9 : 6;
  // body shell: a rounded pod, narrow nose, wide cabin, blunt tail
  const plan = [[-1.95, 0.2], [-1.8, 0.3], [-1.4, 0.36], [-0.95, 0.4], [-0.55, 0.6], [-0.25, 0.66], [1.0, 0.66], [1.4, 0.6], [1.6, 0.5]];
  const interp = (z: number, tab: number[][]) => {
    for (let i = 0; i < tab.length - 1; i++) if (z <= tab[i + 1][0]) {
      const t = (z - tab[i][0]) / (tab[i + 1][0] - tab[i][0]);
      const s = t * t * (3 - 2 * t);
      return tab[i][1] + (tab[i + 1][1] - tab[i][1]) * s;
    }
    return tab[tab.length - 1][1];
  };
  const y1 = [[-1.95, 0.6], [-1.8, 0.76], [-1.3, 0.96], [-0.8, 1.02], [-0.5, 0.98], [0.9, 0.98], [1.6, 0.82]];
  const y0 = [[-1.95, 0.42], [-1.6, 0.3], [-0.9, 0.26], [1.2, 0.26], [1.6, 0.34]];
  const rings: Ring[] = [];
  for (let i = 0; i <= N; i++) {
    const z = -1.95 + (3.55 * (1 - Math.cos((Math.PI * i) / N))) / 2;
    const hw = interp(z, plan);
    const a = interp(z, y0);
    const b = interp(z, y1);
    const h = b - a;
    const half: [number, number][] = [[0, a], [hw * 0.7, a], [hw * 0.95, a + h * 0.18], [hw, a + h * 0.55], [hw * 0.9, b - h * 0.08], [hw * 0.55, b], [0, b + 0.03]];
    rings.push({ z, pts: mirrorRing(smoothPoly(half, lod === 0 ? 1 : 0)) });
  }
  K.add(loft(rings, { capStart: true, capEnd: true }), 'body');
  // canopy: curved roof (green), four slim posts, tinted windscreen, rear curtain panel
  K.put(rbox(1.5, 0.09, 2.4, 0.04, lod === 0 ? 2 : 1), 'accent', 0, 1.82, 0.3, { rx: 0.02 });
  K.put(rbox(1.46, 0.05, 0.16, 0.02, 1), 'accent', 0, 1.77, -0.98, { rx: 0.25 }); // front visor
  const posts: [number, number][] = [[-0.68, -0.8], [0.68, -0.8], [-0.68, 1.3], [0.68, 1.3]];
  for (const [x, z] of posts) K.add(rod([x, 0.96, z], [x, 1.8, z + (z < 0 ? 0.08 : 0)], 0.03, 5), 'trim');
  const ws = rbox(1.3, 0.72, 0.04, 0.02, 1);
  K.put(ws, 'glass', 0, 1.4, -0.84, { rx: 0.16 });
  K.put(rbox(1.0, 0.5, 0.04, 0.02, 1), 'glass', 0, 1.4, 1.27); // rear window
  if (lod < 2) {
    K.put(rbox(1.3, 0.28, 0.05, 0.02, 1), 'body', 0, 1.2, 1.3); // rear panel under the window
    K.put(rbox(1.14, 0.12, 0.6, 0.04, 1), 'seat', 0, 1.06, 0.78); // bench
    K.put(rbox(1.14, 0.42, 0.1, 0.04, 1), 'seat', 0, 1.3, 1.2);
    K.put(rbox(0.46, 0.12, 0.42, 0.04, 1), 'seat', 0, 1.02, -0.15); // driver seat
  }
  // front: mudguard, headlamp, bumper, handlebars
  K.put(rbox(0.36, 0.05, 0.62, 0.02, 1), 'body', 0, 0.62, -1.55);
  K.put(ell(0.1, 0.1, 0.07, 8, 5), 'head', 0, 0.82, -1.98);
  K.put(rbox(0.5, 0.05, 0.06, 0.02, 1), 'chrome', 0, 0.52, -2.02);
  if (lod < 2) {
    K.put(cylX(0.014, 0.62, 5), 'trim', 0, 1.1, -0.88);
    K.add(rod([0, 0.8, -1.35], [0, 1.1, -0.88], 0.02, 4), 'trim');
    for (const s of [-1, 1]) {
      K.put(ell(0.05, 0.05, 0.02, 5, 4), 'chrome', s * 0.38, 1.18, -0.82);
      K.put(rbox(0.18, 0.18, 0.32, 0.06, 1), 'body', s * 0.64, 0.5, 0.95); // rear wheel covers
      K.put(rbox(0.3, 0.08, 0.05, 0.03, 1), 'tail', s * 0.5, 0.9, 1.6);
    }
    K.put(rbox(0.5, 0.2, 0.05, 0.02, 1), 'trim', 0, 0.62, 1.62);
    plate(K, 0, 0.62, 1.64, 1, 0.42);
    plate(K, 0, 0.5, -2.04, -1, 0.34);
    // the driver
  }
  rider(K, { y: 1.02, z: -0.1, lean: 0.12, shirt: 0x7b8d6d, skin: 0x6a4630, bars: [1.12, -0.88], peg: [0.2, -0.7], legW: 0.2 });
  // wheels: one steering at the front, two at the back
  const w = { r: 0.28, wid: 0.14 };
  const specs: [number, number][] = [[0, -1.55], [-0.7, 0.9], [0.7, 0.9]];
  for (const [x, z] of specs) {
    if (K.separateWheels) K.wheels.push({ x, z, r: w.r, wid: w.wid, front: z < 0, style: 'car' });
    else for (const p of wheelParts(x, z, w.r, w.wid, 'car', lod)) K.parts.push(p);
  }
}

/* ------------------------------------------------------------------------------------------------ the city bus (ECTS) */

export const BUS = { len: 9.6, wid: 2.5, doorZ: [-4.0, 1.1] as number[], doorW: 0.9, doorY0: 0.72, doorH: 1.75, boardY: 2.56, boardZ: -4.86 };
const YELLOW = 0xf0b72a;
const RED = 0xc2372c;
const BUS_WINDOWS = [-3.7, -2.4, -1.1, 0.2, 1.5, 2.8, 4.1];
const BG: Record<string, [number, number, number, number][]> = {
  E: [[0, 0, 1, 5], [0, 0, 3, 1], [0, 2, 3, 1], [0, 4, 3, 1]],
  C: [[0, 0, 1, 5], [0, 0, 3, 1], [0, 4, 3, 1]],
  T: [[0, 0, 3, 1], [1, 0, 1, 5]],
  S: [[0, 0, 3, 1], [0, 0, 1, 3], [0, 2, 3, 1], [2, 2, 1, 3], [0, 4, 3, 1]],
};

function busLetters(K: Kit, text: string, side: 1 | -1 | 0, zc: number, y: number) {
  const cw = 0.1;
  const ch = 0.092;
  const gap = 0.14;
  const lw = 3 * cw;
  const total = text.length * lw + (text.length - 1) * gap;
  [...text].forEach((c, i) => {
    const off = -total / 2 + i * (lw + gap);
    for (const [gx, gy, gw, gh] of BG[c]) {
      const along = off + gx * cw + (gw * cw) / 2;
      const yy = y + 2.5 * ch - gy * ch - (gh * ch) / 2;
      if (side === 0) K.add(new BoxGeometry(gw * cw, gh * ch, 0.04).translate(along, yy, BUS.len / 2 + 0.06), 'plate');
      else K.add(new BoxGeometry(0.04, gh * ch, gw * cw).translate(side * (BUS.wid / 2 + 0.05), yy, zc + (side === -1 ? along : -along)), 'plate');
    }
  });
}

function bus(K: Kit, doors: boolean) {
  const lod = K.lod;
  const N = lod === 0 ? 14 : lod === 1 ? 10 : 6;
  const L = 9.6;
  const rings: Ring[] = [];
  for (let i = 0; i <= N; i++) {
    const z = -(L / 2) * Math.cos((Math.PI * i) / N);
    const e = Math.min(1, (L / 2 - Math.abs(z)) / 0.5); // rounding at the ends
    const k = 0.84 + 0.16 * Math.sqrt(Math.max(0, e));
    const hw = 1.25 * k;
    const top = 2.86 - (1 - e) * 0.16;
    const half: [number, number][] = [[0, 0.42], [hw * 0.8, 0.42], [hw * 0.97, 0.52], [hw, 0.85], [hw, top - 0.35], [hw * 0.94, top - 0.1], [hw * 0.7, top - 0.01], [0, top + 0.015]];
    rings.push({ z, pts: mirrorRing(smoothPoly(half, lod === 0 ? 1 : 0)) });
  }
  K.add(loft(rings, { capStart: true, capEnd: true }), 'accent', YELLOW);
  // the red band round the whole bus
  for (const s of [-1, 1]) K.put(rbox(0.05, 0.56, 9.0, 0.02, 1), 'accent', s * 1.255, 1.08, 0, { hex: RED });
  K.put(rbox(2.2, 0.56, 0.05, 0.02, 1), 'accent', 0, 1.08, -4.78, { hex: RED });
  K.put(rbox(2.2, 0.56, 0.05, 0.02, 1), 'accent', 0, 1.08, 4.78, { hex: RED });
  // glass: windscreen, rear window, side windows
  K.put(rbox(2.14, 0.98, 0.05, 0.05, 1), 'glass', 0, 2.1, -4.79);
  K.put(rbox(1.9, 0.62, 0.05, 0.05, 1), 'glass', 0, 2.1, 4.79);
  K.put(rbox(1.9, 0.26, 0.06, 0.03, 1), 'trim', 0, BUS.boardY, -4.82); // destination board
  K.put(rbox(1.7, 0.17, 0.07, 0.03, 1), 'amber', 0, BUS.boardY, -4.84, { hex: 0xffc247 });
  for (const side of [-1, 1] as const) {
    for (const z of BUS_WINDOWS) {
      if (side === 1 && BUS.doorZ.some((dz) => Math.abs(dz - z) < BUS.doorW / 2 + 0.6)) continue;
      K.put(rbox(0.05, 0.82, 1.1, 0.04, 1), 'glass', side * 1.26, 2.05, z);
    }
  }
  for (const dz of BUS.doorZ) {
    if (doors) {
      K.put(rbox(0.07, BUS.doorH, BUS.doorW, 0.03, 1), 'glass', 1.27, BUS.doorY0 + BUS.doorH / 2, dz, { hex: 0x35506a });
      K.put(rbox(0.09, BUS.doorH + 0.04, 0.06, 0.02, 1), 'accent', 1.27, BUS.doorY0 + BUS.doorH / 2, dz, { hex: YELLOW });
    } else K.put(rbox(0.05, BUS.doorH, BUS.doorW, 0.02, 1), 'trim', 1.25, BUS.doorY0 + BUS.doorH / 2, dz);
    if (lod < 2) K.put(rbox(0.22, 0.05, 0.9, 0.02, 1), 'trim', 1.3, 0.45, dz); // step
  }
  // bumpers, lamps, mirrors, roof unit, plates
  K.put(rbox(2.5, 0.28, 0.3, 0.1, 1), 'trim', 0, 0.5, -4.78);
  K.put(rbox(2.5, 0.28, 0.3, 0.1, 1), 'trim', 0, 0.5, 4.78);
  for (const s of [-1, 1]) {
    K.put(rbox(0.46, 0.2, 0.1, 0.07, 1), 'head', s * 0.8, 0.98, -4.84);
    K.put(rbox(0.4, 0.28, 0.1, 0.07, 1), 'tail', s * 0.85, 1.0, 4.84);
    if (lod < 2) {
      K.put(rbox(0.08, 0.5, 0.18, 0.03, 1), 'trim', s * 1.42, 1.9, -4.5);
      K.add(rod([s * 1.25, 1.9, -4.5], [s * 1.4, 1.9, -4.5], 0.02, 4), 'trim');
      K.put(rbox(0.1, 0.1, 0.06, 0.03, 1), 'amber', s * 1.0, 1.35, -4.86);
    }
  }
  K.put(rbox(1.3, 0.2, 2.2, 0.08, 1), 'metal', 0, 2.97, 0.8, { hex: 0xcfd3d6 });
  plate(K, 0, 0.46, -4.95, -1, 0.5);
  plate(K, 0, 0.5, 4.97, 1, 0.5);
  if (lod === 0) {
    busLetters(K, 'ECTS', -1, 2.5, 1.05);
    busLetters(K, 'ECTS', 1, 3.1, 1.05);
    busLetters(K, 'ECTS', 0, 0, 1.05);
    // wheel arch liners
    for (const s of [-1, 1]) for (const z of [-3.0, 2.9]) K.put(rbox(0.04, 0.88, 1.2, 0.02, 1), 'trim', s * 1.255, 0.78, z);
  }
  for (const z of [-3.0, 2.9]) {
    for (const s of [-1, 1]) {
      if (K.separateWheels) {
        if (s === 1) {
          K.wheels.push({ x: -1.1, z, r: 0.5, wid: 0.3, front: false, style: 'car' });
          K.wheels.push({ x: 1.1, z, r: 0.5, wid: 0.3, front: false, style: 'car' });
        }
      } else for (const p of wheelParts(s * 1.1, z, 0.5, 0.3, 'car', lod)) K.parts.push(p);
    }
  }
}

/* ------------------------------------------------------------------------------------------------ entry */

export function buildModel(model: VehicleModel, K: Kit, o: { doors?: boolean } = {}) {
  switch (model) {
    case 'sedan':
      return buildCar(K, SEDAN);
    case 'sedan2':
      return buildCar(K, SEDAN2);
    case 'hatch':
      return buildCar(K, HATCH);
    case 'suv':
      return buildCar(K, SUV);
    case 'suvlux':
      return buildCar(K, SUVLUX);
    case 'pickup':
      return buildCar(K, PICKUP);
    case 'minibus':
      buildCar(K, MINIBUS);
      return minibusExtras(K);
    case 'moto':
      return moto(K, false);
    case 'okada2':
      return moto(K, true);
    case 'bike':
      return bike(K);
    case 'keke':
      return keke(K);
    case 'bus':
      return bus(K, o.doors ?? true);
  }
}

/** Danfo-style van: a dark stripe, the sliding door seams and a roof carrier. */
function minibusExtras(K: Kit) {
  const lod = K.lod;
  for (const s of [-1, 1]) {
    K.put(rbox(0.045, 0.16, 4.9, 0.02, 1), 'trim', s * 0.985, 0.72, 0.1);
    if (lod === 0) {
      const [a, b] = MINIBUS.slide!;
      if (s === 1) {
        K.put(rbox(0.04, 0.025, b - a, 0.01, 1), 'chrome', 0.995, 1.0, (a + b) / 2); // slide rail
        K.put(rbox(0.05, 0.03, 0.18, 0.012, 1), 'chrome', 1.0, 1.0, a + 0.15);
      }
    }
  }
  if (lod < 2) for (let i = 0; i < 4; i++) K.put(rbox(1.7, 0.03, 0.05, 0.012, 1), 'trim', 0, 2.3, -0.7 + i * 0.9);
}

export type { Role, BufferGeometry };
