// Road-event props, the destination gate, road signs and the inside-the-car cockpit. All procedural (docs/DRIVE.md).
import {
  BoxGeometry,
  CanvasTexture,
  Color,
  ConeGeometry,
  CylinderGeometry,
  DoubleSide,
  Group,
  InstancedMesh,
  Mesh,
  MeshBasicMaterial,
  MeshLambertMaterial,
  Object3D,
  PlaneGeometry,
  SRGBColorSpace,
  TorusGeometry,
} from 'three';
import type { DriveKind } from '../../../api/drive';
import type { VehicleKind } from '../model';
import { ColorBatch, MatBatch } from './batch';
import { figure, vehicleGeometry } from './vehicles';
import { LANE_IN, LANE_OUT, ROAD_HALF } from './world';

// ---------------------------------------------------------------- signs
const texCache = new Map<string, CanvasTexture>();

/** A road sign texture: a green board with white lines (real road names only). */
export function signTexture(line1: string, line2: string, tone: 'green' | 'blue' = 'green'): CanvasTexture {
  const key = `${tone}|${line1}|${line2}`;
  const hit = texCache.get(key);
  if (hit) return hit;
  const c = document.createElement('canvas');
  c.width = 512;
  c.height = 160;
  const g = c.getContext('2d')!;
  g.fillStyle = tone === 'green' ? '#2c6b47' : '#2b5c8f';
  g.fillRect(0, 0, 512, 160);
  g.strokeStyle = '#f2f0e8';
  g.lineWidth = 6;
  g.strokeRect(8, 8, 496, 144);
  g.fillStyle = '#f6f4ec';
  g.textAlign = 'center';
  g.textBaseline = 'middle';
  let size = 54;
  g.font = `700 ${size}px "Outfit","Segoe UI",system-ui,sans-serif`;
  while (g.measureText(line1).width > 450 && size > 26) {
    size -= 2;
    g.font = `700 ${size}px "Outfit","Segoe UI",system-ui,sans-serif`;
  }
  g.fillText(line1, 256, line2 ? 64 : 80);
  if (line2) {
    g.font = `500 34px "Figtree","Segoe UI",system-ui,sans-serif`;
    g.globalAlpha = 0.9;
    g.fillText(line2, 256, 116);
  }
  const t = new CanvasTexture(c);
  t.colorSpace = SRGBColorSpace;
  t.anisotropy = 2;
  texCache.set(key, t);
  return t;
}

/** A sign on two poles, facing +z (toward the oncoming driver). */
export function buildSign(): { group: Group; board: Mesh; setText(l1: string, l2: string, tone?: 'green' | 'blue'): void } {
  const group = new Group();
  const pm = new MeshLambertMaterial({ color: '#7b8088' });
  for (const x of [-1.5, 1.5]) {
    const p = new Mesh(new CylinderGeometry(0.06, 0.06, 3.4, 6), pm);
    p.position.set(x, 1.7, 0);
    group.add(p);
  }
  const board = new Mesh(new PlaneGeometry(4.2, 1.31), new MeshBasicMaterial({ side: DoubleSide }));
  board.position.set(0, 3.5, 0.05);
  group.add(board);
  return {
    group,
    board,
    setText(l1, l2, tone = 'green') {
      (board.material as MeshBasicMaterial).map = signTexture(l1, l2, tone);
      (board.material as MeshBasicMaterial).needsUpdate = true;
    },
  };
}

// ---------------------------------------------------------------- shared small materials
const lam = (hex: string) => new MeshLambertMaterial({ color: hex });
const figMat = new MeshLambertMaterial({ vertexColors: true });
const SHIRTS = [0xb8553f, 0x4f7ca8, 0xc9a24a, 0x6a8f5c, 0x8a6a9a, 0xd8d2c4];
const SKINS = [0x6a4630, 0x7a5236, 0x59382a, 0x8a5e40];

