// Body proportions, the bone hierarchy and the part builder that merges geometry per bone and material.
// Units are metres; the character stands on y = 0 facing +z. "L" is the character's left (+x).
import { BufferGeometry, Group, Mesh, Object3D, type Material } from 'three';
import type { BodyType, Gender } from '../../../lib/types';
import { merge, triCount, type Ring, type V3 } from './geo';

export type BoneName =
  | 'body' | 'chest' | 'neck' | 'head'
  | 'armL' | 'foreL' | 'handL' | 'armR' | 'foreR' | 'handR'
  | 'thighL' | 'shinL' | 'footL' | 'thighR' | 'shinR' | 'footR';

export const BONE_PARENT: Record<BoneName, BoneName | null> = {
  body: null,
  chest: 'body',
  neck: 'chest',
  head: 'neck',
  armL: 'chest',
  foreL: 'armL',
  handL: 'foreL',
  armR: 'chest',
  foreR: 'armR',
  handR: 'foreR',
  thighL: 'body',
  shinL: 'thighL',
  footL: 'shinL',
  thighR: 'body',
  shinR: 'thighR',
  footR: 'shinR',
};

/** Limb profile: [y (local, joint at 0, limb hangs to -y), half-width x, half-depth z]. */
export type Profile = [number, number, number][];

export interface Dims {
  gender: Gender;
  build: BodyType;
  /** Uniform scale applied to the whole model (women are a little shorter). */
  scale: number;
  torso: Ring[];
  hipX: number;
  hipY: number;
  kneeY: number;
  ankleY: number;
  shoulderX: number;
  shoulderY: number;
  neckBaseY: number;
  headPivotY: number;
  /** Head-local origin in model space. */
  headCenter: V3;
  neckR: number;
  upperArm: Profile;
  foreArm: Profile;
  hand: Profile;
  thigh: Profile;
  shin: Profile;
  armLen: number;
  foreLen: number;
  thighLen: number;
  shinLen: number;
  /** Arm rest angle away from the body (radians). */
  armOut: number;
}

const MALE_TORSO: [number, number, number, number, number][] = [
  // y,    w,     df,    db,    n
  [0.815, 0.1, 0.058, 0.068, 2.2],
  [0.84, 0.145, 0.08, 0.09, 2.4],
  [0.89, 0.161, 0.088, 0.1, 2.4],
  [0.95, 0.162, 0.088, 0.097, 2.4],
  [1.01, 0.154, 0.088, 0.088, 2.4],
  [1.08, 0.154, 0.092, 0.086, 2.4],
  [1.15, 0.162, 0.098, 0.088, 2.4],
  [1.22, 0.173, 0.105, 0.092, 2.5],
  [1.28, 0.182, 0.107, 0.095, 2.6],
  [1.33, 0.188, 0.101, 0.092, 2.6],
  [1.375, 0.19, 0.088, 0.085, 2.6],
  [1.41, 0.172, 0.072, 0.072, 2.4],
  [1.435, 0.128, 0.062, 0.065, 2.2],
  [1.455, 0.078, 0.052, 0.056, 2],
  [1.47, 0.05, 0.045, 0.05, 2],
];

const FEMALE_TORSO: [number, number, number, number, number][] = [
  [0.8, 0.108, 0.062, 0.075, 2.2],
  [0.83, 0.158, 0.084, 0.1, 2.3],
  [0.88, 0.176, 0.09, 0.116, 2.3],
  [0.94, 0.17, 0.088, 0.108, 2.3],
  [1.0, 0.146, 0.082, 0.088, 2.3],
  [1.05, 0.13, 0.077, 0.077, 2.3],
  [1.11, 0.134, 0.081, 0.077, 2.3],
  [1.165, 0.143, 0.094, 0.08, 2.3],
  [1.215, 0.15, 0.118, 0.082, 2.3],
  [1.265, 0.153, 0.112, 0.082, 2.4],
  [1.305, 0.158, 0.09, 0.079, 2.4],
  [1.35, 0.162, 0.078, 0.074, 2.4],
  [1.385, 0.148, 0.065, 0.065, 2.3],
  [1.415, 0.1, 0.055, 0.058, 2.1],
  [1.435, 0.064, 0.047, 0.05, 2],
  [1.45, 0.044, 0.04, 0.045, 2],
];

function scaleProfile(p: Profile, k: number, kd = k): Profile {
  return p.map(([y, w, d]) => [y, w * k, d * kd]);
}

