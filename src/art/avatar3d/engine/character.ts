// Assembles a full character from an AvatarConfig: rig, skin, face, hair, clothes, accessories.
import { Box3, BufferGeometry, Vector3 } from 'three';
import type { AvatarConfig } from '../../../lib/types';
import { avatarKey, migrateAvatar, skinTone } from '../catalog';
import { bonePositions, makeDims, makeRig, PartBuilder, type BoneName, type Dims, type Profile, type Rig } from './body';
import { buildClothes } from './clothing';
import { buildAccessories } from './accessories';
import { ellipsoid, loft, type Ring, type V3 } from './geo';
import { buildFace, buildFacialHair, HeadSurface } from './head';
import { buildHair, type HatMat } from './hair';
import { coralMat, decalMat, fabric, glossy, luma, matte, mix, shade, soft, towelMat, unlit } from './materials';

export interface Character {
  root: Rig['root'];
  rig: Rig;
  dims: Dims;
  config: AvatarConfig;
  stats: { tris: number; meshes: number; buildMs: number };
  /** Long hair: keep head turns small. */
  longHair: boolean;
  /** Walk stride scale: 1 in trousers, shorter in knee skirts, short steps in wrappers and robes. */
  stride: number;
  /** Top of the head/hair/hat in model space (after scale). */
  topY: number;
  /** Head centre in model space (after scale). */
  headY: number;
  dispose(): void;
}

function limbRings(p: Profile, at: V3): Ring[] {
  return p.map(([y, w, d]) => ({ y: at[1] + y, w, df: d, x: at[0], z: at[2] })).sort((a, b) => a.y - b.y);
}

function seedOf(s: string) {
  let h = 2166136261;
  for (let i = 0; i < s.length; i++) h = Math.imul(h ^ s.charCodeAt(i), 16777619);
  return h >>> 0;
}