function mesh(g: ConstructorParameters<typeof Mesh>[0], m: ConstructorParameters<typeof Mesh>[1], x: number, y: number, z: number) {
  const o = new Mesh(g, m);
  o.position.set(x, y, z);
  return o;
}

export interface EventProps {
  group: Group;
  /** Called every frame. `resolved` is true once the player has chosen; `t` seconds since the props appeared. */
  update(dt: number, t: number, resolved: boolean, ok: boolean): void;
  /** Distance (m) before the props at which the car should stop. */
  gap: number;
  /** The lane the car should stop in. */
  lane: number;
  /** Crawl speed (m/s) the props move forward at after the choice (queue pulling away); 0 = they stay. */
  leaves: number;
  dispose(): void;
}

export function buildEventProps(kind: DriveKind, seed: number): EventProps {
  const group = new Group();
  const geos: { dispose(): void }[] = [];
  const upd: ((dt: number, t: number, resolved: boolean, ok: boolean) => void)[] = [];
  const track = <T extends { dispose(): void }>(o: T) => {
    geos.push(o);
    return o;
  };
  let gap = 8;
  let lane = LANE_OUT;
  let leaves = 0;

  if (kind === 'ambush') {
    gap = 7;
    const plankM = lam('#8a6a48');
    const tyreM = lam('#1f2024');
    const plank = mesh(track(new BoxGeometry(6.4, 0.16, 0.34)), plankM, 3.9, 0.5, -1.6);
    group.add(plank);
    for (const x of [1.4, 6.4]) group.add(mesh(track(new CylinderGeometry(0.42, 0.42, 0.34, 10)), tyreM, x, 0.17, -1.6));
    const figs: Mesh[] = [];
    [LANE_IN - 0.5, LANE_IN + 2.0, LANE_OUT + 0.7].forEach((x, i) => {
      const g = track(figure(SHIRTS[(seed + i) % SHIRTS.length], SKINS[(seed + i) % SKINS.length], { arms: i !== 1 }));
      const f = new Mesh(g, figMat);
      f.position.set(x, 0, -2.6 - i * 0.4);
      f.rotation.y = Math.PI;
      f.userData.x0 = x;
      f.userData.side = x > 3.5 ? 1 : -1;
      group.add(f);
      figs.push(f);
    });
    upd.push((dt, t, resolved) => {
      const a = Math.min(1, dt * 3);
      for (const f of figs) {
        const tx = resolved ? (f.userData.side > 0 ? ROAD_HALF + 2.4 : -0.2 + (f.userData.x0 < 1 ? -0.4 : 0)) : f.userData.x0;
        f.position.x += (tx - f.position.x) * a;
        f.position.y = resolved ? 0 : Math.abs(Math.sin(t * 5 + f.userData.x0)) * 0.05; // restless
      }
      plank.scale.y = resolved ? Math.max(0.001, plank.scale.y - dt * 4) : 1;
      plank.visible = plank.scale.y > 0.01;
    });
  } else if (kind === 'police') {
    gap = 9;
    const coneG = track(new ConeGeometry(0.28, 0.7, 8));
    const coneM = lam('#d8643a');
    const cones: Mesh[] = [];
    [1.0, 2.2, 3.4, 4.1, 7.0].forEach((x, i) => {
      const c = mesh(coneG, coneM, x, 0.35, -1.6 + (i === 0 ? 0 : -0.2));
      group.add(c);
      cones.push(c);
    });
    const unif = 0x3c5878;
    const officers: Mesh[] = [];
    [4.6, 7.3].forEach((x, i) => {
      const f = new Mesh(track(figure(unif, SKINS[(seed + i) % SKINS.length], { cap: 0x23303f, arms: i === 0 })), figMat);
      f.position.set(x, 0, -1.8);
      f.rotation.y = Math.PI;
      group.add(f);
      officers.push(f);
    });
    // a police pickup parked beside the road with a light bar
    const veh = new Mesh(vehicleGeometry('pickup'), new MeshLambertMaterial({ vertexColors: true, color: '#dfe5ea' }));
    veh.position.set(ROAD_HALF + 1.6, 0, -4.8);
    veh.rotation.y = 0.18;
    group.add(veh);
    const redM = new MeshBasicMaterial({ color: '#d2423a' });
    const blueM = new MeshBasicMaterial({ color: '#3a6cd2' });
    const lbG = track(new BoxGeometry(0.4, 0.12, 0.3));
    const lbR = mesh(lbG, redM, ROAD_HALF + 1.45, 1.85, -4.35);
    const lbB = mesh(lbG, blueM, ROAD_HALF + 1.8, 1.85, -4.3);
    group.add(lbR, lbB);
    const sign = buildSign();
    sign.setText('POLICE', 'Checkpoint', 'blue');
    sign.group.position.set(-0.2, 0, 4);
    sign.group.scale.setScalar(0.8);
    group.add(sign.group);
    upd.push((_dt, t, resolved) => {
      lbR.visible = Math.floor(t * 4) % 2 === 0;
      lbB.visible = !lbR.visible;
      officers[0].rotation.y = Math.PI + (resolved ? Math.sin(t * 6) * 0.2 : 0);
      for (const c of cones) c.visible = !(resolved && c.position.x < 3);
    });
    lane = LANE_OUT;
  } else if (kind === 'goslow') {
    gap = 16;
    leaves = 5;
    const kinds: VehicleKind[] = ['sedan', 'keke', 'suv', 'bus', 'sedan', 'keke', 'pickup', 'sedan'];
    const COLS = [0xc3c7cd, 0x4a5d7a, 0xa23c36, 0xefebe0, 0x5a8068, 0xaab3bd, 0x9a7650];
    const spots: { k: VehicleKind; x: number; z: number; c: number }[] = [];
    let z = -4;
    for (let i = 0; i < 12; i++) {
      for (const x of [LANE_IN, LANE_OUT]) {
        if ((i + (x > 3 ? 1 : 0) + seed) % 3 === 0 && i > 1) continue;
        const k = kinds[(i * 2 + (x > 3 ? 1 : 0) + seed) % kinds.length];
        const col = k === 'keke' ? 0xe3b53c : k === 'bus' ? 0xe9e6dc : COLS[(i + seed) % COLS.length];
        spots.push({ k, x: x + (((i * 37 + seed) % 7) - 3) * 0.06, z: z - ((i * 13) % 5) * 0.4, c: col });
      }
      z -= 6.2 + (i % 3);
    }
    // okada riders weaving at the edge
    for (let i = 0; i < 3; i++) spots.push({ k: i === 1 ? ('okada2' as VehicleKind) : 'moto', x: 4.1 + (i - 1) * 0.35, z: -10 - i * 14, c: 0x8f98a4 });
    const qMat = track(new MeshLambertMaterial({ vertexColors: true }));
    const dm = new Object3D();
    for (const k of new Set(spots.map((sp) => sp.k))) {
      const list = spots.filter((sp) => sp.k === k);
      const im = new InstancedMesh(vehicleGeometry(k), qMat, list.length);
      list.forEach((sp, i) => {
        dm.position.set(sp.x, 0, sp.z);
        dm.rotation.set(0, 0, 0);
        dm.updateMatrix();
        im.setMatrixAt(i, dm.matrix);
        im.setColorAt(i, new Color(sp.c));
      });
      im.frustumCulled = false;
      group.add(im);
      geos.push({ dispose: () => im.dispose() });
    }
  } else if (kind === 'dry') {
    // out of fuel: the car coasts to a stop where it is; two cones mark the spot
    gap = 3;
    lane = LANE_OUT;
    const coneM = lam('#d9682f');
    const baseM = lam('#e9e5db');
    for (const z of [-1.2, -3.6]) {
      group.add(mesh(track(new CylinderGeometry(0.05, 0.3, 0.7, 8)), coneM, LANE_OUT + 0.9, 0.35, z));
      group.add(mesh(track(new BoxGeometry(0.7, 0.05, 0.7)), baseM, LANE_OUT + 0.9, 0.03, z));
    }
  } else {
    gap = 0.4;
    lane = LANE_OUT;
    const hawker = new Mesh(track(figure(0xd9d3c3, SKINS[seed % SKINS.length], { tray: true })), figMat);
    hawker.position.set(ROAD_HALF + 0.55, 0, 0.1);
    hawker.rotation.y = -Math.PI / 2;
    group.add(hawker);
    const woman = new Mesh(track(figure(0xa65a3a, SKINS[(seed + 1) % SKINS.length], { cap: 0xc9a24a, scale: 0.92 })), figMat);
    woman.position.set(ROAD_HALF + 0.85, 0, 1.5);
    woman.rotation.y = -Math.PI / 2;
    group.add(woman);
    upd.push((_dt, t, resolved) => {
      hawker.position.y = Math.abs(Math.sin(t * 3)) * 0.03;
      woman.rotation.z = resolved ? 0 : Math.sin(t * 2) * 0.03;
    });
  }

  return {
    group,
    gap,
    lane,
    leaves,
    update(dt, t, resolved, ok) {
      for (const u of upd) u(dt, t, resolved, ok);
    },
    dispose() {
      geos.forEach((g) => g.dispose());
    },
  };
}

