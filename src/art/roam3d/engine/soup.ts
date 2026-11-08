// Free roam: a tiny triangle-soup builder. Everything static in the street scene is poured into a few of these (positions +
// vertex colours, optional UVs) and turned into ONE mesh each, so the whole street costs a handful of draw calls.
// World axes: x = map x (east), y = up, z = map y (south). `tri`/`quad` take a hint normal and flip the winding to match it,
// so every face is front-facing from the outside without thinking about order.
import { BufferGeometry, Color, Float32BufferAttribute } from 'three';

const _c = new Color();
const _rgb = new Map<string, [number, number, number]>();

/** Growable float buffer (no JS array of numbers: a chunk's soup is a few hundred thousand floats, and garbage would show as hitches). */
class FBuf {
  a: Float32Array;
  n = 0;
  constructor(cap = 6144) {
    this.a = new Float32Array(cap);
  }
  ensure(extra: number) {
    if (this.n + extra <= this.a.length) return;
    const b = new Float32Array(Math.max(this.a.length * 2, this.n + extra));
    b.set(this.a.subarray(0, this.n));
    this.a = b;
  }
}

export class Soup {
  private p = new FBuf();
  private c = new FBuf();
  private nr = new FBuf();
  private t = new FBuf(4096);
  withUv = false;
  tris = 0;
  /** Keep only the triangles whose centre lies in [x0, z0, x1, z1) (a streaming chunk). */
  clip: [number, number, number, number] | null = null;

  /** Floats written to the position buffer (0 = nothing in this soup). */
  get size() {
    return this.p.n;
  }

  private rgb(hex: string | number | Color): [number, number, number] {
    if (typeof hex === 'string') {
      let v = _rgb.get(hex);
      if (!v) {
        _c.set(hex);
        v = [_c.r, _c.g, _c.b];
        _rgb.set(hex, v);
      }
      return v;
    }
    _c.set(hex as Color);
    return [_c.r, _c.g, _c.b];
  }

  /** One triangle; the winding is flipped if it disagrees with the hint normal (nx, ny, nz). */
  tri(ax: number, ay: number, az: number, bx: number, by: number, bz: number, cx: number, cy: number, cz: number, hex: string | number | Color, nx: number, ny: number, nz: number, ka = 1, kb = ka, kc = ka) {
    if (this.clip) {
      const mx = (ax + bx + cx) / 3, mz = (az + bz + cz) / 3;
      const k = this.clip;
      if (mx < k[0] || mx >= k[2] || mz < k[1] || mz >= k[3]) return;
    }
    const ux = bx - ax, uy = by - ay, uz = bz - az;
    const vx = cx - ax, vy = cy - ay, vz = cz - az;
    let dx = uy * vz - uz * vy, dy = uz * vx - ux * vz, dz = ux * vy - uy * vx;
    const flip = dx * nx + dy * ny + dz * nz < 0;
    const l = Math.hypot(dx, dy, dz);
    if (l < 1e-12) return; // a degenerate sliver draws nothing
    dx /= l; dy /= l; dz /= l;
    if (flip) { dx = -dx; dy = -dy; dz = -dz; }
    const [r, g, b] = this.rgb(hex);
    const P = this.p, C = this.c, N = this.nr;
    P.ensure(9); C.ensure(9); N.ensure(9);
    const o = P.n;
    const pa = P.a, ca = C.a, na = N.a;
    if (!flip) {
      pa[o] = ax; pa[o + 1] = ay; pa[o + 2] = az; pa[o + 3] = bx; pa[o + 4] = by; pa[o + 5] = bz; pa[o + 6] = cx; pa[o + 7] = cy; pa[o + 8] = cz;
      ca[o] = r * ka; ca[o + 1] = g * ka; ca[o + 2] = b * ka; ca[o + 3] = r * kb; ca[o + 4] = g * kb; ca[o + 5] = b * kb; ca[o + 6] = r * kc; ca[o + 7] = g * kc; ca[o + 8] = b * kc;
    } else {
      pa[o] = ax; pa[o + 1] = ay; pa[o + 2] = az; pa[o + 3] = cx; pa[o + 4] = cy; pa[o + 5] = cz; pa[o + 6] = bx; pa[o + 7] = by; pa[o + 8] = bz;
      ca[o] = r * ka; ca[o + 1] = g * ka; ca[o + 2] = b * ka; ca[o + 3] = r * kc; ca[o + 4] = g * kc; ca[o + 5] = b * kc; ca[o + 6] = r * kb; ca[o + 7] = g * kb; ca[o + 8] = b * kb;
    }
    for (let i = 0; i < 9; i += 3) { na[o + i] = dx; na[o + i + 1] = dy; na[o + i + 2] = dz; }
    P.n += 9; C.n += 9; N.n += 9;
    if (this.withUv) { this.t.ensure(6); this.t.n += 6; }
    this.tris++;
  }

  /** Quad a-b-c-d (in order around it) facing the hint normal. k0 darkens a and b, k1 darkens c and d (a soft ground contact). */
  quad(a: number[], b: number[], c: number[], d: number[], hex: string | number | Color, n: number[], k0 = 1, k1 = k0) {
    this.tri(a[0], a[1], a[2], b[0], b[1], b[2], c[0], c[1], c[2], hex, n[0], n[1], n[2], k0, k0, k1);
    this.tri(a[0], a[1], a[2], c[0], c[1], c[2], d[0], d[1], d[2], hex, n[0], n[1], n[2], k0, k1, k1);
  }

  /** Quad with UVs (u0,v0 at a, u1,v1 at c); a-b is the bottom edge, c-d the top. */
  quadUv(a: number[], b: number[], c: number[], d: number[], n: number[], u0: number, v0: number, u1: number, v1: number, hex: string | number | Color = '#ffffff') {
    const n0 = this.p.n;
    const wasUv = this.withUv;
    this.withUv = false;
    this.quad(a, b, c, d, hex, n);
    this.withUv = wasUv;
    if (!wasUv) return;
    // the vertices that survived the clip: look each corner up by position
    const corners = [a, b, c, d];
    const uvs = [[u0, v0], [u1, v0], [u1, v1], [u0, v1]];
    const P = this.p.a;
    this.t.ensure((this.p.n - n0) / 3 * 2);
    for (let i = n0; i < this.p.n; i += 3) {
      let uv = uvs[0];
      for (let k = 0; k < 4; k++) {
        const q = corners[k];
        if (Math.abs(P[i] - q[0]) < 1e-4 && Math.abs(P[i + 1] - q[1]) < 1e-4 && Math.abs(P[i + 2] - q[2]) < 1e-4) { uv = uvs[k]; break; }
      }
      this.t.a[this.t.n++] = uv[0];
      this.t.a[this.t.n++] = uv[1];
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
    g.setAttribute('position', new Float32BufferAttribute(this.p.a.slice(0, this.p.n), 3));
    g.setAttribute('color', new Float32BufferAttribute(this.c.a.slice(0, this.c.n), 3));
    g.setAttribute('normal', new Float32BufferAttribute(this.nr.a.slice(0, this.nr.n), 3));
    if (this.withUv) g.setAttribute('uv', new Float32BufferAttribute(this.t.a.slice(0, this.t.n), 2));
    g.computeBoundingSphere();
    return g;
  }
}