export function buildCharacter(input: AvatarConfig): Character {
  const t0 = performance.now();
  const cfg = migrateAvatar(input); // tolerant of v1 looks, {} and junk
  const female = cfg.gender === 'female';
  const d = makeDims(cfg.gender, cfg.body);
  const rig = makeRig(d);
  const b = new PartBuilder();
  const pos = bonePositions(d);
  const tone = skinTone(cfg.skin);

  const skin = matte(tone.base);
  const skinShade = matte(tone.shade);

  // ---------------------------------------------------------------- body
  b.add('body', skin, loft(d.torso, { seg: 18, capLo: true }));
  const neckRings: Ring[] = [
    { y: d.neckBaseY - 0.035, w: d.neckR * 1.25, df: d.neckR * 1.15, db: d.neckR * 1.25, z: -0.004 },
    { y: d.neckBaseY + 0.01, w: d.neckR * 1.04, df: d.neckR, db: d.neckR * 1.05, z: -0.004 },
    { y: d.headPivotY + 0.02, w: d.neckR * 0.98, df: d.neckR * 0.95, db: d.neckR, z: -0.002 },
    { y: d.headPivotY + 0.06, w: d.neckR * 0.9, df: d.neckR * 0.9, db: d.neckR * 0.95, z: 0.0 },
  ];
  b.add('neck', skin, loft(neckRings, { seg: 12 }));
  for (const s of ['L', 'R'] as const) {
    const sd = s === 'L' ? 1 : -1;
    b.add(`arm${s}` as BoneName, skin, loft(limbRings(d.upperArm, pos[`arm${s}`]), { seg: 10 }));
    b.add(`fore${s}` as BoneName, skin, loft(limbRings(d.foreArm, pos[`fore${s}`]), { seg: 10 }));
    const hp = pos[`hand${s}`];
    b.add(`hand${s}` as BoneName, skin, loft(limbRings(d.hand, hp), { seg: 10 }));
    // thumb on the front edge, angled in
    b.add(`hand${s}` as BoneName, skin, ellipsoid(0.0105, 0.027, 0.0105, { p: [hp[0] - sd * 0.008, hp[1] - 0.04, hp[2] + 0.03], r: [0.45, 0, sd * 0.25] }, 7, 5));
    b.add(`thigh${s}` as BoneName, skin, loft(limbRings(d.thigh, pos[`thigh${s}`]), { seg: 12 }));
    b.add(`shin${s}` as BoneName, skin, loft(limbRings(d.shin, pos[`shin${s}`]), { seg: 12 }));
  }

  // ---------------------------------------------------------------- head
  const h = new HeadSurface(cfg.face, female);
  const hc = d.headCenter;
  const toHead = (g: BufferGeometry) => g.translate(hc[0], hc[1], hc[2]);
  b.add('head', skin, toHead(h.mesh()));
  const face = buildFace(h, cfg);
  const lip = matte(tone.lip);
  const add = (mat: ReturnType<typeof matte>, list: BufferGeometry[]) => list.forEach((g) => b.add('head', mat, toHead(g)));
  add(skin, face.skin);
  add(skinShade, face.skinShade);
  add(soft('#f4efe6'), face.eyeWhite);
  add(soft('#2a170e'), face.iris);
  add(soft('#110a08'), face.lash);
  add(unlit('#ffffff'), face.shine);
  add(lip, face.lip);
  add(matte('#2a0f0d'), face.mouthDark);
  add(soft('#f6f2ea'), face.teeth);

  const hairCol = cfg.hairColor;
  const browCol = luma(hairCol) > 0.35 ? shade(hairCol, -0.35) : shade(hairCol, -0.1);
  add(matte(browCol), face.brow);
  const fh = buildFacialHair(h, female ? 'none' : cfg.facialHair);
  add(matte(hairCol, true), fh.hair);
  add(matte(mix(tone.base, hairCol, 0.32)), fh.stubble);

  // ---------------------------------------------------------------- clothes
  const topFabric = cfg.top.f === 'plain' && cfg.top.s === 'jeans' ? 'denim' : cfg.top.f;
  const botFabric = cfg.bottom.f === 'plain' && cfg.bottom.s === 'jeans' ? 'denim' : cfg.bottom.f;
  const topMat = fabric(topFabric, cfg.top.c);
  const botMat = fabric(botFabric, cfg.bottom.c);
  const trimFor = (c: string) => matte(luma(c) > 0.5 ? shade(c, -0.12) : shade(c, 0.1), true);
  const embCol = cfg.accent.toLowerCase() === cfg.top.c.toLowerCase() ? (luma(cfg.accent) > 0.5 ? shade(cfg.accent, -0.4) : shade(cfg.accent, 0.5)) : cfg.accent;
  const clothMats = {
    skin,
    top: topMat,
    topTrim: cfg.top.f === 'plain' ? trimFor(cfg.top.c) : topMat,
    bottom: botMat,
    bottomTrim: trimFor(cfg.bottom.c),
    inner: matte('#f6f4ef', true),
    innerTee: matte('#3a3f4a', true),
    shoe: ['formal', 'boots', 'heels'].includes(cfg.shoes.s) ? glossy(cfg.shoes.c, 50, '#555555') : matte(cfg.shoes.c),
    sole: matte(cfg.shoes.s === 'sandals' || cfg.shoes.s === 'slippers' ? shade(cfg.shoes.c, -0.35) : '#2b2622'),
    accent: matte(cfg.accent, true),
    accentDark: matte(shade(cfg.accent, luma(cfg.accent) > 0.6 ? -0.18 : -0.3), true),
    gold: glossy('#d9a441', 80, '#fff2c0'),
    silver: glossy('#c9ccd2', 80),
    black: matte('#17171b'),
    white: matte('#f4f2ec', true),
    leather: matte('#3b2418'),
    reflect: matte('#d9dde3'),
    embroidery: decalMat('embroidery', embCol),
    embroideryBand: matte(embCol, true),
    graphic: decalMat('graphic', cfg.accent),
    button: matte(luma(cfg.top.c) > 0.5 ? '#3a3a3a' : '#e8e4da'),
  };
  const cloth = buildClothes(b, d, cfg, clothMats);

  // ---------------------------------------------------------------- hair & headwear
  const hair = buildHair(h, { hair: cfg.hair, hat: cfg.hat, female, seed: seedOf(avatarKey(cfg)) & 0xffff }, {
    torso: d.torso,
    hc,
    neckR: d.neckR,
    neckBaseY: d.neckBaseY,
    shoulderX: d.shoulderX,
    shoulderY: d.shoulderY,
    margin: Math.max(0.012, cloth.outer(d.shoulderY) + 0.008),
  });
  add(matte(hairCol, true), hair.hair);
  const gele = cfg.hat === 'gele' || cfg.hat === 'head_tie' || cfg.hat === 'fila';
  const hatMats: Record<HatMat, ReturnType<typeof matte>> = {
    accent: matte(cfg.accent, true),
    accentDark: matte(shade(cfg.accent, -0.25), true),
    accentFabric: gele ? fabric(cfg.top.f === 'plain' ? 'asooke' : cfg.top.f, cfg.accent) : matte(cfg.accent, true),
    coral: coralMat(),
    coralBead: soft('#d4372c'),
    black: glossy('#141418', 30, '#444444'),
    gold: glossy('#d9a441', 80, '#fff2c0'),
    white: matte('#f4f2ec'),
  };
  for (const k of Object.keys(hair.hat) as HatMat[]) add(hatMats[k], hair.hat[k]!);

  // ---------------------------------------------------------------- accessories
  buildAccessories(b, d, h, cfg, {
    gold: clothMats.gold,
    black: matte('#141418'),
    lens: glossy('#0d1014', 90, '#9aa4b0'),
    white: clothMats.white,
    coralBead: soft('#d4372c'),
    leather: clothMats.leather,
    accent: matte(cfg.accent, true),
    accentDark: matte(shade(cfg.accent, -0.3), true),
    screen: glossy('#1d2a3d', 90),
    towel: towelMat(cfg.accent),
    silver: clothMats.silver,
  }, cloth.outer);

  const built = b.finish(rig, d);

  // ---------------------------------------------------------------- rest pose
  // Swing the arms out just enough that the hands clear wide skirts, tunics and hips (robes are worn over the arms).
  if (!['agbada', 'boubou'].includes(cfg.top.s)) {
    const reach = d.armLen + d.foreLen + 0.12;
    for (let th = d.armOut; th <= 0.42; th += 0.01) {
      let ok = true;
      for (let s = d.armLen + 0.06; s <= reach; s += 0.03) {
        const y = d.shoulderY - Math.cos(th) * s;
        const x = d.shoulderX + Math.sin(th) * s;
        const r = s > d.armLen + d.foreLen ? 0.022 : 0.034;
        if (x - r < cloth.widthAt(y) + 0.006) {
          ok = false;
          break;
        }
      }
      d.armOut = th;
      if (ok) break;
    }
  }
  restPose(rig, d);

  const topLocal = Math.max(hair.top, h.pt(1, 0).y + 0.005);
  const char: Character = {
    root: rig.root,
    rig,
    dims: d,
    config: cfg,
    stats: { tris: built.tris, meshes: built.meshes, buildMs: performance.now() - t0 },
    longHair: hair.long,
    stride: ['maxi', 'boubou', 'agbada'].includes(cfg.top.s) || (['wrapper', 'long_skirt'].includes(cfg.bottom.s) && !['gown'].includes(cfg.top.s))
      ? 0.38
      : cfg.bottom.s === 'skirt' || cfg.top.s === 'gown' || cfg.top.s === 'kaftan'
        ? 0.75
        : 1,
    topY: (hc[1] + topLocal) * d.scale,
    headY: hc[1] * d.scale,
    dispose() {
      for (const g of built.geometries) g.dispose();
      rig.root.removeFromParent();
    },
  };
  return char;
}

