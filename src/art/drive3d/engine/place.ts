// The destination as it looks on the normal 3D city map (docs/DRIVE.md).
// Landmarks (museum, palace, Oba Market sheds, UNIBEN gate, UBTH, Bronze Tech Hub, police HQ, stadium, shrine, motor park shelters,
// the Ikpoba bridge, farm huts) are drawn by the very same builder the city uses (`buildLandmarks` in city3d/engine/build.ts,
// asked for just the pieces this place needs). Every other place is the same building the city map stands there: the nearest
// building of the city layout (same size, walls, roof shape and colours), with its district's neighbours and trees.
// World scale: one city world unit is 10 m here (a city shop-house of 9 map units is 9 m wide). Facing: the model's front is +z.
import {
  BoxGeometry,
  BufferGeometry,
  ConeGeometry,
  CylinderGeometry,
  Float32BufferAttribute,
  Group,
  Mesh,
  MeshBasicMaterial,
  MeshStandardMaterial,
} from 'three';
import { HomeBuilder } from '../../home3d/engine/build';
import { BRIDGE, GROVE, STADIUM, TECH_HUB, MARKETS } from '../../map/mapGeo';
import { buildLandmarks } from '../../city3d/engine/build';
import { getCityLayout, type Building } from '../../city3d/engine/layout';
import { toWorld } from '../../city3d/model';
import { ColorBatch } from './batch';

const M = 10;

interface LandmarkDef {
  keys: string[];
  /** Map-space centre of the piece (it is moved to the origin). */
  cx: number;
  cy: number;
}

const marketOf = (id: string): LandmarkDef | null => {
  const m = MARKETS.find((q) => q[3] === id);
  return m ? { keys: ['market:' + id], cx: m[0], cy: m[1] } : null;
};

/** Place id -> the landmark pieces the city draws for it. */
function landmarkFor(id: string): LandmarkDef | null {
  switch (id) {
    case 'national_museum':
      return { keys: ['museum'], cx: 500, cy: 500 };
    case 'emotan_statue':
      return null;
    case 'oba_palace':
      return { keys: ['palace'], cx: 410, cy: 503 };
    case 'uniben':
      return { keys: ['uniben'], cx: 488, cy: 123 };
    case 'ubth':
      return { keys: ['ubth'], cx: 421, cy: 170 };
    case 'bronze_tech_hub':
      return { keys: ['hub'], cx: TECH_HUB.x, cy: TECH_HUB.y };
    case 'police_hq':
      return { keys: ['police'], cx: 497, cy: 610 };
    case 'ogbemudia_stadium':
      return { keys: ['stadium'], cx: STADIUM.x, cy: STADIUM.y };
    case 'babas_shrine':
      return { keys: ['shrine'], cx: GROVE.x + 3, cy: GROVE.y + 2 };
    case 'iguobazuwa_farm':
      return { keys: ['farm'], cx: 70, cy: 330 };
    case 'ikpoba_riverbank':
      return { keys: ['bridge'], cx: BRIDGE.x, cy: BRIDGE.y };
    case 'uselu_park':
      return { keys: ['park:0'], cx: 452, cy: 288 };
    case 'oluku_park':
      return { keys: ['park:1'], cx: 398, cy: 58 };
    case 'ramat_park':
      return { keys: ['ramat', 'park:2'], cx: 696, cy: 406 };
    case 'aduwawa_park':
      return { keys: ['park:3'], cx: 828, cy: 358 };
    default:
      return marketOf(id);
  }
}

export interface PlaceInfo {
  id: string;
  name: string;
  scene: string;
  x: number;
  y: number;
}

export interface PlaceModel {
  group: Group;
  /** Footprint (m) along x (across the frontage) and z (depth), centred on the origin. */
  width: number;
  depth: number;
  /** Highest point (m) and the height of the entrance sign. */
  top: number;
  landmark: boolean;
  setDark(dark: number): void;
  dispose(): void;
}

const PAD: Record<string, string> = {
  market: '#c7ab7e',
  campus: '#a9c27c',
  hospital: '#d9d6cc',
  palace: '#b98a5e',
  museum: '#d9d0b8',
  police: '#cfcabd',
  bank: '#d4cfc2',
  office: '#d4cfc2',
  mall: '#cfcabd',
  hotel: '#cfcabd',
  motorpark: '#a9a08b',
  farm: '#a9c27c',
  shrine: '#a88f64',
  zoo: '#9cbf76',
};

