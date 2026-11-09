// Shared vehicle library: the lofted car body used by every four-wheeler (sedans, hatchback, SUVs, pickup, minibus).
// A car is a design: tables over z (plan width, sill height, shoulder height) that a smooth cross-section is swept along, a glass
// greenhouse swept the same way with a body-colour roof panel and dark pillars, then the details (grille, lamps, plates, mirrors,
// handles, door seams, arch liners, bumpers). Real proportions, original shapes. Metres, nose -z.
import { BoxGeometry, BufferGeometry, Float32BufferAttribute, PlaneGeometry } from 'three';
import { Kit, type Role } from './kit';
import { fan, loft, mirrorRing, pchip, rbox, rod, smoothPoly, cylZ, type Ring } from './prim';
import { wheelParts } from './wheels';

type Tab = [number, number][];

export interface CarDesign {
  /** Overall length and the widest half width of the body. */
  L: number;
  hw: number;
  /** Over z (nose -L/2 .. tail +L/2): plan width factor, underside height, shoulder (top of the lower body) height, centre crown. */
  plan: Tab;
  y0: Tab;
  y1: Tab;
  crown: Tab;
  /** Greenhouse stations: z and roof height. First and last sit on the body (the windscreen and rear glass bases). */
  cab: { z: number; top: number; hwt?: number }[];
  cabBase: number;
  hwb: number;
  hwt: number;
  /** Cab station indexes between which the roof panel runs. */
  roof: [number, number];
  /** Door seams (z), the A pillar base z is cab[0].z. */
  seams: number[];
  /** z of the B-type pillars (default: the second seam). */
  posts?: number[];
  /** Angular, flat-shaded panels (a wedge truck) instead of smooth curves. */
  crisp?: boolean;
  /** Black pillars and frame under a body-colour roof (a floating-roof look); otherwise the whole greenhouse shell is body colour. */
  dark?: boolean;
  /** Rear-door spare wheel with a cover (an upright off-roader). */
  spare?: boolean;
  /** Running boards / side steps. */
  wheel: { zf: number; zr: number; r: number; wid: number; x: number };
  /** Lamp shapes. */
  head: { w: number; h: number; y: number; yaw?: number; drl?: boolean; round?: boolean };
  tail: { w: number; h: number; y: number; bar?: boolean };
  grille: { w: number; h: number; y: number; style: 'sedan' | 'suv' | 'lux' | 'van' };
  plateY: [number, number];
  /** Optional features. */
  rails?: boolean;
  sill?: number;
  cladding?: boolean;
  fin?: boolean;
  running?: boolean;
  /** Rear: 'boot' (sedan), 'hatch' (steep glass), 'tail' (SUV/van tailgate). */
  rear: 'boot' | 'hatch' | 'tail';
  exhaust?: boolean;
  /** Pickup: bed from this z to the tail; wall height above the shoulder. */
  bed?: { z0: number; wall: number };
  /** Sliding door (van): z range of the door on the right side. */
  slide?: [number, number];
  mirrorZ: number;
}

/** 3 x 5 pixel font for the plates (rows top to bottom). */
const FONT: Record<string, string[]> = {
  A: ['010', '101', '111', '101', '101'],
  B: ['110', '101', '110', '101', '110'],
  D: ['110', '101', '101', '101', '110'],
  E: ['111', '100', '110', '100', '111'],
  N: ['101', '111', '111', '101', '101'],
  O: ['111', '101', '101', '101', '111'],
  '1': ['010', '110', '010', '010', '111'],
  '2': ['110', '001', '010', '100', '111'],
  '3': ['110', '001', '010', '001', '110'],
};

/**
 * A generic Nigerian-style plate: white, a green band along the top, the letters read correctly from outside.
 * `face` +1 = rear (seen from +z), -1 = front (seen from -z). Near detail draws "BEN 123 AB"; far levels only the plate.
 */
