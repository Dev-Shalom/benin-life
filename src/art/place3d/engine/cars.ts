// Dealer showrooms, garages and the home parking bay draw their cars from the shared vehicle library (src/art/vehicles), the same
// models the drive scene, free roam and traffic use. A model is built once as coloured parts (a role + geometry each); drawing one
// puts every part into the HomeBuilder's own layers (solid, glass, glow), so a car merges into the place's few meshes like any prop.
// Frame: front = +z (the library's nose is -z, so parts are turned half a turn), ground y = 0, scaled by `s`.
// The LuxCar keys are internal ids; the models are original generic designs and CAR_NAMES are generic names (no real brands).
import type { BufferGeometry } from 'three';
import type { HomeBuilder, Layer } from '../../home3d/engine/build';
import { LUX_MODEL, vehicleParts, type Part, type Role, type VehicleModel } from '../../vehicles';

type B = HomeBuilder;

export type LuxCar = 'gle63' | 'g63' | 'urus' | 'cybertruck' | 'escalade' | 'c300' | 'camry';

const ROLE_HEX: Record<Role, string> = {
  body: '#ffffff', glass: '#3a5068', trim: '#1d1f24', tyre: '#18191d', rim: '#cdd2d9', disc: '#2c3037', chrome: '#e2e6ea',
  head: '#f4f7ff', tail: '#e0242c', amber: '#ffa526', plate: '#f3f2ea', plateband: '#2a8a4a', seat: '#2e3238', accent: '#2f7d4a',
  skin: '#7a5236', cloth: '#4d6a8f', metal: '#8b929b',
};
const ROLE_LAYER: Partial<Record<Role, Layer>> = { glass: 'glass', head: 'glow', tail: 'glow', amber: 'glow' };

const cache = new Map<string, Part[]>();

function partsOf(model: VehicleModel, rider: boolean): Part[] {
  const key = model + (rider ? 'r' : '');
  let p = cache.get(key);
  if (!p) {
    p = vehicleParts(model, 0, { rider });
    cache.set(key, p);
  }
  return p;
}

const hex = (n: number) => `#${n.toString(16).padStart(6, '0')}`;

function put(b: B, model: VehicleModel, s: number, paint: string, rider = true, turn = true) {
  for (const p of partsOf(model, rider)) {
    const g: BufferGeometry = p.g.clone();
    if (turn) g.rotateY(Math.PI);
    g.scale(s, s, s);
    const colour = p.role === 'body' ? paint : p.hex !== undefined ? hex(p.hex) : ROLE_HEX[p.role];
    b.geo(g, 0, 0, 0, colour, { layer: ROLE_LAYER[p.role] ?? 'solid', mat: 'plain', noOcc: true });
  }
}

/** A generic saloon / SUV / pickup of the library in the given paint (the lots and yards use it for ordinary cars). */
export function drawModel(b: B, model: VehicleModel, x: number, z: number, ry: number, s: number, paint: string) {
  b.setFrame(x, 0, z, ry);
  put(b, model, s, paint, false);
}

/** Bajaj-style commuter motorcycle, no brand cues: tank in `tank`, no rider. */
export function motorcycle(b: B, s: number, tank = '#b0202d') {
  put(b, 'moto', s, tank, false);
}

/** A roadster bicycle in `frame`, no rider. */
export function bicycle(b: B, s: number, frame = '#1f5a3a') {
  put(b, 'bike', s, frame, false);
}

/** Draw a showroom / garage car at (x, z) with yaw `ry`, scale s, in absolute layout space (resets the builder frame). */
export function drawCar(b: B, kind: LuxCar, x: number, z: number, ry: number, s: number, paint?: string) {
  b.setFrame(x, 0, z, ry);
  const m = LUX_MODEL[kind];
  put(b, m.model, s, paint ?? m.paint, false);
}

/** Generic names for the showroom tags / tests (no real brands or models). */
export const CAR_NAMES: Record<LuxCar, string> = {
  gle63: 'Coupe SUV',
  g63: 'Boxy Off-Roader',
  urus: 'Sport SUV',
  cybertruck: 'Double-Cab Pickup',
  escalade: 'Executive SUV',
  c300: 'Executive Saloon',
  camry: 'Family Saloon',
};
