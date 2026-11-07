// The roadside world of the drive scene. A "street" is the dual carriageway along one straight stretch of the route, generated in
// 60 m chunks around the car and drawn with a handful of InstancedMeshes (about 24 draw calls). The street group sits at the
// stretch's origin facing along its heading; content is in the group's own frame (x = right of the road, z = -distance along it),
// so every chunk is a pure function of (street seed, chunk number, district style): it looks the same whenever it comes back.
// The district style (core, residential, cramped, GRA, campus, market, farm) comes from the same map zones the city map uses.
// Colours are muted real-world ones (laterite, cream, grey-green), no brands. docs/DRIVE.md.
import {
  BoxGeometry,
  BufferGeometry,
  Color,
  ConeGeometry,
  CylinderGeometry,
  Group,
  IcosahedronGeometry,
  InstancedMesh,
  Material,
  MeshBasicMaterial,
  MeshLambertMaterial,
  Object3D,
} from 'three';
import { ColorBatch } from './batch';
import { vehicleGeometry } from './vehicles';

export const PERIOD = 60;
export const COPIES = 5;
export const ROAD_HALF = 7.2;
export const LANE_IN = 2.6;
export const LANE_OUT = 5.6;

export type Style = 'core' | 'res' | 'cramped' | 'gra' | 'campus' | 'market' | 'farm';

function rng(seed: number) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const WALLS = ['#d8ccb2', '#c8b697', '#bda78a', '#d4c19c', '#a9b3a2', '#b9a79b', '#cbbdac', '#9fa9b1', '#c6a892', '#dfd7c5', '#b5a58a'];
const ROOFS = ['#6f7479', '#7d5a48', '#5d6b62', '#8a8f94', '#6b5a50'];
const AWNINGS = ['#b85c3c', '#3f7f5e', '#3b6aa3', '#c9a13c', '#8a4a6a', '#d0d0c8'];
const TREE_G = ['#5f8a4e', '#6b9558', '#4f7a47', '#789c5c', '#58844f'];
const UMB = ['#c0503c', '#3c78b4', '#d6a63a', '#4f9166', '#e0e0d8'];
const STALL = ['#2f6fd0', '#d63c32', '#f2b632', '#2e9d58', '#e06a1c', '#7a4ac8', '#e9e6dc'];

interface StyleDef {
  gap: number;
  w: [number, number];
  depth: [number, number];
  storeys: [number, number];
  setback: [number, number];
  walls: string[];
  roofs: string[];
  awn: number;
  shut: number;
  trees: [number, number];
  umb: number;
  parked: number;
  wallProb: number;
  hip: number;
  stalls: number;
  lawn: boolean;
  palms: number;
}

