// Vehicles for the drive scene now come from the shared library (src/art/vehicles, docs/DRIVE.md "Vehicles"): this file keeps the old
// import path working and holds what is not a vehicle (pedestrian figures) plus the bus door leaf.
import { BoxGeometry, BufferAttribute, BufferGeometry, Color, SphereGeometry } from 'three';
import { mergeGeometries } from 'three/examples/jsm/utils/BufferGeometryUtils.js';
import { BUS } from '../../vehicles';

export { BUS, VEH_LEN, vehicleGeometry, vehicleKit, unitWheelGeometry, disposeVehicleCache, vehicleMaterial, setVehicleRenderer, setVehicleLight } from '../../vehicles';
export type { WheelSpec, VehicleModel, VehicleMaterial } from '../../vehicles';

const YELLOW = 0xf0b72a;

function paint(g: BufferGeometry, hex: number): BufferGeometry {
  const c = new Color(hex);
  const n = g.getAttribute('position').count;
  const a = new Float32Array(n * 3);
  for (let i = 0; i < n; i++) {
    a[i * 3] = c.r;
    a[i * 3 + 1] = c.g;
    a[i * 3 + 2] = c.b;
  }
  g.setAttribute('color', new BufferAttribute(a, 3));
  // the shared vehicle material reads aPart (glow, body mask): figures never glow and take no tint
  g.setAttribute('aPart', new BufferAttribute(new Float32Array(n * 4), 4));
  return g;
}

function box(w: number, h: number, d: number, x: number, y: number, z: number, hex: number, ti = 0, tr = 0): BufferGeometry {
  const g = new BoxGeometry(w, h, d);
  if (ti || tr) {
    const p = g.getAttribute('position');
    for (let i = 0; i < p.count; i++) {
      if (p.getY(i) > 0) p.setZ(i, p.getZ(i) + (p.getZ(i) < 0 ? ti : -tr));
    }
    g.computeVertexNormals();
  }
  g.translate(x, y, z);
  return paint(g.index ? g.toNonIndexed() : g, hex);
}

function merge(parts: (BufferGeometry | null)[]): BufferGeometry {
  const ok = parts.filter(Boolean) as BufferGeometry[];
  const g = mergeGeometries(ok, false);
  ok.forEach((p) => p.dispose());
  g.computeBoundingSphere();
  return g;
}

/** One door leaf (the player's bus has four, instanced, so they can slide open). Origin at the hinge edge, centred in y. */
export function busDoorLeaf(): BufferGeometry {
  const w = BUS.doorW / 2 - 0.02;
  return merge([box(0.07, BUS.doorH, w, 0, 0, w / 2, 0x35506a), box(0.09, BUS.doorH + 0.04, 0.05, 0, 0, 0.025, YELLOW)]);
}

/** Pedestrians and roadside props reuse the same vertex colour convention. */
export function figure(shirt: number, skin: number, opts: { cap?: number; tray?: boolean; arms?: boolean; scale?: number } = {}): BufferGeometry {
  const p: BufferGeometry[] = [];
  p.push(box(0.2, 0.7, 0.24, -0.11, 0.35, 0, 0x2f3646), box(0.2, 0.7, 0.24, 0.11, 0.35, 0, 0x2f3646));
  p.push(box(0.48, 0.62, 0.28, 0, 1.0, 0, shirt));
  const head = new SphereGeometry(0.17, 7, 5);
  head.translate(0, 1.5, 0);
  p.push(paint(head.toNonIndexed(), skin));
  if (opts.cap !== undefined) p.push(box(0.36, 0.08, 0.38, 0, 1.64, -0.03, opts.cap));
  if (opts.arms) p.push(box(0.12, 0.55, 0.12, -0.32, 1.12, -0.18, shirt, 0, 0), box(0.12, 0.55, 0.12, 0.32, 1.12, -0.18, shirt));
  else p.push(box(0.11, 0.55, 0.12, -0.3, 0.98, 0, shirt), box(0.11, 0.55, 0.12, 0.3, 0.98, 0, shirt));
  if (opts.tray) {
    p.push(box(0.9, 0.06, 0.6, 0, 1.76, 0, 0xcfd4d8));
    p.push(box(0.8, 0.3, 0.5, 0, 1.94, 0, 0x6fa1c4));
  }
  const g = merge(p);
  if (opts.scale) g.scale(opts.scale, opts.scale, opts.scale);
  return g;
}

