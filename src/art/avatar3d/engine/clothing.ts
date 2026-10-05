// Clothing built from the body's own cross-sections (grown outwards), so every piece fits every body type.
import { BufferGeometry, Float32BufferAttribute, Vector3, type Material } from 'three';
import type { AvatarConfig } from '../../../lib/types';
import { bonePositions, type BoneName, type Dims, type PartBuilder, type Profile } from './body';
import { box, ellipsoid, gridSurface, grow, lerp, loft, ringAt, ringXZ, sliceRings, smooth, tube, type Ring, type V3 } from './geo';

export interface ClothMats {
  skin: Material;
  top: Material;
  topTrim: Material;
  bottom: Material;
  bottomTrim: Material;
  inner: Material;
  innerTee: Material;
  shoe: Material;
  sole: Material;
  accent: Material;
  accentDark: Material;
  gold: Material;
  silver: Material;
  black: Material;
  white: Material;
  leather: Material;
  reflect: Material;
  embroidery: Material;
  embroideryBand: Material;
  graphic: Material;
  button: Material;
}

export interface ClothResult {
  /** Outermost garment thickness on the torso at height y (for necklaces, straps). */
  outer: (y: number) => number;
  /** Covered arms (no wristwatch on bare skin needed?) and sleeve end. */
  longSleeves: boolean;
  /** Legs hidden under a long garment. */
  legsHidden: boolean;
  /** Widest torso-hung garment (or body) half-width at height y, for arm clearance. Robes excluded. */
  widthAt: (y: number) => number;
}

type Ctx = {
  d: Dims;
  b: PartBuilder;
  m: ClothMats;
  pos: Record<BoneName, V3>;
  covers: [number, number, number][];
  /** Ring sets of skirts and tunics (the arms must clear them). */
  skirts: Ring[][];
  female: boolean;
  neckY: number;
};

// ---------------------------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------------------------

function cover(c: Ctx, y0: number, y1: number, t: number) {
  c.covers.push([Math.min(y0, y1), Math.max(y0, y1), t]);
}

/** Widen rings near the hips so a top always covers the trouser legs below it. */
function hipSafe(c: Ctx, r: Ring, extra = 0.024): Ring {
  const d = c.d;
  if (r.y > d.hipY + 0.06) return r;
  const need = d.hipX + legR(d, Math.min(r.y, d.hipY)) + extra;
  return r.w >= need ? r : { ...r, w: need };
}

/** Torso garment between two heights, grown by t. `flare` widens towards the bottom. */
function torsoPiece(c: Ctx, y0: number, y1: number, t: number, o: { flare?: number; seg?: number; hemLip?: boolean } = {}): BufferGeometry {
  let rings = sliceRings(c.d.torso, y0, y1, t).map((r) => hipSafe(c, r, 0.022 + t * 0.4));
  if (o.flare) {
    const span = y1 - y0;
    rings = rings.map((r) => grow(r, o.flare! * Math.pow(1 - (r.y - y0) / span, 2)));
  }
  if (o.hemLip) {
    const lo = rings[0];
    rings = [{ ...grow(lo, 0.0035), y: lo.y - 0.0015 }, ...rings];
  }
  cover(c, y0, y1, t + (o.flare ?? 0));
  return loft(rings, { seg: o.seg ?? 18, tile: 0.25 });
}

/** Torso garment with a front opening of half-angle alpha(y) (V-necks, jackets, vests). */
function torsoOpen(c: Ctx, y0: number, y1: number, t: number, alpha: (y: number) => number, rows = 14, cols = 20, flare = 0): BufferGeometry {
  cover(c, y0, y1, t);
  return gridSurface(cols, rows, (u, v) => {
    const y = lerp(y0, y1, v);
    const al = alpha(y);
    const r = hipSafe(c, grow(ringAt(c.d.torso, y), t + flare * Math.pow(1 - v, 2)), 0.022 + t * 0.4);
    const [x, z] = ringXZ(r, lerp(al, Math.PI * 2 - al, u));
    return [x, y, z];
  }, { tile: 0.25, uAnchor: 0.5 });
}

/** Surface point + outward normal on the torso at height y, angle a, grown by t. */
function onTorso(c: Ctx, y: number, a: number, t: number): { p: Vector3; n: Vector3 } {
  const r = grow(ringAt(c.d.torso, y), t);
  const [x, z] = ringXZ(r, a);
  const [x1, z1] = ringXZ(r, a + 0.01);
  const [x0, z0] = ringXZ(r, a - 0.01);
  const tx = x1 - x0;
  const tz = z1 - z0;
  return { p: new Vector3(x, y, z), n: new Vector3(-tz, 0, tx).normalize() };
}

/** Angle on the torso ring at height y whose lateral offset is about x (front half). */
function angleAtX(c: Ctx, y: number, x: number, t: number): number {
  const r = grow(ringAt(c.d.torso, y), t);
  let lo = 0;
  let hi = Math.PI / 2;
  const ax = Math.abs(x);
  for (let i = 0; i < 24; i++) {
    const m = (lo + hi) / 2;
    if (ringXZ(r, m)[0] < ax) lo = m;
    else hi = m;
  }
  return ((lo + hi) / 2) * Math.sign(x || 1);
}