const DEF: Record<Style, StyleDef> = {
  res: { gap: 0.2, w: [6, 12.5], depth: [9, 15], storeys: [1, 4.2], setback: [4.4, 7], walls: WALLS, roofs: ROOFS, awn: 1, shut: 0.9, trees: [3, 5], umb: 2, parked: 0.85, wallProb: 0.55, hip: 0.25, stalls: 0, lawn: false, palms: 0.3 },
  core: { gap: 0.1, w: [7, 12], depth: [10, 15], storeys: [2, 5.4], setback: [4.4, 6], walls: ['#e4e0d6', '#d9d4c6', '#cfd2d0', '#e7dfca', '#c9c4b6', '#dcd7cb'], roofs: ['#8f979c', '#7e878c', '#9aa2a6'], awn: 1, shut: 1, trees: [1, 3], umb: 3, parked: 1, wallProb: 0.2, hip: 0.05, stalls: 0, lawn: false, palms: 0.2 },
  cramped: { gap: 0.12, w: [5, 8.5], depth: [6, 9], storeys: [1, 2.3], setback: [4.2, 5.4], walls: ['#e3cba8', '#dcc09a', '#e9d8bd', '#d6c3a5', '#e6cdab'], roofs: ['#8a4a2c', '#7b4328', '#96553a', '#6e3b25', '#8f969b'], awn: 0.9, shut: 0.8, trees: [1, 3], umb: 3, parked: 0.5, wallProb: 0.3, hip: 0, stalls: 0, lawn: false, palms: 0.2 },
  gra: { gap: 0.32, w: [10, 15], depth: [10, 13], storeys: [1, 2.5], setback: [7.5, 10.5], walls: ['#fbf8f1', '#f6f2e9', '#f3f3ef', '#f8eedc'], roofs: ['#b8432f', '#c25b3c', '#2f6f55', '#3d5f80', '#5d6a72'], awn: 0, shut: 0, trees: [5, 8], umb: 0, parked: 0.5, wallProb: 0.97, hip: 0.9, stalls: 0, lawn: true, palms: 0.5 },
  campus: { gap: 0.4, w: [14, 22], depth: [10, 14], storeys: [1, 2.4], setback: [9, 13], walls: ['#efe4cc', '#f2ead9', '#e6dcc4'], roofs: ['#3f7d4a', '#2f6f45', '#4b8a52'], awn: 0, shut: 0, trees: [6, 9], umb: 0, parked: 0.25, wallProb: 0, hip: 0.2, stalls: 0, lawn: true, palms: 0.35 },
  market: { gap: 0.06, w: [5, 9], depth: [7, 10], storeys: [1, 1.7], setback: [4.4, 5.4], walls: ['#d8c3a0', '#e3d2b3', '#cdb48a', '#d9c9a6'], roofs: ['#9aa1a6', '#8a9196', '#7d8a90', '#b0553a'], awn: 1, shut: 1, trees: [1, 2], umb: 6, parked: 0.3, wallProb: 0, hip: 0, stalls: 8, lawn: false, palms: 0.1 },
  farm: { gap: 0.72, w: [6, 9], depth: [6, 8], storeys: [1, 1.3], setback: [6, 12], walls: ['#d8ccb2', '#c8b697', '#b9a79b'], roofs: ['#8a6a48', '#7d5a48', '#6b5a50'], awn: 0.2, shut: 0.3, trees: [4, 7], umb: 0.3, parked: 0.08, wallProb: 0.15, hip: 0.4, stalls: 0, lawn: false, palms: 0.5 },
};

export const STYLE_GROUND: Record<Style, string> = {
  res: '#b3a281',
  core: '#a89b80',
  cramped: '#b09d7c',
  gra: '#8fa66a',
  campus: '#8fb067',
  market: '#b9a07a',
  farm: '#9fae72',
};

export interface StreetSpec {
  seed: number;
  /** Buildings may stand between u0b and u1b (metres along the street axis); asphalt may run a little further (the cross street at a junction). */
  u0b: number;
  u1b: number;
  u0a: number;
  u1a: number;
  styleAt(u: number): Style;
  /** The destination plot: no frontage on the right-hand side inside this u range. */
  plot?: [number, number] | null;
}

export interface Street {
  group: Group;
  /** The first chunk currently built. */
  k0: number;
  fill(spec: StreetSpec, k0: number): void;
  setDark(dark: number): void;
  /** Rain: 0 dry .. 1 wet. The asphalt and pavement darken and take a faint sky-coloured sheen. */
  setWet(wet: number): void;
  dispose(): void;
}

