// The drive's route (no three.js): the real road route between two places turned into a drivable track.
//
// 1. The route comes from the same road graph the city map uses (src/art/city3d/route.ts: mapGeo ROADS + the Ring Road, Dijkstra).
// 2. It is simplified to a few straight stretches. Every real bend of 22 degrees or more becomes a junction the car turns at
//    (left or right, as on the map); a run along the Ring Road becomes a roundabout the car goes round (counter-clockwise, drive on the right).
// 3. Stretches get scene lengths in proportion to the map, the whole track in proportion to the trip's real seconds.
// 4. A speed profile (slow into corners, stops at bus stops, slow-downs behind traffic) is turned into a time table that is
//    stretched to the server's trip time, so the car's place on the track is a function of the server clock only.
// docs/DRIVE.md.
import type { Pt } from '../map/mapGeo';
import { ROUTE_LINES, roadRouteNodes } from '../city3d/route';
import { ROAD_NAME, type RoadSeg } from './model';

const STEP = 1;
/** The player's lane sits this far to the right of the street's centre line. */
export const LANE_OFFSET = 5.6;
const MIN_SEG = 78;
const DEG = Math.PI / 180;

export interface Straight {
  /** Path distance (m) where the straight starts / ends. */
  sa: number;
  sb: number;
  /** World position of the street axis at `sa` and the heading (0 = north, a right turn adds). */
  ox: number;
  oz: number;
  psi: number;
  /** Road name. */
  name: string;
  /** Where buildings may stand (u = metres along the axis from the origin) and where asphalt may run (stubs of the cross street). */
  u0b: number;
  u1b: number;
  u0a: number;
  u1a: number;
}

export interface Junction {
  kind: 'turn' | 'round';
  /** Path distance where the turn starts / ends. */
  sa: number;
  sb: number;
  /** +1 = right, -1 = left (the net turn). */
  dir: 1 | -1;
  /** Net turn in radians, right positive. */
  theta: number;
  /** Where the two street axes cross (turn) or the roundabout centre. */
  x: number;
  z: number;
  /** Roundabout island and outer asphalt radii (round only). */
  island: number;
  outer: number;
  /** The road you turn onto. */
  into: string;
  /** Stretch indices before and after. */
  from: number;
  to: number;
}

export interface BusStop {
  s: number;
  dwell: number;
  name: string;
}

export interface Track {
  /** Track length in metres. */
  L: number;
  /** Real trip seconds the profile is stretched to. */
  total: number;
  xs: Float32Array;
  zs: Float32Array;
  psis: Float32Array;
  /** Signed curvature (right positive) per metre. */
  kap: Float32Array;
  straights: Straight[];
  junctions: Junction[];
  stops: BusStop[];
  /** Traffic slow-downs [sa, sb] (a slow vehicle ahead). */
  slows: { sa: number; sb: number }[];
  roads: RoadSeg[];
  /** Route in map space (dense, for the mini-map) and the start / end places. */
  mapPts: Pt[];
  /** Pose of the lane path at distance s (clamped): x, z, heading. */
  pose(s: number): { x: number; z: number; psi: number };
  /** World position at distance s and lateral offset `lat` (axis frame: right positive, the player's lane is +LANE_OFFSET). */
  at(s: number, lat: number): { x: number; z: number; psi: number };
  /** Map-space position for path distance s. */
  mapAt(s: number): [number, number];
  /** Where the car is (path distance) `t` real seconds into the trip, and the reference speed (m/s, real time) there. */
  sOfT(t: number): number;
  /** Seconds into the trip the car reaches distance s (the table). */
  tOfS(s: number): number;
  vRef(s: number): number;
  /** Speed cap (m/s, real time) at distance s from corners, stops and slow-downs; the car never goes faster than this. */
  vLim(s: number): number;
  /** Straight from s to s + len (no turns, stops or junction zones)? */
  straightAhead(s: number, len: number): boolean;
  /** The next junction ahead of s, if any. */
  nextJunction(s: number): Junction | null;
  /** The straight containing s (or the nearest). */
  straightAt(s: number): number;
}

const wrapPi = (a: number) => {
  while (a > Math.PI) a -= Math.PI * 2;
  while (a <= -Math.PI) a += Math.PI * 2;
  return a;
};

