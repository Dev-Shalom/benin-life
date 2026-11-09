// Shared vehicle library: wheels. A UNIT wheel has radius 1, width 1 and its axis along x; the scene scales it by (wid, r, r). It is
// one merged geometry: a tyre with a rounded sidewall and a tread, a dark brake disc, and an alloy rim (lip ring, spokes, hub) that
// is lighter than the tyre so a turning wheel reads. Both faces carry the rim, so the same geometry serves left and right.
import { BufferGeometry, CylinderGeometry, LatheGeometry, Vector2 } from 'three';
import { bake, type Lod, type Part, type Role } from './kit';
import { cylX, rbox } from './prim';

const unit = new Map<string, BufferGeometry>();

function lathe(profile: [number, number][], seg: number): BufferGeometry {
  // profile: (radius, axial) listed from one face to the other; the lathe turns about y, then y becomes the wheel's x axis
  const g = new LatheGeometry(profile.map((p) => new Vector2(p[0], p[1])), seg);
  g.rotateZ(Math.PI / 2);
  g.deleteAttribute('uv');
  return g;
}

function carWheel(lod: Lod): Part[] {
  const parts: Part[] = [];
  const add = (g: BufferGeometry, role: Role) => parts.push({ g, role });
  const seg = lod === 0 ? 20 : lod === 1 ? 10 : 8;
  if (lod >= 1) {
    add(cylX(1, 1, seg), 'tyre');
    if (lod === 1) for (const sd of [-1, 1]) {
      const d = cylX(0.6, 0.04, 8);
      d.translate(sd * 0.5, 0, 0);
      add(d, 'rim');
    }
    return parts;
  }
  // tyre: a short modern sidewall (rim about 70 % of the radius), rounded shoulder, flat tread; the profile runs face to face
  add(
    lathe(
      [[0.7, -0.46], [0.84, -0.5], [0.96, -0.43], [1, -0.26], [1, 0.26], [0.96, 0.43], [0.84, 0.5], [0.7, 0.46]],
      seg,
    ),
    'tyre',
  );
  // dark barrel behind the spokes
  add(cylX(0.72, 0.9, seg), 'disc');
  for (const s of [-1, 1]) {
    // brake disc (a lighter steel ring) and a red caliper, seen between the spokes
    const bd = cylX(0.52, 0.05, seg);
    bd.translate(s * 0.34, 0, 0);
    add(bd, 'metal');
    const cal = rbox(0.1, 0.22, 0.2, 0.04, 1);
    cal.translate(s * 0.34, 0.5, 0);
    cal.rotateX(0.5);
    parts.push({ g: cal, role: 'accent', hex: 0xb22a24 });
    // rim lip: a ring just inside the tyre bead
    const lip = lathe([[0.68, 0], [0.74, 0.03], [0.7, 0.06]], seg);
    lip.translate(s * 0.46 - 0.03, 0, 0);
    add(lip, 'rim');
    // five spokes, each a small rounded bar from the hub to the lip
    for (let k = 0; k < 5; k++) {
      const a = (k / 5) * Math.PI * 2;
      const sp = rbox(0.07, 0.56, 0.15, 0.03, 1);
      sp.translate(0, 0.4, 0);
      sp.rotateX(a);
      sp.translate(s * 0.45, 0, 0);
      add(sp, 'rim');
    }
    const hub = cylX(0.17, 0.08, 10);
    hub.translate(s * 0.47, 0, 0);
    add(hub, 'chrome');
  }
  return parts;
}

/** Thin wire wheel for bicycles and motorcycles: slim tyre, a rim ring, crossed spokes, a hub. */
function spokeWheel(lod: Lod): Part[] {
  const parts: Part[] = [];
  const add = (g: BufferGeometry, role: Role) => parts.push({ g, role });
  const seg = lod === 0 ? 20 : lod === 1 ? 12 : 8;
  add(lathe([[0.84, -0.5], [0.94, -0.46], [1, -0.3], [1, 0.3], [0.94, 0.46], [0.84, 0.5]], seg), 'tyre');
  add(lathe([[0.76, -0.12], [0.84, -0.1], [0.84, 0.1], [0.76, 0.12]], seg), 'rim');
  if (lod === 2) {
    add(cylX(0.78, 0.04, seg), 'disc');
    return parts;
  }
  const n = lod === 0 ? 8 : 4;
  for (let k = 0; k < n; k++) {
    const sp = new CylinderGeometry(0.014, 0.014, 1.62, 3);
    sp.rotateX(Math.PI / 2 + 0.0);
    sp.rotateX((k / n) * Math.PI);
    add(sp, 'metal');
  }
  add(cylX(0.1, 0.2, 8), 'chrome');
  return parts;
}

/** The unit wheel for a style and detail level (cached). */
export function unitWheel(style: 'car' | 'spoke' = 'car', lod: Lod = 0): BufferGeometry {
  const key = style + lod;
  let g = unit.get(key);
  if (!g) {
    g = bake(style === 'car' ? carWheel(lod) : spokeWheel(lod));
    unit.set(key, g);
  }
  return g;
}

/** A wheel placed on the ground: used when wheels are baked into a body. Returns parts (cloned from the unit pieces by rebuilding). */
export function wheelParts(x: number, z: number, r: number, wid: number, style: 'car' | 'spoke', lod: Lod): Part[] {
  const parts = style === 'car' ? carWheel(lod) : spokeWheel(lod);
  for (const p of parts) {
    p.g.scale(wid, r, r);
    p.g.translate(x, r, z);
  }
  return parts;
}

export function disposeWheels() {
  unit.forEach((g) => g.dispose());
  unit.clear();
}
