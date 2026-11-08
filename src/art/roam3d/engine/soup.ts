// Free roam: a tiny triangle-soup builder. Everything static in the street scene is poured into a few of these (positions +
// vertex colours, optional UVs) and turned into ONE mesh each, so the whole street costs a handful of draw calls.
// World axes: x = map x (east), y = up, z = map y (south). `tri`/`quad` take a hint normal and flip the winding to match it,
// so every face is front-facing from the outside without thinking about order.
import { BufferGeometry, Color, Float32BufferAttribute } from 'three';

const _c = new Color();

export class Soup {
  pos: number[] = [];
  col: number[] = [];
  uv: number[] = [];
  withUv = false;
  tris = 0;

  private color(hex: string | number | Color, k = 1): [number, number, number] {
    _c.set(hex as string);
    return [_c.r * k, _c.g * k, _c.b * k];
  }

  /** One triangle; the winding is flipped if it disagrees with the hint normal (nx, ny, nz). */
  tri(ax: number, ay: number, az: number, bx: number, by: number, bz: number, cx: number, cy: number, cz: number, hex: string | number | Color, nx: number, ny: number, nz: number, ka = 1, kb = ka, kc = ka) {
    const ux = bx - ax, uy = by - ay, uz = bz - az;
    const vx = cx - ax, vy = cy - ay, vz = cz - az;
    const dx = uy * vz - uz * vy, dy = uz * vx - ux * vz, dz = ux * vy - uy * vx;
    const flip = dx * nx + dy * ny + dz * nz < 0;
    const A = this.color(hex, ka), B = this.color(hex, kb), C = this.color(hex, kc);
    if (!flip) this.push3(ax, ay, az, A, bx, by, bz, B, cx, cy, cz, C);
    else this.push3(ax, ay, az, A, cx, cy, cz, C, bx, by, bz, B);
    if (this.withUv) this.uv.push(0, 0, 0, 0, 0, 0);
    this.tris++;
  }

  private push3(ax: number, ay: number, az: number, A: number[], bx: number, by: number, bz: number, B: number[], cx: number, cy: number, cz: number, C: number[]) {
    this.pos.push(ax, ay, az, bx, by, bz, cx, cy, cz);
    this.col.push(A[0], A[1], A[2], B[0], B[1], B[2], C[0], C[1], C[2]);
  }

  /** Quad a-b-c-d (in order around it) facing the hint normal. k0 darkens a and b, k1 darkens c and d (a soft ground contact). */
  quad(a: number[], b: number[], c: number[], d: number[], hex: string | number | Color, n: number[], k0 = 1, k1 = k0) {
    this.tri(a[0], a[1], a[2], b[0], b[1], b[2], c[0], c[1], c[2], hex, n[0], n[1], n[2], k0, k0, k1);
    this.tri(a[0], a[1], a[2], c[0], c[1], c[2], d[0], d[1], d[2], hex, n[0], n[1], n[2], k0, k1, k1);
  }

  /** Quad with UVs (u0,v0 at a, u1,v1 at c); a-b is the bottom edge, c-d the top. */
  quadUv(a: number[], b: number[], c: number[], d: number[], n: number[], u0: number, v0: number, u1: number, v1: number, hex: string | number | Color = '#ffffff') {
    const before = this.uv.length;
    const wasUv = this.withUv;
    this.withUv = false;
    this.quad(a, b, c, d, hex, n);
    this.withUv = wasUv;
    // six vertices: (a b c) (a c d) in the winding that was used, so look the corner up by position
    const cs: Record<string, [number, number]> = {};
    const key = (p: number[]) => `${p[0].toFixed(4)},${p[1].toFixed(4)},${p[2].toFixed(4)}`;
    cs[key(a)] = [u0, v0];
    cs[key(b)] = [u1, v0];
    cs[key(c)] = [u1, v1];
    cs[key(d)] = [u0, v1];
    const base = this.pos.length - 18;
    for (let i = 0; i < 6; i++) {
      const k = `${this.pos[base + i * 3].toFixed(4)},${this.pos[base + i * 3 + 1].toFixed(4)},${this.pos[base + i * 3 + 2].toFixed(4)}`;
      const uv = cs[k] ?? [0, 0];
      this.uv[before + i * 2] = uv[0];
      this.uv[before + i * 2 + 1] = uv[1];
    }
  }

