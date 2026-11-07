// Free roam: low-poly vehicles for the moving traffic (one unit geometry per kind, white body so each instance can be tinted).
import type { BufferGeometry } from 'three';
import { Soup } from './soup';

function wheel(s: Soup, x: number, z: number, r = 0.34) {
  s.box(x, 0, z, r * 2, r * 2, 0.24, 0, '#1d1f24', 1);
}

/** Car: 3.9 x 1.8 m, long axis +x. */
export function carGeometry(): BufferGeometry {
  const s = new Soup();
  s.box(0, 0.3, 0, 3.9, 0.62, 1.8, 0, '#ffffff', 0.8);
  s.box(-0.2, 0.92, 0, 2.1, 0.5, 1.62, 0, '#ffffff', 0.9);
  s.box(-0.2, 0.96, 0, 2.14, 0.4, 1.64, 0, '#3a4b57', 1);
  s.box(-0.2, 1.42, 0, 2.0, 0.06, 1.55, 0, '#ffffff', 1);
  for (const x of [1.25, -1.25]) for (const z of [0.82, -0.82]) wheel(s, x, z);
  s.box(1.96, 0.55, 0.55, 0.06, 0.16, 0.3, 0, '#f6efc9', 1);
  s.box(1.96, 0.55, -0.55, 0.06, 0.16, 0.3, 0, '#f6efc9', 1);
  s.box(-1.96, 0.55, 0.55, 0.06, 0.16, 0.3, 0, '#c0392b', 1);
  s.box(-1.96, 0.55, -0.55, 0.06, 0.16, 0.3, 0, '#c0392b', 1);
  return s.geometry();
}

/** Bus (the yellow ECTS bus of the map): 5.2 x 2.4 m. */
export function busGeometry(): BufferGeometry {
  const s = new Soup();
  s.box(0, 0.4, 0, 5.2, 2.0, 2.3, 0, '#ffffff', 0.85);
  s.box(0, 1.35, 0, 5.24, 0.75, 2.34, 0, '#3a4b57', 1);
  s.box(0, 0.9, 0, 5.24, 0.22, 2.34, 0, '#d63c32', 1);
  s.box(0, 2.4, 0, 5.0, 0.08, 2.1, 0, '#ffffff', 1);
  for (const x of [1.6, -1.6]) for (const z of [1.0, -1.0]) wheel(s, x, z, 0.46);
  return s.geometry();
}

/** Keke (tricycle taxi): 2.0 x 1.5 m. */
export function kekeGeometry(): BufferGeometry {
  const s = new Soup();
  s.box(-0.15, 0.3, 0, 1.5, 0.8, 1.4, 0, '#ffffff', 0.85);
  s.box(-0.15, 1.1, 0, 1.45, 0.78, 1.38, 0, '#ffffff', 0.9);
  s.box(-0.15, 1.2, 0, 1.48, 0.46, 1.4, 0, '#3a4b57', 1);
  s.box(-0.15, 1.88, 0, 1.6, 0.07, 1.5, 0, '#2a2d36', 1);
  s.box(0.85, 0.2, 0, 0.5, 0.7, 0.5, 0, '#ffffff', 0.85);
  wheel(s, 0.95, 0, 0.26);
  for (const z of [0.68, -0.68]) wheel(s, -0.55, z, 0.26);
  return s.geometry();
}