export function plate(K: Kit, x: number, y: number, z: number, face: 1 | -1, w = 0.5, text = 'BEN 123 AB') {
  const h = w * 0.24;
  K.put(rbox(w, h, 0.025, 0.006, 1), 'plate', x, y, z + face * 0.008);
  K.put(rbox(w * 0.96, h * 0.14, 0.006, 0.002, 1), 'plateband', x, y + h * 0.4, z + face * 0.022);
  if (K.lod > 0) return;
  // layout in the plate's own plane: u to the viewer's right, v up
  const chars = [...text];
  const unit = (w * 0.9) / (chars.length * 4 - 1); // one pixel step: letters are 3 px wide plus 1 px gap
  const px = unit * 0.82;
  const rowH = (h * 0.52) / 5;
  const total = chars.length * 4 * unit - unit;
  const quads: BufferGeometry[] = [];
  chars.forEach((c, i) => {
    const glyph = FONT[c];
    if (!glyph) return;
    for (let r = 0; r < 5; r++) {
      let col = 0;
      while (col < 3) {
        if (glyph[r][col] !== '1') {
          col++;
          continue;
        }
        let end = col;
        while (end + 1 < 3 && glyph[r][end + 1] === '1') end++;
        const wq = (end - col + 1) * unit - (unit - px);
        const q = new PlaneGeometry(wq, rowH * 0.92);
        const u = -total / 2 + (i * 4 + col) * unit + wq / 2;
        q.translate(u, (2 - r) * rowH - h * 0.08, 0);
        if (face === -1) q.rotateY(Math.PI);
        q.translate(x, y, z + face * 0.036);
        quads.push(q);
        col = end + 1;
      }
    }
  });
  quads.forEach((q) => K.add(q, 'trim'));
}

