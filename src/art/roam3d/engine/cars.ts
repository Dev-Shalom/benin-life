// Free roam: the moving traffic. One unit geometry per kind (white body so each instance can be tinted), taken from the shared vehicle
// library (src/art/vehicles) at the traffic detail level and turned into this scene's frame: long axis +x, nose +x, y up.
import type { BufferGeometry } from 'three';
import { vehicleGeometry, type VehicleModel } from '../../vehicles';

function inRoamFrame(model: VehicleModel, lod: 1 | 2, scale: number): BufferGeometry {
  const g = vehicleGeometry(model, lod).clone();
  g.rotateY(-Math.PI / 2); // library nose is -z, roam's is +x
  g.scale(scale, scale, scale);
  g.computeBoundingSphere();
  return g;
}

/** Car: about 4 m long. `low` = Graphics Low (the lightest model). */
export function carGeometry(_low = false): BufferGeometry {
  return inRoamFrame('sedan', 2, 0.92);
}

/** Bus (the yellow minibus of the city streets): 5.3 m. */
export function busGeometry(_low = false): BufferGeometry {
  return inRoamFrame('minibus', 2, 1);
}

/** Keke (tricycle taxi): about 2.2 m. */
export function kekeGeometry(_low = false): BufferGeometry {
  return inRoamFrame('keke', 2, 0.62);
}

/** Okada (motorcycle taxi) with its rider: about 2 m. */
export function okadaGeometry(_low = false): BufferGeometry {
  return inRoamFrame('moto', 2, 1);
}