/** A patch on the front of the torso, centred on x = cx, with half-width hw(y). Patch uvs 0..1. */
function frontPatch(c: Ctx, y0: number, y1: number, t: number, hw: (y: number) => number, cx = 0, rows = 6, cols = 6, back = false): BufferGeometry {
  return gridSurface(cols, rows, (u, v) => {
    const y = lerp(y0, y1, v);
    const w = hw(y);
    const x = cx + lerp(-w, w, u);
    const a = angleAtX(c, y, x, t);
    const r = grow(ringAt(c.d.torso, y), t);
    const [px, pz] = ringXZ(r, back ? Math.PI - a : a);
    return [px, y, pz];
  }, { patchUv: true });
}

function limbRings(p: Profile, at: V3, t = 0): Ring[] {
  return p.map(([y, w, dd]) => ({ y: at[1] + y, w: w + (w > 0 ? t : 0), df: dd + (dd > 0 ? t : 0), x: at[0], z: at[2] })).sort((a, b) => a.y - b.y);
}

/** Sleeve / trouser leg on a limb between local heights yTop..yEnd (yTop > yEnd). */
function limbPiece(c: Ctx, bone: BoneName, p: Profile, yTop: number, yEnd: number, t: number, o: { flare?: number; seg?: number; dome?: boolean } = {}): BufferGeometry {
  const at = c.pos[bone];
  const base = limbRings(p, at);
  let rings: Ring[] = sliceRings(base, at[1] + yEnd, at[1] + yTop, 0).map((r) => ({ ...r, x: at[0], z: at[2] }));
  const span = yTop - yEnd;
  rings = rings.map((r) => {
    const k = 1 - (r.y - at[1] - yEnd) / span; // 0 top .. 1 end
    const g = t + (o.flare ?? 0) * k * k;
    return r.w < 1e-4 ? r : grow(r, g);
  });
  if (o.dome) {
    // round the open top off inside the pelvis piece
    const top = rings[rings.length - 1];
    rings.push({ ...top, y: top.y + 0.03, w: top.w * 0.6, df: top.df * 0.6, db: (top.db ?? top.df) * 0.6 });
  }
  return loft(rings, { seg: o.seg ?? 10, tile: 0.2 });
}

/** Radius of the leg (thigh/shin) at model height y. */
function legR(d: Dims, y: number): number {
  const sample = (p: Profile, local: number) => {
    const rs = p.map(([yy, w]) => ({ y: yy, w, df: w }));
    return ringAt(rs, local).w;
  };
  if (y > d.kneeY) return sample(d.thigh, y - d.hipY);
  return sample(d.shin, y - d.kneeY);
}

/** Rings for skirts and long tunics: follow the hips, then enclose both legs down to the hem. */
function skirtRings(c: Ctx, yTop: number, yHem: number, t: number, flare: number): Ring[] {
  const d = c.d;
  const crotch = d.torso[0].y + 0.035;
  const keys = d.torso.map((r) => r.y).filter((y) => y > crotch && y < yTop - 0.005);
  const below: number[] = [];
  const n = Math.max(2, Math.ceil((crotch - yHem) / 0.06));
  for (let i = 0; i <= n; i++) below.push(lerp(crotch, yHem, i / n));
  const ys = [...new Set([yTop, ...keys, ...below])].sort((a, b) => b - a);
  const out: Ring[] = ys.map((y) => {
    const base = grow(ringAt(d.torso, Math.max(y, crotch)), t);
    const s = y < crotch ? (crotch - y) / Math.max(0.01, crotch - yHem) : 0;
    const fl = flare * s * (0.6 + 0.4 * s);
    // both legs must fit inside (they join the hips just below the hip joint)
    const legs = y < d.hipY + 0.07 ? d.hipX + legR(d, Math.min(y, d.hipY)) + t + 0.014 : 0;
    const legD = y < d.hipY + 0.07 ? legR(d, Math.min(y, d.hipY)) + t + 0.016 : 0;
    return {
      y,
      w: Math.max(base.w + fl, legs),
      df: Math.max(base.df + fl * 0.75, legD),
      db: Math.max((base.db ?? base.df) + fl * 0.75, legD),
      n: y < crotch ? 2.2 : base.n,
    };
  });
  c.skirts.push(out);
  return out.sort((a, b) => a.y - b.y);
}

function hemmed(rings: Ring[], lip = 0.004): Ring[] {
  const lo = rings[0];
  return [{ ...grow(lo, lip), y: lo.y - 0.0015 }, ...rings];
}

const band = (c: Ctx, y0: number, y1: number, t: number, seg = 18) => loft(sliceRings(c.d.torso, y0, y1, t).map((r) => hipSafe(c, r, 0.022 + t * 0.4)), { seg });

// ---------------------------------------------------------------------------------------------
// tops
// ---------------------------------------------------------------------------------------------

