// Shared vehicle library (one source of truth for every scene): drive, free roam (own car, traffic, other players), the garage and
// showrooms, the city map markers and the shop thumbnails. Procedural, no assets. Geometry is built once per (model, lod) and cached;
// every vehicle is ONE merged geometry with vertex colours (body paint is WHITE so the instance / material colour tints only the
// paint) plus an `aPart` attribute that lets lamps glow at night (see vehicleMaterial). Nose -z, wheels on y = 0. docs/DRIVE.md "Vehicles".
import type { BufferGeometry } from 'three';
import { bake, Kit, type Lod, type Part, type WheelSpec } from './kit';
import { buildModel, type VehicleModel } from './models';
import { unitWheel, disposeWheels } from './wheels';

export { BUS, VEH_LEN, type VehicleModel } from './models';
export { vehicleMaterial, setVehicleRenderer, setVehicleLight, type VehicleMaterial, type Lod, type WheelSpec, type Role, type Part } from './kit';
export { LUX_MODEL } from './lux';

const cache = new Map<string, BufferGeometry>();
const kitCache = new Map<string, { body: BufferGeometry; wheels: WheelSpec[] }>();

/** A vehicle with its wheels baked in (traffic, parked cars, map markers). */
export function vehicleGeometry(model: VehicleModel, lod: Lod = 0): BufferGeometry {
  const key = model + lod;
  let g = cache.get(key);
  if (!g) {
    const K = new Kit(lod, false);
    buildModel(model, K);
    g = bake(K.parts);
    cache.set(key, g);
  }
  return g;
}

/** The player's vehicle: the body WITHOUT wheels plus the wheel specs (the scene draws the wheels so they steer and spin). The bus has no door leaves baked in. */
export function vehicleKit(model: VehicleModel, lod: Lod = 0): { body: BufferGeometry; wheels: WheelSpec[] } {
  const key = model + lod;
  let k = kitCache.get(key);
  if (!k) {
    const K = new Kit(lod, true);
    buildModel(model, K, { doors: false });
    k = { body: bake(K.parts), wheels: K.wheels };
    kitCache.set(key, k);
  }
  return k;
}

/** Unit wheel (radius 1, width 1, axis x) for the separately drawn wheels: scale by (wid, r, r). */
export function unitWheelGeometry(style: 'car' | 'spoke' = 'car', lod: Lod = 0): BufferGeometry {
  return unitWheel(style, lod);
}

/** Raw coloured parts (role + geometry) of a vehicle: for scenes that merge into their own layers (the place and home builders). */
export function vehicleParts(model: VehicleModel, lod: Lod = 0, o: { rider?: boolean } = {}): Part[] {
  const K = new Kit(lod, false);
  K.rider = o.rider ?? true;
  buildModel(model, K);
  return K.parts;
}

/** Triangle count of a geometry. */
export function triCount(g: BufferGeometry): number {
  return Math.round((g.index ? g.index.count : g.getAttribute('position').count) / 3);
}

export function disposeVehicleCache() {
  cache.forEach((g) => g.dispose());
  cache.clear();
  kitCache.forEach((k) => k.body.dispose());
  kitCache.clear();
  disposeWheels();
}

/** A copy of a vehicle geometry with its body paint baked to `hex` (for scenes whose material cannot tint, e.g. the map's keke marker). */
export function paintedBody(g: BufferGeometry, hex: number): BufferGeometry {
  const c = g.clone();
  const col = c.getAttribute('color');
  const part = c.getAttribute('aPart');
  const r = ((hex >> 16) & 255) / 255;
  const gg = ((hex >> 8) & 255) / 255;
  const b = (hex & 255) / 255;
  const lin = (v: number) => Math.pow(v, 2.2);
  for (let i = 0; i < col.count; i++) if (part.getY(i) > 0.5) col.setXYZ(i, col.getX(i) * lin(r), col.getY(i) * lin(gg), col.getZ(i) * lin(b));
  return c;
}

/** Map-scale marker of a vehicle: long axis +x, `len` long in the map's own units, about 130 triangles. */
export function markerGeometry(len: number, model: VehicleModel = 'sedan', lod: Lod = 3): BufferGeometry {
  const g = vehicleGeometry(model, lod).clone();
  g.rotateY(-Math.PI / 2);
  g.computeBoundingBox();
  const l = g.boundingBox!.max.x - g.boundingBox!.min.x;
  g.scale(len / l, len / l, len / l);
  g.computeBoundingSphere();
  return g;
}