// ---------------------------------------------------------------- gate
export interface Gate {
  group: Group;
  /** 0 = barrier down, 1 = up */
  setOpen(v: number): void;
  setDark(dark: number): void;
  dispose(): void;
}

/** Accent colour of the destination's gate from its scene type. */
export function gateAccent(scene: string): string {
  switch (scene) {
    case 'market':
      return '#c9763a';
    case 'police':
      return '#3d5f8c';
    case 'hospital':
      return '#3f8a6a';
    case 'campus':
      return '#4f7f5e';
    case 'bank':
    case 'office':
      return '#5a6b82';
    case 'club':
    case 'lounge':
      return '#6a5a8a';
    case 'palace':
    case 'museum':
    case 'shrine':
      return '#a5552e';
    case 'airport':
    case 'motorpark':
      return '#4c7489';
    default:
      return '#b98a4a';
  }
}

export function buildGate(name: string, accent: string): Gate {
  const group = new Group();
  const geos: { dispose(): void }[] = [];
  const own = <T extends { dispose(): void }>(o: T) => {
    geos.push(o);
    return o;
  };
  const cream = '#d9cfba';
  const dark = '#4a4f57';
  const W = ROAD_HALF + 1.6;
  const cb = new ColorBatch();
  for (const s of [-1, 1]) {
    cb.add(new BoxGeometry(1.5, 6.6, 1.5), accent, s * W, 3.3, 0);
    cb.add(new BoxGeometry(1.9, 0.35, 1.9), cream, s * W, 6.75, 0);
    cb.add(new BoxGeometry(60, 2.6, 0.5), cream, s * (W + 31), 1.3, 0);
    cb.add(new BoxGeometry(60, 0.2, 0.7), dark, s * (W + 31), 2.7, 0);
  }
  cb.add(new BoxGeometry(W * 2 + 1.5, 1.5, 1.2), accent, 0, 6.2, 0);
  // guard hut
  cb.add(new BoxGeometry(2.2, 2.4, 2.2), cream, -(W + 2.2), 1.2, 3.2);
  cb.add(new BoxGeometry(2.6, 0.2, 2.6), dark, -(W + 2.2), 2.5, 3.2);
  // the compound beyond: a hall in the accent colour, a lawn and palms
  cb.add(new BoxGeometry(30, 9, 11), cream, 0, 4.5, -34);
  cb.add(new BoxGeometry(31, 0.8, 12), accent, 0, 9.4, -34);
  cb.add(new BoxGeometry(6, 3.4, 0.3), '#40566a', 0, 1.7, -28.4);
  cb.add(new BoxGeometry(70, 0.06, 40), '#7d9a63', 0, 0.01, -26);
  cb.add(new BoxGeometry(ROAD_HALF * 2, 0.05, 40), '#a69a86', 0, 0.03, -20);
  for (const x of [-12, -7, 7, 12, -16, 16]) {
    cb.add(new CylinderGeometry(0.25, 0.35, 6, 6), '#8a6c4a', x, 3, -14 - Math.abs(x) * 0.3);
    cb.add(new ConeGeometry(2.2, 0.7, 7), '#4d7f45', x, 6.2, -14 - Math.abs(x) * 0.3);
  }
  const built = cb.build();
  if (built) {
    group.add(built.mesh);
    own(built.geometry);
    own(built.material);
  }
  const board = new Mesh(own(new PlaneGeometry(9.4, 1.18)), own(new MeshBasicMaterial({ map: signTexture(name.length > 26 ? name.slice(0, 26) : name, '', 'green') })));
  board.position.set(0, 6.2, 0.62);
  group.add(board);
  // boom barrier (turns up)
  const pivot = new Group();
  pivot.position.set(-(W - 0.9), 1.1, 2.2);
  const armLen = W * 2 - 1.4;
  const segs = 6;
  const armRed = own(new MeshLambertMaterial({ color: '#cf3d33' }));
  const armWhite = own(new MeshLambertMaterial({ color: '#eeeeea' }));
  const arm = new MatBatch();
  for (let i = 0; i < segs; i++) arm.add(i % 2 ? armRed : armWhite, new BoxGeometry(armLen / segs, 0.16, 0.16), (armLen / segs) * (i + 0.5), 0, 0);
  geos.push(...arm.build(pivot));
  group.add(pivot);
  const lampM = own(new MeshBasicMaterial({ color: '#d8d2c4' }));
  const lamps = new MatBatch();
  for (const s of [-1, 1]) lamps.add(lampM, new BoxGeometry(0.7, 0.3, 0.5), s * W, 5.5, 0.95);
  geos.push(...lamps.build(group));
  const warm = new Color('#ffe3a0');
  const cool = new Color('#d8d2c4');
  return {
    group,
    setOpen(v) {
      pivot.rotation.z = v * 1.35;
    },
    setDark(d) {
      lampM.color.copy(cool).lerp(warm, d);
    },
    dispose() {
      geos.forEach((g) => g.dispose());
    },
  };
}