function sleeves(c: Ctx, kind: 'short' | 'long' | 'elbow' | 'bell' | 'puff' | 'none', t: number, mat: Material, trim?: Material) {
  if (kind === 'none') return;
  const d = c.d;
  for (const s of ['L', 'R'] as const) {
    const arm = `arm${s}` as BoneName;
    const fore = `fore${s}` as BoneName;
    if (kind === 'short') {
      c.b.add(arm, mat, limbPiece(c, arm, d.upperArm, 0.06, -0.13, t, { flare: 0.008 }));
    } else if (kind === 'puff') {
      c.b.add(arm, mat, limbPiece(c, arm, d.upperArm, 0.06, -0.11, t, { flare: 0.006 }));
      const at = c.pos[arm];
      c.b.add(arm, mat, ellipsoid(0.058, 0.05, 0.056, { p: [at[0] + (s === 'L' ? 0.008 : -0.008), at[1] - 0.012, at[2]] }, 10, 7));
    } else if (kind === 'elbow' || kind === 'bell') {
      c.b.add(arm, mat, limbPiece(c, arm, d.upperArm, 0.06, -d.armLen - 0.03, t));
      c.b.add(fore, mat, limbPiece(c, fore, d.foreArm, 0.03, -0.11, t + 0.004, { flare: kind === 'bell' ? 0.05 : 0.012 }));
    } else {
      c.b.add(arm, mat, limbPiece(c, arm, d.upperArm, 0.06, -d.armLen - 0.03, t));
      c.b.add(fore, mat, limbPiece(c, fore, d.foreArm, 0.03, -d.foreLen + 0.022, t));
      if (trim) c.b.add(fore, trim, limbPiece(c, fore, d.foreArm, -d.foreLen + 0.05, -d.foreLen + 0.018, t + 0.003));
    }
  }
}

function crewNeck(c: Ctx, t: number, mat: Material) {
  const y = c.neckY;
  c.b.add('body', mat, band(c, y - 0.009, y + 0.002, t + 0.003));
}

/** Shirt collar: a stand around the neck and two points folded onto the chest. */
function shirtCollar(c: Ctx, t: number, mat: Material) {
  const d = c.d;
  const y = c.neckY;
  const r = d.neckR + 0.012;
  const rings: Ring[] = [
    { y: y - 0.008, ...pick(grow(ringAt(d.torso, y - 0.008), t + 0.002)) },
    { y: y + 0.012, w: r + 0.006, df: r + 0.012, db: r + 0.006, z: -0.004 },
    { y: y + 0.024, w: r + 0.004, df: r + 0.01, db: r + 0.004, z: -0.004 },
  ];
  c.b.add('chest', mat, shiftChest(c, loft(rings, { seg: 16, a0: 0.28, a1: Math.PI * 2 - 0.28 })));
  for (const s of [1, -1]) {
    const top = onTorso(c, y - 0.004, s * 0.3, t + 0.004);
    const tip = onTorso(c, y - 0.05, s * 0.46, t + 0.006);
    const mid = onTorso(c, y - 0.03, s * 0.2, t + 0.006);
    c.b.add('chest', mat, shiftChest(c, tri3(top.p, tip.p, mid.p, 0.003)));
  }
}

/** Geometry already in model space; chest-bone parts are fine as-is (builder handles offsets). */
const shiftChest = (_c: Ctx, g: BufferGeometry) => g;
const pick = (r: Ring) => ({ w: r.w, df: r.df, db: r.db, n: r.n, z: r.z, x: r.x });

/** A flat triangle (collar points). Uses a double-sided fabric material. */
function tri3(a: Vector3, b: Vector3, c: Vector3, lift: number): BufferGeometry {
  const n = new Vector3().subVectors(b, a).cross(new Vector3().subVectors(c, a)).normalize().multiplyScalar(lift);
  const g = new BufferGeometry();
  const P = [a, b, c].map((p) => p.clone().add(n));
  g.setAttribute('position', new Float32BufferAttribute(P.flatMap((p) => [p.x, p.y, p.z]), 3));
  g.setAttribute('uv', new Float32BufferAttribute([0, 0, 1, 0, 0.5, 1], 2));
  g.setIndex([0, 1, 2]);
  g.computeVertexNormals();
  return g;
}

function placket(c: Ctx, y0: number, y1: number, t: number, mat: Material, buttons: number, btnMat: Material) {
  c.b.add('body', mat, frontPatch(c, y0, y1, t + 0.0012, () => 0.0085, 0, 4, 2));
  for (let i = 0; i < buttons; i++) {
    const y = lerp(y1 - 0.02, y0 + 0.02, buttons === 1 ? 0 : i / (buttons - 1));
    const q = onTorso(c, y, 0, t + 0.003);
    c.b.add('body', btnMat, ellipsoid(0.0045, 0.0045, 0.0022, { p: [q.p.x, q.p.y, q.p.z] }, 6, 4));
  }
}

function tie(c: Ctx, t: number, mat: Material, bottom = 1.1) {
  const y = c.neckY;
  c.b.add('body', mat, frontPatch(c, bottom, y - 0.022, t + 0.004, (yy) => lerp(0.026, 0.011, smooth(bottom, y - 0.02, yy)), 0, 6, 3));
  const k = onTorso(c, y - 0.014, 0, t + 0.008);
  c.b.add('body', mat, box(0.024, 0.02, 0.012, { p: [k.p.x, k.p.y, k.p.z] }));
}

function belt(c: Ctx, y: number, t: number) {
  c.b.add('body', c.m.leather, band(c, y - 0.014, y + 0.014, t + 0.004));
  const q = onTorso(c, y, 0, t + 0.008);
  c.b.add('body', c.m.silver, box(0.03, 0.024, 0.006, { p: [q.p.x, q.p.y, q.p.z] }));
}

