// Everything that makes the ECTS bus ride special: the sliding doors, the destination board, the inside of the bus (seats, poles,
// driver, passengers, windows open to the road) and the bus stops (shelter, ECTS sign, people who get on and off).
// All procedural. docs/DRIVE.md.
import {
  BoxGeometry,
  CanvasTexture,
  CylinderGeometry,
  DoubleSide,
  Group,
  InstancedMesh,
  Mesh,
  MeshBasicMaterial,
  MeshLambertMaterial,
  Object3D,
  PlaneGeometry,
  SphereGeometry,
  SRGBColorSpace,
  TorusGeometry,
} from 'three';
import { ColorBatch } from './batch';
import { BUS, busDoorLeaf, figure } from './vehicles';

const tex = (draw: (g: CanvasRenderingContext2D, w: number, h: number) => void, w = 512, h = 64): CanvasTexture => {
  const c = document.createElement('canvas');
  c.width = w;
  c.height = h;
  draw(c.getContext('2d')!, w, h);
  const t = new CanvasTexture(c);
  t.colorSpace = SRGBColorSpace;
  t.anisotropy = 2;
  return t;
};

/** The front destination board text: "ECTS" and where the bus is going (amber board, dark lettering). */
export function destBoard(dest: string): { mesh: Mesh; dispose(): void } {
  const label = dest.length > 24 ? dest.slice(0, 23) + '…' : dest;
  const t = tex((g, w, h) => {
    g.fillStyle = '#ffc247';
    g.fillRect(0, 0, w, h);
    g.fillStyle = '#7a2a20';
    g.fillRect(0, 0, 118, h);
    g.fillStyle = '#fff6df';
    g.font = '800 40px "Outfit","Segoe UI",system-ui,sans-serif';
    g.textBaseline = 'middle';
    g.textAlign = 'center';
    g.fillText('ECTS', 59, h / 2 + 2);
    g.fillStyle = '#1b1d22';
    let size = 40;
    g.font = `800 ${size}px "Outfit","Segoe UI",system-ui,sans-serif`;
    while (g.measureText(label).width > w - 150 && size > 18) {
      size -= 2;
      g.font = `800 ${size}px "Outfit","Segoe UI",system-ui,sans-serif`;
    }
    g.fillText(label, 118 + (w - 118) / 2, h / 2 + 2);
  });
  const geo = new PlaneGeometry(1.74, 0.2);
  const mat = new MeshBasicMaterial({ map: t });
  const mesh = new Mesh(geo, mat);
  mesh.rotation.y = Math.PI;
  mesh.position.set(0, BUS.boardY, BUS.boardZ + 0.01);
  return {
    mesh,
    dispose() {
      geo.dispose();
      mat.dispose();
      t.dispose();
    },
  };
}

export interface BusRig {
  /** Inside of the bus (child of the bus group); visible for the Inside camera only. */
  interior: Group;
  /** The four door leaves on the outside (child of the bus group). */
  doors: InstancedMesh;
  /** Door open amount 0..1 (both doors). */
  setDoor(open: number): void;
  setDark(dark: number): void;
  dispose(): void;
}

const SKIN = [0x6a4630, 0x7a5236, 0x59382a, 0x8a5e40];
const SHIRT = [0xb8553f, 0x4f7ca8, 0xc9a24a, 0x6a8f5c, 0x8a6a9a, 0xd8d2c4, 0x3c5878];

