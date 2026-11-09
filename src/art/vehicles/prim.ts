// Shared vehicle library: small geometry primitives (no colours, positions + normals only). The kit colours and merges them.
// Everything is built once per kind and cached, so none of this runs per frame.
import { BoxGeometry, BufferAttribute, BufferGeometry, CylinderGeometry, Float32BufferAttribute, Quaternion, SphereGeometry, Vector3 } from 'three';

const clamp = (v: number, a: number, b: number) => Math.max(a, Math.min(b, v));

/** A box with rounded edges and true rounded normals (smooth shading on a 48-triangle part). Centred on the origin. */
export function rbox(w: number, h: number, d: number, r = Math.min(w, h, d) * 0.3, seg = 2): BufferGeometry {
  r = Math.max(0.002, Math.min(r, w / 2 - 1e-3, h / 2 - 1e-3, d / 2 - 1e-3));
  const g = new BoxGeometry(w, h, d, seg, seg, seg);
  const p = g.getAttribute('position') as BufferAttribute;
  const n = g.getAttribute('normal') as BufferAttribute;
  const hx = w / 2 - r;
  const hy = h / 2 - r;
  const hz = d / 2 - r;
  for (let i = 0; i < p.count; i++) {
    const x = p.getX(i);
    const y = p.getY(i);
    const z = p.getZ(i);
    const cx = clamp(x, -hx, hx);
    const cy = clamp(y, -hy, hy);
    const cz = clamp(z, -hz, hz);
    let dx = x - cx;
    let dy = y - cy;
    let dz = z - cz;
    const l = Math.hypot(dx, dy, dz);
    if (l < 1e-9) continue;
    dx /= l;
    dy /= l;
    dz /= l;
    p.setXYZ(i, cx + dx * r, cy + dy * r, cz + dz * r);
    n.setXYZ(i, dx, dy, dz);
  }
  g.deleteAttribute('uv');
  return g;
}

/** Ellipsoid with radii (rx, ry, rz) centred on the origin. */
export function ell(rx: number, ry: number, rz: number, ws = 10, hs = 6): BufferGeometry {
  const g = new SphereGeometry(1, ws, hs);
  g.scale(rx, ry, rz);
  g.deleteAttribute('uv');
  return g;
}

/** A cylinder from a to b (radius r), `seg` sides. */
export function rod(a: [number, number, number], b: [number, number, number], r: number, seg = 5, r2 = r): BufferGeometry {
  const va = new Vector3(...a);
  const vb = new Vector3(...b);
  const dir = vb.clone().sub(va);
  const len = dir.length();
  const g = new CylinderGeometry(r2, r, len, seg, 1, false);
  const q = new Quaternion().setFromUnitVectors(new Vector3(0, 1, 0), dir.normalize());
  g.applyQuaternion(q);
  const m = va.clone().add(vb).multiplyScalar(0.5);
  g.translate(m.x, m.y, m.z);
  g.deleteAttribute('uv');
  return g;
}

/** A cylinder along the x axis (wheel-like), centred on the origin. */
export function cylX(r: number, len: number, seg = 10, r2 = r): BufferGeometry {
  const g = new CylinderGeometry(r2, r, len, seg, 1, false);
  g.rotateZ(Math.PI / 2);
  g.deleteAttribute('uv');
  return g;
}

/** A cylinder along the z axis, centred on the origin. */
export function cylZ(r: number, len: number, seg = 10, r2 = r): BufferGeometry {
  const g = new CylinderGeometry(r2, r, len, seg, 1, false);
  g.rotateX(Math.PI / 2);
  g.deleteAttribute('uv');
  return g;
}

