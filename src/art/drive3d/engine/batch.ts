// Merge many small static parts into a few draw calls (cheap Android phones: draw calls matter more than triangles).
// ColorBatch: parts carry their own colour as vertex colours -> ONE mesh with a vertex-colour material.
// MatBatch: parts keep one material each (for materials that change at runtime) -> one mesh per material.
import { BufferAttribute, BufferGeometry, Color, Group, Material, Mesh, MeshLambertMaterial } from 'three';
import { mergeGeometries } from 'three/examples/jsm/utils/BufferGeometryUtils.js';

function flat(g: BufferGeometry): BufferGeometry {
  return g.index ? g.toNonIndexed() : g;
}

function placed(g: BufferGeometry, x: number, y: number, z: number, rx = 0, ry = 0, rz = 0): BufferGeometry {
  if (rx) g.rotateX(rx);
  if (ry) g.rotateY(ry);
  if (rz) g.rotateZ(rz);
  g.translate(x, y, z);
  return flat(g);
}

export class ColorBatch {
  private parts: BufferGeometry[] = [];

  add(g: BufferGeometry, hex: string | number, x = 0, y = 0, z = 0, rx = 0, ry = 0, rz = 0): this {
    const p = placed(g, x, y, z, rx, ry, rz);
    const c = new Color(hex);
    const n = p.getAttribute('position').count;
    const a = new Float32Array(n * 3);
    for (let i = 0; i < n; i++) {
      a[i * 3] = c.r;
      a[i * 3 + 1] = c.g;
      a[i * 3 + 2] = c.b;
    }
    p.setAttribute('color', new BufferAttribute(a, 3));
    p.deleteAttribute('uv');
    this.parts.push(p);
    return this;
  }

  /** One mesh (Lambert, vertex colours) or null when empty. The geometry and material are returned for disposal. */
  build(material?: Material): { mesh: Mesh; geometry: BufferGeometry; material: Material } | null {
    if (!this.parts.length) return null;
    const geometry = mergeGeometries(this.parts, false);
    this.parts.forEach((p) => p.dispose());
    this.parts = [];
    const mat = material ?? new MeshLambertMaterial({ vertexColors: true });
    return { mesh: new Mesh(geometry, mat), geometry, material: mat };
  }
}

export class MatBatch {
  private parts = new Map<Material, BufferGeometry[]>();

  add(m: Material, g: BufferGeometry, x = 0, y = 0, z = 0, rx = 0, ry = 0, rz = 0): this {
    const p = placed(g, x, y, z, rx, ry, rz);
    p.deleteAttribute('uv');
    const list = this.parts.get(m);
    if (list) list.push(p);
    else this.parts.set(m, [p]);
    return this;
  }

  /** Adds one merged mesh per material to `group`; returns the merged geometries to dispose. */
  build(group: Group): BufferGeometry[] {
    const out: BufferGeometry[] = [];
    for (const [m, list] of this.parts) {
      const g = mergeGeometries(list, false);
      list.forEach((p) => p.dispose());
      out.push(g);
      group.add(new Mesh(g, m));
    }
    this.parts.clear();
    return out;
  }
}
