// Geometry builder for the 3D home and every place interior: every static part is a box/cylinder with a
// vertex colour, merged into a handful of meshes (one Lambert mesh for nearly everything, one unlit mesh
// for things that glow, one for glass, one for screens, one additive mesh for light pools). So a whole
// furnished room costs ~5 draw calls.
// F1 real feel (docs/FEEL_PLAN.md):
// - every part carries `feelUv` (world metres, box-projected by face normal) + `feelTile` (atlas tile, picked
//   with `opt.mat`, the builder's current `mat`, or guessed from the colour) for the shared texture atlas;
// - big boxes are subdivided (~0.5 m) so the baked AO has vertices to darken;
// - solid boxes register as occluders; finish() bakes ambient occlusion into the vertex colours (contact
//   at the floor, wall/floor seams, corners, under furniture) once, at build time (0 cost per frame);
// - `pool` / `beam` add fake light (additive discs and cones) to the 'light' layer.
import {
  BoxGeometry,
  BufferGeometry,
  CircleGeometry,
  Color,
  CylinderGeometry,
  Float32BufferAttribute,
  Matrix4,
  Quaternion,
  Euler,
  Vector3,
} from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import { MAT, MAT_SCALE, type Mat } from '../../feel/atlas';

export type Layer = 'solid' | 'glow' | 'glass' | 'screen' | 'light';
export const LAYERS: Layer[] = ['solid', 'glow', 'glass', 'screen', 'light'];

const _c = new Color();
const _m = new Matrix4();
const _q = new Quaternion();
const _e = new Euler();
const _p = new Vector3();
const _s = new Vector3(1, 1, 1);

/** Colours the furniture / prop code uses for a material, so it gets the right atlas tile untouched. */
const MAT_BY_COLOUR: Record<string, Mat> = {
  '#8a5a33': 'wood', '#5b3a24': 'wood', '#c49a6c': 'wood', '#6b4f3a': 'carpet', '#7a4f2a': 'carpet',
  '#9aa3ab': 'metal', '#59616b': 'metal', '#c8ced4': 'metal', '#23262c': 'plain',
  '#a7b0b6': 'zinc', '#7f898f': 'zinc',
  '#f6f3ec': 'fabric', '#d2342a': 'fabric', '#1f7a3f': 'fabric', '#2f6fb3': 'fabric', '#d9a441': 'fabric',
  '#6d4aa0': 'fabric', '#e07a2e': 'fabric', '#0b625a': 'fabric', '#c74b8a': 'fabric',
};

interface Occ { x0: number; z0: number; x1: number; z1: number; y0: number; y1: number; part: number }

export interface BoxOpt { ry?: number; rx?: number; rz?: number; layer?: Layer; mat?: Mat; uv?: number; seg?: number; noOcc?: boolean }

export class HomeBuilder {
  private parts: Record<Layer, BufferGeometry[]> = { solid: [], glow: [], glass: [], screen: [], light: [] };
  private occ: Occ[] = [];
  /** Current piece frame (position + yaw), applied after the part's own transform. */
  frame = new Matrix4();
  tris = 0;
  /** Atlas tile for parts that don't name one (null = guess from the colour, else plain). */
  mat: Mat | null = null;
  /** Bake AO in finish() (off for tiny one-off builds). */
  ao = true;

  setFrame(x: number, y: number, z: number, yaw: number) {
    _q.setFromEuler(_e.set(0, yaw, 0));
    this.frame.compose(_p.set(x, y, z), _q, _s.set(1, 1, 1));
  }

  resetFrame() {
    this.frame.identity();
  }