/** Monotone cubic interpolation through (x, y) knots: smooth, never overshoots. */
export function pchip(pts: [number, number][]): (x: number) => number {
  const n = pts.length;
  const xs = pts.map((p) => p[0]);
  const ys = pts.map((p) => p[1]);
  const d: number[] = [];
  const h: number[] = [];
  for (let i = 0; i < n - 1; i++) {
    h.push(xs[i + 1] - xs[i]);
    d.push((ys[i + 1] - ys[i]) / (xs[i + 1] - xs[i]));
  }
  const m: number[] = new Array(n).fill(0);
  if (n === 2) m[0] = m[1] = d[0];
  else {
    for (let i = 1; i < n - 1; i++) m[i] = d[i - 1] * d[i] <= 0 ? 0 : (2 * d[i - 1] * d[i]) / (d[i - 1] + d[i]);
    m[0] = d[0];
    m[n - 1] = d[n - 2];
  }
  return (x: number) => {
    if (x <= xs[0]) return ys[0];
    if (x >= xs[n - 1]) return ys[n - 1];
    let i = 0;
    while (x > xs[i + 1]) i++;
    const t = (x - xs[i]) / h[i];
    const t2 = t * t;
    const t3 = t2 * t;
    return (2 * t3 - 3 * t2 + 1) * ys[i] + (t3 - 2 * t2 + t) * h[i] * m[i] + (-2 * t3 + 3 * t2) * ys[i + 1] + (t3 - t2) * h[i] * m[i + 1];
  };
}

/** Catmull-Rom subdivision of an open polyline: `sub` extra points per segment. */
export function smoothPoly(pts: [number, number][], sub: number): [number, number][] {
  if (sub <= 0) return pts.slice();
  const out: [number, number][] = [];
  const n = pts.length;
  for (let i = 0; i < n - 1; i++) {
    const p0 = pts[Math.max(0, i - 1)];
    const p1 = pts[i];
    const p2 = pts[i + 1];
    const p3 = pts[Math.min(n - 1, i + 2)];
    for (let k = 0; k <= sub; k++) {
      if (i > 0 && k === 0) continue;
      const t = k / (sub + 1);
      const t2 = t * t;
      const t3 = t2 * t;
      out.push([
        0.5 * (2 * p1[0] + (-p0[0] + p2[0]) * t + (2 * p0[0] - 5 * p1[0] + 4 * p2[0] - p3[0]) * t2 + (-p0[0] + 3 * p1[0] - 3 * p2[0] + p3[0]) * t3),
        0.5 * (2 * p1[1] + (-p0[1] + p2[1]) * t + (2 * p0[1] - 5 * p1[1] + 4 * p2[1] - p3[1]) * t2 + (-p0[1] + 3 * p1[1] - 3 * p2[1] + p3[1]) * t3),
      ]);
    }
  }
  out.push(pts[n - 1]);
  return out;
}

export interface Ring {
  z: number;
  /** Closed loop (x, y) points around the section. */
  pts: [number, number][];
}

/** Mirror a right-hand half profile (bottom centre -> top centre, x >= 0) into a closed ring. */
export function mirrorRing(half: [number, number][]): [number, number][] {
  const out: [number, number][] = half.map((p) => [p[0], p[1]]);
  for (let i = half.length - 2; i >= 1; i--) out.push([-half[i][0], half[i][1]]);
  return out;
}

/**
 * Loft a list of rings (same point count) into an indexed, smoothly shaded surface.
 * `closed` wraps the last point to the first; `capStart` / `capEnd` close the ends with a fan; `ref` gives the interior reference
 * point of ring i (default: the ring's centroid) used to turn every face outward.
 */
