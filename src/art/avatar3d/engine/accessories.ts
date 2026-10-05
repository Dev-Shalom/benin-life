// Accessories: shades, glasses, watch, chain, coral beads, bracelet, earrings, phone, bag, backpack, lanyard, towel.
import { Vector3, type Material } from 'three';
import type { AvatarConfig } from '../../../lib/types';
import { bonePositions, type BoneName, type Dims, type PartBuilder } from './body';
import { bead, box, ellipsoid, gridSurface, grow, lerp, loft, ringAt, ringXZ, smooth, torus, tube, type Ring, type V3 } from './geo';
import { FEATURE, type HeadSurface } from './head';
import { earPoint } from './hair';

export interface AccMats {
  gold: Material;
  black: Material;
  lens: Material;
  white: Material;
  coralBead: Material;
  leather: Material;
  accent: Material;
  accentDark: Material;
  screen: Material;
  towel: Material;
  silver: Material;
}

export function buildAccessories(
  b: PartBuilder,
  d: Dims,
  h: HeadSurface,
  cfg: AvatarConfig,
  m: AccMats,
  outer: (y: number) => number,
) {
  const acc = new Set(cfg.accessories);
  const pos = bonePositions(d);
  const hc = new Vector3(...d.headCenter);
  const toModel = (p: Vector3): V3 => [p.x + hc.x, p.y + hc.y, p.z + hc.z];
  const neckY = d.neckBaseY - (d.gender === 'female' ? 0.01 : 0.012);
  const f = d.gender === 'female';

  const onTorso = (y: number, a: number, extra = 0): Vector3 => {
    const r = grow(ringAt(d.torso, y), outer(y) + extra);
    const [x, z] = ringXZ(r, a);
    return new Vector3(x, y, z);
  };
  /** Point on the front (or back) of the torso at lateral position x. */
  const atX = (y: number, x: number, front: boolean, extra = 0): Vector3 => {
    const r = grow(ringAt(d.torso, y), outer(y) + extra);
    let lo = 0;
    let hi = Math.PI / 2;
    for (let i = 0; i < 24; i++) {
      const mid = (lo + hi) / 2;
      if (Math.abs(ringXZ(r, mid)[0]) < Math.abs(x)) lo = mid;
      else hi = mid;
    }
    const a0 = (lo + hi) / 2;
    const a = front ? a0 * Math.sign(x) : (Math.PI - a0) * Math.sign(x);
    const [px, pz] = ringXZ(r, a);
    return new Vector3(px, y, pz);
  };
  /**
   * Closed necklace: hugs the back and sides of the neck, then drapes in a U onto the chest,
   * `drop` metres below the neck at the front.
   */
  const necklace = (drop: number, extra: number, n = 28): Vector3[] => {
    const r = d.neckR + 0.012 + extra;
    const pts: Vector3[] = [];
    const nb = Math.round(n * 0.32);
    for (let i = 0; i < nb; i++) {
      const a = Math.PI / 2 + (i / nb) * Math.PI;
      pts.push(new Vector3(r * Math.sin(a), neckY - 0.002, r * Math.cos(a) - 0.004));
    }
    const nf = n - nb;
    for (let i = 0; i < nf; i++) {
      const s = -1 + (2 * i) / nf;
      const x = s * r * 1.04;
      const y = neckY - 0.004 - drop * Math.pow(Math.max(0, 1 - s * s), 0.85);
      const surf = atX(y, x, true, extra + 0.004);
      const zc = Math.sqrt(Math.max(0, r * r - x * x)) - 0.004;
      const w = smooth(0.7, 1.0, Math.abs(s));
      pts.push(new Vector3(x, y, Math.max(lerp(surf.z, zc, w), zc)));
    }
    return pts;
  };

  // ---- eyewear (head-local -> model)
  if (acc.has('shades') || acc.has('glasses')) {
    const shades = acc.has('shades');
    const ey = FEATURE.eyeY * h.ys;
    for (const sd of [1, -1]) {
      const e = h.front(sd * FEATURE.eyeX, ey);
      const c = e.p.clone().add(new Vector3(0, 0.001, 0.013));
      if (shades) {
        const g = ellipsoid(0.0235, 0.0165, 0.0042, { p: toModel(c), r: [0, sd * 0.12, 0] }, 12, 6);
        b.add('head', m.lens, g);
      }
      b.add('head', shades ? m.black : m.gold, torus(0.021, shades ? 0.0022 : 0.0016, { p: toModel(c), r: [0, sd * 0.12, 0], s: [1.08, 0.78, 1] }, 4, 16));
      // temple arm back to the ear
      const ear = earPoint(h, sd);
      const start = c.clone().add(new Vector3(sd * 0.022, 0.003, -0.004));
      b.add('head', shades ? m.black : m.gold, tube([toModel(start), toModel(new Vector3(ear.x + sd * 0.003, ear.y + 0.03, ear.z + 0.012))], 0.0018, 4));
    }
    const br = h.front(0, ey + 0.004);
    b.add('head', shades ? m.black : m.gold, box(0.016, 0.003, 0.003, { p: toModel(br.p.clone().add(new Vector3(0, 0.002, 0.016))) }));
  }

  // ---- earrings
  if (acc.has('earrings')) {
    for (const sd of [1, -1]) {
      const p = earPoint(h, sd);
      if (acc.has('coral')) {
        b.add('head', m.coralBead, bead(0.0065, { p: toModel(p.clone().add(new Vector3(sd * 0.002, -0.004, 0))) }));
        b.add('head', m.coralBead, bead(0.0055, { p: toModel(p.clone().add(new Vector3(sd * 0.002, -0.016, 0))) }));
      } else {
        b.add('head', m.gold, torus(0.0105, 0.0017, { p: toModel(p.clone().add(new Vector3(sd * 0.002, -0.011, 0))), r: [0, Math.PI / 2, 0] }, 4, 12));
      }
    }
  }

  // ---- neck pieces
  if (acc.has('chain')) {
    const pts = necklace(f ? 0.1 : 0.13, 0.006, 30);
    b.add('body', m.gold, tube([...pts, pts[0]].map((p) => [p.x, p.y, p.z] as V3), 0.0042, 5));
    const low = onTorso(neckY - (f ? 0.1 : 0.13) - 0.02, 0, 0.012);
    b.add('body', m.gold, box(0.022, 0.03, 0.006, { p: [low.x, low.y, low.z] }));
  }
  if (acc.has('coral')) {
    const strands = f ? [0.04, 0.075, 0.11] : [0.05, 0.09, 0.135];
    strands.forEach((drop, si) => {
      const n = 26 + si * 6;
      const pts = necklace(drop, 0.008 + si * 0.002, n);
      pts.forEach((p, i) => {
        const r = (i % 6 === 0 ? 0.0105 : 0.0085) * (si === 0 ? 1.1 : 1);
        b.add('body', i % 9 === 4 && si === 1 ? m.gold : m.coralBead, bead(r, { p: [p.x, p.y, p.z] }));
      });
    });
  }
  if (acc.has('lanyard')) {
    const card = onTorso(1.17, 0.12, 0.012);
    for (const sd of [1, -1]) {
      const pts: V3[] = [];
      for (let i = 0; i <= 6; i++) {
        const t = i / 6;
        const a = lerp(Math.PI * 0.8 * sd, sd * 0.12, t);
        const y = lerp(neckY + 0.006, 1.2, Math.pow(t, 1.6));
        const p = onTorso(y, a, 0.006);
        pts.push([p.x, p.y, p.z]);
      }
      b.add('body', m.accent, tube(pts, 0.0035, 4));
    }
    b.add('body', m.white, box(0.05, 0.068, 0.004, { p: [card.x, card.y - 0.025, card.z + 0.002], r: [0, 0.12, 0] }));
    b.add('body', m.accent, box(0.044, 0.014, 0.0045, { p: [card.x, card.y - 0.002, card.z + 0.0025], r: [0, 0.12, 0] }));
  }
  if (acc.has('towel')) {
    // draped over the right shoulder: front -> over the top -> back
    const xs = -d.shoulderX * 0.6;
    const topY = d.shoulderY + 0.062 + outer(d.shoulderY);
    b.add('chest', m.towel, gridSurface(10, 3, (u, v) => {
      const x = xs + (v - 0.5) * 0.1;
      const phi = u * Math.PI;
      const y = lerp(u < 0.5 ? 1.13 : 1.2, topY, Math.sin(phi));
      const front = u < 0.5;
      const yy = Math.min(y, neckY - 0.012);
      const q = atX(yy, x, front, 0.014);
      const depth = Math.abs(q.z);
      return [x, y, Math.cos(phi) * Math.max(depth, 0.03)];
    }, { tile: 0.14 }));
  }

  // ---- back
  if (acc.has('backpack')) {
    const back = ringAt(d.torso, 1.2);
    const z0 = -((back.db ?? back.df) + outer(1.2) + 0.055);
    const rings: Ring[] = [0.98, 1.0, 1.1, 1.24, 1.33, 1.35].map((y, i, arr) => {
      const k = i === 0 || i === arr.length - 1 ? 0.0 : i === 1 || i === arr.length - 2 ? 0.8 : 1;
      return { y, w: 0.125 * k + 0.0001, df: 0.055 * k + 0.0001, z: z0, n: 4 };
    });
    b.add('body', m.accent, loft(rings, { seg: 16 }));
    b.add('body', m.accentDark, ellipsoid(0.085, 0.06, 0.02, { p: [0, 1.06, z0 - 0.055] }, 10, 6));
    for (const sd of [1, -1]) {
      const over = d.shoulderY + 0.05 + outer(d.shoulderY);
      const f1 = atX(1.33, sd * 0.105, true, 0.008);
      const f2 = atX(1.2, sd * 0.125, true, 0.008);
      const f3 = atX(1.08, sd * 0.15, true, 0.008);
      const pts: V3[] = [
        [sd * 0.075, 1.32, z0 + 0.035],
        [sd * 0.098, over - 0.01, -0.045],
        [sd * 0.1, over, 0.0],
        [f1.x, f1.y, f1.z],
        [f2.x, f2.y, f2.z],
        [f3.x, f3.y, f3.z],
      ];
      b.add('body', m.accentDark, tube(pts, 0.0085, 4));
    }
  }

  // ---- wrists and hands
  const wrist = (side: 'L' | 'R') => {
    const fore = `fore${side}` as BoneName;
    const at = pos[fore];
    const y = at[1] - d.foreLen + 0.035;
    const prof = d.foreArm.map(([yy, w, dd]) => ({ y: at[1] + yy, w, df: dd, x: at[0], z: at[2] }));
    const r = ringAt(prof, y);
    return { fore, at, y, r };
  };
  if (acc.has('watch')) {
    const { fore, y, r } = wrist('L');
    b.add(fore, m.black, loft([{ ...grow(r, 0.0045), y: y - 0.008 }, { ...grow(r, 0.0045), y: y + 0.008 }], { seg: 10 }));
    b.add(fore, m.gold, ellipsoid(0.004, 0.012, 0.012, { p: [(r.x ?? 0) + r.w + 0.006, y, 0] }, 10, 6));
  }
  if (acc.has('bracelet')) {
    const { fore, y, r } = wrist('R');
    if (acc.has('coral')) {
      for (let i = 0; i < 12; i++) {
        const a = (i / 12) * Math.PI * 2;
        const [x, z] = ringXZ(grow(r, 0.007), a);
        b.add(fore, m.coralBead, bead(0.0068, { p: [x, y - 0.004, z] }));
      }
    } else {
      b.add(fore, m.gold, torus(r.w + 0.006, 0.0028, { p: [r.x ?? 0, y, 0], r: [Math.PI / 2, 0, 0], s: [1, (r.df + 0.006) / (r.w + 0.006), 1] }, 4, 14));
    }
  }
  if (acc.has('phone')) {
    const at = pos.handR;
    b.add('handR', m.black, box(0.009, 0.13, 0.066, { p: [at[0] + 0.004, at[1] - 0.085, at[2] + 0.028], r: [-0.12, 0, 0] }));
    b.add('handR', m.screen, box(0.0012, 0.118, 0.058, { p: [at[0] - 0.0012, at[1] - 0.085, at[2] + 0.028], r: [-0.12, 0, 0] }));
  }
  if (acc.has('bag')) {
    const at = pos.handL;
    const y = at[1] - 0.205;
    b.add('handL', m.accent, loft([
      { y: y - 0.06, w: 0.026, df: 0.07, n: 4 }, { y: y - 0.055, w: 0.03, df: 0.078, n: 4 }, { y: y + 0.04, w: 0.026, df: 0.07, n: 4 }, { y: y + 0.045, w: 0.02, df: 0.06, n: 4 },
    ].map((r) => ({ ...r, x: at[0] + 0.006, z: at[2] + 0.01 })), { seg: 12, capLo: true, capHi: true }));
    b.add('handL', m.accentDark, torus(0.042, 0.0045, { p: [at[0] + 0.006, y + 0.045, at[2] + 0.01], r: [0, Math.PI / 2, 0] }, 4, 10, Math.PI));
    b.add('handL', m.gold, box(0.004, 0.012, 0.02, { p: [at[0] + 0.006 + 0.031, y + 0.02, at[2] + 0.01] }));
  }
}