  private push(g: BufferGeometry, color: string, layer: Layer, x: number, y: number, z: number, rx = 0, ry = 0, rz = 0, opt: BoxOpt = {}, occ = false) {
    _q.setFromEuler(_e.set(rx, ry, rz));
    _m.compose(_p.set(x, y, z), _q, _s.set(1, 1, 1));
    g.applyMatrix4(_m);
    g.applyMatrix4(this.frame);
    _c.set(color);
    const pos = g.attributes.position;
    const nor = g.attributes.normal;
    const n = pos.count;
    const col = new Float32Array(n * 3);
    let y0 = Infinity, y1 = -Infinity;
    if (layer === 'glass') {
      // windows: a soft vertical gradient so the sky behind reads lighter at the top
      for (let i = 0; i < n; i++) { const yy = pos.getY(i); if (yy < y0) y0 = yy; if (yy > y1) y1 = yy; }
    }
    for (let i = 0; i < n; i++) {
      let k = 1;
      if (layer === 'glass' && y1 > y0) k = 0.72 + 0.28 * ((pos.getY(i) - y0) / (y1 - y0));
      col[i * 3] = _c.r * k;
      col[i * 3 + 1] = _c.g * k;
      col[i * 3 + 2] = _c.b * k;
    }
    g.setAttribute('color', new Float32BufferAttribute(col, 3));
    // atlas: tile + world-metre UVs projected by the dominant normal axis
    const mat: Mat = opt.mat ?? this.mat ?? MAT_BY_COLOUR[color.toLowerCase()] ?? 'plain';
    const scale = 1 / (opt.uv ?? MAT_SCALE[mat]);
    const uv = new Float32Array(n * 2);
    const tile = new Float32Array(n).fill(MAT[mat]);
    for (let i = 0; i < n; i++) {
      const px = pos.getX(i), py = pos.getY(i), pz = pos.getZ(i);
      const ax = Math.abs(nor.getX(i)), ay = Math.abs(nor.getY(i)), az = Math.abs(nor.getZ(i));
      let u: number, v: number;
      if (ay >= ax && ay >= az) { u = px; v = pz; }
      else if (ax >= az) { u = pz; v = py; }
      else { u = px; v = py; }
      uv[i * 2] = u * scale;
      uv[i * 2 + 1] = v * scale;
    }
    g.deleteAttribute('uv');
    g.setAttribute('feelUv', new Float32BufferAttribute(uv, 2));
    g.setAttribute('feelTile', new Float32BufferAttribute(tile, 1));
    if (occ && layer === 'solid' && !opt.noOcc) {
      g.computeBoundingBox();
      const bb = g.boundingBox!;
      const w = bb.max.x - bb.min.x, d = bb.max.z - bb.min.z, h = bb.max.y - bb.min.y;
      // worth casting AO: not a floor slab, not a thin leg, not the whole world
      if (h > 0.08 && Math.max(w, d) > 0.14 && w < 25 && d < 25 && bb.max.y > 0.05)
        this.occ.push({ x0: bb.min.x, z0: bb.min.z, x1: bb.max.x, z1: bb.max.z, y0: bb.min.y, y1: bb.max.y, part: this.parts[layer].length });
    }
    this.parts[layer].push(g);
  }

  /** Box of size w×h×d whose BOTTOM centre sits at (x, y, z) in the current frame. */
  box(w: number, h: number, d: number, x: number, y: number, z: number, color: string, opt: BoxOpt = {}) {
    const layer = opt.layer ?? 'solid';
    // subdivide big solid boxes so the baked AO has vertices to work with (~0.5 m floors, ~0.6 m walls)
    let sx = 1, sy = 1, sz = 1;
    if (layer === 'solid' && this.ao && opt.seg !== 1) {
      const flat = h < 0.15;
      const cell = opt.seg ?? (flat ? 0.5 : 0.65);
      if (w > 1.2) sx = Math.min(28, Math.ceil(w / cell));
      if (d > 1.2) sz = Math.min(28, Math.ceil(d / cell));
      if (h > 1.2) sy = Math.min(8, Math.ceil(h / 0.6));
      if (flat) sy = 1;
    }
    const g = new BoxGeometry(w, h, d, sx, sy, sz);
    g.translate(0, h / 2, 0);
    this.push(g, color, layer, x, y, z, opt.rx, opt.ry, opt.rz, opt, true);
  }

  /** Cylinder whose bottom centre sits at (x, y, z). */
  cyl(rTop: number, rBot: number, h: number, x: number, y: number, z: number, color: string, opt: { seg?: number; rx?: number; ry?: number; rz?: number; layer?: Layer; mat?: Mat; uv?: number; occ?: boolean } = {}) {
    const g = new CylinderGeometry(rTop, rBot, h, opt.seg ?? 10, 1, false);
    g.translate(0, h / 2, 0);
    this.push(g, color, opt.layer ?? 'solid', x, y, z, opt.rx, opt.ry ?? 0, opt.rz, opt, Boolean(opt.occ));
  }

  /** Fake light pool on the floor: an additive disc, bright centre fading to nothing (vertex colours). */
  pool(x: number, z: number, r: number, color: string, y = 0.02, strength = 1) {
    const g = new CircleGeometry(r, 20, 0, Math.PI * 2);
    g.rotateX(-Math.PI / 2);
    // CircleGeometry has one centre vertex (index 0) and a rim: add a mid ring for a softer falloff
    const ring = new CircleGeometry(r * 0.55, 20);
    ring.rotateX(-Math.PI / 2);
    this.pushLight(g, color, x, y, z, (px, pz) => 1 - Math.min(1, Math.hypot(px - x, pz - z) / r), strength);
    this.pushLight(ring, color, x, y + 0.003, z, (px, pz) => Math.max(0, 1 - Math.hypot(px - x, pz - z) / (r * 0.55)) * 0.6, strength);
  }

  /** Fake light beam: an open cone from (x, y, z) down to the floor, bright at the top. */
  beam(x: number, y: number, z: number, rTop: number, rBot: number, color: string, strength = 0.5) {
    const g = new CylinderGeometry(rTop, rBot, y, 14, 1, true);
    g.translate(0, y / 2, 0);
    this.pushLight(g, color, x, 0, z, (_px, _pz, py) => Math.pow(py / y, 1.6), strength);
  }