export function loft(rings: Ring[], o: { closed?: boolean; capStart?: boolean; capEnd?: boolean; ref?: (i: number) => [number, number]; inward?: boolean; flat?: boolean } = {}): BufferGeometry {
  const closed = o.closed ?? true;
  const M = rings[0].pts.length;
  const pos: number[] = [];
  for (const r of rings) for (const p of r.pts) pos.push(p[0], p[1], r.z);
  const idx: number[] = [];
  const segs = closed ? M : M - 1;
  for (let i = 0; i < rings.length - 1; i++) {
    for (let j = 0; j < segs; j++) {
      const a = i * M + j;
      const b = i * M + ((j + 1) % M);
      const c = (i + 1) * M + j;
      const d = (i + 1) * M + ((j + 1) % M);
      idx.push(a, c, b, b, c, d);
    }
  }
  const g = new BufferGeometry();
  g.setAttribute('position', new Float32BufferAttribute(pos, 3));
  g.setIndex(idx);
  // turn every face outward: compare the face normal with the direction from the ring's reference point
  let sign = 0;
  for (let t = 0; t < idx.length; t += 3) {
    const ia = idx[t] * 3;
    const ib = idx[t + 1] * 3;
    const ic = idx[t + 2] * 3;
    const ax = pos[ia], ay = pos[ia + 1], az = pos[ia + 2];
    const ux = pos[ib] - ax, uy = pos[ib + 1] - ay, uz = pos[ib + 2] - az;
    const vx = pos[ic] - ax, vy = pos[ic + 1] - ay, vz = pos[ic + 2] - az;
    const nx = uy * vz - uz * vy, ny = uz * vx - ux * vz;
    const ri = Math.min(rings.length - 1, Math.floor(idx[t] / M));
    let rx: number, ry: number;
    if (o.ref) [rx, ry] = o.ref(ri);
    else {
      rx = 0;
      ry = 0;
      for (const p of rings[ri].pts) {
        rx += p[0];
        ry += p[1];
      }
      rx /= M;
      ry /= M;
    }
    sign += nx * (ax - rx) + ny * (ay - ry);
  }
  if (sign < 0 !== !!o.inward) {
    for (let t = 0; t < idx.length; t += 3) {
      const b = idx[t + 1];
      idx[t + 1] = idx[t + 2];
      idx[t + 2] = b;
    }
    g.setIndex(idx);
  }
  // end caps: a fan to the ring centroid, wound to face away from the body along z
  const cap = (ri: number, nzWant: number) => {
    const r = rings[ri];
    let cx = 0;
    let cy = 0;
    for (const p of r.pts) {
      cx += p[0];
      cy += p[1];
    }
    cx /= M;
    cy /= M;
    const c = pos.length / 3;
    pos.push(cx, cy, r.z);
    for (let j = 0; j < M; j++) {
      const a = ri * M + j;
      const b = ri * M + ((j + 1) % M);
      const ax = pos[a * 3], ay = pos[a * 3 + 1];
      const bx = pos[b * 3], by = pos[b * 3 + 1];
      const nz = (ax - cx) * (by - cy) - (ay - cy) * (bx - cx);
      if (nz * nzWant > 0) idx.push(c, a, b);
      else idx.push(c, b, a);
    }
  };
  if (o.capStart && closed) cap(0, -1);
  if (o.capEnd && closed) cap(rings.length - 1, 1);
  if (o.capStart || o.capEnd) {
    g.setAttribute('position', new Float32BufferAttribute(pos, 3));
    g.setIndex(idx);
  }
  g.computeVertexNormals();
  if (o.flat) {
    const f = g.toNonIndexed();
    g.dispose();
    f.computeVertexNormals();
    return f;
  }
  return g;
}

/** A filled polygon (x, y) lying in a plane, as a fan from its centre; used for wheel-arch liners and decals. */
export function fan(pts: [number, number, number][], c: [number, number, number]): BufferGeometry {
  const pos: number[] = [...c];
  for (const p of pts) pos.push(p[0], p[1], p[2]);
  const idx: number[] = [];
  for (let i = 1; i < pts.length; i++) idx.push(0, i, i + 1);
  const g = new BufferGeometry();
  g.setAttribute('position', new Float32BufferAttribute(pos, 3));
  g.setIndex(idx);
  g.computeVertexNormals();
  return g;
}