export function buildBusRig(): BusRig {
  const interior = new Group();
  const owned: { dispose(): void }[] = [];
  const own = <T extends { dispose(): void }>(o: T) => {
    owned.push(o);
    return o;
  };
  const cb = new ColorBatch();
  const cream = '#e6dfc9';
  const FLOOR = 0.72;
  cb.add(new BoxGeometry(2.3, 0.06, 9.2), '#676b72', 0, FLOOR, 0);
  cb.add(new BoxGeometry(0.55, 0.02, 9.0), '#8a8e95', 0, FLOOR + 0.04, 0);
  // lower walls (left whole; right with the two door gaps) up to the window sill, pillars, header and ceiling
  cb.add(new BoxGeometry(0.06, 0.93, 9.2), cream, -1.2, 1.185, 0);
  const gaps = BUS.doorZ.map((z) => [z - BUS.doorW / 2, z + BUS.doorW / 2]);
  let z0 = -4.6;
  for (const [a, b] of [...gaps, [4.6, 4.6]]) {
    if (a > z0) cb.add(new BoxGeometry(0.06, 0.93, a - z0), cream, 1.2, 1.185, (a + z0) / 2);
    z0 = b;
  }
  for (const s of [-1, 1]) {
    cb.add(new BoxGeometry(0.1, 0.3, 9.2), cream, s * 1.2, 2.55, 0);
    for (const z of [-4.35, -3.05, -1.75, -0.45, 0.85, 2.15, 3.45, 4.6]) cb.add(new BoxGeometry(0.1, 0.9, 0.18), cream, s * 1.2, 2.05, z);
  }
  cb.add(new BoxGeometry(2.4, 0.08, 9.4), '#eceae2', 0, 2.72, 0);
  for (const z of [-3.2, -0.6, 2.0, 4.0]) cb.add(new BoxGeometry(0.5, 0.03, 0.9), '#fff6d8', 0, 2.67, z);
  // front: bulkhead below the windscreen, pillars and header (the glass itself is left open so the road shows)
  cb.add(new BoxGeometry(2.4, 0.78, 0.12), '#3c4048', 0, 1.11, -4.78);
  cb.add(new BoxGeometry(2.4, 0.3, 0.12), cream, 0, 2.55, -4.78);
  for (const s of [-1, 1]) cb.add(new BoxGeometry(0.16, 0.8, 0.12), cream, s * 1.2, 2.05, -4.78);
  cb.add(new BoxGeometry(2.3, 0.22, 0.5), '#2e3238', 0, 1.56, -4.5); // dashboard
  cb.add(new BoxGeometry(2.4, 2.0, 0.1), cream, 0, 1.7, 4.75); // rear wall
  // seats: red cushions and backs on dark frames, pairs left and right, aisle between
  const seatRows = [-2.7, -1.6, -0.5, 2.2, 3.3];
  const seatXs = [-0.74, 0.74];
  for (const z of seatRows) {
    for (const x of seatXs) {
      if (x > 0 && BUS.doorZ.some((dz) => Math.abs(dz - z) < BUS.doorW / 2 + 0.55)) continue;
      if (z === -2.7 && x > 0) continue; // your own seat: you sit in it, you do not see it
      cb.add(new BoxGeometry(0.85, 0.34, 0.5), '#2b2f36', x, 0.93, z);
      cb.add(new BoxGeometry(0.85, 0.14, 0.55), '#a93a31', x, 1.1, z);
      cb.add(new BoxGeometry(0.85, 0.5, 0.12), '#8f2f28', x, 1.42, z + 0.26);
      cb.add(new BoxGeometry(0.03, 0.46, 0.14), '#2b2f36', x, 1.42, z + 0.26);
    }
  }
  cb.add(new BoxGeometry(2.1, 0.14, 0.5), '#a93a31', 0, 1.1, 4.35); // back bench
  cb.add(new BoxGeometry(2.1, 0.5, 0.12), '#8f2f28', 0, 1.42, 4.6);
  // poles and ceiling rails
  for (const s of [-1, 1]) {
    cb.add(new BoxGeometry(0.05, 0.05, 9.0), '#c9ccd0', s * 0.34, 2.5, 0);
    for (const z of [-2.15, -1.05, 0.05, 1.7, 2.75, 3.85]) cb.add(new CylinderGeometry(0.025, 0.025, 1.8, 6), '#c9ccd0', s * 0.34, 1.62, z);
  }
  // the driver (left-hand drive: the driver sits on the left), seat, wheel and a calm profile
  cb.add(new BoxGeometry(0.55, 0.14, 0.5), '#2e3238', -0.62, 1.05, -3.7);
  cb.add(new BoxGeometry(0.55, 0.6, 0.12), '#2e3238', -0.62, 1.4, -3.4);
  cb.add(new BoxGeometry(0.46, 0.55, 0.26), '#3c5878', -0.62, 1.45, -3.62);
  const head = new SphereGeometry(0.15, 8, 6);
  cb.add(head, '#6a4630', -0.62, 1.88, -3.62);
  // passengers
  let seed = 7;
  const r = () => {
    seed = (seed * 16807) % 2147483647;
    return seed / 2147483647;
  };
  for (const z of seatRows) {
    for (const x of seatXs) {
      if (x > 0 && BUS.doorZ.some((dz) => Math.abs(dz - z) < BUS.doorW / 2 + 0.55)) continue;
      if (z === -2.7 && x > 0) continue; // your seat
      for (const dx of [-0.2, 0.2]) {
        if (r() < 0.5) continue;
        const sx = x + dx;
        cb.add(new BoxGeometry(0.34, 0.5, 0.22), '#' + SHIRT[Math.floor(r() * SHIRT.length)].toString(16).padStart(6, '0'), sx, 1.45, z + 0.12);
        cb.add(new SphereGeometry(0.14, 7, 5), '#' + SKIN[Math.floor(r() * SKIN.length)].toString(16).padStart(6, '0'), sx, 1.86, z + 0.12);
      }
    }
  }
  const built = cb.build(own(new MeshLambertMaterial({ vertexColors: true })));
  if (built) {
    interior.add(built.mesh);
    own(built.geometry);
  }
  // steering wheel (static, the driver's hands are the dashboard's problem)
  const wheel = new Mesh(own(new TorusGeometry(0.2, 0.022, 6, 18)), own(new MeshLambertMaterial({ color: '#23272e' })));
  wheel.position.set(-0.62, 1.55, -4.3);
  wheel.rotation.x = -1.0;
  interior.add(wheel);
  interior.visible = false;

  // door leaves: A hinges at the door centre side... closed they meet in the middle, open they slide to the door's two edges
  const leafGeo = own(busDoorLeaf());
  const leafMat = own(new MeshLambertMaterial({ vertexColors: true }));
  const doors = new InstancedMesh(leafGeo, leafMat, 4);
  doors.frustumCulled = false;
  const o = new Object3D();
  const half = BUS.doorW / 2 - 0.02;
  const setDoor = (open: number) => {
    let i = 0;
    for (const dz of BUS.doorZ) {
      // leaf toward the front: from the door centre running to -z; leaf toward the rear: running to +z
      for (const dir of [-1, 1]) {
        const slide = open * (half - 0.04) * dir;
        o.position.set(1.28 + open * 0.05, BUS.doorY0 + BUS.doorH / 2, dz + slide);
        o.rotation.set(0, 0, 0);
        o.scale.set(1, 1, dir);
        o.updateMatrix();
        doors.setMatrixAt(i++, o.matrix);
      }
    }
    doors.instanceMatrix.needsUpdate = true;
  };
  setDoor(0);

  return {
    interior,
    doors,
    setDoor,
    setDark() {
      /* lit by the scene lights */
    },
    dispose() {
      owned.forEach((d) => d.dispose());
      doors.dispose();
    },
  };
}

