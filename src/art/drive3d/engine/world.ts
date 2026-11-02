// The roadside world of the drive scene: a dual carriageway with a median, shop-houses, compound walls, trees, lamps,
// electric poles, umbrellas and parked cars. Everything repeats every PERIOD metres and is built once as a handful of
// InstancedMeshes, so the whole street is ~20 draw calls. The scene scrolls the `scroll` group by (distance mod PERIOD),
// which makes the street endless. Colours are muted real-world ones (laterite, cream, grey-green), no brands.
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
export const COPIES = 4;
export const ROAD_HALF = 7.2;
export const LANE_IN = 2.6;
export const LANE_OUT = 5.6;

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

export interface World {
  /** Add to the scene; position.z = distance mod PERIOD. */
  scroll: Group;
  /** Static meshes (ground, road): never moves. */
  fixed: Group;
  /** Update the lit windows, lamps and awnings for a darkness 0..1. */
  setDark(dark: number): void;
  /** Whole-world vertical tint for the ground and road by day/night is done by lighting, not here. */
  dispose(): void;
}

interface Opts {
  seed: number;
  /** 1 = full density, 0.55 = low tier. */
  density: number;
}

export function buildWorld({ seed, density }: Opts): World {
  const scroll = new Group();
  const fixed = new Group();
  const disposables: { dispose(): void }[] = [];
  const track = <T extends { dispose(): void }>(o: T): T => {
    disposables.push(o);
    return o;
  };
  const lambert = (hex = '#ffffff') => track(new MeshLambertMaterial({ color: hex }));
  const basic = (hex = '#ffffff') => track(new MeshBasicMaterial({ color: hex }));

  // ---------- static ground, road, kerbs: merged into two draw calls ----------
  const lit = new ColorBatch();
  const wires = new ColorBatch();
  const slab = (w: number, d: number, x: number, y: number, z: number, hex: string, h = 0.04) => {
    lit.add(new BoxGeometry(w, h, d), hex, x, y - h / 2, z);
  };
  const LEN = PERIOD * COPIES * 1.8;
  slab(900, LEN, 0, 0, -LEN * 0.35, '#b3a281', 0.1); // ground
  slab(ROAD_HALF * 2, LEN, 0, 0.03, -LEN * 0.35, '#5b6068'); // asphalt
  slab(1.3, LEN, 0, 0.12, -LEN * 0.35, '#b8b6ae', 0.2); // median kerb
  slab(0.8, LEN, 0, 0.2, -LEN * 0.35, '#6f8f5d', 0.06); // median planting
  for (const s of [-1, 1]) {
    slab(3.4, LEN, s * (ROAD_HALF + 1.7), 0.1, -LEN * 0.35, '#c4bcab', 0.2); // pavement
    slab(0.14, LEN, s * ROAD_HALF, 0.03, -LEN * 0.35, '#d9d6cc', 0.05); // edge line
    slab(6, LEN, s * (ROAD_HALF + 6.4), 0.02, -LEN * 0.35, '#a08e6e', 0.05); // laterite verge
    // electric cables run straight through the poles
    for (const [y, dx] of [[7.0, 0], [6.5, 0.5]] as const) wires.add(new BoxGeometry(0.03, 0.03, LEN), '#2a2d33', s * (ROAD_HALF + 2.6 + dx), y, -LEN * 0.35);
  }
  const fixedLit = lit.build();
  if (fixedLit) {
    fixed.add(fixedLit.mesh);
    track(fixedLit.geometry);
    track(fixedLit.material);
  }
  const fixedWires = wires.build(new MeshBasicMaterial({ vertexColors: true }));
  if (fixedWires) {
    fixed.add(fixedWires.mesh);
    track(fixedWires.geometry);
    track(fixedWires.material);
  }

  const dummy = new Object3D();
  const instanced = (g: BufferGeometry, m: Material, count: number) => {
    const im = new InstancedMesh(track(g), m, Math.max(1, count));
    im.frustumCulled = false;
    im.count = 0;
    scroll.add(im);
    return im;
  };
  const place = (im: InstancedMesh, x: number, y: number, z: number, sx: number, sy: number, sz: number, hex: string, ry = 0) => {
    dummy.position.set(x, y, z);
    dummy.rotation.set(0, ry, 0);
    dummy.scale.set(sx, sy, sz);
    dummy.updateMatrix();
    im.setMatrixAt(im.count, dummy.matrix);
    im.setColorAt(im.count, new Color(hex));
    im.count++;
  };
  const done = (im: InstancedMesh) => {
    im.instanceMatrix.needsUpdate = true;
    if (im.instanceColor) im.instanceColor.needsUpdate = true;
  };

  const MAXB = 18 * COPIES;
  const body = instanced(new BoxGeometry(1, 1, 1), lambert(), MAXB);
  const roof = instanced(new BoxGeometry(1, 1, 1), lambert(), MAXB * 2);
  const awning = instanced(new BoxGeometry(1, 1, 1), lambert(), MAXB);
  const shutter = instanced(new BoxGeometry(1, 1, 1), lambert(), MAXB);
  const winMat = basic();
  const windows = instanced(new BoxGeometry(1, 1, 1), winMat, MAXB * 6);
  const winRand: number[] = [];
  const winBase: Color[] = [];
  const wall = instanced(new BoxGeometry(1, 1, 1), lambert(), 40 * COPIES);
  const trunk = instanced(new CylinderGeometry(0.16, 0.24, 1, 6), lambert(), 24 * COPIES);
  const canopy = instanced(new IcosahedronGeometry(1, 1), lambert(), 24 * COPIES);
  const palmTop = instanced(new IcosahedronGeometry(1, 0), lambert(), 8 * COPIES);
  const poleMat = lambert('#6d6a64');
  const lampPole = instanced(new CylinderGeometry(0.07, 0.1, 1, 6), poleMat, 8 * COPIES);
  const lampArm = instanced(new BoxGeometry(1, 0.07, 0.07), poleMat, 16 * COPIES);
  const bulbMat = basic('#d8d2c4');
  const lampHead = instanced(new BoxGeometry(0.5, 0.1, 0.22), bulbMat, 16 * COPIES);
  const ePole = instanced(new CylinderGeometry(0.08, 0.11, 1, 6), lambert('#7d7468'), 10 * COPIES);
  const eArm = instanced(new BoxGeometry(1.2, 0.07, 0.07), lambert('#6d6560'), 10 * COPIES);
  const umbPole = instanced(new CylinderGeometry(0.03, 0.03, 1, 5), lambert('#555'), 12 * COPIES);
  const umbTop = instanced(new ConeGeometry(1, 0.35, 8), lambert(), 12 * COPIES);
  const shrub = instanced(new IcosahedronGeometry(1, 0), lambert(), 14 * COPIES);
  const parked = instanced(vehicleGeometry('sedan').clone(), track(new MeshLambertMaterial({ vertexColors: true })), 6 * COPIES);

  for (let c = 0; c < COPIES; c++) {
    const z0 = -c * PERIOD; // copy c covers z in (z0 - PERIOD, z0]
    const rr = rng(seed + 11); // identical layout for every copy: the street is periodic
    for (const side of [-1, 1] as const) {
      // buildings along the frontage
      let z = -2;
      while (z > -PERIOD + 6) {
        const w = 6 + rr() * 6.5;
        const gap = rr();
        if (gap < 0.2 + (1 - density) * 0.45) {
          // open lot: a tree and a wall, no building
          z -= w + 2;
          continue;
        }
        const depth = 9 + rr() * 6;
        const storeys = 1 + Math.floor(rr() * rr() * 4.2);
        const h = storeys * 3.1 + 0.4;
        const setback = ROAD_HALF + 3.6 + 0.8 + rr() * 2.6;
        const cx = side * (setback + depth / 2);
        const cz = z0 + z - w / 2;
        const wallC = WALLS[Math.floor(rr() * WALLS.length)];
        place(body, cx, h / 2, cz, depth, h, w, wallC);
        place(roof, cx, h + 0.12, cz, depth + 0.3, 0.24, w + 0.3, ROOFS[Math.floor(rr() * ROOFS.length)]);
        if (rr() < 0.4) place(roof, cx + side * 1, h + 0.7, cz, 1.4, 1.1, 1.4, '#7f8a92'); // water tank
        const face = cx - side * (depth / 2 + 0.04); // wall facing the road
        // shop front: awning + shutter on the ground floor
        place(awning, face - side * 0.5, 2.7, cz, 1.1, 0.12, w * 0.86, AWNINGS[Math.floor(rr() * AWNINGS.length)]);
        place(shutter, face, 1.35, cz, 0.1, 2.5, w * 0.7, rr() < 0.5 ? '#65707a' : '#7d6a58');
        for (let s = 1; s < storeys; s++) {
          const nw = Math.max(1, Math.floor(w / 2.6));
          for (let k = 0; k < nw; k++) {
            const wz = cz - w / 2 + (w / nw) * (k + 0.5);
            place(windows, face, s * 3.1 + 1.7, wz, 0.1, 1.15, 1.2, '#ffffff');
            winRand.push(rr());
            winBase.push(new Color().setHSL(0.56 + rr() * 0.04, 0.18, 0.62 + rr() * 0.1));
          }
        }
        // compound wall between neighbours
        if (rr() < 0.55) place(wall, side * (setback - 0.3), 0.7, cz - w / 2 - 0.6, 0.25, 1.4, 1.2, '#cfc6b4');
        z -= w + 0.6 + rr() * 1.4;
      }
      // trees on the pavement, palms and mango
      const nt = Math.round((3 + rr() * 2) * density);
      for (let i = 0; i < nt; i++) {
        const tz = z0 - 2 - rr() * (PERIOD - 4);
        const tx = side * (ROAD_HALF + 2.2 + rr() * 0.8);
        const palm = rr() < 0.3;
        if (palm) {
          const th = 5 + rr() * 2.5;
          place(trunk, tx, th / 2, tz, 0.7, th, 0.7, '#8a6c4a');
          place(palmTop, tx, th + 0.2, tz, 1.7, 0.55, 1.7, '#4d7f45');
        } else {
          const th = 2.4 + rr() * 1.2;
          const cr = 1.7 + rr() * 1.1;
          place(trunk, tx, th / 2, tz, 1, th, 1, '#6b523c');
          place(canopy, tx, th + cr * 0.6, tz, cr, cr * 0.8, cr, TREE_G[Math.floor(rr() * TREE_G.length)]);
        }
      }
      // electric poles with cross arms, every 30 m
      for (let k = 0; k < 2; k++) {
        const pz = z0 - 8 - k * 30;
        const px = side * (ROAD_HALF + 2.6);
        place(ePole, px, 4, pz, 1, 8, 1, '#ffffff');
        place(eArm, px + side * 0.25, 7.1, pz, 1, 1, 1, '#ffffff');
      }
      // umbrellas (hawkers, pure-water and recharge-card stalls)
      const nu = Math.round(2 * density + rr());
      for (let i = 0; i < nu; i++) {
        const uz = z0 - 4 - rr() * (PERIOD - 8);
        const ux = side * (ROAD_HALF + 3.0 + rr() * 0.5);
        place(umbPole, ux, 1.0, uz, 1, 2, 1, '#ffffff');
        place(umbTop, ux, 2.1, uz, 1.1, 1, 1.1, UMB[Math.floor(rr() * UMB.length)]);
      }
      // parked cars along the kerb
      if (rr() < 0.85 * density + 0.1) {
        const pz = z0 - 6 - rr() * (PERIOD - 14);
        dummy.position.set(side * (ROAD_HALF + 1.4), 0, pz);
        dummy.rotation.set(0, side > 0 ? 0 : Math.PI, 0);
        dummy.scale.set(1, 1, 1);
        dummy.updateMatrix();
        parked.setMatrixAt(parked.count, dummy.matrix);
        parked.setColorAt(parked.count, new Color(WALLS[Math.floor(rr() * WALLS.length)]).offsetHSL(0, 0, -0.08));
        parked.count++;
      }
    }
    // median: lamps every 30 m, shrubs between
    for (let k = 0; k < 2; k++) {
      const lz = z0 - 6 - k * 30;
      place(lampPole, 0, 4.2, lz, 1, 8.4, 1, '#ffffff');
      place(lampArm, -1.1, 8.3, lz, 2.2, 1, 1, '#ffffff');
      place(lampArm, 1.1, 8.3, lz, 2.2, 1, 1, '#ffffff');
      place(lampHead, -2.0, 8.2, lz, 1, 1, 1, '#ffffff');
      place(lampHead, 2.0, 8.2, lz, 1, 1, 1, '#ffffff');
    }
    for (let k = 0; k < 4 * density; k++) place(shrub, 0, 0.45, z0 - 3 - k * 15, 0.45, 0.4, 0.45, TREE_G[k % TREE_G.length]);
  }
  [body, roof, awning, shutter, windows, wall, trunk, canopy, palmTop, lampPole, lampArm, lampHead, ePole, eArm, umbPole, umbTop, shrub, parked].forEach(done);

  // lane dashes (instanced), one per 6 m on both lane boundaries
  const dash = instanced(new BoxGeometry(0.14, 0.02, 2.6), basic('#e7e4da'), 2 * (PERIOD / 6) * COPIES);
  for (let c = 0; c < COPIES; c++) for (let i = 0; i < PERIOD / 6; i++) for (const x of [-4.1, 4.1]) place(dash, x, 0.075, -c * PERIOD - i * 6 - 1.5, 1, 1, 1, '#ffffff');
  done(dash);

  const lampOn = new Color('#ffe3a0');
  const lampOff = new Color('#cfc9bb');
  const tmpC = new Color();
  let lastBucket = -1;
  return {
    scroll,
    fixed,
    setDark(dark: number) {
      const bucket = Math.round(dark * 8) + (dark > 0.45 ? 100 : 0);
      if (bucket === lastBucket) return;
      lastBucket = bucket;
      bulbMat.color.copy(lampOff).lerp(lampOn, dark);
      const night = dark > 0.45;
      for (let i = 0; i < winRand.length; i++) {
        if (night) tmpC.set(winRand[i] < 0.55 ? '#ffd88a' : '#33383f');
        else tmpC.copy(winBase[i]);
        windows.setColorAt(i, tmpC);
      }
      if (windows.instanceColor) windows.instanceColor.needsUpdate = true;
    },
    dispose() {
      disposables.forEach((d) => d.dispose());
    },
  };
}