/** Body-type multipliers by height band (smooth, so curves stay soft). */
function bodyMul(build: BodyType, female: boolean, y: number): { w: number; df: number; db: number } {
  if (build === 'average') return { w: 1, df: 1, db: 1 };
  const bump = (c: number, r: number) => Math.max(0, 1 - Math.abs(y - c) / r);
  if (build === 'slim') {
    const neck = y > 1.43 ? (y - 1.43) / 0.04 : 0; // keep the neck join the same
    const k = 0.86 + 0.14 * Math.min(1, neck);
    return { w: k, df: k, db: k };
  }
  // thick
  if (female) {
    const hips = bump(0.9, 0.16);
    const waist = bump(1.07, 0.12);
    const bust = bump(1.23, 0.08);
    const neck = y > 1.42 ? 0 : 1;
    return {
      w: 1 + (0.06 + 0.14 * hips + 0.08 * waist) * neck,
      df: 1 + (0.06 + 0.1 * waist + 0.12 * bust + 0.05 * hips) * neck,
      db: 1 + (0.06 + 0.24 * hips) * neck,
    };
  }
  const belly = bump(1.07, 0.22);
  const neck = y > 1.42 ? 0 : 1;
  return {
    w: 1 + (0.1 + 0.09 * belly) * neck,
    df: 1 + (0.08 + 0.32 * belly) * neck,
    db: 1 + (0.09 + 0.05 * belly) * neck,
  };
}

export function makeDims(gender: Gender, build: BodyType): Dims {
  const female = gender === 'female';
  const rows = female ? FEMALE_TORSO : MALE_TORSO;
  const torso: Ring[] = rows.map(([y, w, df, db, n]) => {
    const m = bodyMul(build, female, y);
    return { y, w: w * m.w, df: df * m.df, db: db * m.db, n };
  });
  const limbK = build === 'slim' ? 0.85 : build === 'thick' ? 1.2 : 1;
  const legK = build === 'slim' ? 0.88 : build === 'thick' ? (female ? 1.24 : 1.14) : 1;

  const upperArm: Profile = [
    [0.048, 0.0, 0.0], [0.04, 0.03, 0.03], [0.018, 0.047, 0.045], [-0.03, 0.05, 0.047], [-0.1, 0.046, 0.044],
    [-0.2, 0.04, 0.04], [-0.27, 0.035, 0.036], [-0.3, 0.031, 0.031], [-0.315, 0.0, 0.0],
  ];
  const foreArm: Profile = [
    [0.022, 0.0, 0.0], [0.012, 0.031, 0.031], [-0.03, 0.037, 0.035], [-0.09, 0.036, 0.032], [-0.19, 0.03, 0.025],
    [-0.245, 0.026, 0.021], [-0.262, 0.0, 0.0],
  ];
  // hands: x = thickness, z = palm width (palms face the thighs)
  const hand: Profile = [
    [0.006, 0.0, 0.0], [0.0, 0.019, 0.025], [-0.03, 0.02, 0.038], [-0.07, 0.018, 0.04], [-0.1, 0.015, 0.036],
    [-0.124, 0.012, 0.027], [-0.138, 0.0, 0.0],
  ];
  const thigh: Profile = [
    [0.07, 0.0, 0.0], [0.05, 0.062, 0.062], [0.0, 0.084, 0.084], [-0.1, 0.08, 0.08], [-0.22, 0.068, 0.068],
    [-0.35, 0.056, 0.056], [-0.41, 0.051, 0.051], [-0.44, 0.041, 0.041], [-0.452, 0.0, 0.0],
  ];
  const shin: Profile = [
    [0.03, 0.0, 0.0], [0.02, 0.042, 0.042], [0.0, 0.05, 0.05], [-0.08, 0.054, 0.058], [-0.18, 0.047, 0.05],
    [-0.3, 0.037, 0.038], [-0.39, 0.031, 0.032], [-0.42, 0.027, 0.028], [-0.432, 0.0, 0.0],
  ];

  if (female) {
    return {
      gender, build, scale: 0.955, torso,
      hipX: 0.086 * (build === 'thick' ? 1.1 : build === 'slim' ? 0.94 : 1),
      hipY: 0.88, kneeY: 0.47, ankleY: 0.075,
      shoulderX: 0.158 * (build === 'thick' ? 1.05 : build === 'slim' ? 0.95 : 1),
      shoulderY: 1.362, neckBaseY: 1.44, headPivotY: 1.51,
      headCenter: [0, 1.51 + 0.094, 0.014],
      neckR: 0.0435 * (build === 'thick' ? 1.08 : build === 'slim' ? 0.95 : 1),
      upperArm: scaleProfile(upperArm, 0.84 * limbK).map(([y, w, d]) => [y * 0.93, w, d]),
      foreArm: scaleProfile(foreArm, 0.86 * limbK).map(([y, w, d]) => [y * 0.95, w, d]),
      hand: scaleProfile(hand, 0.9).map(([y, w, d]) => [y * 0.93, w, d]),
      thigh: scaleProfile(thigh, 1.02 * legK).map(([y, w, d]) => [y * 0.99, w, d]),
      shin: scaleProfile(shin, 0.95 * Math.sqrt(legK)).map(([y, w, d]) => [y * 0.98, w, d]),
      armLen: 0.29 * 0.93,
      foreLen: 0.245 * 0.95,
      thighLen: 0.41,
      shinLen: 0.395,
      armOut: 0.13,
    };
  }
  return {
    gender, build, scale: 1, torso,
    hipX: 0.088 * (build === 'thick' ? 1.06 : build === 'slim' ? 0.95 : 1),
    hipY: 0.9, kneeY: 0.49, ankleY: 0.08,
    shoulderX: 0.181 * (build === 'thick' ? 1.06 : build === 'slim' ? 0.95 : 1),
    shoulderY: 1.382, neckBaseY: 1.458, headPivotY: 1.538,
    headCenter: [0, 1.538 + 0.097, 0.014],
    neckR: 0.052 * (build === 'thick' ? 1.1 : build === 'slim' ? 0.94 : 1),
    upperArm: scaleProfile(upperArm, 1.08 * limbK),
    foreArm: scaleProfile(foreArm, 1.04 * Math.sqrt(limbK)),
    hand,
    thigh: scaleProfile(thigh, legK),
    shin: scaleProfile(shin, Math.sqrt(legK)),
    armLen: 0.29,
    foreLen: 0.245,
    thighLen: 0.41,
    shinLen: 0.41,
    armOut: build === 'thick' ? 0.17 : 0.12,
  };
}