export function buildCar(K: Kit, D: CarDesign, wheelStyle: 'car' = 'car') {
  const lod = K.lod;
  const N = lod === 0 ? 18 : lod === 1 ? 12 : lod === 2 ? 6 : 4;
  const slim = lod >= 2; // far traffic: a five-point section and a four-station greenhouse
  const crisp = !!D.crisp;
  const sub = lod === 0 && !crisp ? 1 : 0;
  const hwF = pchip(D.plan.map(([z, v]) => [z, v * D.hw] as [number, number]));
  const y0F = pchip(D.y0);
  const y1F = pchip(D.y1);
  const crF = pchip(D.crown);
  const front = -D.L / 2;
  const rear = D.L / 2;
  // cross-section fractions (x fraction at height fraction u of the lower body)
  const profX = pchip([[0, 0.72], [0.1, 0.94], [0.34, 1], [0.64, 0.985], [0.9, 0.93], [0.985, 0.72]]);
  const side = (z: number, y: number) => {
    const y0 = y0F(z);
    const y1 = y1F(z);
    const u = Math.min(0.985, Math.max(0, (y - y0) / (y1 - y0)));
    return hwF(z) * profX(u);
  };
  const dHw = (z: number) => (hwF(Math.min(rear, z + 0.05)) - hwF(Math.max(front, z - 0.05))) / 0.1;

  /* ---------------------------------------------------------------- lower body */
  const rings: Ring[] = [];
  for (let i = 0; i <= N; i++) {
    const z = -(D.L / 2) * Math.cos((Math.PI * i) / N);
    const hw = hwF(z);
    const y0 = y0F(z);
    const y1 = y1F(z);
    const h = y1 - y0;
    const half: [number, number][] = crisp ? [[0, y0], [hw * 0.92, y0], [hw, y0 + h * 0.14], [hw, y1 - h * 0.12], [hw * 0.9, y1], [0, y1]] : slim ? [[0, y0], [hw * 0.95, y0 + h * 0.12], [hw, y0 + h * 0.55], [hw * 0.8, y1], [0, y1 + crF(z)]] : [
      [0, y0],
      [hw * 0.72, y0],
      [hw * 0.94, y0 + h * 0.1],
      [hw, y0 + h * 0.34],
      [hw * 0.985, y0 + h * 0.64],
      [hw * 0.93, y1 - h * 0.1],
      [hw * 0.72, y1 - h * 0.015],
      [0, y1 + crF(z)],
    ];
    rings.push({ z, pts: mirrorRing(smoothPoly(half, sub)) });
  }
  K.add(loft(rings, { capStart: true, capEnd: true, flat: crisp }), 'body');

  /* ---------------------------------------------------------------- greenhouse */
  // The glasshouse is one swept surface; the pillars, the roof panel and the window frame are ribbons cut from the SAME rings (nudged a
  // few millimetres outward), so they sit flush on the glass edge instead of floating over it.
  const kEdgeCtl = slim ? 2 : 3;
  const cabSub = lod === 0 && !crisp ? 1 : 0;
  const kE = kEdgeCtl * (cabSub + 1);
  const nHalf = slim ? 4 : 6 + (6 - 1) * cabSub; // points in the half profile
  const kLast = 2 * (nHalf - 1) - kE; // mirrored index of kE
  const topF = pchip(D.cab.map((c) => [c.z, c.top] as [number, number]));
  const hwtF = pchip(D.cab.map((c) => [c.z, c.hwt ?? D.hwt] as [number, number]));
  const cabEnd0 = D.cab[0].z;
  const cabEnd1 = D.cab[D.cab.length - 1].z;
  const ringAt = (z: number): [number, number][] => {
    const yb = D.cabBase;
    const yt = Math.max(yb + 0.025, topF(z));
    const h = yt - yb;
    const hwb = D.hwb;
    const hwt = hwtF(z);
    const end = z <= cabEnd0 + 1e-4 || z >= cabEnd1 - 1e-4;
    const half: [number, number][] = slim ? [[0, yb], [hwb, yb], [hwt + 0.025, yt - h * 0.11], [0, yt]] : [
      [0, yb],
      [hwb, yb],
      [hwb - (hwb - hwt) * 0.4, yb + h * 0.55],
      [hwt + 0.025, yt - h * 0.1],
      [hwt * 0.8, yt - h * 0.004],
      [0, yt + (end ? 0 : 0.01)],
    ];
    return mirrorRing(smoothPoly(half, cabSub));
  };
  // stations: the design's own plus evenly spaced ones so the windscreen and rear glass curve smoothly
  const zset = new Set<number>(D.cab.map((c) => c.z));
  const extra = lod === 0 ? 10 : lod === 1 ? 2 : 0;
  for (let i = 1; i <= extra; i++) zset.add(cabEnd0 + ((cabEnd1 - cabEnd0) * i) / (extra + 1));
  const cz = [...zset].sort((a, b) => a - b).filter((z, i, arr) => i === 0 || z - arr[i - 1] > 0.04);
  const rf0 = D.cab[D.roof[0]];
  const rf1 = D.cab[D.roof[1]];
  const czs = slim ? [cabEnd0, rf0.z, rf1.z, cabEnd1] : cz;
  const cabRings: Ring[] = czs.map((z) => ({ z, pts: ringAt(z) }));
  // Near levels: a SHELL in body colour (or black pillars under a body roof) with separate glass PANES proud of it by a few mm:
  // windscreen, rear glass, and a side window between every pair of posts. Far levels keep one glass loft with a roof panel.
  K.add(loft(cabRings, { capStart: true, capEnd: true, flat: crisp }), lod < 2 ? (D.dark ? 'trim' : 'body') : 'glass');
  const cyRef = D.cabBase;
  /** The ring at z on the SHELL's own facets (linear between stations), so a pane lies exactly on the shell instead of dipping under it. */
  const ringLin = (z: number): [number, number][] => {
    let i = 0;
    while (i < czs.length - 2 && z > czs[i + 1]) i++;
    const t = Math.min(1, Math.max(0, (z - czs[i]) / (czs[i + 1] - czs[i] || 1)));
    const a = cabRings[i].pts;
    const b = cabRings[i + 1].pts;
    return a.map((p, k) => [p[0] + (b[k][0] - p[0]) * t, p[1] + (b[k][1] - p[1]) * t] as [number, number]);
  };
  /** A ribbon on the glasshouse surface between two z (rings sampled at every station in range), over ring points i0..i1. */
  const ribbon = (z0: number, z1: number, i0: number, i1: number, role: Role, off = 0.005, hex?: number, offY = off * 0.6) => {
    const zs = czs.filter((z) => z > z0 + 1e-4 && z < z1 - 1e-4);
    const all = [z0, ...zs, z1];
    const rr: Ring[] = all.map((z) => ({
      z,
      pts: ringLin(z).slice(i0, i1 + 1).map(([x, y]) => [x + Math.sign(x) * off, y + offY] as [number, number]),
    }));
    K.add(loft(rr, { closed: false, ref: () => [0, cyRef] }), role, hex);
  };
  // body-colour roof panel over the top between the windscreen and the rear glass
  if (lod >= 2 || D.dark) ribbon(rf0.z, rf1.z, kE, kLast, 'body', 0.004);
  if (lod === 3) {
    for (const s of [-1, 1]) K.put(rbox(0.2, 0.3, 2.6, 0.05, 1), 'tyre', s * (D.hw * 0.9), 0.26, 0, { sy: 1 });
    return;
  }
  if (lod < 2) {
    const g0 = Math.min(0.05, (czs[1] - czs[0]) * 0.2); // margin of a pane to the pillar (small on a steep, short windscreen)
    // windscreen and rear glass: the top arc between the pillars
    ribbon(cabEnd0 + g0, rf0.z - Math.min(0.03, (rf0.z - cabEnd0) * 0.1), kE, kLast, 'glass', 0.0, undefined, 0.004);
    ribbon(rf1.z + Math.min(0.03, (cabEnd1 - rf1.z) * 0.1), cabEnd1 - g0, kE, kLast, 'glass', 0.0, undefined, 0.004);
    // side windows: one pane between every two posts (front door, rear door, a quarter glass behind the last post)
    const posts = [...(D.posts ?? [D.seams[1] ?? 0.2])].filter((z) => z > cabEnd0 + 0.1 && z < cabEnd1 - 0.1).sort((a, b) => a - b);
    // side panes only where the side wall is tall enough to hold a window (the glasshouse ends taper to nothing)
    const tall = czs.filter((z) => topF(z) - D.cabBase > 0.24);
    const zFirst = tall.length ? tall[0] : cabEnd0 + 0.04;
    const zLast = tall.length ? tall[tall.length - 1] : cabEnd1 - 0.06;
    const edges: number[] = [zFirst];
    for (const z of posts) edges.push(z - 0.045, z + 0.045);
    edges.push(zLast);
    const w0 = cabSub ? 2 : 1;
    for (let i = 0; i + 1 < edges.length; i += 2) {
      if (edges[i + 1] - edges[i] < 0.12) continue;
      ribbon(edges[i], edges[i + 1], w0, kE - 1, 'glass', 0.004);
      ribbon(edges[i], edges[i + 1], kLast + 1, 2 * (nHalf - 1) - w0, 'glass', 0.004);
    }
    // the belt line: a slim bright strip along the foot of the glass
    ribbon(cabEnd0 + 0.05, cabEnd1 - 0.05, 1, 1 + (cabSub ? 1 : 0), 'chrome', 0.007);
  }

  /* ---------------------------------------------------------------- details */
  const wz = [D.wheel.zf, D.wheel.zr];
  // wheel-arch liners: a dark patch behind each wheel that follows the body side, sampled finely and smoothed so its edge is a clean arc
  const archR = D.wheel.r + 0.05;
  const yAxle = D.wheel.r;
  const archPts = (zc: number, s: number, r: number, off: number, n: number, yLow: number): [number, number, number][] => {
    const a0 = Math.asin(Math.min(1, Math.max(-1, (yLow - yAxle) / r)));
    const raw: [number, number, number][] = [];
    for (let k = 0; k <= n; k++) {
      const a = a0 + (k / n) * (Math.PI - 2 * a0);
      const z = zc + r * Math.cos(a);
      const y = Math.min(yAxle + r * Math.sin(a), y1F(z) - 0.08);
      raw.push([s * (side(z, y) + off), y, z]);
    }
    return raw.map((p, i) => (i === 0 || i === n ? p : ([(raw[i - 1][0] + p[0] * 2 + raw[i + 1][0]) / 4, p[1], p[2]] as [number, number, number])));
  };
  if (lod < 2) for (const s of [-1, 1]) {
    for (const zc of wz) {
      const n = lod === 0 ? 22 : 10;
      const pts = archPts(zc, s, archR, 0.016, n, y0F(zc) + 0.03);
      const c: [number, number, number] = [s * (side(zc, yAxle) + 0.016), yAxle, zc];
      K.add(flipFor(fan(pts, c), s), 'trim');
      if (D.cladding) {
        // a flush flare: a dark band that follows the arch and touches the body
        const outer = archPts(zc, s, archR + 0.07, 0.024, n, y0F(zc) + 0.03);
        const inner = pts.map((p) => [p[0] + s * 0.006, p[1], p[2]] as [number, number, number]);
        const pos: number[] = [];
        const idx: number[] = [];
        for (let k = 0; k <= n; k++) pos.push(...inner[k], ...outer[k]);
        for (let k = 0; k < n; k++) idx.push(k * 2, k * 2 + 1, k * 2 + 2, k * 2 + 1, k * 2 + 3, k * 2 + 2);
        const g = new BufferGeometry();
        g.setAttribute('position', new Float32BufferAttribute(pos, 3));
        g.setIndex(idx);
        g.computeVertexNormals();
        K.add(flipFor(g, s), 'trim');
      }
    }
  }
  // grille, intakes, bumpers
  const gy = D.grille.y;
  const gw = D.grille.w;
  const gh = D.grille.h;
  K.put(rbox(gw, gh, 0.06, 0.02, lod === 0 ? 2 : 1), 'trim', 0, gy, front + 0.02);
  if (D.grille.style === 'sedan' || D.grille.style === 'lux') {
    K.put(rbox(gw * 0.96, 0.022, 0.05, 0.008, 1), 'chrome', 0, gy + gh / 2 - 0.01, front + 0.03);
    if (lod === 0) K.put(rbox(gw * 0.9, 0.012, 0.04, 0.004, 1), 'chrome', 0, gy - gh * 0.08, front + 0.03);
  }
  if (D.grille.style === 'suv' && lod === 0) {
    for (let i = 0; i < 3; i++) K.put(rbox(gw * 0.9, 0.014, 0.05, 0.005, 1), 'chrome', 0, gy - gh * 0.3 + i * gh * 0.3, front + 0.035);
  }
  if (D.grille.style === 'van') K.put(rbox(gw * 0.7, 0.03, 0.05, 0.01, 1), 'chrome', 0, gy + gh * 0.2, front + 0.03);
  // lower air intake + splitter
  K.put(rbox(D.hw * 1.5, 0.05, 0.1, 0.02, 1), 'trim', 0, y0F(front) + 0.03, front + 0.03);
  if (lod < 2) {
    for (const s of [-1, 1]) K.put(rbox(0.16, 0.09, 0.06, 0.03, 1), 'trim', s * (hwF(front + 0.1) * 0.8), y0F(front) + 0.14, front + 0.05, { ry: -s * 0.35 });
  }
  // rear: dark lower valance
  K.put(rbox(D.hw * 1.5, 0.14, 0.06, 0.03, 1), 'trim', 0, y0F(rear) + 0.12, rear - 0.025);
  // lamps
  const hz = front + 0.17;
  const hx = hwF(hz) * 0.74;
  const lampY = D.head.y;
  const wideHead = D.head.w > 1.2; // one full-width light bar instead of two lamps
  const wideTail = D.tail.w > 1.2;
  if (wideHead) K.put(rbox(D.head.w, D.head.h, 0.06, D.head.h * 0.45, 1), 'head', 0, D.head.y, front + 0.02);
  if (wideTail) K.put(rbox(D.tail.w, D.tail.h, 0.06, D.tail.h * 0.45, 1), 'tail', 0, D.tail.y, rear - 0.02);
  for (const s of wideHead && wideTail ? [] : [-1, 1]) {
    const yaw = -s * Math.atan2(1, Math.max(0.2, dHw(hz))) * 0.9;
    if (D.head.round) {
      K.put(cylZ(D.head.h / 2, 0.07, lod === 0 ? 14 : 8), 'head', s * (D.hw * 0.7), lampY, front + 0.01);
      if (lod === 0) K.put(cylZ(D.head.h / 2 + 0.018, 0.04, 14), 'chrome', s * (D.hw * 0.7), lampY, front - 0.012);
    } else K.put(rbox(D.head.w, D.head.h, 0.07, Math.min(D.head.h, 0.1) * 0.45, lod === 0 ? 2 : 1), 'head', s * hx, lampY, hz + 0.05, { ry: yaw, rz: -s * (D.head.yaw ?? 0.12) });
    if (D.head.drl && lod === 0) K.put(rbox(D.head.w * 0.9, 0.018, 0.06, 0.006, 1), 'chrome', s * hx, lampY + D.head.h * 0.5 + 0.02, hz + 0.0, { ry: yaw, rz: -s * (D.head.yaw ?? 0.12) });
    // rear lamps wrap the corner
    const tz = D.bed ? rear - 0.0 : rear - 0.14;
    const tx = D.bed ? D.hw * 0.86 : hwF(tz) * 0.76;
    if (D.tail.bar) {
      K.put(rbox(D.tail.w, D.tail.h, 0.06, D.tail.h * 0.4, 1), 'tail', s * tx, D.tail.y, rear - 0.05, { ry: s * 0.12 });
    } else {
      K.put(rbox(D.tail.w, D.tail.h * 0.7, 0.045, Math.min(D.tail.w, D.tail.h * 0.7) * 0.4, lod === 0 ? 2 : 1), 'tail', s * tx, D.tail.y, D.bed ? tz : tz + 0.07, { ry: D.bed ? 0 : s * 0.32 });
    }
    if (lod === 0) {
      // indicators and reverse lamps
      K.put(rbox(0.1, 0.03, 0.05, 0.01, 1), 'amber', s * (hx - D.head.w * 0.32), lampY - D.head.h * 0.65, hz + 0.02, { ry: yaw });
      K.put(rbox(0.1, 0.04, 0.05, 0.012, 1), 'chrome', s * (tx - D.tail.w * 0.28), D.tail.y - D.tail.h * 0.7, rear - 0.06);
    }
  }
  if (D.tail.bar && !wideTail) K.put(rbox(D.hw * 1.1, D.tail.h * 0.35, 0.05, 0.01, 1), 'tail', 0, D.tail.y, rear - 0.015);
  // spare wheel on the rear door (an upright off-roader): a tyre with a body-colour cover
  if (D.spare && lod < 2) {
    K.put(cylZ(0.38, 0.16, lod === 0 ? 14 : 8), 'tyre', 0, y1F(rear) - 0.12, rear + 0.1);
    K.put(cylZ(0.31, 0.02, lod === 0 ? 14 : 8), 'body', 0, y1F(rear) - 0.12, rear + 0.185);
  }
  // plates
  if (lod < 2) {
    plate(K, 0, D.plateY[0], front - 0.004, -1);
    plate(K, 0, D.plateY[1], rear + 0.004, 1);
  }
  // mirrors: a body-colour shell on a short dark foot, fixed to the door at the foot of the A pillar
  if (lod < 2) {
    for (const s of [-1, 1]) {
      const mz = D.mirrorZ;
      const mx = D.hwb + 0.07;
      K.put(rbox(0.13, 0.09, 0.19, 0.04, 1), 'body', s * mx, D.cabBase + 0.03, mz);
      K.put(rbox(0.06, 0.03, 0.06, 0.012, 1), 'trim', s * (D.hwb + 0.01), D.cabBase + 0.0, mz + 0.02);
    }
  }
  // door seams, handles, sill, belt trim: lod 0 only
  if (lod === 0) {
    const yLo = (z: number) => y0F(z) + 0.12;
    const yHi = (z: number) => y1F(z) - 0.03;
    for (const s of [-1, 1]) {
      for (const z of D.seams) {
        const a: [number, number, number] = [s * (side(z, yLo(z)) + 0.003), yLo(z), z];
        const b: [number, number, number] = [s * (side(z, yHi(z)) + 0.003), yHi(z), z];
        K.add(rod(a, b, 0.0065, 4), 'trim');
      }
      // handles at the rear edge of each door
      const hy = y1F(0) - 0.14;
      for (let i = 0; i + 1 < D.seams.length; i++) {
        const z = D.seams[i + 1] - 0.14;
        K.put(rbox(0.15, 0.028, 0.035, 0.012, 1), 'chrome', s * (side(z, hy) + 0.006), hy, z, { ry: Math.PI / 2 });
      }
      // dark sill cladding
      const z0 = D.wheel.zf + archR * 0.6;
      const z1 = D.wheel.zr - archR * 0.6;
      const zc = (z0 + z1) / 2;
      K.put(rbox(0.045, 0.075, z1 - z0, 0.02, 1), 'trim', s * (side(zc, y0F(zc) + 0.07) + 0.0), y0F(zc) + 0.075, zc);
    }
    if (D.exhaust) {
      K.put(cylZ(0.035, 0.1, 8), 'chrome', D.hw * 0.5, y0F(rear) + 0.04, rear - 0.0);
    }
  }
  // roof rails: a chrome bar on short feet that stand ON the roof (the flat of the roof ends at 80 % of the top half width)
  if (D.rails) {
    for (const s of [-1, 1]) {
      const x = s * D.hwt * 0.74;
      const yTop = (z: number) => topF(z) + 0.012;
      const zA = rf0.z + 0.2;
      const zB = rf1.z - 0.1;
      const y = Math.max(yTop(zA), yTop(zB)) + 0.05;
      K.add(rod([x, y, zA], [x, y, zB], 0.02, 5), 'chrome');
      const feet = lod === 0 ? 4 : 2;
      for (let i = 0; i < feet; i++) {
        const z = zA + ((zB - zA) * i) / (feet - 1);
        K.add(rod([x, y, z], [x, yTop(z) - 0.012, z], 0.016, 4), 'trim');
      }
    }
  }
  if (D.running) {
    for (const s of [-1, 1]) K.put(rbox(0.16, 0.04, (D.wheel.zr - D.wheel.zf) * 0.78, 0.015, 1), 'trim', s * (D.hw + 0.02), y0F(0) + 0.03, (D.wheel.zr + D.wheel.zf) / 2);
  }
  // pickup bed
  if (D.bed) buildBed(K, D, side, y1F, hwF, rear);

  /* ---------------------------------------------------------------- wheels */
  const w = D.wheel;
  for (const z of wz) {
    for (const s of [-1, 1]) {
      if (K.separateWheels) {
        if (s === 1) {
          K.wheels.push({ x: -w.x, z, r: w.r, wid: w.wid, front: z < 0, style: wheelStyle });
          K.wheels.push({ x: w.x, z, r: w.r, wid: w.wid, front: z < 0, style: wheelStyle });
        }
      } else for (const p of wheelParts(s * w.x, z, w.r, w.wid, wheelStyle, lod)) K.parts.push(p);
    }
  }
}

