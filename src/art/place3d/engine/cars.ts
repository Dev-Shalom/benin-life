// Dealer showrooms, garages and the home parking bay draw their cars from the shared vehicle library (src/art/vehicles), the same
// models the drive scene, free roam and traffic use. A model is baked once; drawing one copies it into the HomeBuilder's 'vehicle'
// layer with its paint colour baked into the body vertices. The scenes draw that layer with the shared vehicle material (paint and
// glass reflections on High, lamps that glow at night), so cars still merge into the place's few meshes: one extra draw call.
// Frame: front = +z (the library's nose is -z, so models are turned half a turn), ground y = 0, scaled by `s`.
// The LuxCar keys are internal ids; the models are original generic designs and CAR_NAMES are generic names (no real brands).
import { Color } from 'three';
import type { HomeBuilder } from '../../home3d/engine/build';
import { LUX_MODEL, paintedBody, vehicleGeometryPlain, type VehicleModel } from '../../vehicles';

type B = HomeBuilder;

export type LuxCar = 'gle63' | 'g63' | 'urus' | 'cybertruck' | 'escalade' | 'c300' | 'camry';

function put(b: B, model: VehicleModel, s: number, paint: string, rider = true) {
  const g = paintedBody(vehicleGeometryPlain(model, rider), new Color(paint).getHex());
  g.rotateY(Math.PI);
  g.scale(s, s, s);
  b.vehicle(g);
}

/** A generic saloon / SUV / pickup of the library in the given paint (the lots and yards use it for ordinary cars). */
export function drawModel(b: B, model: VehicleModel, x: number, z: number, ry: number, s: number, paint: string) {
  b.setFrame(x, 0, z, ry);
  put(b, model, s, paint, false);
}

/** Commuter motorcycle, no brand cues: tank in `tank`, no rider. */
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