function decal(c: Ctx, mat: Material, y0: number, y1: number, hw: number, t: number, cx = 0, back = false) {
  c.b.add('body', mat, frontPatch(c, y0, y1, t + 0.0015, () => hw, cx, 6, 6, back));
}

/** Agbada / boubou robe: wide "wings" folded over the arms, a long panel to the shins. */
function robe(c: Ctx, o: { wing: number; wingBottom: number; panel: number; hem: number }, mat: Material) {
  const d = c.d;
  const sx = d.shoulderX;
  const top = grow(ringAt(d.torso, c.neckY + 0.006), 0.02);
  const rings: Ring[] = [
    { ...top, y: c.neckY + 0.006, n: 2 },
    { y: d.shoulderY + 0.042, w: sx + o.wing * 0.42, df: 0.096, db: 0.092, n: 2.2 },
    { y: d.shoulderY + 0.012, w: sx + o.wing * 0.78, df: 0.112, db: 0.104, n: 2.3 },
    { y: d.shoulderY - 0.06, w: sx + o.wing * 0.97, df: 0.124, db: 0.114, n: 2.4, ra: 0.01, rk: 10 },
    { y: (d.shoulderY + o.wingBottom) / 2, w: sx + o.wing * 1.04, df: 0.132, db: 0.122, n: 2.4, ra: 0.022, rk: 10 },
    { y: o.wingBottom, w: sx + o.wing * 1.1, df: 0.136, db: 0.126, n: 2.4, ra: 0.03, rk: 10 },
    { y: o.wingBottom - 0.014, w: sx + o.panel, df: 0.14, db: 0.13, n: 2.3, ra: 0.02, rk: 8 },
    { y: (o.wingBottom + o.hem) / 2, w: sx + o.panel + 0.012, df: 0.146, db: 0.136, n: 2.3, ra: 0.028, rk: 8 },
    { y: o.hem, w: sx + o.panel + 0.024, df: 0.152, db: 0.142, n: 2.3, ra: 0.034, rk: 8 },
  ];
  c.b.add('body', mat, loft(hemmed(rings, 0.005), { seg: 40, tile: 0.3 }));
  // embroidered trim along the bottom of the wings
  const wb = rings[5];
  c.b.add('body', c.m.embroideryBand, loft([{ ...grow(wb, 0.003), y: o.wingBottom - 0.002 }, { ...grow(rings[4], 0.003), y: o.wingBottom + 0.026 }], { seg: 40, tile: 0.1 }));
  cover(c, o.hem, c.neckY, 0.03);
  return rings;
}

function robeDecal(c: Ctx, mat: Material, rings: Ring[], y0: number, y1: number, hw: number) {
  c.b.add('body', mat, gridSurface(6, 6, (u, v) => {
    const y = lerp(y0, y1, v);
    const r = grow(ringAt(rings, y), 0.002);
    const a = (u - 0.5) * 2 * Math.asin(Math.min(0.95, hw / r.w));
    const [x, z] = ringXZ(r, a);
    return [x, y, z];
  }, { patchUv: true }));
}