const ACCENT: Record<string, string> = {
  buka: '#c0643f',
  salon: '#5c7fb5',
  cyber: '#3f7f9c',
  pos: '#2e9d58',
  club: '#6a5a8a',
  lounge: '#6a5a8a',
  cinema: '#a23c36',
  bank: '#2f5f8f',
  mall: '#c9763a',
  hotel: '#8a6a4a',
  hospital: '#3f8a6a',
  car_dealer: '#4a5d7a',
  workshop: '#7a5a3a',
  office: '#5a6b82',
  street: '#b98a4a',
  home_face_me: '#b5553a',
  home_flat: '#4f7ca8',
  home_duplex: '#5a8068',
  market: '#c9763a',
  zoo: '#4f8f5e',
  monument: '#a5552e',
  motorpark: '#d6b02c',
};

/** Build the destination model. `null` only if the city layout has nothing near (never in practice). */
export function buildPlaceModel(loc: PlaceInfo): PlaceModel {
  const group = new Group();
  const owned: { dispose(): void }[] = [];
  const own = <T extends { dispose(): void }>(o: T) => {
    owned.push(o);
    return o;
  };
  const solid = own(new MeshStandardMaterial({ vertexColors: true, flatShading: true, roughness: 0.86, metalness: 0.015 }));
  const glowMat = own(new MeshBasicMaterial({ vertexColors: true, color: '#9db4c4' }));
  const lm = landmarkFor(loc.id);
  let width = 14;
  let depth = 12;
  let top = 6;
  let landmark = false;

  const pad = new ColorBatch();
  const batch = new ColorBatch();

  if (lm) {
    landmark = true;
    const b = new HomeBuilder();
    buildLandmarks(b, lm.keys);
    const parts = b.finish();
    const [wx, wz] = toWorld(lm.cx, lm.cy);
    const place = (g: BufferGeometry) => {
      g.translate(-wx, 0, -wz);
      g.scale(M, M, M);
      g.computeBoundingBox();
      return g;
    };
    let box: { minx: number; maxx: number; minz: number; maxz: number; maxy: number } | null = null;
    for (const [layer, mat] of [['solid', solid], ['glow', glowMat]] as const) {
      const g = parts[layer];
      if (!g) continue;
      place(g);
      const bb = g.boundingBox!;
      box = box
        ? { minx: Math.min(box.minx, bb.min.x), maxx: Math.max(box.maxx, bb.max.x), minz: Math.min(box.minz, bb.min.z), maxz: Math.max(box.maxz, bb.max.z), maxy: Math.max(box.maxy, bb.max.y) }
        : { minx: bb.min.x, maxx: bb.max.x, minz: bb.min.z, maxz: bb.max.z, maxy: bb.max.y };
      group.add(new Mesh(own(g), mat));
    }
    parts.glass?.dispose();
    parts.screen?.dispose();
    parts.light?.dispose();
    if (box) {
      width = Math.min(70, box.maxx - box.minx);
      depth = Math.min(60, box.maxz - box.minz);
      top = box.maxy;
      // centre the footprint on the origin
      const ox = (box.minx + box.maxx) / 2;
      const oz = (box.minz + box.maxz) / 2;
      group.children.forEach((c) => c.position.set(-ox, 0, -oz));
    }
  } else {
    // the very building the city map stands there
    const L = getCityLayout();
    const near = (x: number, y: number, n: number, skip: Building[] = []) =>
      [...L.buildings]
        .filter((q) => !skip.includes(q))
        .map((q) => ({ q, d: Math.hypot(q.x - x, q.y - y) }))
        .sort((a, c) => a.d - c.d)
        .slice(0, n)
        .map((o) => o.q);
    const [main] = near(loc.x, loc.y, 1);
    const big = ['mall', 'hotel', 'bank', 'hospital', 'cinema', 'office', 'car_dealer', 'hotel', 'lounge'].includes(loc.scene);
    const small = ['buka', 'salon', 'cyber', 'pos', 'street', 'workshop'].includes(loc.scene);
    const isHome = loc.scene.startsWith('home_');
    const spec = main ?? ({ w: 9, d: 7, h: 0.4, wall: '#ead7b6', roof: '#b5583a', roofType: 'hip', a: 0, x: 0, y: 0, lit: false, st: 'res' } as Building);
    let w = Math.min(14, Math.max(7, spec.w));
    let d = Math.min(12, Math.max(6, spec.d));
    let h = Math.max(3.4, spec.h * M);
    if (big) {
      w = Math.min(20, w * 1.55);
      d = Math.min(14, d * 1.4);
      h = Math.max(h * 1.2, 7.5);
    } else if (small) {
      w = Math.min(w, 9);
      h = Math.min(h, 4.2);
    } else if (isHome) {
      w = Math.max(w, 11);
      h = Math.max(h, loc.scene === 'home_flat' ? 8 : 5.2);
    }
    let roofType = spec.roofType;
    if (big && roofType !== 'flat' && h > 7) roofType = 'flat';
    const building = (bw: number, bd: number, bh: number, rt: Building['roofType'], wall: string, roof: string, x: number, z: number) => {
      batch.add(new BoxGeometry(bw, bh, bd), wall, x, bh / 2, z);
      if (rt === 'flat') {
        batch.add(new BoxGeometry(bw * 1.03, 0.45, bd * 1.03), roof, x, bh + 0.22, z);
        batch.add(new BoxGeometry(bw * 0.9, 0.18, 0.18), '#d9d4c8', x, bh + 0.54, z + bd * 0.46);
      } else if (rt === 'hip') {
        const rh = Math.min(3.2, 1.2 + Math.min(bw, bd) * 0.28);
        const cone = new ConeGeometry(Math.SQRT1_2, 1, 4, 1);
        cone.rotateY(Math.PI / 4);
        cone.translate(0, 0.5, 0);
        cone.scale(bw * 1.08, rh, bd * 1.1);
        batch.add(cone, roof, x, bh, z);
      } else {
        const rh = Math.min(3, 1 + bd * 0.3);
        batch.add(gable(bw * 1.08, rh, bd * 1.1), roof, x, bh, z);
      }
    };
    building(w, d, h, roofType, spec.wall, spec.roof, 0, 0);
    // shop front: dark door and windows band on the road side (+z), an awning in the place's own colour
    const acc = ACCENT[loc.scene] ?? '#b98a4a';
    batch.add(new BoxGeometry(w * 0.82, 0.2, 1.5), acc, 0, 2.9, d / 2 + 0.75);
    batch.add(new BoxGeometry(1.5, 2.3, 0.1), '#3b4048', -w * 0.22, 1.15, d / 2 + 0.03);
    for (const k of [0.18, 0.34]) batch.add(new BoxGeometry(w * 0.12, 1.2, 0.1), '#7fa3bc', w * k, 1.5, d / 2 + 0.03);
    if (h > 5) for (let i = 0; i < Math.floor(w / 3.2); i++) batch.add(new BoxGeometry(1.2, 1.1, 0.1), '#8fb0c4', -w / 2 + 1.8 + i * 3.2, h - 1.6, d / 2 + 0.03);
    // neighbours, as the city map has them
    const nb = near(loc.x, loc.y, 4, [main]).filter((q) => Math.hypot(q.x - loc.x, q.y - loc.y) < 60).slice(0, 2);
    nb.forEach((q, i) => {
      const side = i === 0 ? -1 : 1;
      const nw = Math.min(12, Math.max(6, q.w));
      const nd = Math.min(11, Math.max(5.5, q.d));
      const nh = Math.max(3.2, Math.min(9, q.h * M));
      building(nw, nd, nh, q.roofType, q.wall, q.roof, side * (w / 2 + nw / 2 + 2.2), (nd - d) / 2);
    });
    // trees the layout has around here (palms and canopies)
    const trees = [...L.trees]
      .map((t) => ({ t, dd: Math.hypot(t.x - loc.x, t.y - loc.y) }))
      .sort((a, c) => a.dd - c.dd)
      .slice(0, 3);
    trees.forEach(({ t }, i) => {
      const tx = (i - 1) * (w * 0.7 + 3) + (i === 1 ? 0 : (i - 1) * 3);
      const tz = d / 2 + 5.2 + (i % 2) * 1.5;
      if (t.palm) {
        batch.add(new CylinderGeometry(0.2, 0.3, 6, 6), '#8a6c4a', tx, 3, tz);
        batch.add(new ConeGeometry(2.2, 0.8, 7), '#4d7f45', tx, 6.2, tz);
      } else {
        batch.add(new CylinderGeometry(0.22, 0.3, 2.6, 6), '#6b523c', tx, 1.3, tz);
        batch.add(new ConeGeometry(Math.max(1.8, t.r * 0.5), 2.6, 7), '#5f8a4e', tx, 3.6, tz);
      }
    });
    width = w + (nb.length ? 26 : 4);
    depth = d + 6;
    top = h + 3;
  }

  // forecourt dressing (the city map shows market stalls round the market sheds and trees round the rest)
  {
    const frontZ = depth / 2 + 3.2;
    const STALLS = ['#2f6fd0', '#d63c32', '#f2b632', '#2e9d58', '#e06a1c', '#7a4ac8', '#e9e6dc'];
    if (loc.scene === 'market') {
      const n = Math.max(4, Math.min(9, Math.round(width / 5)));
      for (let i = 0; i < n; i++) {
        const x = -width / 2 + (width * (i + 0.5)) / n;
        const z = frontZ + (i % 2) * 0.6;
        batch.add(new BoxGeometry(2.2, 0.9, 1.6), i % 2 ? '#9c7a4f' : '#b08c5d', x, 0.45, z);
        batch.add(new BoxGeometry(2.8, 0.12, 2.4), STALLS[(i * 3 + 1) % STALLS.length], x, 2.2, z);
        for (const dx of [-1.2, 1.2]) batch.add(new CylinderGeometry(0.04, 0.04, 2.2, 5), '#555', x + dx, 1.1, z + 0.9);
        batch.add(new BoxGeometry(0.7, 0.3, 0.7), STALLS[(i * 5 + 2) % STALLS.length], x + 0.4, 1.05, z);
      }
    } else if (landmark) {
      for (const sx of [-1, 1]) {
        const tx = sx * (width / 2 + 3);
        batch.add(new CylinderGeometry(0.22, 0.3, 6, 6), '#8a6c4a', tx, 3, depth / 2 + 3);
        batch.add(new ConeGeometry(2.2, 0.8, 7), '#4d7f45', tx, 6.2, depth / 2 + 3);
      }
    }
  }
  // a flat pad under the place (the compound / forecourt), a little larger than its footprint
  pad.add(new BoxGeometry(width + 10, 0.12, depth + 12), PAD[loc.scene] ?? '#cbbd9d', 0, 0.06, 2);
  const padB = pad.build(own(new MeshStandardMaterial({ vertexColors: true, flatShading: true, roughness: 0.95, metalness: 0 })));
  if (padB) {
    group.add(padB.mesh);
    own(padB.geometry);
  }
  const bB = batch.build(solid);
  if (bB) {
    group.add(bB.mesh);
    own(bB.geometry);
  }

  return {
    group,
    width,
    depth,
    top,
    landmark,
    setDark(dark) {
      glowMat.color.set(dark > 0.45 ? '#ffd27a' : '#9db4c4');
    },
    dispose() {
      owned.forEach((o) => o.dispose());
    },
  };
}

/** Gable roof: ridge along x at y = height, eaves at z = +-d/2 (flat normals). */
function gable(w: number, h: number, d: number): BufferGeometry {
  const hw = w / 2;
  const hd = d / 2;
  const p = [
    -hw, 0, hd, hw, 0, hd, hw, h, 0, -hw, 0, hd, hw, h, 0, -hw, h, 0,
    hw, 0, -hd, -hw, 0, -hd, -hw, h, 0, hw, 0, -hd, -hw, h, 0, hw, h, 0,
    hw, 0, hd, hw, 0, -hd, hw, h, 0, -hw, 0, -hd, -hw, 0, hd, -hw, h, 0,
  ];
  const g = new BufferGeometry();
  g.setAttribute('position', new Float32BufferAttribute(p, 3));
  g.computeVertexNormals();
  return g;
}