/** Bind-pose position of each bone in model space. */
export function bonePositions(d: Dims): Record<BoneName, V3> {
  const sx = d.shoulderX;
  const p: Partial<Record<BoneName, V3>> = {
    body: [0, d.hipY, 0],
    chest: [0, d.shoulderY, 0],
    neck: [0, d.neckBaseY, -0.004],
    head: [0, d.headPivotY, 0],
  };
  for (const [side, k] of [['L', 1], ['R', -1]] as const) {
    p[`arm${side}`] = [k * sx, d.shoulderY, 0];
    p[`fore${side}`] = [k * sx, d.shoulderY - d.armLen, 0];
    p[`hand${side}`] = [k * sx, d.shoulderY - d.armLen - d.foreLen, 0];
    p[`thigh${side}`] = [k * d.hipX, d.hipY, 0];
    p[`shin${side}`] = [k * d.hipX, d.kneeY, 0];
    p[`foot${side}`] = [k * d.hipX, d.ankleY, 0];
  }
  return p as Record<BoneName, V3>;
}

export type Rig = Record<BoneName, Object3D> & { root: Group };

export function makeRig(d: Dims): Rig {
  const pos = bonePositions(d);
  const root = new Group();
  root.name = 'avatar';
  const rig = { root } as Rig;
  const names = Object.keys(BONE_PARENT) as BoneName[];
  for (const n of names) {
    const o = new Object3D();
    o.name = n;
    rig[n] = o;
  }
  for (const n of names) {
    const parent = BONE_PARENT[n];
    const pp = parent ? pos[parent] : [0, 0, 0];
    rig[n].position.set(pos[n][0] - pp[0], pos[n][1] - pp[1], pos[n][2] - pp[2]);
    (parent ? rig[parent] : root).add(rig[n]);
  }
  root.scale.setScalar(d.scale);
  return rig;
}

/** Collects model-space geometry per bone and material, then merges each bucket into one mesh. */
export class PartBuilder {
  private buckets = new Map<BoneName, Map<Material, BufferGeometry[]>>();

  add(bone: BoneName, mat: Material, ...geos: BufferGeometry[]) {
    let m = this.buckets.get(bone);
    if (!m) this.buckets.set(bone, (m = new Map()));
    let list = m.get(mat);
    if (!list) m.set(mat, (list = []));
    list.push(...geos);
  }

  /** Builds meshes into the rig. Returns triangle and draw-call counts. */
  finish(rig: Rig, d: Dims): { tris: number; meshes: number; geometries: BufferGeometry[] } {
    const pos = bonePositions(d);
    let tris = 0;
    let meshes = 0;
    const geometries: BufferGeometry[] = [];
    for (const [bone, byMat] of this.buckets) {
      const [bx, by, bz] = pos[bone];
      for (const [mat, list] of byMat) {
        const geo = list.length === 1 ? list[0] : merge(list);
        geo.translate(-bx, -by, -bz);
        geo.computeBoundingSphere();
        const mesh = new Mesh(geo, mat);
        mesh.name = `${bone}:${mat.name}`;
        rig[bone].add(mesh);
        tris += triCount(geo);
        meshes++;
        geometries.push(geo);
        if (list.length > 1) for (const g of list) g.dispose();
      }
    }
    return { tris, meshes, geometries };
  }
}