export function buildStreet(density: number): Street {
  const group = new Group();
  const disposables: { dispose(): void }[] = [];
  const track = <T extends { dispose(): void }>(o: T): T => {
    disposables.push(o);
    return o;
  };
  const lambert = (hex = '#ffffff') => track(new MeshLambertMaterial({ color: hex }));
  const basic = (hex = '#ffffff') => track(new MeshBasicMaterial({ color: hex }));

  const dummy = new Object3D();
  const col = new Color();
  const ims: InstancedMesh[] = [];
  const instanced = (g: BufferGeometry, m: Material, count: number) => {
    const im = new InstancedMesh(track(g), m, Math.max(1, count));
    im.frustumCulled = false;
    im.count = 0;
    group.add(im);
    ims.push(im);
    return im;
  };
  const place = (im: InstancedMesh, x: number, y: number, uz: number, sx: number, sy: number, sz: number, hex: string, ry = 0) => {
    if (im.count >= im.instanceMatrix.count) return;
    dummy.position.set(x, y, -uz);
    dummy.rotation.set(0, ry, 0);
    dummy.scale.set(sx, sy, sz);
    dummy.updateMatrix();
    im.setMatrixAt(im.count, dummy.matrix);
    im.setColorAt(im.count, col.set(hex));
    im.count++;
  };

  const C = COPIES;
  const unit = () => new BoxGeometry(1, 1, 1);
  const slabMat = lambert();
  const slab = instanced(unit(), slabMat, 30 * C);
  const wire = instanced(unit(), basic('#2a2d33'), 6 * C);
  const body = instanced(unit(), lambert(), 22 * C);
  const roof = instanced(unit(), lambert(), 44 * C);
  const hipG = new ConeGeometry(Math.SQRT1_2, 1, 4, 1);
  hipG.rotateY(Math.PI / 4);
  hipG.translate(0, 0.5, 0);
  const roofHip = instanced(hipG, lambert(), 16 * C);
  const awning = instanced(unit(), lambert(), 26 * C);
  const shutter = instanced(unit(), lambert(), 22 * C);
  const winMat = basic();
  const windows = instanced(unit(), winMat, 90 * C);
  const wall = instanced(unit(), lambert(), 40 * C);
  const crate = instanced(unit(), lambert(), 60 * C);
  const trunk = instanced(new CylinderGeometry(0.16, 0.24, 1, 6), lambert(), 30 * C);
  const canopy = instanced(new IcosahedronGeometry(1, 1), lambert(), 30 * C);
  const palmTop = instanced(new IcosahedronGeometry(1, 0), lambert(), 12 * C);
  const poleMat = lambert('#6d6a64');
  const lampPole = instanced(new CylinderGeometry(0.07, 0.1, 1, 6), poleMat, 8 * C);
  const lampArm = instanced(new BoxGeometry(1, 0.07, 0.07), poleMat, 16 * C);
  const bulbMat = basic('#d8d2c4');
  const lampHead = instanced(new BoxGeometry(0.5, 0.1, 0.22), bulbMat, 16 * C);
  const ePole = instanced(new CylinderGeometry(0.08, 0.11, 1, 6), lambert('#7d7468'), 10 * C);
  const eArm = instanced(new BoxGeometry(1.2, 0.07, 0.07), lambert('#6d6560'), 10 * C);
  const umbPole = instanced(new CylinderGeometry(0.03, 0.03, 1, 5), lambert('#555'), 20 * C);
  const umbTop = instanced(new ConeGeometry(1, 0.35, 8), lambert(), 20 * C);
  const shrub = instanced(new IcosahedronGeometry(1, 0), lambert(), 16 * C);
  const parked = instanced(vehicleGeometry('sedan').clone(), track(new MeshLambertMaterial({ vertexColors: true })), 6 * C);
  const dash = instanced(new BoxGeometry(0.14, 0.02, 2.6), basic('#e7e4da'), 2 * (PERIOD / 6) * C);

  const winRand: number[] = [];
  const winBase: Color[] = [];
  let dark = 0;
  const tmpC = new Color();
  const recolourWindows = () => {
    const night = dark > 0.45;
    for (let i = 0; i < winRand.length && i < windows.count; i++) {
      if (night) tmpC.set(winRand[i] < 0.55 ? '#ffd88a' : '#33383f');
      else tmpC.copy(winBase[i]);
      windows.setColorAt(i, tmpC);
    }
    if (windows.instanceColor) windows.instanceColor.needsUpdate = true;
  };
  const lampOn = new Color('#ffe3a0');
  const lampOff = new Color('#cfc9bb');

  let lastKey = '';
  const street: Street = {
    group,
    k0: Number.NaN,
    fill(spec, k0) {
      const key = `${spec.seed}|${k0}|${spec.u0b}|${spec.u1b}|${spec.u0a}|${spec.u1a}|${spec.plot?.join(',') ?? ''}`;
      if (key === lastKey) return;
      lastKey = key;
      street.k0 = k0;
      for (const im of ims) im.count = 0;
      winRand.length = 0;
      winBase.length = 0;
      const inB = (u: number, pad = 0) => u >= spec.u0b - pad && u <= spec.u1b + pad;
      for (let c = 0; c < C; c++) {
        const k = k0 + c;
        const uA = k * PERIOD;
        const uB = uA + PERIOD;
        const st = spec.styleAt(uA + PERIOD / 2);
        const D = DEF[st];
        const rr = rng((spec.seed * 7919 + k * 104729 + 13) >>> 0);
        // asphalt (with the cross-street stubs at the ends), road furniture only where the street is a street
        const a0 = Math.max(uA, spec.u0a);
        const a1 = Math.min(uB, spec.u1a);
        if (a1 > a0) place(slab, 0, 0.0, (a0 + a1) / 2, ROAD_HALF * 2, 0.06, a1 - a0 + 0.02, '#5b6068');
        const f0 = Math.max(uA, spec.u0b - 3);
        const f1 = Math.min(uB, spec.u1b + 3);
        if (f1 > f0) {
          const mu = (f0 + f1) / 2;
          const ml = f1 - f0 + 0.02;
          place(slab, 0, 0.1, mu, 1.3, 0.2, ml, '#b8b6ae'); // median kerb
          place(slab, 0, 0.2, mu, 0.8, 0.06, ml, '#6f8f5d'); // median planting
          for (const s of [-1, 1]) {
            place(slab, s * (ROAD_HALF + 1.7), 0.1, mu, 3.4, 0.2, ml, '#c4bcab'); // pavement
            place(slab, s * ROAD_HALF, 0.05, mu, 0.14, 0.06, ml, '#d9d6cc'); // edge line
            place(slab, s * (ROAD_HALF + 6.4), 0.01, mu, 6, 0.05, ml, D.lawn ? '#87a35f' : '#a08e6e'); // verge
            if (D.lawn) place(slab, s * (ROAD_HALF + 20), 0.012, mu, 30, 0.04, ml, '#87a35f');
            for (const [y, dx] of [[7.0, 0], [6.5, 0.5]] as const) place(wire, s * (ROAD_HALF + 2.6 + dx), y, mu, 0.03, 0.03, ml, '#ffffff');
          }
          // lane dashes
          for (let i = 0; i < PERIOD / 6; i++) {
            const du = uA + i * 6 + 1.5;
            if (du < spec.u0b || du > spec.u1b) continue;
            for (const x of [-4.1, 4.1]) place(dash, x, 0.075, du, 1, 1, 1, '#ffffff');
          }
        }
        for (const side of [-1, 1] as const) {
          // buildings along the frontage
          let u = uA + 2;
          while (u < uB - 6) {
            const w = D.w[0] + rr() * (D.w[1] - D.w[0]);
            const gap = rr();
            const wmid = u + w / 2;
            if (gap < D.gap + (1 - density) * 0.4) {
              if (rr() < 0.7 && inB(wmid) && !(side === 1 && spec.plot && wmid > spec.plot[0] && wmid < spec.plot[1])) {
                // open lot: a tree and a wall
                const tx = side * (ROAD_HALF + 5 + rr() * 2);
                const th = 2.6 + rr() * 1.4;
                place(trunk, tx, th / 2, wmid, 1, th, 1, '#6b523c');
                place(canopy, tx, th + 1.1, wmid, 2, 1.7, 2, TREE_G[Math.floor(rr() * TREE_G.length)]);
              }
              u += w + 2;
              continue;
            }
            const depth = D.depth[0] + rr() * (D.depth[1] - D.depth[0]);
            const storeys = Math.max(1, Math.floor(D.storeys[0] + rr() * rr() * (D.storeys[1] - D.storeys[0])));
            const h = storeys * 3.1 + 0.4;
            const setback = ROAD_HALF + 3.6 + D.setback[0] - 4.4 + 0.8 + rr() * (D.setback[1] - D.setback[0]);
            const cx = side * (setback + depth / 2);
            const wallC = D.walls[Math.floor(rr() * D.walls.length)];
            const roofC = D.roofs[Math.floor(rr() * D.roofs.length)];
            const hip = rr() < D.hip;
            const skip = !inB(wmid) || u + w > spec.u1b || u < spec.u0b || (side === 1 && spec.plot && u + w > spec.plot[0] && u < spec.plot[1]);
            if (!skip) {
              place(body, cx, h / 2, wmid, depth, h, w, wallC);
              if (hip && storeys <= 2) {
                const rh = Math.min(3.2, 1.2 + Math.min(w, depth) * 0.26);
                place(roofHip, cx, h, wmid, depth * 1.08, rh, w * 1.08, roofC);
              } else {
                place(roof, cx, h + 0.12, wmid, depth + 0.3, 0.24, w + 0.3, roofC);
                if (rr() < 0.4) place(roof, cx + side, h + 0.7, wmid, 1.4, 1.1, 1.4, '#7f8a92'); // water tank
              }
              const face = cx - side * (depth / 2 + 0.04);
              if (rr() < D.awn) place(awning, face - side * 0.5, 2.7, wmid, 1.1, 0.12, w * 0.86, AWNINGS[Math.floor(rr() * AWNINGS.length)]);
              if (rr() < D.shut) place(shutter, face, 1.35, wmid, 0.1, 2.5, w * 0.7, rr() < 0.5 ? '#65707a' : '#7d6a58');
              else if (st === 'gra' || st === 'campus') place(shutter, face, 1.3, wmid, 0.1, 2.2, Math.min(w * 0.6, 5), '#8aa7b8'); // glazed front
              for (let s = st === 'gra' || st === 'campus' ? 0 : 1; s < storeys; s++) {
                const nw = Math.max(1, Math.floor(w / 2.6));
                for (let q = 0; q < nw; q++) {
                  const wz = wmid - w / 2 + (w / nw) * (q + 0.5);
                  place(windows, face, s * 3.1 + 1.7, wz, 0.1, 1.15, 1.2, '#ffffff');
                  winRand.push(rr());
                  winBase.push(new Color().setHSL(0.56 + rr() * 0.04, 0.18, 0.62 + rr() * 0.1));
                }
              }
              if (rr() < D.wallProb) place(wall, side * (setback - 0.3), st === 'gra' ? 1.1 : 0.7, wmid - w / 2 - 0.6, 0.25, st === 'gra' ? 2.2 : 1.4, 1.2, '#cfc6b4');
              if (st === 'gra') {
                // gate pillars and a hedge to the road
                place(wall, side * (ROAD_HALF + 3.9), 1.2, wmid, 0.9, 2.4, 0.9, '#e9e2d0');
                place(shrub, side * (ROAD_HALF + 3.3), 0.7, wmid + 2.2, 0.9, 0.75, 0.9, '#4f7a47');
              }
            }
            u += w + 0.6 + rr() * 1.4;
          }
          // market stalls on the pavement: table, tarp canopy, crates
          const ns = Math.round(D.stalls * density);
          for (let i = 0; i < ns; i++) {
            const su = uA + 3 + (i + rr() * 0.6) * ((PERIOD - 6) / Math.max(1, ns));
            if (!inB(su, -2) || (side === 1 && spec.plot && su > spec.plot[0] - 4 && su < spec.plot[1] + 4)) continue;
            const sx = side * (ROAD_HALF + 2.4 + rr() * 0.5);
            place(crate, sx, 0.45, su, 1.6, 0.9, 2.0, rr() < 0.5 ? '#9c7a4f' : '#b08c5d');
            place(awning, sx, 2.15, su, 2.2, 0.1, 2.5, STALL[Math.floor(rr() * STALL.length)]);
            place(umbPole, sx - side * 0.8, 1.1, su - 0.9, 1.4, 2.2, 1.4, '#ffffff');
            place(umbPole, sx + side * 0.8, 1.1, su + 0.9, 1.4, 2.2, 1.4, '#ffffff');
            place(crate, sx + side * 0.2, 1.0, su, 0.7, 0.3, 0.7, STALL[Math.floor(rr() * STALL.length)]);
          }
          // trees on the pavement, palms and mango
          const nt = Math.round((D.trees[0] + rr() * (D.trees[1] - D.trees[0])) * density);
          for (let i = 0; i < nt; i++) {
            const tu = uA + 2 + rr() * (PERIOD - 4);
            const tx = side * (ROAD_HALF + 2.2 + rr() * 0.8);
            if (!inB(tu, 2) || (side === 1 && spec.plot && tu > spec.plot[0] && tu < spec.plot[1])) continue;
            if (rr() < D.palms) {
              const th = 5 + rr() * 2.5;
              place(trunk, tx, th / 2, tu, 0.7, th, 0.7, '#8a6c4a');
              place(palmTop, tx, th + 0.2, tu, 1.7, 0.55, 1.7, '#4d7f45');
            } else {
              const th = 2.4 + rr() * 1.2;
              const cr = 1.7 + rr() * 1.1;
              place(trunk, tx, th / 2, tu, 1, th, 1, '#6b523c');
              place(canopy, tx, th + cr * 0.6, tu, cr, cr * 0.8, cr, TREE_G[Math.floor(rr() * TREE_G.length)]);
            }
          }
          // electric poles with cross arms, every 30 m
          for (let q = 0; q < 2; q++) {
            const pu = uA + 8 + q * 30;
            if (!inB(pu, 2)) continue;
            const px = side * (ROAD_HALF + 2.6);
            place(ePole, px, 4, pu, 1, 8, 1, '#ffffff');
            place(eArm, px + side * 0.25, 7.1, pu, 1, 1, 1, '#ffffff');
          }
          // umbrellas (hawkers, pure-water and recharge-card stalls)
          const nu = Math.round(D.umb * density + rr());
          for (let i = 0; i < nu; i++) {
            const uu = uA + 4 + rr() * (PERIOD - 8);
            const ux = side * (ROAD_HALF + 3.0 + rr() * 0.5);
            if (!inB(uu, -2) || (side === 1 && spec.plot && uu > spec.plot[0] - 3 && uu < spec.plot[1] + 3)) continue;
            place(umbPole, ux, 1.0, uu, 1, 2, 1, '#ffffff');
            place(umbTop, ux, 2.1, uu, 1.1, 1, 1.1, UMB[Math.floor(rr() * UMB.length)]);
          }
          // parked cars along the kerb
          if (rr() < D.parked * density + 0.05) {
            const pu = uA + 6 + rr() * (PERIOD - 14);
            if (inB(pu, -3) && !(side === 1 && spec.plot && pu > spec.plot[0] - 4 && pu < spec.plot[1] + 4)) {
              dummy.position.set(side * (ROAD_HALF + 1.4), 0, -pu);
              dummy.rotation.set(0, side > 0 ? 0 : Math.PI, 0);
              dummy.scale.set(1, 1, 1);
              dummy.updateMatrix();
              if (parked.count < parked.instanceMatrix.count) {
                parked.setMatrixAt(parked.count, dummy.matrix);
                parked.setColorAt(parked.count, col.set(WALLS[Math.floor(rr() * WALLS.length)]).offsetHSL(0, 0, -0.08));
                parked.count++;
              }
            }
          }
        }
        // median: lamps every 30 m, shrubs between
        for (let q = 0; q < 2; q++) {
          const lu = uA + 6 + q * 30;
          if (!inB(lu, 2)) continue;
          place(lampPole, 0, 4.2, lu, 1, 8.4, 1, '#ffffff');
          place(lampArm, -1.1, 8.3, lu, 2.2, 1, 1, '#ffffff');
          place(lampArm, 1.1, 8.3, lu, 2.2, 1, 1, '#ffffff');
          place(lampHead, -2.0, 8.2, lu, 1, 1, 1, '#ffffff');
          place(lampHead, 2.0, 8.2, lu, 1, 1, 1, '#ffffff');
        }
        for (let q = 0; q < Math.round(4 * density); q++) {
          const su = uA + 3 + q * 15;
          if (inB(su, 0)) place(shrub, 0, 0.45, su, 0.45, 0.4, 0.45, TREE_G[q % TREE_G.length]);
        }
      }
      for (const im of ims) {
        im.instanceMatrix.needsUpdate = true;
        if (im.instanceColor) im.instanceColor.needsUpdate = true;
      }
      recolourWindows();
    },
    setDark(d) {
      const bucket = Math.round(d * 8) + (d > 0.45 ? 100 : 0);
      const prev = Math.round(dark * 8) + (dark > 0.45 ? 100 : 0);
      dark = d;
      bulbMat.color.copy(lampOff).lerp(lampOn, d);
      if (bucket !== prev) recolourWindows();
    },
    setWet(w) {
      slabMat.color.setScalar(1 - 0.3 * w);
      slabMat.emissive.set('#6d8aa6').multiplyScalar(0.13 * w);
    },
    dispose() {
      disposables.forEach((d) => d.dispose());
    },
  };
  return street;
}