  private pushLight(g: BufferGeometry, color: string, x: number, y: number, z: number, fall: (px: number, pz: number, py: number) => number, strength: number) {
    g.translate(x, y, z);
    g.applyMatrix4(this.frame);
    _c.set(color);
    const pos = g.attributes.position;
    const n = pos.count;
    const col = new Float32Array(n * 3);
    const uv = new Float32Array(n * 2);
    for (let i = 0; i < n; i++) {
      const px = pos.getX(i), py = pos.getY(i), pz = pos.getZ(i);
      const k = Math.max(0, fall(px, pz, py - y)) * strength;
      col[i * 3] = _c.r * k;
      col[i * 3 + 1] = _c.g * k;
      col[i * 3 + 2] = _c.b * k;
      uv[i * 2] = px;
      uv[i * 2 + 1] = pz;
    }
    g.deleteAttribute('uv');
    g.setAttribute('color', new Float32BufferAttribute(col, 3));
    g.setAttribute('feelUv', new Float32BufferAttribute(uv, 2));
    g.setAttribute('feelTile', new Float32BufferAttribute(new Float32Array(n), 1));
    // CircleGeometry / open cylinders are indexed like the boxes: fine for mergeGeometries
    this.parts.light.push(g);
  }

  /** Bake ambient occlusion into the solid parts' vertex colours. */
  private bakeAO() {
    const occ = this.occ;
    const list = this.parts.solid;
    for (let pi = 0; pi < list.length; pi++) {
      const g = list[pi];
      const pos = g.attributes.position;
      const nor = g.attributes.normal;
      const col = g.attributes.color as Float32BufferAttribute;
      g.computeBoundingBox();
      const bb = g.boundingBox!;
      // occluders near this part only
      const near: Occ[] = [];
      for (const o of occ) {
        if (o.part === pi) continue;
        if (o.x1 < bb.min.x - 0.8 || o.x0 > bb.max.x + 0.8 || o.z1 < bb.min.z - 0.8 || o.z0 > bb.max.z + 0.8) continue;
        if (o.y1 < bb.min.y - 0.05) continue;
        near.push(o);
      }
      const big = bb.max.x - bb.min.x > 25 || bb.max.z - bb.min.z > 25;
      for (let i = 0; i < pos.count; i++) {
        const px = pos.getX(i), py = pos.getY(i), pz = pos.getZ(i);
        const nx = nor.getX(i), ny = nor.getY(i), nz = nor.getZ(i);
        if (ny < -0.5) continue; // bottoms are never seen
        let o = 0;
        // contact: side faces darken towards the floor
        if (Math.abs(ny) < 0.5 && py > -0.1 && !big) o += 0.26 * (1 - smooth(0, 0.5, py));
        for (const c of near) {
          if (py > c.y1 + 0.04) continue;
          const dx = Math.max(c.x0 - px, 0, px - c.x1);
          const dz = Math.max(c.z0 - pz, 0, pz - c.z1);
          const d = Math.hypot(dx, dz);
          if (d > 0.75) continue;
          if (d < 1e-4) {
            // under something (floor under a bed / table / counter)
            if (py <= c.y0 + 0.02 && ny > 0.5) o += 0.42 * (1 - smooth(0, 1.1, c.y0 - py));
            continue;
          }
          const ux = -dx * Math.sign(px - (c.x0 + c.x1) / 2) / d;
          const uz = -dz * Math.sign(pz - (c.z0 + c.z1) / 2) / d;
          const facing = nx * ux + nz * uz + Math.max(ny, 0) * 0.85;
          if (facing <= 0.05) continue;
          const hf = Math.min(1, Math.max(0, (c.y1 - Math.max(py, c.y0)) / 0.7));
          o += 0.34 * Math.min(1, facing) * hf * Math.exp(-d / 0.3);
        }
        const k = 1 - Math.min(0.62, o);
        if (k < 0.999) {
          col.setX(i, col.getX(i) * k);
          col.setY(i, col.getY(i) * k);
          col.setZ(i, col.getZ(i) * k);
        }
      }
    }
  }

  /** Merge each layer into one geometry (null when empty). */
  finish(): Record<Layer, BufferGeometry | null> {
    if (this.ao) this.bakeAO();
    const out = {} as Record<Layer, BufferGeometry | null>;
    for (const k of LAYERS) {
      const list = this.parts[k];
      if (!list.length) {
        out[k] = null;
        continue;
      }
      for (const g of list) if (g.attributes.uv) g.deleteAttribute('uv');
      const m = mergeGeometries(list, false);
      for (const g of list) g.dispose();
      out[k] = m;
      if (m) this.tris += (m.index ? m.index.count : m.attributes.position.count) / 3;
    }
    return out;
  }
}

function smooth(a: number, b: number, x: number) {
  const t = Math.min(1, Math.max(0, (x - a) / (b - a)));
  return t * t * (3 - 2 * t);
}