export function restPose(rig: Rig, d: Dims) {
  // M2: every joint a pose may bend goes back to straight here (knees, hips, spine). Before, the shins
  // and the body/chest twist were left as the last pose set them, so a sit (knees 1.45 rad) leaked into
  // the stand-up when the next pose only called restPose ("bent legs after watching TV").
  rig.body.rotation.set(0, 0, 0);
  rig.chest.rotation.set(0, 0, 0);
  rig.shinL.rotation.set(0, 0, 0);
  rig.shinR.rotation.set(0, 0, 0);
  rig.armL.rotation.set(0, 0, d.armOut);
  rig.armR.rotation.set(0, 0, -d.armOut);
  rig.foreL.rotation.set(-0.16, 0, 0.02);
  rig.foreR.rotation.set(-0.16, 0, -0.02);
  rig.handL.rotation.set(-0.06, 0.1, 0);
  rig.handR.rotation.set(-0.06, -0.1, 0);
  rig.thighL.rotation.set(0, 0, 0.028);
  rig.thighR.rotation.set(0, 0, -0.028);
  rig.footL.rotation.set(0, 0.12, -0.028);
  rig.footR.rotation.set(0, -0.12, 0.028);
  rig.body.position.y = d.hipY;
}

/** World-space bounds of the whole character (for framing). */
export function bounds(c: Character): Box3 {
  c.root.updateMatrixWorld(true);
  return new Box3().setFromObject(c.root);
}

export const _v = new Vector3();