// ---------------------------------------------------------------- junctions and the roundabout (built once per track)
export interface JunctionSpec {
  kind: 'turn' | 'round';
  x: number;
  z: number;
  island: number;
  outer: number;
  /** Roundabout: directions (radians from +x towards +z) the streets leave in, kept clear of buildings. */
  avoid?: number[];
  /** Turn: dashes of the turning lane along the car's path: x, z, heading. */
  guide?: [number, number, number][];
}

/** Asphalt patches where the road turns and the roundabout (island with planting, kerb, lane dashes). In world coordinates. */
export function buildJunctions(list: JunctionSpec[]): { group: Group; dispose(): void } | null {
  if (!list.length) return null;
  const b = new ColorBatch();
  for (const j of list) {
    if (j.kind === 'turn') {
      b.add(new CylinderGeometry(15, 15, 0.1, 28), '#c4bcab', j.x, 0.03, j.z);
      b.add(new CylinderGeometry(11.2, 11.2, 0.1, 28), '#5b6068', j.x, 0.04, j.z);
      for (const [gx, gz, gp] of j.guide ?? []) b.add(new BoxGeometry(0.14, 0.02, 1.3), '#e7e4da', gx, 0.1, gz, 0, -gp, 0);
    } else {
      b.add(new CylinderGeometry(j.outer + 3.5, j.outer + 3.5, 0.1, 40), '#c4bcab', j.x, 0.03, j.z);
      b.add(new CylinderGeometry(j.outer, j.outer, 0.1, 40), '#5b6068', j.x, 0.04, j.z);
      b.add(new CylinderGeometry(j.island + 0.7, j.island + 0.7, 0.4, 28), '#cfcabb', j.x, 0.2, j.z);
      b.add(new CylinderGeometry(j.island - 0.2, j.island - 0.2, 0.46, 28), '#6f8f5d', j.x, 0.2, j.z);
      // lane dashes round the ring
      const R = 22;
      for (let i = 0; i < 28; i++) {
        const a = (i / 28) * Math.PI * 2;
        b.add(new BoxGeometry(0.16, 0.02, 1.6), '#e7e4da', j.x + Math.cos(a) * R, 0.1, j.z + Math.sin(a) * R, 0, -a, 0);
      }
      // a ring of shop-houses, trees and walls round the roundabout, leaving the street mouths open
      const rr = rng(Math.round(j.x * 7 + j.z * 13) >>> 0);
      const avoid = j.avoid ?? [];
      const angDiff = (a: number, b: number) => Math.abs(Math.atan2(Math.sin(a - b), Math.cos(a - b)));
      for (let i = 0; i < 22; i++) {
        const a = (i / 22) * Math.PI * 2 + rr() * 0.12;
        if (avoid.some((q) => angDiff(a, q) < 0.5)) continue;
        const r = j.outer + 14 + rr() * 6;
        const w = 9 + rr() * 6;
        const d = 8 + rr() * 5;
        const h = 4 + Math.floor(rr() * rr() * 4) * 3.1;
        const cx = j.x + Math.cos(a) * r;
        const cz = j.z + Math.sin(a) * r;
        const wc = ['#e4e0d6', '#d9d4c6', '#cfd2d0', '#e7dfca', '#d8ccb2', '#c8b697'][Math.floor(rr() * 6)];
        // the long side faces the roundabout
        b.add(new BoxGeometry(d, h, w), wc, cx, h / 2, cz, 0, -a, 0);
        b.add(new BoxGeometry(d + 0.3, 0.24, w + 0.3), ['#8f979c', '#7e878c', '#9aa2a6', '#7d5a48'][Math.floor(rr() * 4)], cx, h + 0.12, cz, 0, -a, 0);
        b.add(new BoxGeometry(0.1, 2.5, w * 0.7), '#65707a', cx - Math.cos(a) * (d / 2 + 0.03), 1.3, cz - Math.sin(a) * (d / 2 + 0.03), 0, -a, 0);
        if (rr() < 0.55) {
          const tr = r - d / 2 - 3.2;
          const tx = j.x + Math.cos(a + 0.1) * tr;
          const tz = j.z + Math.sin(a + 0.1) * tr;
          b.add(new CylinderGeometry(0.22, 0.3, 5.6, 6), '#8a6c4a', tx, 2.8, tz);
          b.add(new ConeGeometry(2, 0.7, 7), '#4d7f45', tx, 5.8, tz);
        }
      }
      // palms and shrubs on the island
      for (let i = 0; i < 6; i++) {
        const a = (i / 6) * Math.PI * 2 + 0.3;
        const r = j.island - 3.3;
        const th = 5 + (i % 3) * 0.8;
        b.add(new CylinderGeometry(0.2, 0.3, th, 6), '#8a6c4a', j.x + Math.cos(a) * r, th / 2 + 0.4, j.z + Math.sin(a) * r);
        b.add(new ConeGeometry(1.8, 0.6, 7), '#4d7f45', j.x + Math.cos(a) * r, th + 0.6, j.z + Math.sin(a) * r);
      }
    }
  }
  const built = b.build();
  if (!built) return null;
  const group = new Group();
  group.add(built.mesh);
  return {
    group,
    dispose() {
      built.geometry.dispose();
      built.material.dispose();
    },
  };
}
