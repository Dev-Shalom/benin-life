// Geometry builder for the 3D home: every static part is a box/cylinder with a vertex colour,
// merged into a handful of meshes (one Lambert mesh for nearly everything, one unlit mesh for things
// that glow at night, one for glass, one for screens). So a whole furnished home costs ~4 draw calls.
import {
  BoxGeometry,
  BufferGeometry,
  Color,
  CylinderGeometry,
  Float32BufferAttribute,
  Matrix4,
  Quaternion,
  Euler,
  Vector3,
} from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';

export type Layer = 'solid' | 'glow' | 'glass' | 'screen';

const _c = new Color();
const _m = new Matrix4();
const _q = new Quaternion();
const _e = new Euler();
const _p = new Vector3();
const _s = new Vector3(1, 1, 1);

export class HomeBuilder {
  private parts: Record<Layer, BufferGeometry[]> = { solid: [], glow: [], glass: [], screen: [] };
  /** Current piece frame (position + yaw), applied after the part's own transform. */
  frame = new Matrix4();
  tris = 0;

  setFrame(x: number, y: number, z: number, yaw: number) {
    _q.setFromEuler(_e.set(0, yaw, 0));
    this.frame.compose(_p.set(x, y, z), _q, _s.set(1, 1, 1));
  }

  resetFrame() {
    this.frame.identity();
  }

  private push(g: BufferGeometry, color: string, layer: Layer, x: number, y: number, z: number, rx = 0, ry = 0, rz = 0) {
    _q.setFromEuler(_e.set(rx, ry, rz));
    _m.compose(_p.set(x, y, z), _q, _s.set(1, 1, 1));
    g.applyMatrix4(_m);
    g.applyMatrix4(this.frame);
    _c.set(color);
    const n = g.attributes.position.count;
    const col = new Float32Array(n * 3);
    for (let i = 0; i < n; i++) {
      col[i * 3] = _c.r;
      col[i * 3 + 1] = _c.g;
      col[i * 3 + 2] = _c.b;
    }
    g.setAttribute('color', new Float32BufferAttribute(col, 3));
    this.parts[layer].push(g);
  }

  /** Box of size w×h×d whose BOTTOM centre sits at (x, y, z) in the current frame. */
  box(w: number, h: number, d: number, x: number, y: number, z: number, color: string, opt: { ry?: number; rx?: number; rz?: number; layer?: Layer } = {}) {
    const g = new BoxGeometry(w, h, d);
    g.translate(0, h / 2, 0);
    this.push(g, color, opt.layer ?? 'solid', x, y, z, opt.rx, opt.ry, opt.rz);
  }

  /** Cylinder whose bottom centre sits at (x, y, z). */
  cyl(rTop: number, rBot: number, h: number, x: number, y: number, z: number, color: string, opt: { seg?: number; rx?: number; ry?: number; rz?: number; layer?: Layer } = {}) {
    const g = new CylinderGeometry(rTop, rBot, h, opt.seg ?? 10, 1, false);
    g.translate(0, h / 2, 0);
    this.push(g, color, opt.layer ?? 'solid', x, y, z, opt.rx, opt.ry ?? 0, opt.rz);
  }

  /** Merge each layer into one geometry (null when empty). */
  finish(): Record<Layer, BufferGeometry | null> {
    const out = {} as Record<Layer, BufferGeometry | null>;
    for (const k of Object.keys(this.parts) as Layer[]) {
      const list = this.parts[k];
      if (!list.length) {
        out[k] = null;
        continue;
      }
      // all parts are indexed with position/normal/uv/color; drop uv (no textures) to save memory
      for (const g of list) g.deleteAttribute('uv');
      const m = mergeGeometries(list, false);
      for (const g of list) g.dispose();
      out[k] = m;
      if (m) this.tris += (m.index ? m.index.count : m.attributes.position.count) / 3;
    }
    return out;
  }
}