// ---------------------------------------------------------------- cockpit
export interface Cockpit {
  group: Group;
  /** Steering input -1..1 */
  steer(v: number): void;
  setLook(bodyHex: number, dark: number): void;
  dispose(): void;
}

/** What the driver sees: dashboard and steering wheel (cars), handlebar (keke, okada, bicycle). Child of the camera.
 *  Parts are merged per material, so the whole cockpit is about five draw calls. */
export function buildCockpit(kind: VehicleKind): Cockpit {
  const group = new Group();
  const geos: { dispose(): void }[] = [];
  const dashM = new MeshLambertMaterial({ color: '#4a4f58', emissive: '#262b34' });
  const trimM = new MeshLambertMaterial({ color: '#2f333a', emissive: '#171a20' });
  const bodyM = new MeshLambertMaterial({ color: '#b9bdc4' });
  const glowM = new MeshBasicMaterial({ color: '#5fae9c' });
  geos.push(dashM, trimM, bodyM, glowM);
  const mb = new MatBatch();
  let wheelGroup: Group | null = null;

  if (kind === 'moto' || kind === 'bike' || kind === 'keke') {
    // handlebar view: the bar, two grips, two mirrors, a small gauge
    const wide = kind === 'keke' ? 0.46 : 0.4;
    mb.add(trimM, new CylinderGeometry(0.018, 0.018, wide * 2, 8), 0, -0.36, -0.78, 0, 0, Math.PI / 2);
    for (const s of [-1, 1]) {
      mb.add(trimM, new CylinderGeometry(0.03, 0.03, 0.16, 8), s * wide, -0.36, -0.78, 0, 0, Math.PI / 2);
      mb.add(trimM, new BoxGeometry(0.1, 0.07, 0.02), s * (wide + 0.04), -0.2, -0.9);
      mb.add(trimM, new BoxGeometry(0.02, 0.15, 0.02), s * (wide + 0.04), -0.28, -0.88);
    }
    mb.add(trimM, new CylinderGeometry(0.06, 0.06, 0.04, 12), 0, -0.3, -0.95, Math.PI / 2 - 0.5);
    mb.add(glowM, new CylinderGeometry(0.045, 0.045, 0.01, 12), 0, -0.285, -0.925, Math.PI / 2 - 0.5);
    if (kind === 'keke') {
      // the keke's metal roof edge and windscreen frame
      mb.add(trimM, new BoxGeometry(1.3, 0.05, 0.05), 0, 0.4, -0.9);
      for (const s of [-1, 1]) mb.add(trimM, new BoxGeometry(0.05, 0.9, 0.05), s * 0.62, 0, -0.9);
    }
  } else {
    // car / bus dashboard (phones are tall and narrow: keep it small and a little way off so the road stays the star)
    const bus = kind === 'bus';
    const x0 = 0.38; // the camera sits at the driver, the dash is centred on the car
    mb.add(dashM, new BoxGeometry(1.8, 0.2, 0.46), x0, -0.5, -1.18);
    mb.add(trimM, new BoxGeometry(1.8, 0.07, 0.3), x0, -0.38, -1.25);
    mb.add(bodyM, new BoxGeometry(1.6, 0.05, 2.3), x0, -0.6, -2.7); // bonnet
    mb.add(trimM, new BoxGeometry(0.34, 0.1, 0.04), 0, -0.34, -1.12); // instrument hood
    mb.add(glowM, new BoxGeometry(0.07, 0.04, 0.01), -0.07, -0.33, -1.09);
    mb.add(glowM, new BoxGeometry(0.07, 0.04, 0.01), 0.07, -0.33, -1.09);
    mb.add(trimM, new BoxGeometry(0.28, 0.16, 0.03), x0 + 0.08, -0.38, -1.12); // centre screen
    mb.add(glowM, new BoxGeometry(0.24, 0.12, 0.01), x0 + 0.08, -0.38, -1.1);
    // steering wheel (turns)
    wheelGroup = new Group();
    wheelGroup.position.set(0, -0.36, -0.82);
    wheelGroup.rotation.x = -1.1;
    const wm = new MatBatch();
    wm.add(trimM, new TorusGeometry(bus ? 0.17 : 0.14, 0.017, 6, 20));
    wm.add(dashM, new BoxGeometry(0.05, 0.05, 0.03));
    wm.add(trimM, new BoxGeometry(0.26, 0.02, 0.02));
    wm.add(trimM, new BoxGeometry(0.02, 0.12, 0.02), 0, -0.06, 0);
    geos.push(...wm.build(wheelGroup));
    group.add(wheelGroup);
  }
  geos.push(...mb.build(group));
  return {
    group,
    steer(v) {
      if (wheelGroup) wheelGroup.rotation.z = -v * 0.9;
    },
    setLook(bodyHex, dark) {
      bodyM.color.set(bodyHex);
      bodyM.color.multiplyScalar(1 - dark * 0.5);
      bodyM.emissive.set(bodyHex).multiplyScalar(0.12 + dark * 0.14);
      dashM.color.set('#4a4f58').multiplyScalar(0.6 + 0.4 * (1 - dark));
      trimM.color.set('#2f333a').multiplyScalar(0.7 + 0.3 * (1 - dark));
      glowM.color.set('#5fae9c').multiplyScalar(0.55 + dark * 0.45);
    },
    dispose() {
      geos.forEach((g) => g.dispose());
    },
  };
}