/** A fan built from points on the left or right side: make its faces point outward (+x for the right side). */
function flipFor(g: BufferGeometry, s: number): BufferGeometry {
  const idx = g.getIndex()!;
  const pos = g.getAttribute('position');
  let nx = 0;
  for (let t = 0; t < idx.count; t += 3) {
    const a = idx.getX(t);
    const b = idx.getX(t + 1);
    const c = idx.getX(t + 2);
    const uy = pos.getY(b) - pos.getY(a);
    const uz = pos.getZ(b) - pos.getZ(a);
    const vy = pos.getY(c) - pos.getY(a);
    const vz = pos.getZ(c) - pos.getZ(a);
    nx += uy * vz - uz * vy;
  }
  if (nx * s < 0) {
    const arr = Array.from({ length: idx.count }, (_, i) => idx.getX(i));
    for (let t = 0; t < arr.length; t += 3) {
      const b = arr[t + 1];
      arr[t + 1] = arr[t + 2];
      arr[t + 2] = b;
    }
    g.setIndex(arr);
    g.computeVertexNormals();
  }
  return g;
}

function buildBed(K: Kit, D: CarDesign, side: (z: number, y: number) => number, y1F: (z: number) => number, hwF: (z: number) => number, rear: number) {
  const b = D.bed!;
  const len = rear - b.z0;
  const zc = (b.z0 + rear) / 2;
  const yTop = y1F(zc);
  // a dark load floor sunk between the walls, side walls, tailgate, bulkhead
  K.put(new BoxGeometry(D.hw * 1.62, 0.04, len - 0.1), 'trim', 0, yTop - 0.02, zc);
  for (const s of [-1, 1]) {
    K.put(rbox(0.1, b.wall, len, 0.035, 1), 'body', s * (hwF(zc) * 0.93), yTop + b.wall / 2 - 0.03, zc);
    if (K.lod === 0) K.put(rbox(0.12, 0.03, len + 0.02, 0.012, 1), 'chrome', s * (hwF(zc) * 0.93), yTop + b.wall - 0.015, zc);
  }
  K.put(rbox(D.hw * 1.74, b.wall, 0.1, 0.035, 1), 'body', 0, yTop + b.wall / 2 - 0.03, rear - 0.06);
  K.put(rbox(D.hw * 1.74, b.wall + 0.06, 0.1, 0.035, 1), 'body', 0, yTop + (b.wall + 0.06) / 2 - 0.03, b.z0 + 0.05);
  if (K.lod === 0) {
    // tailgate handle + a rear step bumper
    K.put(rbox(0.22, 0.03, 0.03, 0.01, 1), 'chrome', 0, yTop + b.wall - 0.07, rear + 0.0);
    K.put(rbox(D.hw * 1.5, 0.1, 0.12, 0.04, 1), 'trim', 0, yTop - 0.55, rear - 0.02);
  }
  void side;
}

export type { Role };
export { Float32BufferAttribute };
