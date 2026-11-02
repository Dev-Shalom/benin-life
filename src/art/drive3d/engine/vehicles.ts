// Procedural low-poly vehicles for the drive scene (no assets). Every vehicle is ONE merged geometry with vertex colours,
// facing -z, wheels on y = 0. Body panels are painted WHITE so an instance colour (or the material colour) tints only the
// body; glass, tyres, lamps and trim keep their own colour. docs/DRIVE.md.
import { BoxGeometry, BufferAttribute, BufferGeometry, Color, CylinderGeometry, SphereGeometry } from 'three';
import { mergeGeometries } from 'three/examples/jsm/utils/BufferGeometryUtils.js';
import type { VehicleKind } from '../model';

const BODY = 0xffffff;
const GLASS = 0x56697e;
const TYRE = 0x1b1d22;
const HEAD = 0xfff0c8;
const TAIL = 0xd0382f;
const TRIM = 0x23272e;

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
  return g;
}

/** A box centred at (x, y, z) with its own colour. `ti`/`tr` pull the TOP face in on z at the front (-z) / rear (+z): a slanted screen. */
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

function wheel(r: number, wid: number, x: number, z: number, seg = 10): BufferGeometry {
  const g = new CylinderGeometry(r, r, wid, seg);
  g.rotateZ(Math.PI / 2);
  g.translate(x, r, z);
  const t = paint(g.toNonIndexed(), TYRE);
  return t;
}

function person(x: number, y: number, z: number, shirt: number, skin: number, helmet?: number): BufferGeometry[] {
  const parts: BufferGeometry[] = [];
  parts.push(box(0.38, 0.5, 0.22, x, y + 0.25, z, shirt));
  const head = new SphereGeometry(0.15, 7, 5);
  head.translate(x, y + 0.66, z);
  parts.push(paint(head.toNonIndexed(), helmet ?? skin));
  return parts;
}

function merge(parts: BufferGeometry[]): BufferGeometry {
  const g = mergeGeometries(parts, false);
  parts.forEach((p) => p.dispose());
  g.computeBoundingSphere();
  return g;
}

function sedan(): BufferGeometry {
  const p: BufferGeometry[] = [];
  p.push(box(1.78, 0.5, 4.3, 0, 0.62, 0, BODY, 0, 0));
  p.push(box(1.7, 0.18, 1.2, 0, 0.95, -1.5, BODY)); // bonnet
  p.push(box(1.7, 0.2, 0.9, 0, 0.95, 1.7, BODY)); // boot
  p.push(box(1.56, 0.5, 2.1, 0, 1.14, 0.1, GLASS, 0.5, 0.35)); // cabin glass
  p.push(box(1.52, 0.07, 1.4, 0, 1.43, 0.15, BODY)); // roof
  p.push(box(0.4, 0.14, 0.08, -0.6, 0.72, -2.17, HEAD), box(0.4, 0.14, 0.08, 0.6, 0.72, -2.17, HEAD));
  p.push(box(0.4, 0.12, 0.08, -0.6, 0.74, 2.17, TAIL), box(0.4, 0.12, 0.08, 0.6, 0.74, 2.17, TAIL));
  p.push(box(1.8, 0.14, 4.2, 0, 0.36, 0, TRIM));
  for (const x of [-0.9, 0.9]) for (const z of [-1.4, 1.4]) p.push(wheel(0.33, 0.24, x, z));
  return merge(p);
}

function suv(): BufferGeometry {
  const p: BufferGeometry[] = [];
  p.push(box(1.9, 0.72, 4.6, 0, 0.82, 0, BODY));
  p.push(box(1.82, 0.62, 3.2, 0, 1.46, 0.45, GLASS, 0.35, 0.1));
  p.push(box(1.8, 0.07, 2.9, 0, 1.8, 0.5, BODY));
  p.push(box(0.46, 0.16, 0.08, -0.65, 0.98, -2.32, HEAD), box(0.46, 0.16, 0.08, 0.65, 0.98, -2.32, HEAD));
  p.push(box(0.4, 0.2, 0.08, -0.7, 1.0, 2.32, TAIL), box(0.4, 0.2, 0.08, 0.7, 1.0, 2.32, TAIL));
  p.push(box(1.92, 0.16, 4.5, 0, 0.5, 0, TRIM));
  for (const x of [-0.95, 0.95]) for (const z of [-1.5, 1.5]) p.push(wheel(0.4, 0.28, x, z));
  return merge(p);
}

function pickup(): BufferGeometry {
  const p: BufferGeometry[] = [];
  p.push(box(1.85, 0.6, 5.0, 0, 0.8, 0, BODY));
  p.push(box(1.7, 0.6, 1.7, 0, 1.4, -0.7, GLASS, 0.4, 0.1));
  p.push(box(1.66, 0.07, 1.3, 0, 1.73, -0.65, BODY));
  p.push(box(1.7, 0.4, 0.1, 0, 1.3, 1.0, BODY)); // bed front wall
  p.push(box(0.1, 0.4, 1.9, -0.88, 1.3, 1.85, BODY), box(0.1, 0.4, 1.9, 0.88, 1.3, 1.85, BODY));
  p.push(box(1.7, 0.4, 0.1, 0, 1.3, 2.8, BODY));
  p.push(box(0.44, 0.15, 0.08, -0.65, 0.95, -2.52, HEAD), box(0.44, 0.15, 0.08, 0.65, 0.95, -2.52, HEAD));
  p.push(box(0.3, 0.18, 0.08, -0.7, 1.0, 2.52, TAIL), box(0.3, 0.18, 0.08, 0.7, 1.0, 2.52, TAIL));
  p.push(box(1.87, 0.14, 4.9, 0, 0.5, 0, TRIM));
  for (const x of [-0.93, 0.93]) for (const z of [-1.6, 1.6]) p.push(wheel(0.4, 0.28, x, z));
  return merge(p);
}