// ---------------------------------------------------------------- bus stop
export interface StopRig {
  group: Group;
  /** Seconds since the bus pulled in (< 0 = it has not arrived yet, large = it has left). */
  update(tDwell: number): void;
  dispose(): void;
}

/** A bus stop at the origin: shelter with an ECTS sign, facing the road (the road is toward -x), with 3 people waiting and 2 who get off.
 *  The bus door is at z = `doorAt` (local, forward is -z) and lateral x = `doorX`. */
export function buildStop(name: string, seed: number, doorX: number, doorZ: number): StopRig {
  const group = new Group();
  const owned: { dispose(): void }[] = [];
  const own = <T extends { dispose(): void }>(o: T) => {
    owned.push(o);
    return o;
  };
  const cb = new ColorBatch();
  const dark = '#3b4048';
  // shelter: posts, tinted back panel, roof, bench
  for (const z of [-1.5, 1.5]) for (const x of [-0.7, 0.7]) cb.add(new BoxGeometry(0.08, 2.4, 0.08), dark, x, 1.2, z);
  cb.add(new BoxGeometry(1.7, 0.1, 3.4), '#c2372c', 0, 2.46, 0); // ECTS red roof
  cb.add(new BoxGeometry(1.74, 0.06, 3.44), '#f0b72a', 0, 2.38, 0);
  cb.add(new BoxGeometry(0.05, 1.5, 3.0), '#9bb7c4', 0.7, 1.35, 0);
  cb.add(new BoxGeometry(0.5, 0.07, 2.2), '#8a6c4a', 0.35, 0.62, 0);
  cb.add(new BoxGeometry(0.06, 0.6, 0.06), dark, 0.35, 0.3, -0.9);
  cb.add(new BoxGeometry(0.06, 0.6, 0.06), dark, 0.35, 0.3, 0.9);
  // sign pole with a yellow and red plate
  cb.add(new CylinderGeometry(0.04, 0.04, 3.1, 6), '#7b8088', -0.4, 1.55, -2.3);
  cb.add(new BoxGeometry(0.06, 0.62, 0.8), '#f0b72a', -0.4, 3.0, -2.3);
  cb.add(new BoxGeometry(0.07, 0.2, 0.8), '#c2372c', -0.4, 2.76, -2.3);
  const built = cb.build(own(new MeshLambertMaterial({ vertexColors: true })));
  if (built) {
    group.add(built.mesh);
    own(built.geometry);
  }
  const t = own(
    tex(
      (g, w, h) => {
        g.fillStyle = '#f0b72a';
        g.fillRect(0, 0, w, h);
        g.fillStyle = '#1b1d22';
        g.textAlign = 'center';
        g.textBaseline = 'middle';
        g.font = '800 54px "Outfit","Segoe UI",system-ui,sans-serif';
        g.fillText('BUS STOP', w / 2, 40);
        g.fillStyle = '#c2372c';
        g.fillRect(0, h - 34, w, 34);
        g.fillStyle = '#fff';
        g.font = '800 24px "Outfit","Segoe UI",system-ui,sans-serif';
        const n = name.length > 22 ? name.slice(0, 21) + '…' : name;
        g.fillText('ECTS · ' + n, w / 2, h - 16);
      },
      256,
      128,
    ),
  );
  const plate = new Mesh(own(new PlaneGeometry(0.78, 0.44)), own(new MeshBasicMaterial({ map: t, side: DoubleSide })));
  plate.rotation.y = -Math.PI / 2;
  plate.position.set(-0.445, 3.0, -2.3);
  group.add(plate);

  // people
  const figMat = own(new MeshLambertMaterial({ vertexColors: true }));
  const mk = (i: number, extra = {}) => {
    const g = own(figure(SHIRT[(seed + i * 2) % SHIRT.length], SKIN[(seed + i) % SKIN.length], { arms: false, ...extra }));
    const m = new Mesh(g, figMat);
    group.add(m);
    return m;
  };
  const waiting = [0, 1, 2].map((i) => ({ m: mk(i), x0: 0.1 - i * 0.05, z0: -0.8 + i * 0.7 }));
  const getting = [0, 1].map((i) => ({ m: mk(i + 3, { cap: i === 0 ? 0xc9a24a : undefined }), x1: -1.5 - i * 0.6, z1: doorZ - 1.4 + i * 3.2 }));
  const lerp = (a: number, b: number, k: number) => a + (b - a) * Math.max(0, Math.min(1, k));
  const update = (td: number) => {
    waiting.forEach((p, i) => {
      const start = 0.9 + i * 0.55;
      const k = (td - start) / 1.4;
      p.m.visible = td < start + 1.4;
      p.m.position.set(lerp(p.x0, doorX, k), 0.28, lerp(p.z0, doorZ, k));
      p.m.rotation.y = -Math.PI / 2 + (k > 0 ? 0 : 0);
    });
    getting.forEach((p, j) => {
      const start = 0.5 + j * 0.9;
      const k = (td - start) / 1.7;
      p.m.visible = td >= start;
      p.m.position.set(lerp(doorX, p.x1, k), 0.28, lerp(doorZ, p.z1, k));
      p.m.rotation.y = Math.PI / 2;
    });
  };
  update(-1);
  return {
    group,
    update,
    dispose() {
      owned.forEach((d) => d.dispose());
    },
  };
}