function buildTop(c: Ctx, cfg: AvatarConfig): { longSleeves: boolean; legsHidden: boolean; tucked: boolean } {
  const { d, m } = c;
  const f = c.female;
  const s = cfg.top.s;
  const ny = c.neckY;
  const hem = f ? 0.93 : 0.9;
  switch (s) {
    case 'tee':
    case 'graphic_tee':
    case 'polo': {
      c.b.add('body', m.top, torsoPiece(c, hem, ny, 0.011, { hemLip: true, flare: 0.004 }));
      sleeves(c, 'short', 0.011, m.top);
      if (s === 'polo') {
        shirtCollar(c, 0.011, m.topTrim);
        placket(c, ny - 0.085, ny - 0.006, 0.011, m.topTrim, 2, m.button);
      } else crewNeck(c, 0.011, m.topTrim);
      if (s === 'graphic_tee') decal(c, m.graphic, 1.13 - (f ? 0.03 : 0), 1.31 - (f ? 0.03 : 0), 0.085, 0.011);
      return { longSleeves: false, legsHidden: false, tucked: false };
    }
    case 'short_shirt':
    case 'shirt':
    case 'shirt_tie': {
      const tucked = s !== 'short_shirt';
      c.b.add('body', m.top, torsoPiece(c, tucked ? 0.97 : hem - 0.01, ny, 0.011, { hemLip: !tucked, flare: tucked ? 0 : 0.006 }));
      sleeves(c, s === 'short_shirt' ? 'short' : 'long', 0.011, m.top, m.topTrim);
      shirtCollar(c, 0.011, m.topTrim);
      placket(c, tucked ? 0.98 : hem, ny - 0.008, 0.011, m.topTrim, 5, m.button);
      if (s === 'shirt_tie') tie(c, 0.011, m.accent);
      return { longSleeves: s !== 'short_shirt', legsHidden: false, tucked };
    }
    case 'blazer': {
      // inner shirt (only the V shows)
      c.b.add('body', m.inner, torsoPiece(c, 1.0, ny, 0.009));
      shirtCollar(c, 0.009, m.inner);
      if (!f) tie(c, 0.009, m.accent, 1.12);
      const vBottom = f ? 1.12 : 1.1;
      const alpha = (y: number) => (y > vBottom ? 0.48 * smooth(vBottom, ny, y) ** 0.8 : 0);
      c.b.add('body', m.top, torsoOpen(c, f ? 0.88 : 0.83, ny + 0.004, 0.021, alpha, 18, 22, 0.008));
      // lapels: folded strips along the opening
      for (const sd of [1, -1]) {
        c.b.add('body', m.topTrim, gridSurface(1, 6, (u, v) => {
          const y = lerp(vBottom, ny - 0.004, v);
          const a = sd * Math.max(alpha(y), 0.02);
          const q = onTorso(c, y, a, 0.024);
          const out = onTorso(c, y, a + sd * (0.14 + 0.18 * v), 0.026);
          const p = q.p.lerp(out.p, u);
          return [p.x, p.y, p.z];
        }, { patchUv: true }));
      }
      const b1 = onTorso(c, vBottom - 0.02, 0, 0.024);
      c.b.add('body', m.button, ellipsoid(0.007, 0.007, 0.003, { p: [b1.p.x, b1.p.y, b1.p.z] }, 6, 4));
      sleeves(c, 'long', 0.016, m.top, m.topTrim);
      // pocket square line
      const pk = onTorso(c, 1.25, 0.55, 0.024);
      c.b.add('body', m.topTrim, box(0.05, 0.004, 0.006, { p: [pk.p.x, pk.p.y, pk.p.z], r: [0, 0.55, 0] }));
      return { longSleeves: true, legsHidden: false, tucked: true };
    }
    case 'hoodie': {
      c.b.add('body', m.top, torsoPiece(c, 0.885, ny + 0.004, 0.019));
      c.b.add('body', m.topTrim, band(c, 0.86, 0.892, 0.025));
      sleeves(c, 'long', 0.017, m.top, m.topTrim);
      // the hood lies folded on the upper back, its rim around the neck
      const backY = ny - 0.035;
      const back = ringAt(d.torso, backY);
      c.b.add('chest', m.top, ellipsoid(f ? 0.095 : 0.11, 0.06, 0.04, { p: [0, backY + 0.004, -((back.db ?? back.df) + 0.03)], r: [0.5, 0, 0] }, 12, 8));
      const pts: V3[] = [];
      for (let i = 0; i <= 10; i++) {
        const a = lerp(0.9, Math.PI * 2 - 0.9, i / 10);
        const q = onTorso(c, ny + 0.004, a, 0.024);
        pts.push([q.p.x, q.p.y, q.p.z]);
      }
      c.b.add('chest', m.top, tube(pts, 0.014, 6));
      decal(c, m.topTrim, 0.92, 1.03, f ? 0.072 : 0.085, 0.022);
      for (const sd of [1, -1]) {
        const q = onTorso(c, ny - 0.008, sd * 0.3, 0.024);
        c.b.add('body', m.white, tube([[q.p.x, q.p.y, q.p.z], [q.p.x + sd * 0.004, q.p.y - 0.09, q.p.z + 0.014]], 0.0028, 4));
      }
      return { longSleeves: true, legsHidden: false, tucked: false };
    }
    case 'singlet': {
      c.b.add('body', m.top, torsoPiece(c, 0.9, f ? 1.3 : 1.33, 0.006, { hemLip: true }));
      for (const sd of [1, -1]) {
        const pts: V3[] = [];
        for (let i = 0; i <= 8; i++) {
          const t = i / 8;
          const a = lerp(sd * 0.42, sd * (Math.PI - 0.42), t);
          const y = lerp(f ? 1.3 : 1.33, ny - 0.002, Math.sin(t * Math.PI));
          const q = onTorso(c, y, a, 0.007);
          pts.push([q.p.x, q.p.y, q.p.z]);
        }
        c.b.add('body', m.top, tube(pts, 0.009, 4));
      }
      return { longSleeves: false, legsHidden: false, tucked: false };
    }
    case 'buba': {
      const bh = f ? 0.88 : 0.79;
      if (bh < 0.86) {
        c.b.add('body', m.top, loft(hemmed(skirtRings(c, ny, bh, 0.02, 0.05)), { seg: 20, tile: 0.25 }));
        cover(c, bh, ny, 0.025);
      } else c.b.add('body', m.top, torsoPiece(c, bh, ny, 0.018, { flare: 0.03, hemLip: true }));
      sleeves(c, f ? 'bell' : 'elbow', 0.016, m.top);
      crewNeck(c, 0.018, m.topTrim);
      decal(c, m.embroidery, ny - 0.11, ny - 0.006, 0.05, 0.018);
      return { longSleeves: false, legsHidden: false, tucked: false };
    }
    case 'kaftan': {
      c.b.add('body', m.top, loft(hemmed(skirtRings(c, ny, 0.68, 0.014, 0.012)), { seg: 20, tile: 0.25 }));
      cover(c, 0.68, ny, 0.016);
      sleeves(c, 'long', 0.013, m.top, m.topTrim);
      c.b.add('body', m.topTrim, band(c, ny - 0.006, ny + 0.012, 0.014));
      decal(c, m.embroidery, 1.17, ny - 0.006, 0.042, 0.014);
      decal(c, m.embroidery, 1.25, 1.33, 0.03, 0.014, 0.09);
      return { longSleeves: true, legsHidden: false, tucked: false };
    }
    case 'agbada':
    case 'boubou': {
      const isAg = s === 'agbada';
      const rings = robe(c, isAg ? { wing: 0.12, wingBottom: 0.86, panel: 0.045, hem: 0.16 } : { wing: 0.11, wingBottom: 0.92, panel: 0.06, hem: 0.1 }, m.top);
      robeDecal(c, m.embroidery, rings, 1.12, c.neckY - 0.004, 0.075);
      if (isAg) {
        // inner kaftan cuffs peek out at the wrists
        for (const sd of ['L', 'R'] as const) {
          const fore = `fore${sd}` as BoneName;
          c.b.add(fore, m.top, limbPiece(c, fore, d.foreArm, -d.foreLen + 0.07, -d.foreLen + 0.02, 0.012));
        }
      } else {
        sleeves(c, 'elbow', 0.014, m.top);
      }
      return { longSleeves: isAg, legsHidden: !isAg, tucked: false };
    }
    case 'gown':
    case 'maxi': {
      const long = s === 'maxi';
      c.b.add('body', m.top, torsoPiece(c, 1.0, ny - 0.004, 0.009));
      crewNeck(c, 0.009, m.topTrim);
      c.b.add('body', m.top, loft(hemmed(skirtRings(c, 1.03, long ? 0.09 : 0.44, 0.012, long ? 0.12 : 0.13), 0.004), { seg: 22, tile: 0.25 }));
      c.b.add('body', m.topTrim, band(c, 1.0, 1.035, 0.016));
      cover(c, 0.4, ny, 0.012);
      sleeves(c, long ? 'short' : 'puff', 0.01, m.top);
      return { longSleeves: false, legsHidden: long, tucked: true };
    }
    case 'chest_wrap': {
      c.b.add('body', m.top, torsoPiece(c, 0.95, 1.292, 0.012));
      c.b.add('body', m.top, band(c, 1.262, 1.3, 0.019));
      const q = onTorso(c, 1.27, 0.55, 0.022);
      c.b.add('body', m.top, ellipsoid(0.02, 0.026, 0.01, { p: [q.p.x, q.p.y - 0.01, q.p.z], r: [0, 0.55, 0.3] }, 8, 6));
      return { longSleeves: false, legsHidden: false, tucked: true };
    }
    case 'scrubs': {
      const alpha = (y: number) => 0.4 * smooth(f ? 1.27 : 1.3, ny, y);
      c.b.add('body', m.top, torsoOpen(c, 0.87, ny + 0.002, 0.015, alpha, 14, 20, 0.006));
      sleeves(c, 'short', 0.014, m.top);
      decal(c, m.topTrim, 1.2, 1.27, 0.032, 0.015, 0.085);
      return { longSleeves: false, legsHidden: false, tucked: false };
    }
    case 'police': {
      c.b.add('body', m.top, torsoPiece(c, 0.97, ny, 0.011));
      sleeves(c, 'long', 0.012, m.top, m.topTrim);
      shirtCollar(c, 0.011, m.topTrim);
      placket(c, 0.98, ny - 0.008, 0.011, m.topTrim, 5, m.button);
      for (const sd of [1, -1]) {
        // epaulettes
        const q = onTorso(c, d.shoulderY + 0.03, sd * Math.PI / 2, 0.013);
        c.b.add('chest', m.topTrim, box(0.085, 0.006, 0.05, { p: [q.p.x - sd * 0.05, q.p.y + 0.006, 0], r: [0, 0, -sd * 0.38] }));
        // chest pockets with flaps
        decal(c, m.topTrim, 1.2, 1.28, 0.032, 0.011, sd * 0.085);
        decal(c, m.top, 1.26, 1.29, 0.036, 0.015, sd * 0.085);
      }
      const bdg = onTorso(c, 1.31, 0.42, 0.016);
      c.b.add('body', m.gold, ellipsoid(0.011, 0.013, 0.004, { p: [bdg.p.x, bdg.p.y, bdg.p.z] }, 8, 6));
      const tag = onTorso(c, 1.31, -0.42, 0.015);
      c.b.add('body', m.white, box(0.034, 0.009, 0.003, { p: [tag.p.x, tag.p.y, tag.p.z], r: [0, -0.42, 0] }));
      return { longSleeves: true, legsHidden: false, tucked: true };
    }
    case 'vest': {
      c.b.add('body', m.innerTee, torsoPiece(c, 0.9, ny, 0.01, { hemLip: true }));
      sleeves(c, 'short', 0.01, m.innerTee);
      crewNeck(c, 0.01, m.innerTee);
      const alpha = (y: number) => 0.55 * smooth(1.2, ny, y) + 0.04;
      c.b.add('body', m.top, torsoOpen(c, 0.885, ny + 0.004, 0.021, alpha, 14, 22));
      for (const y of [1.0, 1.11]) c.b.add('body', m.reflect, band(c, y, y + 0.024, 0.0235, 22));
      return { longSleeves: false, legsHidden: false, tucked: false };
    }
    case 'bare':
    default:
      return { longSleeves: false, legsHidden: false, tucked: true };
  }
}