function moto(withPassenger = false, rider = 0x4d6a8f): BufferGeometry {
  const p: BufferGeometry[] = [];
  p.push(wheel(0.34, 0.12, 0, -0.78), wheel(0.34, 0.12, 0, 0.82));
  p.push(box(0.2, 0.34, 1.1, 0, 0.66, 0.0, BODY)); // frame + tank
  p.push(box(0.26, 0.12, 0.7, 0, 0.88, 0.45, TRIM)); // seat
  p.push(box(0.5, 0.05, 0.05, 0, 1.08, -0.62, TRIM)); // bars
  p.push(box(0.12, 0.12, 0.08, 0, 0.9, -0.92, HEAD));
  p.push(box(0.1, 0.08, 0.06, 0, 0.82, 1.2, TAIL));
  p.push(...person(0, 0.82, 0.25, rider, 0x7a5236, 0xe6e2d6));
  if (withPassenger) p.push(...person(0, 0.82, 0.7, 0xc9b9a0, 0x6a4630));
  return merge(p);
}

function bike(): BufferGeometry {
  const p: BufferGeometry[] = [];
  p.push(wheel(0.34, 0.04, 0, -0.55, 8), wheel(0.34, 0.04, 0, 0.55, 8));
  p.push(box(0.05, 0.05, 1.1, 0, 0.62, 0, BODY));
  p.push(box(0.4, 0.04, 0.04, 0, 0.98, -0.5, TRIM));
  p.push(...person(0, 0.62, 0.15, 0x6f8a6a, 0x7a5236));
  return merge(p);
}

function keke(): BufferGeometry {
  const p: BufferGeometry[] = [];
  p.push(box(1.35, 0.5, 2.7, 0, 0.62, 0.15, BODY)); // lower body
  p.push(box(1.1, 0.45, 0.9, 0, 0.62, -1.55, BODY, 0, 0)); // nose
  p.push(box(1.28, 0.62, 0.05, 0, 1.2, -0.62, GLASS, 0.18, 0)); // screen
  p.push(box(1.45, 0.07, 2.0, 0, 1.58, 0.45, TRIM)); // dark roof
  for (const [x, z] of [[-0.62, -0.58], [0.62, -0.58], [-0.62, 1.4], [0.62, 1.4]] as const) p.push(box(0.05, 0.9, 0.05, x, 1.13, z, TRIM));
  p.push(box(1.1, 0.12, 0.6, 0, 0.95, 1.05, TRIM)); // back seat
  p.push(box(0.45, 0.12, 0.4, 0, 0.9, -0.15, TRIM)); // driver seat
  p.push(box(0.2, 0.12, 0.06, 0, 0.82, -2.0, HEAD));
  p.push(box(0.8, 0.1, 0.06, 0, 0.8, 1.52, TAIL));
  p.push(wheel(0.28, 0.14, 0, -1.55, 9), wheel(0.28, 0.14, -0.7, 0.9, 9), wheel(0.28, 0.14, 0.7, 0.9, 9));
  p.push(...person(0, 0.9, -0.15, 0x7b8d6d, 0x6a4630));
  return merge(p);
}

function bus(): BufferGeometry {
  const p: BufferGeometry[] = [];
  p.push(box(2.3, 2.5, 9.2, 0, 1.6, 0, BODY));
  p.push(box(2.34, 0.8, 8.4, 0, 2.0, 0, GLASS)); // window band
  p.push(box(2.36, 0.22, 9.0, 0, 1.05, 0, 0x2e7a4a)); // green stripe (ECTS)
  p.push(box(2.1, 0.7, 0.06, 0, 2.05, -4.62, GLASS)); // windscreen
  p.push(box(0.5, 0.2, 0.08, -0.8, 0.95, -4.62, HEAD), box(0.5, 0.2, 0.08, 0.8, 0.95, -4.62, HEAD));
  p.push(box(0.4, 0.3, 0.08, -0.85, 1.1, 4.62, TAIL), box(0.4, 0.3, 0.08, 0.85, 1.1, 4.62, TAIL));
  p.push(box(2.3, 0.3, 9.1, 0, 0.45, 0, TRIM));
  for (const x of [-1.1, 1.1]) for (const z of [-3.0, 2.8]) p.push(wheel(0.5, 0.3, x, z, 10));
  return merge(p);
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

const cache = new Map<string, BufferGeometry>();
export function vehicleGeometry(kind: VehicleKind | 'okada2'): BufferGeometry {
  let g = cache.get(kind);
  if (g) return g;
  switch (kind) {
    case 'suv':
      g = suv();
      break;
    case 'pickup':
      g = pickup();
      break;
    case 'moto':
      g = moto(false);
      break;
    case 'okada2':
      g = moto(true, 0x8a5a44);
      break;
    case 'bike':
      g = bike();
      break;
    case 'keke':
      g = keke();
      break;
    case 'bus':
      g = bus();
      break;
    default:
      g = sedan();
  }
  cache.set(kind, g);
  return g;
}

/** Bounding half-length (z) and a footprint used to keep traffic apart. */
export const VEH_LEN: Record<VehicleKind | 'okada2', number> = { sedan: 4.4, suv: 4.7, pickup: 5.1, moto: 2.2, okada2: 2.2, bike: 1.8, keke: 3.4, bus: 9.4 };

export function disposeVehicleCache() {
  cache.forEach((g) => g.dispose());
  cache.clear();
}
