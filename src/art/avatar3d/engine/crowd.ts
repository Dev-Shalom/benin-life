// L3 crowd rigs: the real avatar (same rig, same poses) built at a lower segment count and baked into ONE
// skinned mesh with vertex colours, so a nearby background person costs 1 draw call and ~1.5-3k triangles
// instead of 33-50 calls and 8-16k. Rigid skinning (each part follows its bone with weight 1) gives exactly the
// per-bone motion of the full character. Textured fabrics become their average colour; decals, eye shine and
// other tiny transparent / unlit bits are dropped (invisible at place zoom).
import {
  BufferGeometry,
  Color,
  Float32BufferAttribute,
  Matrix4,
  Mesh,
  MeshLambertMaterial,
  Skeleton,
  SkinnedMesh,
  Uint16BufferAttribute,
  type Bone,
  type Material,
  type Object3D,
  type Texture,
} from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import type { AvatarConfig } from '../../../lib/types';
import { BONE_PARENT, type BoneName } from './body';
import { buildCharacter, type Character } from './character';
import { withDetail } from './geo';
import { skinTone } from '../catalog';

export interface CrowdRig {
  ch: Character;
  mesh: SkinnedMesh;
  tris: number;
  dispose(): void;
}

let shared: MeshLambertMaterial | null = null;
/** One material for every crowd rig (vertex colours, flat shaded like the Sim). */
export function crowdRigMaterial(): MeshLambertMaterial {
  if (!shared) shared = new MeshLambertMaterial({ vertexColors: true, flatShading: true });
  return shared;
}

const avgCache = new WeakMap<Texture, Color>();
function textureAverage(t: Texture): Color {
  let c = avgCache.get(t);
  if (c) return c;
  c = new Color(1, 1, 1);
  try {
    const img = t.image as CanvasImageSource | undefined;
    if (img && typeof document !== 'undefined') {
      const cv = document.createElement('canvas');
      cv.width = cv.height = 1;
      const ctx = cv.getContext('2d');
      if (ctx) {
        ctx.drawImage(img, 0, 0, 1, 1);
        const d = ctx.getImageData(0, 0, 1, 1).data;
        c.setRGB(d[0] / 255, d[1] / 255, d[2] / 255, 'srgb');
      }
    }
  } catch {
    /* tainted / not drawable: white */
  }
  avgCache.set(t, c);
  return c;
}

function colorOf(m: Material): Color | null {
  const mm = m as Material & { color?: Color; map?: Texture | null; transparent?: boolean; alphaTest?: number };
  if (mm.transparent || (mm.alphaTest ?? 0) > 0) return null; // decals
  if ((m as { isMeshBasicMaterial?: boolean }).isMeshBasicMaterial) return null; // eye shine
  const c = (mm.color ?? new Color(1, 1, 1)).clone();
  if (mm.map) c.multiply(textureAverage(mm.map));
  return c;
}

const BONES = Object.keys(BONE_PARENT) as BoneName[];
const _m = new Matrix4();
const _inv = new Matrix4();