// ---------------------------------------------------------------------------------------------
// bottoms
// ---------------------------------------------------------------------------------------------

function buildBottom(c: Ctx, cfg: AvatarConfig, topInfo: { legsHidden: boolean; tucked: boolean }) {
  const { d, m } = c;
  const s = cfg.bottom.s;
  const f = c.female;
  const waist = f ? 1.03 : 1.0;
  const long = ['maxi', 'boubou'].includes(cfg.top.s);
  const trouserLike = ['trousers', 'jeans', 'joggers', 'scrubs', 'shorts'].includes(s);

  if (trouserLike) {
    const t = s === 'jeans' ? 0.008 : s === 'joggers' || s === 'scrubs' ? 0.014 : 0.011;
    c.b.add('body', m.bottom, loft(sliceRings(d.torso, d.torso[0].y, waist, t), { seg: 18, tile: 0.2 }));
    cover(c, d.torso[0].y, waist, t);
    for (const sd of ['L', 'R'] as const) {
      const thigh = `thigh${sd}` as BoneName;
      const shin = `shin${sd}` as BoneName;
      if (s === 'shorts') {
        c.b.add(thigh, m.bottom, limbPiece(c, thigh, d.thigh, -0.018, -0.25, t + 0.004, { flare: 0.012, dome: true }));
        continue;
      }
      // legs start just below the hip joint: above it the pelvis piece covers, and short tops stay clean
      c.b.add(thigh, m.bottom, limbPiece(c, thigh, d.thigh, -0.018, -d.thighLen - 0.035, t + 0.003, { dome: true }));
      const hemY = -(d.kneeY - d.ankleY) - (s === 'joggers' ? 0.0 : 0.012);
      c.b.add(shin, m.bottom, limbPiece(c, shin, d.shin, 0.03, hemY, t + 0.004, { flare: s === 'joggers' ? -0.006 : s === 'jeans' ? 0.006 : 0.01 }));
      if (s === 'joggers') c.b.add(shin, m.bottomTrim, limbPiece(c, shin, d.shin, hemY + 0.03, hemY - 0.002, t + 0.002));
    }
    if (topInfo.tucked && !long && cfg.top.s !== 'bare' && cfg.top.s !== 'gown' && cfg.top.s !== 'chest_wrap') belt(c, waist - 0.012, t);
    if ((s === 'scrubs' || s === 'joggers') && topInfo.tucked) {
      const q = onTorso(c, waist - 0.02, 0.1, t + 0.004);
      c.b.add('body', m.white, tube([[q.p.x, q.p.y, q.p.z], [q.p.x + 0.006, q.p.y - 0.06, q.p.z + 0.006]], 0.0024, 4));
    }
    if (cfg.top.s === 'bare') c.b.add('body', m.bottomTrim, band(c, waist - 0.015, waist + 0.006, t + 0.004));
    return;
  }

  // dresses already have their own skirt
  if (['gown', 'maxi', 'boubou'].includes(cfg.top.s)) return;
  const hemY = s === 'skirt' ? (f ? 0.47 : 0.5) : 0.085;
  const flare = s === 'skirt' ? -0.015 : s === 'long_skirt' ? 0.08 : -0.012;
  const t = s === 'wrapper' ? 0.014 : 0.011;
  let rings = skirtRings(c, waist, hemY, t, flare);
  if (s === 'wrapper' || s === 'long_skirt') rings = hemmed(rings, 0.004);
  c.b.add('body', m.bottom, loft(rings, { seg: 22, tile: 0.25 }));
  cover(c, hemY, waist, t);
  if (s === 'wrapper') {
    // the overlapping edge running down the front, and the rolled waist
    const pts: V3[] = [];
    for (let i = 0; i <= 10; i++) {
      const y = lerp(waist - 0.01, hemY + 0.01, i / 10);
      const r = grow(ringAt(rings, y), 0.003);
      const [x, z] = ringXZ(r, 0.42 - i * 0.012);
      pts.push([x, y, z]);
    }
    c.b.add('body', m.bottom, tube(pts, 0.006, 4));
    if (cfg.top.s !== 'chest_wrap' || !f) {
      c.b.add('body', m.bottom, loft(sliceRings(d.torso, waist - 0.03, waist + 0.006, t + 0.008), { seg: 22, tile: 0.25 }));
    }
    if (!f) {
      const q = onTorso(c, waist - 0.02, 0.5, t + 0.012);
      c.b.add('body', m.bottom, ellipsoid(0.022, 0.016, 0.014, { p: [q.p.x, q.p.y, q.p.z] }, 8, 6));
    }
  }
}