function rngOf(seed: string) {
  let h = 2166136261;
  for (let i = 0; i < seed.length; i++) h = Math.imul(h ^ seed.charCodeAt(i), 16777619);
  let a = h >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

interface Nd {
  x: number;
  y: number;
  line: number;
  kind: 'n' | 'in' | 'out';
  /** Ring nodes between entry and exit (for the map mapping). */
  ring?: Pt[];
}

function dp(pts: Nd[], tol: number): Nd[] {
  if (pts.length < 3) return pts;
  const keep = new Uint8Array(pts.length);
  keep[0] = keep[pts.length - 1] = 1;
  const stack: [number, number][] = [[0, pts.length - 1]];
  while (stack.length) {
    const [a, b] = stack.pop()!;
    let best = -1;
    let bd = 0;
    const ax = pts[a].x;
    const ay = pts[a].y;
    const dx = pts[b].x - ax;
    const dy = pts[b].y - ay;
    const l2 = dx * dx + dy * dy || 1;
    for (let i = a + 1; i < b; i++) {
      const t = Math.max(0, Math.min(1, ((pts[i].x - ax) * dx + (pts[i].y - ay) * dy) / l2));
      const d = Math.hypot(pts[i].x - (ax + dx * t), pts[i].y - (ay + dy * t));
      if (d > bd) {
        bd = d;
        best = i;
      }
    }
    if (best >= 0 && bd > tol) {
      keep[best] = 1;
      stack.push([a, best], [best, b]);
    }
  }
  return pts.filter((_, i) => keep[i]);
}

interface Seg {
  x0: number;
  y0: number;
  x1: number;
  y1: number;
  mapLen: number;
  /** Map length per road line (to name the stretch). */
  byLine: Map<number, number>;
}

interface Joint {
  kind: 'turn' | 'round';
  theta: number;
  ringPts?: Pt[];
  ringLen?: number;
}

const heading = (s: { x0: number; y0: number; x1: number; y1: number }) => Math.atan2(s.x1 - s.x0, -(s.y1 - s.y0));

function nameOfLine(line: number | undefined): string {
  if (line === undefined || line < 0) return 'Ring Road';
  return ROAD_NAME[ROUTE_LINES[line]] ?? 'Ring Road';
}

function dominant(seg: Seg): number {
  let best = -1;
  let bl = -1;
  for (const [l, v] of seg.byLine) {
    if (l >= 0 && v > bl) {
      bl = v;
      best = l;
    }
  }
  return best;
}

/** Average cruise speed (m/s of scene) a mode drives at when it is not stopping. */
const MODE_SPEED: Record<string, number> = { car: 14, drop: 14, keke: 11, bus: 12, moto: 15, bike: 7, walk: 6 };

export interface TrackInput {
  from: { x: number; y: number };
  to: { x: number; y: number };
  mode: string;
  /** Real trip seconds (the server's arrival minus start). */
  totalSec: number;
  vehicleId?: string | null;
  fromName?: string;
  toName?: string;
}

export function buildTrack(inp: TrackInput): Track {
  const total = Math.max(8, inp.totalSec);
  const { pts, line } = roadRouteNodes(inp.from, inp.to);

  // ---- 1. nodes: drop short place-to-road legs, collapse ring runs into roundabout entry/exit pairs
  let a = 0;
  let b = pts.length - 1;
  if (pts.length > 3 && Math.hypot(pts[1][0] - pts[0][0], pts[1][1] - pts[0][1]) < 55) a = 1;
  if (pts.length > 3 && Math.hypot(pts[b][0] - pts[b - 1][0], pts[b][1] - pts[b - 1][1]) < 55) b -= 1;
  const raw: Nd[] = [];
  for (let i = a; i <= b; i++) raw.push({ x: pts[i][0], y: pts[i][1], line: line[i], kind: 'n' });
  // ring runs of 3+ nodes that have a road before and after become roundabouts
  const nodes: Nd[] = [];
  for (let i = 0; i < raw.length; ) {
    if (raw[i].line === 0) {
      let j = i;
      while (j + 1 < raw.length && raw[j + 1].line === 0) j++;
      const hasBefore = nodes.length > 0 && i > 0;
      const hasAfter = j < raw.length - 1;
      if (j - i >= 2 && hasBefore && hasAfter) {
        const ring: Pt[] = raw.slice(i, j + 1).map((n) => [n.x, n.y] as Pt);
        nodes.push({ ...raw[i], kind: 'in', ring });
        nodes.push({ ...raw[j], kind: 'out' });
        i = j + 1;
        continue;
      }
    }
    nodes.push(raw[i]);
    i++;
  }
  // simplify the stretches between roundabout pairs (the 'in' node ends one stretch, the 'out' node starts the next)
  const verts: Nd[] = [];
  {
    let cur: Nd[] = [];
    for (const n of nodes) {
      if (n.kind === 'out') {
        verts.push(...dp(cur, 5));
        cur = [n];
        continue;
      }
      cur.push(n);
      if (n.kind === 'in') {
        verts.push(...dp(cur, 5));
        cur = [];
      }
    }
    if (cur.length) verts.push(...dp(cur, 5));
  }

  // ---- 2. segments and joints
  const segs: Seg[] = [];
  const joints: Joint[] = [];
  const segOf = (n0: Nd, n1: Nd): Seg => {
    const len = Math.hypot(n1.x - n0.x, n1.y - n0.y);
    const byLine = new Map<number, number>();
    byLine.set(n1.line, len);
    return { x0: n0.x, y0: n0.y, x1: n1.x, y1: n1.y, mapLen: len, byLine };
  };
  for (let i = 0; i + 1 < verts.length; i++) {
    const n0 = verts[i];
    const n1 = verts[i + 1];
    if (n0.kind === 'in' && n1.kind === 'out') continue; // the roundabout jump
    // the line a stretch sits on: look back through the raw nodes between the two vertices
    const sg = segOf(n0, n1);
    const i0 = raw.findIndex((r) => r.x === n0.x && r.y === n0.y);
    const i1 = raw.findIndex((r) => r.x === n1.x && r.y === n1.y);
    if (i0 >= 0 && i1 > i0) {
      sg.byLine = new Map();
      for (let k = i0; k < i1; k++) {
        const l = raw[k + 1].line;
        sg.byLine.set(l, (sg.byLine.get(l) ?? 0) + Math.hypot(raw[k + 1].x - raw[k].x, raw[k + 1].y - raw[k].y));
      }
    }
    segs.push(sg);
  }
  // joints between consecutive segments
  {
    let k = 0;
    for (let i = 1; i + 1 < verts.length; i++) {
      const v = verts[i];
      if (v.kind === 'in') {
        // joint = roundabout; the next segment starts at the 'out' vertex
        const ring = v.ring ?? [];
        let rl = 0;
        for (let q = 1; q < ring.length; q++) rl += Math.hypot(ring[q][0] - ring[q - 1][0], ring[q][1] - ring[q - 1][1]);
        joints.push({ kind: 'round', theta: 0, ringPts: ring, ringLen: rl });
        k++;
      } else if (v.kind === 'out') {
        continue;
      } else {
        joints.push({ kind: 'turn', theta: 0 });
        k++;
      }
    }
  }
  if (joints.length !== Math.max(0, segs.length - 1)) {
    // degenerate (e.g. the roundabout at the very start or end): fall back to the plain polyline
    segs.length = 0;
    joints.length = 0;
    const flat = dp(raw, 6);
    for (let i = 0; i + 1 < flat.length; i++) segs.push(segOf(flat[i], flat[i + 1]));
    for (let i = 0; i + 1 < segs.length; i++) joints.push({ kind: 'turn', theta: 0 });
  }
  if (!segs.length) {
    // two places on top of each other: a short run along the nearest road
    segs.push({ x0: inp.from.x, y0: inp.from.y, x1: inp.from.x, y1: inp.from.y - 40, mapLen: 40, byLine: new Map([[line[a] ?? 0, 40]]) });
  }
  const angleOf = (j: number) => wrapPi(heading(segs[j + 1]) - heading(segs[j]));
  const recomputeAngles = () => joints.forEach((jt, j) => (jt.theta = angleOf(j)));
  recomputeAngles();

  const mergeAt = (j: number) => {
    const s0 = segs[j];
    const s1 = segs[j + 1];
    const byLine = new Map(s0.byLine);
    for (const [l, v] of s1.byLine) byLine.set(l, (byLine.get(l) ?? 0) + v);
    segs.splice(j, 2, { x0: s0.x0, y0: s0.y0, x1: s1.x1, y1: s1.y1, mapLen: s0.mapLen + s1.mapLen, byLine });
    joints.splice(j, 1);
    recomputeAngles();
  };

  // ---- 3. how long is the track
  const speedMode = inp.mode === 'car' && (inp.vehicleId === 'bicycle') ? 'bike' : inp.mode === 'car' && inp.vehicleId === 'bajaj_boxer' ? 'moto' : inp.mode;
  const va = MODE_SPEED[speedMode] ?? 13;
  const nStopsWanted = inp.mode === 'bus' ? (total < 32 ? 0 : total < 60 ? 1 : 2) : 0;
  const dwellEach = 5.5;
  const budget = Math.max(230, (total - nStopsWanted * dwellEach) * va);

  // merge tiny bends first
  for (;;) {
    const j = joints.findIndex((jt) => jt.kind === 'turn' && Math.abs(jt.theta) < 22 * DEG);
    if (j < 0) break;
    mergeAt(j);
  }
  const roundCost = () => joints.filter((j) => j.kind === 'round').length * 105;
  const dOf = () => {
    const mapTotal = segs.reduce((s, g) => s + g.mapLen, 0) || 1;
    const room = Math.max(120, budget - roundCost());
    return segs.map((g) => (room * g.mapLen) / mapTotal);
  };
  for (let guard = 0; guard < 40; guard++) {
    const d = dOf();
    let bad = -1;
    let bv = MIN_SEG;
    d.forEach((v, i) => {
      if (v < bv) {
        bv = v;
        bad = i;
      }
    });
    const maxJ = Math.max(1, Math.floor(budget / 95));
    if (bad < 0 && joints.length <= maxJ) break;
    // remove the gentlest plain turn next to the short stretch (or the gentlest overall when there are too many)
    let cand = -1;
    let ca = Infinity;
    const consider = (j: number) => {
      if (j < 0 || j >= joints.length || joints[j].kind !== 'turn') return;
      const v = Math.abs(joints[j].theta);
      if (v < ca) {
        ca = v;
        cand = j;
      }
    };
    if (bad >= 0) {
      consider(bad - 1);
      consider(bad);
    } else {
      joints.forEach((_, j) => consider(j));
    }
    if (cand < 0) break;
    mergeAt(cand);
  }
  const dBase = dOf().map((v) => Math.max(v, 40));

  // ---- 4. primitives: straights, fillets, roundabouts
  const R_E = 14;
  const R_C = 22;
  const ALPHA = 75 * DEG;
  interface Prim {
    len: number;
    kappa: number;
    tag?: string;
  }
  const prims: Prim[] = [];
  const tIn: number[] = new Array(segs.length).fill(0);
  const tOut: number[] = new Array(segs.length).fill(0);
  const rads: number[] = [];
  joints.forEach((jt, j) => {
    if (jt.kind === 'round') {
      tOut[j] = 20;
      tIn[j + 1] = 20;
      rads.push(0);
      return;
    }
    const th = Math.abs(jt.theta);
    let r = th > 60 * DEG ? 12 : 22;
    let t = r * Math.tan(th / 2);
    const cap = 0.42 * Math.min(dBase[j], dBase[j + 1]);
    if (t > cap) t = cap;
    r = t / Math.tan(th / 2);
    tOut[j] = t;
    tIn[j + 1] = t;
    rads.push(r);
  });
  const straightLens: number[] = segs.map((_, i) => Math.max(20, dBase[i] - tIn[i] - tOut[i]));
  const primOfSeg: number[] = [];
  const primOfJoint: number[] = [];
  const roundPhi: number[] = [];
  segs.forEach((_, i) => {
    primOfSeg.push(prims.length);
    prims.push({ len: straightLens[i], kappa: 0, tag: 's' + i });
    if (i < joints.length) {
      const jt = joints[i];
      primOfJoint.push(prims.length);
      if (jt.kind === 'turn') {
        prims.push({ len: rads[i] * Math.abs(jt.theta), kappa: Math.sign(jt.theta) / rads[i], tag: 'j' + i });
      } else {
        let phi = (150 * DEG - jt.theta) % (Math.PI * 2);
        if (phi < 0) phi += Math.PI * 2;
        if (phi < 40 * DEG) phi += Math.PI * 2;
        roundPhi[i] = phi;
        prims.push({ len: R_E * ALPHA, kappa: 1 / R_E, tag: 'ra' + i });
        prims.push({ len: R_C * phi, kappa: -1 / R_C, tag: 'rc' + i });
        prims.push({ len: R_E * ALPHA, kappa: 1 / R_E, tag: 'rb' + i });
      }
    }
  });

  // ---- integrate to 1 m samples
  const psi0 = heading(segs[0]);
  const xs: number[] = [0];
  const zs: number[] = [0];
  const ps: number[] = [psi0];
  const ks: number[] = [0];
  let x = 0;
  let z = 0;
  let psi = psi0;
  let carry = 0;
  const primS: number[] = [];
  let sAcc = 0;
  for (const p of prims) {
    primS.push(sAcc);
    let left = p.len;
    while (left > 1e-6) {
      const ds = Math.min(left, STEP - carry);
      if (Math.abs(p.kappa) < 1e-9) {
        x += Math.sin(psi) * ds;
        z -= Math.cos(psi) * ds;
      } else {
        const p1 = psi + p.kappa * ds;
        x += (Math.cos(psi) - Math.cos(p1)) / p.kappa;
        z += (Math.sin(psi) - Math.sin(p1)) / p.kappa;
        psi = p1;
      }
      carry += ds;
      left -= ds;
      sAcc += ds;
      if (carry >= STEP - 1e-6) {
        xs.push(x);
        zs.push(z);
        ps.push(psi);
        ks.push(p.kappa);
        carry = 0;
      }
    }
  }
  primS.push(sAcc);
  if (carry > 1e-3) {
    xs.push(x);
    zs.push(z);
    ps.push(psi);
    ks.push(0);
  }
  const N = xs.length - 1;
  const L = N * STEP;
  const px = Float32Array.from(xs);
  const pz = Float32Array.from(zs);
  const pp = Float32Array.from(ps);
  const pk = Float32Array.from(ks);

  const poseAt = (s: number) => {
    const f = Math.max(0, Math.min(N, s / STEP));
    const i = Math.min(N - 1, Math.floor(f));
    const t = f - i;
    return { x: px[i] + (px[i + 1] - px[i]) * t, z: pz[i] + (pz[i + 1] - pz[i]) * t, psi: pp[i] + (pp[i + 1] - pp[i]) * t };
  };
  const atFn = (s: number, lat: number) => {
    if (s < 0) {
      const p0 = poseAt(0);
      const d = s;
      const f = [Math.sin(p0.psi), -Math.cos(p0.psi)];
      const r = [Math.cos(p0.psi), Math.sin(p0.psi)];
      const l = lat - LANE_OFFSET;
      return { x: p0.x + f[0] * d + r[0] * l, z: p0.z + f[1] * d + r[1] * l, psi: p0.psi };
    }
    if (s > L) {
      const p1 = poseAt(L);
      const d = s - L;
      const f = [Math.sin(p1.psi), -Math.cos(p1.psi)];
      const r = [Math.cos(p1.psi), Math.sin(p1.psi)];
      const l = lat - LANE_OFFSET;
      return { x: p1.x + f[0] * d + r[0] * l, z: p1.z + f[1] * d + r[1] * l, psi: p1.psi };
    }
    const p = poseAt(s);
    const l = lat - LANE_OFFSET;
    return { x: p.x + Math.cos(p.psi) * l, z: p.z + Math.sin(p.psi) * l, psi: p.psi };
  };

  // ---- 5. straights and junction zones
  const straights: Straight[] = [];
  const jOut: Junction[] = [];
  const axisAt = (s: number) => atFn(s, 0);
  const line2 = (ax: number, az: number, apsi: number, bx: number, bz: number, bpsi: number): [number, number] => {
    const d1x = Math.sin(apsi);
    const d1z = -Math.cos(apsi);
    const d2x = Math.sin(bpsi);
    const d2z = -Math.cos(bpsi);
    const den = d1x * d2z - d1z * d2x;
    if (Math.abs(den) < 1e-6) return [ax, az];
    const t = ((bx - ax) * d2z - (bz - az) * d2x) / den;
    return [ax + d1x * t, az + d1z * t];
  };
  segs.forEach((_, i) => {
    const sa = primS[primOfSeg[i]];
    const sb = primS[primOfSeg[i] + 1];
    const o = axisAt(sa);
    straights.push({ sa, sb, ox: o.x, oz: o.z, psi: poseAt(sa).psi, name: nameOfLine(dominant(segs[i])), u0b: -80, u1b: sb - sa + 70, u0a: -80, u1a: sb - sa + 70 });
  });
  joints.forEach((jt, j) => {
    const cs = primS[primOfJoint[j]];
    if (jt.kind === 'turn') {
      const ce = primS[primOfJoint[j] + 1];
      const o1 = axisAt(cs);
      const o2 = axisAt(ce);
      const [jx, jz] = line2(o1.x, o1.z, o1.psi, o2.x, o2.z, o2.psi);
      jOut.push({ kind: 'turn', sa: cs, sb: ce, dir: jt.theta >= 0 ? 1 : -1, theta: jt.theta, x: jx, z: jz, island: 0, outer: 11, into: straights[j + 1].name, from: j, to: j + 1 });
    } else {
      const ce = primS[primOfJoint[j] + 3];
      const pr = poseAt(primS[primOfJoint[j] + 1]);
      // circle centre: left of the heading at the start of the circulating arc
      const cx = pr.x - Math.cos(pr.psi) * R_C;
      const cz = pr.z - Math.sin(pr.psi) * R_C;
      jOut.push({ kind: 'round', sa: cs, sb: ce, dir: jt.theta >= 0 ? 1 : -1, theta: jt.theta, x: cx, z: cz, island: 14, outer: 30, into: straights[j + 1].name, from: j, to: j + 1 });
    }
  });
  const circleU = (s: Straight, jn: Junction, r: number, far: boolean) => {
    const fx = Math.sin(s.psi);
    const fz = -Math.cos(s.psi);
    const dx = jn.x - s.ox;
    const dz = jn.z - s.oz;
    const uc = dx * fx + dz * fz;
    const perp = Math.abs(dx * fz * -1 + dz * fx);
    const h = perp < r ? Math.sqrt(r * r - perp * perp) : 0;
    return far ? uc + h : uc - h;
  };
  jOut.forEach((jn) => {
    const sA = straights[jn.from];
    const sB = straights[jn.to];
    if (jn.kind === 'turn') {
      const uA = (jn.x - sA.ox) * Math.sin(sA.psi) + (jn.z - sA.oz) * -Math.cos(sA.psi);
      const uB = (jn.x - sB.ox) * Math.sin(sB.psi) + (jn.z - sB.oz) * -Math.cos(sB.psi);
      sA.u1b = uA - 14;
      sA.u1a = uA + 26;
      sB.u0b = uB + 14;
      sB.u0a = uB - 26;
    } else {
      sA.u1b = circleU(sA, jn, 40, false) - 1;
      sA.u1a = circleU(sA, jn, 30, false) + 2;
      sB.u0b = circleU(sB, jn, 40, true) + 1;
      sB.u0a = circleU(sB, jn, 30, true) - 2;
    }
  });
  const lastS = straights[straights.length - 1];
  lastS.u1b = lastS.sb - lastS.sa + 70;

  // ---- 6. bus stops and traffic slow-downs
  const rnd = rngOf(`${inp.from.x},${inp.from.y}>${inp.to.x},${inp.to.y}:${inp.mode}`);
  const snapStraight = (s: number, clear: number): number | null => {
    let best: number | null = null;
    let bd = Infinity;
    for (const st of straights) {
      const lo = st.sa + clear;
      const hi = st.sb - clear;
      if (hi <= lo) continue;
      const c = Math.max(lo, Math.min(hi, s));
      if (Math.abs(c - s) < bd) {
        bd = Math.abs(c - s);
        best = c;
      }
    }
    return best;
  };
  const stops: BusStop[] = [];
  const stopNames = ['Ring Road Stop', 'Market Stop', 'Junction Stop', 'Roundabout Stop'];
  if (nStopsWanted > 0) {
    const fr = nStopsWanted === 1 ? [0.5] : [0.34, 0.68];
    fr.forEach((f, k) => {
      const s = snapStraight(L * f, 38);
      if (s !== null && s > 60 && s < L - 90 && !stops.some((q) => Math.abs(q.s - s) < 80)) {
        const st = straights[straights.findIndex((q) => s >= q.sa && s <= q.sb)];
        stops.push({ s: Math.round(s), dwell: dwellEach, name: st ? st.name.replace(/ Road$| Rd$/, '') + ' Stop' : stopNames[k] });
      }
    });
  }
  const slows: { sa: number; sb: number }[] = [];
  {
    const n = Math.min(3, Math.floor(L / 420));
    for (let k = 0; k < n; k++) {
      const c = snapStraight(L * ((k + 0.5 + (rnd() - 0.5) * 0.4) / n), 55);
      if (c === null || c < 110 || c > L - 120) continue;
      if (stops.some((q) => Math.abs(q.s - c) < 140) || slows.some((q) => Math.abs(q.sa - c) < 160)) continue;
      slows.push({ sa: Math.round(c - 28), sb: Math.round(c + 28) });
    }
  }

  // ---- 7. speed profile (unscaled, m/s) -> time table scaled to the trip seconds
  const cruise = Math.min(22, va * 1.22);
  const vmax = new Float32Array(N + 1);
  for (let i = 0; i <= N; i++) {
    const kk = Math.abs(pk[i]);
    vmax[i] = kk > 1e-6 ? Math.min(cruise, Math.sqrt(3.1 / kk)) : cruise;
  }
  for (const sl of slows) for (let i = Math.max(0, sl.sa); i <= Math.min(N, sl.sb); i++) vmax[i] = Math.min(vmax[i], 5.2);
  vmax[0] = 0;
  vmax[N] = 0;
  const stopIdx = stops.map((q) => Math.min(N, Math.round(q.s / STEP)));
  stopIdx.forEach((i) => (vmax[i] = 0));
  const A_ACC = 2.3;
  const A_DEC = 3.4;
  const v = Float32Array.from(vmax);
  for (let i = 1; i <= N; i++) v[i] = Math.min(v[i], Math.sqrt(v[i - 1] * v[i - 1] + 2 * A_ACC * STEP));
  for (let i = N - 1; i >= 0; i--) v[i] = Math.min(v[i], Math.sqrt(v[i + 1] * v[i + 1] + 2 * A_DEC * STEP));
  const cumMove = new Float64Array(N + 1);
  for (let i = 0; i < N; i++) {
    const va_ = Math.max(v[i], 1.4);
    const vb_ = Math.max(v[i + 1], 1.4);
    cumMove[i + 1] = cumMove[i] + (2 * STEP) / (va_ + vb_);
  }
  // dwell is spent AT the stop: time(i) at the stop index is the arrival, time(i + 1) includes the wait
  const dwellBefore = new Float64Array(N + 1);
  {
    let run = 0;
    for (let i = 0; i <= N; i++) {
      dwellBefore[i] = run;
      const si = stopIdx.indexOf(i);
      if (si >= 0) run += stops[si].dwell;
    }
  }
  const dwellTotal = stops.reduce((s, q) => s + q.dwell, 0);
  const alpha = Math.max(0.3, (total - dwellTotal) / Math.max(1, cumMove[N]));
  const timeAt = (i: number) => alpha * cumMove[i] + dwellBefore[i];
  // time at a stop index after the dwell (the car leaves)
  const tOfS = (s: number) => {
    const f = Math.max(0, Math.min(N, s / STEP));
    const i = Math.min(N - 1, Math.floor(f));
    return timeAt(i) + (timeAt(i + 1) - timeAt(i)) * (f - i);
  };
  const sOfT = (t: number) => {
    if (t <= 0) return 0;
    const endT = timeAt(N);
    if (t >= endT) return L;
    let lo = 0;
    let hi = N;
    while (hi - lo > 1) {
      const mid = (lo + hi) >> 1;
      if (timeAt(mid) <= t) lo = mid;
      else hi = mid;
    }
    // inside a dwell: timeAt(lo+1) - timeAt(lo) includes the dwell; the car waits at lo for the dwell then moves
    const si = stopIdx.indexOf(lo);
    if (si >= 0) {
      const wait = stops[si].dwell;
      const t0 = timeAt(lo);
      const move = timeAt(lo + 1) - t0 - wait;
      if (t < t0 + wait) return lo * STEP;
      return lo * STEP + STEP * Math.min(1, (t - t0 - wait) / Math.max(1e-6, move));
    }
    const t0 = timeAt(lo);
    const t1 = timeAt(lo + 1);
    return (lo + (t - t0) / Math.max(1e-6, t1 - t0)) * STEP;
  };
  const vAt = (arr: Float32Array, s: number) => {
    const f = Math.max(0, Math.min(N, s / STEP));
    const i = Math.min(N - 1, Math.floor(f));
    return arr[i] + (arr[i + 1] - arr[i]) * (f - i);
  };
  const vRef = (s: number) => Math.max(0, vAt(v, s) / alpha);
  const vLim = (s: number) => Math.max(0, vAt(v, s) / alpha);

  // ---- 8. roads by path fraction (for the chip and the signs)
  const roads: RoadSeg[] = [];
  {
    let f = 0;
    segs.forEach((_, i) => {
      const jt = joints[i];
      let end = L;
      if (jt) end = jt.kind === 'round' ? jOut[i].sa : (jOut[i].sa + jOut[i].sb) / 2;
      roads.push({ name: straights[i].name, f0: f / L, f1: end / L });
      f = end;
      if (jt && jt.kind === 'round') {
        roads.push({ name: 'King’s Square', f0: f / L, f1: jOut[i].sb / L });
        f = jOut[i].sb;
      }
    });
    roads[roads.length - 1].f1 = 1;
  }

  // ---- 9. map keypoints
  const key: { s: number; x: number; y: number }[] = [];
  {
    key.push({ s: 0, x: segs[0].x0, y: segs[0].y0 });
    segs.forEach((g, i) => {
      if (i < joints.length) {
        const jt = joints[i];
        if (jt.kind === 'turn') {
          const m = (primS[primOfJoint[i]] + primS[primOfJoint[i] + 1]) / 2;
          key.push({ s: m, x: g.x1, y: g.y1 });
        } else {
          const sa0 = primS[primOfJoint[i]];
          const sb0 = primS[primOfJoint[i] + 3];
          key.push({ s: sa0, x: g.x1, y: g.y1 });
          const ring = jt.ringPts ?? [];
          const rl = jt.ringLen || 1;
          let acc = 0;
          for (let q = 0; q < ring.length; q++) {
            if (q > 0) acc += Math.hypot(ring[q][0] - ring[q - 1][0], ring[q][1] - ring[q - 1][1]);
            key.push({ s: sa0 + ((sb0 - sa0) * acc) / rl, x: ring[q][0], y: ring[q][1] });
          }
        }
      }
    });
    const lg = segs[segs.length - 1];
    key.push({ s: L, x: lg.x1, y: lg.y1 });
    for (let i = 1; i < key.length; i++) if (key[i].s < key[i - 1].s) key[i].s = key[i - 1].s;
  }
  const mapAt = (s: number): [number, number] => {
    if (s <= 0) return [key[0].x, key[0].y];
    for (let i = 1; i < key.length; i++) {
      if (s <= key[i].s) {
        const a0 = key[i - 1];
        const b0 = key[i];
        const t = (s - a0.s) / Math.max(1e-6, b0.s - a0.s);
        return [a0.x + (b0.x - a0.x) * t, a0.y + (b0.y - a0.y) * t];
      }
    }
    return [key[key.length - 1].x, key[key.length - 1].y];
  };

  const straightAt = (s: number) => {
    let best = 0;
    let bd = Infinity;
    straights.forEach((st, i) => {
      const d = s < st.sa ? st.sa - s : s > st.sb ? s - st.sb : 0;
      if (d < bd) {
        bd = d;
        best = i;
      }
    });
    return best;
  };

  return {
    L,
    total,
    xs: px,
    zs: pz,
    psis: pp,
    kap: pk,
    straights,
    junctions: jOut,
    stops,
    slows,
    roads,
    mapPts: pts.map((p) => [p[0], p[1]] as Pt),
    pose: poseAt,
    at: atFn,
    mapAt,
    sOfT,
    tOfS,
    vRef,
    vLim,
    straightAhead(s, len) {
      const i = straightAt(s);
      const st = straights[i];
      if (s < st.sa - 0.5 || s + len > st.sb) return false;
      return !stops.some((q) => q.s > s - 10 && q.s < s + len);
    },
    nextJunction(s) {
      return jOut.find((j) => j.sb > s) ?? null;
    },
    straightAt,
  };
}