/** Builds a crowd rig for a look. `detail` 0.2-1 scales the segment counts (0.25 by default). */
export function buildCrowdRig(cfg: AvatarConfig, detail = 0.25): CrowdRig {
  // the two heaviest hairs swap for a look-alike (braids ~2x the triangles of a whole crowd body)
  const hair = cfg.hair === 'braids' ? 'ponytail' : cfg.hair === 'locs' ? 'twists' : cfg.hair;
  const ch = withDetail(detail, () => buildCharacter(hair === cfg.hair ? cfg : { ...cfg, hair }));
  const root = ch.root;
  root.position.set(0, 0, 0);
  root.rotation.set(0, 0, 0);
  root.updateMatrixWorld(true);
  _inv.copy(root.matrixWorld).invert();
  const parts: BufferGeometry[] = [];
  const meshes: Mesh[] = [];
  root.traverse((o: Object3D) => {
    if ((o as Mesh).isMesh) meshes.push(o as Mesh);
  });
  // skin hidden under clothes (torso under a top, upper arms under sleeves): a garment on the same bone at least as
  // wide as the skin covers it
  const skinHex = skinTone(cfg.skin).base.toLowerCase();
  const isSkin = (m: Mesh) => !Array.isArray(m.material) && '#' + ((m.material as MeshLambertMaterial).color?.getHexString() ?? '') === skinHex;
  const radius = (m: Mesh) => {
    if (!m.geometry.boundingSphere) m.geometry.computeBoundingSphere();
    return m.geometry.boundingSphere?.radius ?? 0;
  };
  const covered = new Set<Mesh>();
  for (const bone of ['body', 'armL', 'armR'] as const) {
    const on = meshes.filter((m) => m.parent?.name === bone);
    const cloth = Math.max(0, ...on.filter((m) => !isSkin(m)).map(radius));
    for (const m of on) if (isSkin(m) && cloth >= radius(m) * 0.97) covered.add(m);
  }
  for (const mesh of meshes) {
    if (covered.has(mesh)) continue;
    const boneName = mesh.parent?.name as BoneName;
    const bi = BONES.indexOf(boneName);
    const col = Array.isArray(mesh.material) ? null : colorOf(mesh.material);
    if (bi < 0 || !col) continue;
    const src = mesh.geometry;
    // tiny face parts (eyes, lashes, teeth, lips, brows): 1-2 px at place zoom
    if (boneName === 'head') {
      if (!src.boundingSphere) src.computeBoundingSphere();
      if ((src.boundingSphere?.radius ?? 1) < 0.06) continue;
    }
    const g = new BufferGeometry();
    g.setAttribute('position', src.getAttribute('position').clone());
    if (src.index) g.setIndex(src.index.clone());
    const flat = g.index ? g.toNonIndexed() : g;
    if (flat !== g) g.dispose();
    // bone-local -> root-local bind pose
    _m.multiplyMatrices(_inv, mesh.matrixWorld);
    flat.applyMatrix4(_m);
    const n = flat.getAttribute('position').count;
    const colors = new Float32Array(n * 3);
    const si = new Uint16Array(n * 4);
    const sw = new Float32Array(n * 4);
    for (let i = 0; i < n; i++) {
      colors[i * 3] = col.r;
      colors[i * 3 + 1] = col.g;
      colors[i * 3 + 2] = col.b;
      si[i * 4] = bi;
      sw[i * 4] = 1;
    }
    flat.setAttribute('color', new Float32BufferAttribute(colors, 3));
    flat.setAttribute('skinIndex', new Uint16BufferAttribute(si, 4));
    flat.setAttribute('skinWeight', new Float32BufferAttribute(sw, 4));
    parts.push(flat);
  }
  // drop the full-detail meshes; keep the bones
  for (const mesh of meshes) {
    mesh.removeFromParent();
    mesh.geometry.dispose();
  }
  const geo = mergeGeometries(parts) ?? new BufferGeometry();
  for (const p of parts) p.dispose();
  geo.computeVertexNormals();
  const bones = BONES.map((b) => ch.rig[b] as unknown as Bone);
  const skeleton = new Skeleton(bones);
  const mesh = new SkinnedMesh(geo, crowdRigMaterial());
  mesh.frustumCulled = false;
  root.add(mesh);
  root.updateMatrixWorld(true);
  // bind in root space: rest pose = bind pose
  skeleton.calculateInverses();
  mesh.bind(skeleton, mesh.matrixWorld);
  const tris = (geo.getAttribute('position')?.count ?? 0) / 3;
  return {
    ch,
    mesh,
    tris,
    dispose() {
      geo.dispose();
      skeleton.dispose();
      mesh.removeFromParent();
      ch.dispose();
    },
  };
}