  /** Axis-aligned-in-its-own-frame box: centre (cx, cz), base y0, size sx (along the heading a), sy (up), sz (across), yaw a (map angle). */
  box(cx: number, y0: number, cz: number, sx: number, sy: number, sz: number, a: number, hex: string | number | Color, ao = 0.82, top?: string | number | Color) {
    const c = Math.cos(a), s = Math.sin(a);
    const hx = sx / 2, hz = sz / 2;
    const P = (lx: number, y: number, lz: number) => [cx + lx * c - lz * s, y, cz + lx * s + lz * c];
    const y1 = y0 + sy;
    const p000 = P(-hx, y0, -hz), p100 = P(hx, y0, -hz), p110 = P(hx, y0, hz), p010 = P(-hx, y0, hz);
    const q000 = P(-hx, y1, -hz), q100 = P(hx, y1, -hz), q110 = P(hx, y1, hz), q010 = P(-hx, y1, hz);
    const nxp = [c, 0, s], nzp = [-s, 0, c];
    this.quad(p100, p110, q110, q100, hex, nxp, ao, 1);
    this.quad(p010, p000, q000, q010, hex, [-c, 0, -s], ao, 1);
    this.quad(p110, p010, q010, q110, hex, nzp, ao, 1);
    this.quad(p000, p100, q100, q000, hex, [s, 0, -c], ao, 1);
    this.quad(q000, q100, q110, q010, top ?? hex, [0, 1, 0]);
  }

  /** Upright cylinder / cone with `n` sides. */
  cyl(cx: number, y0: number, cz: number, rBot: number, rTop: number, h: number, hex: string | number | Color, n = 7, ao = 0.85) {
    for (let i = 0; i < n; i++) {
      const a0 = (i / n) * Math.PI * 2, a1 = ((i + 1) / n) * Math.PI * 2;
      const am = (a0 + a1) / 2;
      const x0 = Math.cos(a0), z0 = Math.sin(a0), x1 = Math.cos(a1), z1 = Math.sin(a1);
      const nrm = [Math.cos(am), 0.15, Math.sin(am)];
      const A = [cx + x0 * rBot, y0, cz + z0 * rBot], B = [cx + x1 * rBot, y0, cz + z1 * rBot];
      const C = [cx + x1 * rTop, y0 + h, cz + z1 * rTop], D = [cx + x0 * rTop, y0 + h, cz + z0 * rTop];
      this.quad(A, B, C, D, hex, nrm, ao, 1);
      if (rTop > 0.001) this.tri(D[0], D[1], D[2], C[0], C[1], C[2], cx, y0 + h, cz, hex, 0, 1, 0);
    }
  }

  /** Flat horizontal quad strip between two points (width w) at height y. */
  strip(ax: number, az: number, bx: number, bz: number, w: number, y: number, hex: string | number | Color) {
    const dx = bx - ax, dz = bz - az;
    const l = Math.hypot(dx, dz) || 1;
    const nx = (-dz / l) * (w / 2), nz = (dx / l) * (w / 2);
    this.quad([ax + nx, y, az + nz], [bx + nx, y, bz + nz], [bx - nx, y, bz - nz], [ax - nx, y, az - nz], hex, [0, 1, 0]);
  }

  geometry(): BufferGeometry {
    const g = new BufferGeometry();
    g.setAttribute('position', new Float32BufferAttribute(this.pos, 3));
    g.setAttribute('color', new Float32BufferAttribute(this.col, 3));
    if (this.withUv) g.setAttribute('uv', new Float32BufferAttribute(this.uv, 2));
    g.computeVertexNormals();
    g.computeBoundingSphere();
    return g;
  }
}

/**
 * A soup split into square chunks (by triangle centroid) so the GPU can skip the ones that are off screen: one mesh per chunk,
 * each with its own bounding sphere. Same API as Soup (every shape ends in `tri`).
 */
export class ChunkedSoup extends Soup {
  readonly chunks = new Map<string, Soup>();
  private size: number;
  constructor(size = 140) {
    super();
    this.size = size;
  }
  override tri(ax: number, ay: number, az: number, bx: number, by: number, bz: number, cx: number, cy: number, cz: number, hex: string | number | Color, nx: number, ny: number, nz: number, ka = 1, kb = ka, kc = ka) {
    const k = `${Math.floor((ax + bx + cx) / 3 / this.size)},${Math.floor((az + bz + cz) / 3 / this.size)}`;
    let s = this.chunks.get(k);
    if (!s) this.chunks.set(k, (s = new Soup()));
    s.tri(ax, ay, az, bx, by, bz, cx, cy, cz, hex, nx, ny, nz, ka, kb, kc);
    this.tris++;
  }
}