// ---------------------------------------------------------------------------------------------
// shoes
// ---------------------------------------------------------------------------------------------

/** Shoe-like loft along z: rings [z, half-width, top height] above the ground. */
function footLoft(at: V3, rows: [number, number, number][], bottom = 0, n = 2.8, seg = 12): BufferGeometry {
  const pts = rows.map(([z, w, top]) => ({ z, w, h: (top - bottom) / 2, c: (top + bottom) / 2 }));
  return gridSurface(seg, pts.length - 1, (u, v) => {
    const r = pts[Math.round(v * (pts.length - 1))];
    const a = u * Math.PI * 2;
    const e = 2 / n;
    const sx = Math.sign(Math.sin(a)) * Math.pow(Math.abs(Math.sin(a)), e);
    const sy = Math.sign(Math.cos(a)) * Math.pow(Math.abs(Math.cos(a)), e);
    // a = 0 is the top of the foot; winding: around x (top -> +x side), along +z
    return [at[0] + r.w * sx, r.c + r.h * sy, at[2] + r.z];
  }, { closed: true, tile: 0.15, flip: true });
}

function buildShoes(c: Ctx, cfg: AvatarConfig) {
  const { m } = c;
  const s = cfg.shoes.s;
  const f = c.female;
  const k = f ? 0.92 : 1;
  for (const sd of ['L', 'R'] as const) {
    const foot = `foot${sd}` as BoneName;
    const at = c.pos[foot];
    const base: V3 = [at[0], 0, at[2] + 0.004];
    const Z = (z: number) => z * k;
    if (s === 'slippers' || s === 'sandals') {
      // bare foot + sole + straps
      c.b.add(foot, m.skin, footLoft(base, [
        [Z(-0.052), 0.0, 0.02], [Z(-0.048), 0.027, 0.05], [Z(-0.02), 0.032, 0.07], [Z(0.03), 0.038, 0.06],
        [Z(0.09), 0.043, 0.04], [Z(0.13), 0.04, 0.03], [Z(0.155), 0.03, 0.022], [Z(0.163), 0.0, 0.016],
      ], 0.01));
      const th = s === 'sandals' ? 0.02 : 0.012;
      c.b.add(foot, m.sole, footLoft(base, [
        [Z(-0.06), 0.0, th * 0.5], [Z(-0.056), 0.033, th], [Z(0.03), 0.042, th], [Z(0.11), 0.049, th], [Z(0.168), 0.036, th], [Z(0.176), 0.0, th * 0.5],
      ], 0, 4));
      const strapZ = s === 'sandals' ? [0.035, 0.085] : [0.06];
      for (const z of strapZ) {
        c.b.add(foot, m.shoe, footLoft(base, [[Z(z - 0.014), 0.046, 0.062 - z * 0.25], [Z(z + 0.014), 0.047, 0.058 - z * 0.25]], th - 0.002, 2.4, 12));
      }
      continue;
    }
    const sneaker = s === 'sneakers';
    const boot = s === 'boots';
    const heel = s === 'heels';
    const formal = s === 'formal';
    const W = heel ? 0.86 : formal ? 0.94 : 1;
    const top = heel ? 0.052 : formal ? 0.072 : 0.085;
    c.b.add(foot, m.shoe, footLoft(base, [
      [Z(-0.058), 0.0, top * 0.6], [Z(-0.056), 0.03 * W, top], [Z(-0.03), 0.039 * W, top + 0.004], [Z(0.01), 0.042 * W, top + 0.006],
      [Z(0.05), 0.046 * W, top - 0.012], [Z(0.1), 0.047 * W, top - 0.034], [Z(0.14), 0.042 * W, heel ? 0.024 : top - 0.048], [Z(0.165), 0.03 * W, heel ? 0.018 : top - 0.056],
      [Z(heel ? 0.185 : 0.175), 0.0, heel ? 0.012 : top - 0.06],
    ], 0.006));
    if (sneaker || boot || formal) {
      const th = sneaker ? 0.024 : boot ? 0.02 : 0.012;
      c.b.add(foot, sneaker ? m.white : m.sole, footLoft(base, [
        [Z(-0.064), 0.0, th * 0.6], [Z(-0.061), 0.033, th], [Z(0.02), 0.046, th], [Z(0.1), 0.051, th], [Z(0.165), 0.037, th * 0.9], [Z(0.18), 0.0, th * 0.5],
      ], 0, 4));
    }
    if (sneaker) {
      for (let i = 0; i < 3; i++) {
        const z = Z(0.035 + i * 0.022);
        c.b.add(foot, m.white, box(0.04, 0.004, 0.006, { p: [base[0], top - 0.006 - i * 0.008, base[2] + z], r: [0.35, 0, 0] }));
      }
    }
    if (heel) {
      c.b.add(foot, m.shoe, box(0.014, 0.05, 0.014, { p: [base[0], 0.025, base[2] - 0.045] }));
    }
    if (boot) {
      const shin = `shin${sd}` as BoneName;
      c.b.add(shin, m.shoe, limbPiece(c, shin, c.d.shin, -0.24, -(c.d.kneeY - c.d.ankleY) - 0.02, 0.016));
    }
  }
}

// ---------------------------------------------------------------------------------------------

export function buildClothes(b: PartBuilder, d: Dims, cfg: AvatarConfig, m: ClothMats): ClothResult {
  const c: Ctx = { d, b, m, pos: bonePositions(d), covers: [], skirts: [], female: d.gender === 'female', neckY: d.neckBaseY - (d.gender === 'female' ? 0.01 : 0.012) };
  const top = buildTop(c, cfg);
  buildBottom(c, cfg, top);
  buildShoes(c, cfg);
  return {
    outer: (y: number) => c.covers.reduce((mx, [a, bb, t]) => (y >= a - 0.01 && y <= bb + 0.01 ? Math.max(mx, t) : mx), 0),
    longSleeves: top.longSleeves,
    legsHidden: top.legsHidden,
    widthAt: (y: number) => {
      let w = grow(ringAt(d.torso, y), c.covers.reduce((mx, [a, bb, t]) => (y >= a && y <= bb ? Math.max(mx, t) : mx), 0)).w;
      for (const rs of c.skirts) if (y >= rs[0].y && y <= rs[rs.length - 1].y) w = Math.max(w, ringAt(rs, y).w);
      return w;
    },
  };
}

export { onTorso as torsoPoint };
export type { Ctx as ClothCtx };
