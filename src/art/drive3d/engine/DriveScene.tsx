// The live 3D drive (react-three-fiber). Lazy-loaded through ../DriveView.tsx.
//
// The car follows the real route (./track.ts): straight streets, junctions where it turns left or right, the roundabout. Its place
// on the track is a function of the server clock (progress = elapsed / total): the speed profile (slow into corners, stops at bus
// stops, slow-downs behind traffic) is stretched to the trip time, and a small controller keeps the car on it, braking for road
// events and the arrival. The streets around the car are generated chunk by chunk (world.ts), the destination is the very model the
// city map shows there (place.ts). No shadows, no external assets, no per-frame React state (refs only).
import { Canvas, useFrame, useThree } from '@react-three/fiber';
import { useEffect, useRef, type MutableRefObject } from 'react';
import {
  AdditiveBlending,
  BufferAttribute,
  BufferGeometry,
  CanvasTexture,
  Color,
  DirectionalLight,
  DoubleSide,
  Float32BufferAttribute,
  Fog,
  Group,
  HemisphereLight,
  InstancedMesh,
  LineBasicMaterial,
  LineSegments,
  Mesh,
  MeshBasicMaterial,
  MeshLambertMaterial,
  Object3D,
  PerspectiveCamera,
  PlaneGeometry,
  Points,
  PointsMaterial,
  SRGBColorSpace,
  Vector3,
} from 'three';
import type { DriveKind } from '../../../api/drive';
import { cityLight } from '../../city3d/engine/light';
import { districtAt } from '../district';
import { roadAt, type CamMode, type VehicleLook } from '../model';
import { LANE_OFFSET, type Track } from '../track';
import { MANUAL_MS, newStats, type SteerInput, type SteerStats } from '../steer';
import { buildBusRig, buildStop, destBoard, type BusRig, type StopRig } from './bus';
import { buildPlaceModel, type PlaceModel } from './place';
import { buildCockpit, buildEventProps, buildGate, buildSign, gateAccent, type Cockpit, type EventProps, type Gate } from './props';
import { setVehicleLight, setVehicleRenderer, unitWheelGeometry, vehicleGeometry, vehicleKit, vehicleMaterial, type VehicleMaterial, type VehicleModel } from './vehicles';
import { buildJunctions, buildStreet, LANE_IN, LANE_OUT, PERIOD, ROAD_HALF, STYLE_GROUND, type Street, type StreetSpec, type Style } from './world';

/** The player's lane: the outer lane, by the pavement. */
export const MY_LANE = LANE_OFFSET;

export interface OtherCar {
  id: string;
  name: string;
  look: VehicleLook;
}

export interface DriveLive {
  /** 0..1 of the trip, from the server clock. */
  progress: number;
  /** Seconds to arrival (server clock). */
  left: number;
  /** The trip has arrived (the server moved the player): park at the destination. */
  arrived: boolean;
  /** Written by the scene each frame: metres along the track, speed (m/s), the bus stop the bus is standing at (or null). */
  s?: number;
  v?: number;
  stop?: string | null;
  /** Steering (own vehicle): lane index 0..3, whether the player is driving (not the autopilot), the counts to report, turn signal, braking. */
  lane?: number;
  manual?: boolean;
  stats?: SteerStats;
  hitSeq?: number;
  offSeq?: number;
  signal?: -1 | 0 | 1;
  braking?: boolean;
}

export interface DriveApi {
  stats(): { calls: number; triangles: number; geometries: number };
  /** Dev: jump the car to a track distance, hold it there (pin) or set the speed (screenshots). */
  dev(patch: { s?: number; pin?: number | null; speed?: number; dist?: number; hold?: number | null; top?: number | null }): void;
  /** The track being driven (dev / tests). */
  track: Track;
  state(): Record<string, number | boolean | string>;
}

export interface DriveDest {
  id: string;
  name: string;
  scene: string;
  x: number;
  y: number;
}

export interface DriveSceneProps {
  hour: number;
  tier: 'low' | 'high';
  vehicle: VehicleLook;
  cam: CamMode;
  track: Track;
  dest: DriveDest;
  live: MutableRefObject<DriveLive>;
  /** Stop the car for a road event (a new `id` per event). */
  event: { id: number; kind: DriveKind } | null;
  /** The player chose: let the props react and drive on. */
  resolved: { id: number; ok: boolean } | null;
  /** "Go in": push in on the destination. */
  entering: boolean;
  others: OtherCar[];
  /** Own vehicle only: the on-screen controls write into this (lane steps, brake, speed up). Absent = auto-drive only. */
  steer?: MutableRefObject<SteerInput> | null;
  /** It is raining (wet road, streaks, greyer light). */
  rain?: boolean;
  /** Vehicle condition 0..100 (smoke, dent decal, tilt, lower top speed). Absent = 100. */
  cond?: number;
  /** Below this condition the vehicle smokes. */
  smokeBelow?: number;
  seed?: number;
  paused?: boolean;
  /** Dev (screenshots): start at this track distance. */
  startAt?: { s?: number; stopped?: boolean };
  onStopped?: (id: number) => void;
  onReady?: (api: DriveApi) => void;
  onLost?: () => void;
}

type NpcKind = VehicleModel;
interface Npc {
  kind: NpcKind;
  lane: number;
  v: number;
  z: number;
  color: Color;
  hitT?: number;
}
/** Slow same-direction traffic in the player's two lanes: the vehicles you overtake. */
interface SlowNpc {
  kind: NpcKind;
  half: number;
  lane: number;
  v: number;
  s: number;
  hit: boolean;
  passed: boolean;
  vis: boolean;
  color: Color;
}
const HALF_LEN: Record<string, number> = { hatch: 2.1, minibus: 2.7, sedan2: 2.45, sedan: 2.3, suv: 2.4, pickup: 2.6, keke: 1.3, moto: 1.0, okada2: 1.0, bus: 5.4, bike: 0.8 };
const HALF_WID: Record<string, number> = { sedan: 0.78, suv: 0.85, pickup: 0.85, keke: 0.55, moto: 0.18, okada2: 0.18, bus: 1.1, bike: 0.12 };
/** Lateral positions of the lane steps: oncoming lane, inner lane, outer lane (default), the shoulder (off the road). */
const LANE_LAT = [-LANE_IN, LANE_IN, LANE_OFFSET, 8.9];

const NPC_KINDS: NpcKind[] = ['sedan', 'hatch', 'suv', 'keke', 'okada2', 'moto', 'bus', 'pickup', 'sedan2', 'keke', 'minibus', 'bus'];
const NPC_COLORS = ['#c3c7cd', '#4a5d7a', '#a23c36', '#efebe0', '#5a8068', '#6c7480', '#aab3bd', '#7d8ca0', '#9a7650', '#d6d1c2'];
const RING_LEN = 210;
const RING_FAR = -160;
const WHEELBASE: Record<string, number> = { sedan: 2.7, suv: 2.9, pickup: 3.1, moto: 1.6, bike: 1.1, keke: 1.7, bus: 5.9 };

const hash = (s: string) => {
  let h = 2166136261;
  for (let i = 0; i < s.length; i++) h = Math.imul(h ^ s.charCodeAt(i), 16777619);
  return h >>> 0;
};
const clamp = (v: number, a: number, b: number) => Math.max(a, Math.min(b, v));
const smooth = (t: number) => {
  const k = clamp(t, 0, 1);
  return k * k * (3 - 2 * k);
};

function skyTexture(c: ReturnType<typeof cityLight>): CanvasTexture {
  const cv = document.createElement('canvas');
  cv.width = 8;
  cv.height = 256;
  const g = cv.getContext('2d')!;
  const grad = g.createLinearGradient(0, 0, 0, 256);
  const top = new Color(c.sky).lerp(new Color(c.dark > 0.5 ? '#0c1330' : '#7fb0e0'), c.dark > 0.5 ? 0.7 : 0.55);
  grad.addColorStop(0, `#${top.getHexString()}`);
  grad.addColorStop(0.5, c.sky);
  grad.addColorStop(1, c.sky);
  g.fillStyle = grad;
  g.fillRect(0, 0, 8, 256);
  const t = new CanvasTexture(cv);
  t.colorSpace = SRGBColorSpace;
  return t;
}

function radialTexture(): CanvasTexture {
  const cv = document.createElement('canvas');
  cv.width = cv.height = 64;
  const g = cv.getContext('2d')!;
  const r = g.createRadialGradient(32, 32, 2, 32, 32, 31);
  r.addColorStop(0, 'rgba(0,0,0,0.55)');
  r.addColorStop(1, 'rgba(0,0,0,0)');
  g.fillStyle = r;
  g.fillRect(0, 0, 64, 64);
  return new CanvasTexture(cv);
}

function beamTexture(): CanvasTexture {
  const cv = document.createElement('canvas');
  cv.width = 32;
  cv.height = 128;
  const g = cv.getContext('2d')!;
  const gr = g.createLinearGradient(0, 128, 0, 0);
  gr.addColorStop(0, 'rgba(255,240,200,0.85)');
  gr.addColorStop(1, 'rgba(255,240,200,0)');
  g.fillStyle = gr;
  g.fillRect(0, 0, 32, 128);
  const gx = g.createLinearGradient(0, 0, 32, 0);
  gx.addColorStop(0, 'rgba(0,0,0,1)');
  gx.addColorStop(0.5, 'rgba(0,0,0,0)');
  gx.addColorStop(1, 'rgba(0,0,0,1)');
  g.globalCompositeOperation = 'destination-out';
  g.fillStyle = gx;
  g.fillRect(0, 0, 32, 128);
  return new CanvasTexture(cv);
}

function crackTexture(): CanvasTexture {
  const cv = document.createElement('canvas');
  cv.width = 128;
  cv.height = 64;
  const g = cv.getContext('2d')!;
  const r = g.createRadialGradient(64, 32, 2, 64, 32, 44);
  r.addColorStop(0, 'rgba(20,20,22,0.7)');
  r.addColorStop(0.55, 'rgba(30,30,32,0.35)');
  r.addColorStop(1, 'rgba(30,30,32,0)');
  g.fillStyle = r;
  g.fillRect(0, 0, 128, 64);
  g.strokeStyle = 'rgba(235,235,230,0.8)';
  g.lineWidth = 1.4;
  const cracks: [number, number][][] = [
    [[64, 32], [40, 20], [24, 22]],
    [[64, 32], [88, 14], [104, 18]],
    [[64, 32], [92, 46], [108, 44]],
    [[64, 32], [46, 50], [30, 56]],
    [[64, 32], [70, 10]],
  ];
  for (const c of cracks) {
    g.beginPath();
    g.moveTo(c[0][0], c[0][1]);
    for (let i = 1; i < c.length; i++) g.lineTo(c[i][0], c[i][1]);
    g.stroke();
  }
  return new CanvasTexture(cv);
}

function puffTexture(): CanvasTexture {
  const cv = document.createElement('canvas');
  cv.width = cv.height = 64;
  const g = cv.getContext('2d')!;
  const r = g.createRadialGradient(32, 32, 1, 32, 32, 31);
  r.addColorStop(0, 'rgba(255,255,255,0.95)');
  r.addColorStop(0.5, 'rgba(255,255,255,0.5)');
  r.addColorStop(1, 'rgba(255,255,255,0)');
  g.fillStyle = r;
  g.fillRect(0, 0, 64, 64);
  return new CanvasTexture(cv);
}

const _tmp = new Vector3();

function Rig(p: DriveSceneProps) {
  const { scene, camera, gl } = useThree();
  const P = useRef(p);
  P.current = p;
  const st = useRef<{ tick: (dt: number) => void; dispose: () => void; api: DriveApi } | null>(null);

  const tr = p.track;
  const lookKey = `${p.vehicle.kind}|${p.vehicle.color}|${p.tier}|${p.dest.id}|${tr.L.toFixed(1)}|${tr.straights.length}|${tr.stops.length}`;
  useEffect(() => {
    const cam = camera as PerspectiveCamera;
    const low = P.current.tier === 'low';
    const track = P.current.track;
    const kind = P.current.vehicle.kind;
    const isBus = kind === 'bus';
    const root = new Group();
    scene.add(root);
    scene.add(cam);
    const owned: { dispose(): void }[] = [];
    const own = <T extends { dispose(): void }>(o: T) => {
      owned.push(o);
      return o;
    };

    const hemi = new HemisphereLight('#ffffff', '#b7a58f', 1.5);
    const sun = new DirectionalLight('#fff1dc', 2);
    const fill = new DirectionalLight('#dfe8ff', 0.5);
    root.add(hemi, sun, sun.target, fill);
    const fog = new Fog('#cfe5f1', low ? 24 : 32, low ? 105 : 150);
    scene.fog = fog;

    // ---- ground follows the car (a plain colour that tints with the district)
    const groundMat = own(new MeshLambertMaterial({ color: STYLE_GROUND.res }));
    const ground = new Mesh(own(new PlaneGeometry(1400, 1400)), groundMat);
    ground.rotation.x = -Math.PI / 2;
    ground.position.y = -0.02;
    root.add(ground);
    const groundCol = new Color(STYLE_GROUND.res);
    const groundWant = new Color(STYLE_GROUND.res);

    // ---- streets: one per straight, generated around the car, pooled
    const density = low ? 0.6 : 1;
    const baseSeed = (P.current.seed ?? 7) + hash(P.current.dest.id) % 997;
    const POOL = 4;
    const pool: { street: Street | null; idx: number }[] = Array.from({ length: POOL }, () => ({ street: null, idx: -1 }));
    const specs: StreetSpec[] = track.straights.map((s, i) => ({
      seed: baseSeed + i * 131,
      u0b: s.u0b,
      u1b: s.u1b,
      u0a: s.u0a,
      u1a: s.u1a,
      plot: null,
      styleAt: (u: number) => {
        const [mx, my] = track.mapAt(s.sa + Math.max(0, Math.min(s.sb - s.sa, u)));
        return districtAt(mx, my);
      },
    }));
    const junc = buildJunctions(
      track.junctions.map((j) => {
        // directions the two streets meet the roundabout in (so the ring of buildings leaves them open)
        const sA = track.straights[j.from];
        const sB = track.straights[j.to];
        const pa = track.at(sA.sb, 0);
        const pb = track.at(sB.sa, 0);
        const guide: [number, number, number][] = [];
        if (j.kind === 'turn') for (let q = j.sa - 6; q <= j.sb + 6; q += 3.2) {
          const g = track.at(q, 4.1);
          guide.push([g.x, g.z, g.psi]);
        }
        return {
          guide,
          kind: j.kind,
          x: j.x,
          z: j.z,
          island: j.island,
          outer: j.outer,
          avoid: [Math.atan2(pa.z - j.z, pa.x - j.x), Math.atan2(pb.z - j.z, pb.x - j.x)],
        };
      }),
    );
    if (junc) {
      root.add(junc.group);
      own(junc);
    }
    // the roundabout island is the museum drum of King's Square, drawn by the city's own landmark builder
    let roundMuseum: PlaceModel | null = null;
    if (track.junctions.some((j) => j.kind === 'round')) {
      try {
        roundMuseum = buildPlaceModel({ id: 'national_museum', name: 'Benin National Museum', scene: 'museum', x: 500, y: 500 });
        const j = track.junctions.find((q) => q.kind === 'round')!;
        roundMuseum.group.position.set(j.x, 0.3, j.z);
        roundMuseum.group.scale.setScalar(0.62);
        root.add(roundMuseum.group);
      } catch {
        roundMuseum = null;
      }
    }

    // ---- the player's vehicle: body without wheels + wheels that steer and spin
    // vehicles come from the shared library (src/art/vehicles): the player's vehicle at full detail (a lighter one on Graphics Low),
    // traffic at a cheaper level; their lamps glow with the night (vmats)
    const vmats: VehicleMaterial[] = [];
    setVehicleRenderer(gl);
    // near = the player's vehicle, the car ahead, other players: paint and glass reflect a baked sky (not on Graphics Low); traffic is cheap
    const vmat = (c: string | number = 0xffffff, near = false) => {
      const m = own(vehicleMaterial(c, { cheap: low || !near }));
      vmats.push(m);
      return m;
    };
    const lodNear = low ? 1 : 0;
    const lodTraffic = low ? 2 : 1;
    const kit = vehicleKit(kind, lodNear);
    const carMat = vmat(isBus ? '#ffffff' : P.current.vehicle.color, true);
    const car = new Group();
    const rig = new Group();
    car.add(rig);
    const carMesh = new Mesh(kit.body, carMat);
    rig.add(carMesh);
    const wheelGeo = unitWheelGeometry(kit.wheels[0]?.style ?? 'car', lodNear);
    const wheelMat = vmat(0xffffff, true);
    const wheels = new InstancedMesh(wheelGeo, wheelMat, Math.max(1, kit.wheels.length));
    wheels.frustumCulled = false;
    rig.add(wheels);
    const shadowTex = own(radialTexture());
    const shadow = new Mesh(own(new PlaneGeometry(isBus ? 3.8 : 3.4, isBus ? 11.5 : 6.4)), own(new MeshBasicMaterial({ map: shadowTex, transparent: true, depthWrite: false })));
    shadow.rotation.x = -Math.PI / 2;
    shadow.position.y = 0.06;
    car.add(shadow);
    const beamTex = own(beamTexture());
    const beamMat = own(new MeshBasicMaterial({ map: beamTex, transparent: true, depthWrite: false, blending: AdditiveBlending, opacity: 0 }));
    const beamGeo = own(new PlaneGeometry(2.6, 16));
    const beamZ = isBus ? -14.6 : -10.5;
    const beams = [-0.62, 0.62].map((x) => {
      const b = new Mesh(beamGeo, beamMat);
      b.rotation.x = -Math.PI / 2;
      b.position.set(x * (isBus ? 1.9 : 1.4), 0.08, beamZ);
      car.add(b);
      return b;
    });
    const wide = kind === 'moto' || kind === 'bike';
    if (wide) beams.forEach((b, i) => (b.visible = i === 0));
    root.add(car);

    // ---- own-vehicle extras (drive 3): brake / tail lights, turn signal lamps, a dent decal, smoke
    kit.body.computeBoundingBox();
    const bb = kit.body.boundingBox!;
    const bw = Math.max(0.3, (bb.max.x - bb.min.x) / 2);
    const bh = bb.max.y - bb.min.y;
    const lampGeo = own(new PlaneGeometry(0.34, 0.15));
    const tailMat = own(new MeshBasicMaterial({ color: '#e0352b', transparent: true, opacity: 0, depthWrite: false, side: DoubleSide }));
    const sigMat = own(new MeshBasicMaterial({ color: '#f0a533', transparent: true, opacity: 0.95, depthWrite: false, side: DoubleSide }));
    const lampY = bb.min.y + bh * 0.52;
    const tails: Mesh[] = [];
    const sigs: { m: Mesh; side: -1 | 1 }[] = [];
    for (const sx of wide ? [0] : [-1, 1]) {
      const tl = new Mesh(lampGeo, tailMat);
      tl.position.set(sx * bw * 0.72, lampY, bb.max.z + 0.02);
      rig.add(tl);
      tails.push(tl);
    }
    for (const side of [-1, 1] as const) {
      const sr = new Mesh(lampGeo, sigMat);
      sr.position.set(side * bw * (wide ? 0.5 : 0.92), lampY - 0.12, bb.max.z + 0.025);
      sr.scale.set(0.55, 1, 1);
      sr.visible = false;
      rig.add(sr);
      const sf = new Mesh(lampGeo, sigMat);
      sf.position.set(side * bw * (wide ? 0.5 : 0.92), lampY - 0.12, bb.min.z - 0.025);
      sf.scale.set(0.55, 1, 1);
      sf.visible = false;
      rig.add(sf);
      sigs.push({ m: sr, side }, { m: sf, side });
    }
    // a cracked dent decal on the door sides (shown at low condition)
    const dentTex = own(crackTexture());
    const dentMat = own(new MeshBasicMaterial({ map: dentTex, transparent: true, depthWrite: false, opacity: 0.85, polygonOffset: true, polygonOffsetFactor: -2 }));
    const dentGeo = own(new PlaneGeometry(Math.min(1.1, (bb.max.z - bb.min.z) * 0.28), bh * 0.3));
    const dents = [1, -1].map((sx) => {
      const d = new Mesh(dentGeo, dentMat);
      d.position.set(sx * (bb.max.x + 0.012), bb.min.y + bh * 0.46, (bb.min.z + bb.max.z) / 2 + 0.2);
      d.rotation.y = (sx * Math.PI) / 2;
      d.visible = false;
      rig.add(d);
      return d;
    });
    // smoke from under the bonnet (preallocated points, updated in place)
    const smokeN = low ? 10 : 22;
    const smokePos = new Float32Array(smokeN * 3);
    const smokeAge = new Float32Array(smokeN);
    for (let i = 0; i < smokeN; i++) {
      smokeAge[i] = (i / smokeN) * 1.4;
      smokePos[i * 3 + 1] = -50;
    }
    const smokeGeo = own(new BufferGeometry());
    const smokeAttr = new BufferAttribute(smokePos, 3); // keeps the array: updated in place each frame
    smokeGeo.setAttribute('position', smokeAttr);
    const smokeMat = own(new PointsMaterial({ color: '#6f757d', map: own(puffTexture()), size: 1.3, sizeAttenuation: true, transparent: true, opacity: 0.75, depthWrite: false }));
    const smoke = new Points(smokeGeo, smokeMat);
    smoke.frustumCulled = false;
    smoke.visible = false;
    rig.add(smoke);

    // bus extras: destination board, door leaves, the inside
    let busRig: BusRig | null = null;
    let board: { mesh: Mesh; dispose(): void } | null = null;
    if (isBus) {
      busRig = buildBusRig();
      rig.add(busRig.doors, busRig.interior);
      board = destBoard(P.current.dest.name);
      rig.add(board.mesh);
    }

    const cockpit: Cockpit = buildCockpit(kind);
    cam.add(cockpit.group);
    cockpit.group.visible = false;

    // ---- bus stops along the way
    const stopRigs: { rig: StopRig; s: number; name: string; arrivedAt: number; state: 'before' | 'dwell' | 'after' }[] = [];
    if (isBus) {
      track.stops.forEach((sp, i) => {
        const sr = buildStop(sp.name, i + baseSeed, -1.5, 0);
        const pose = track.at(sp.s + 4, ROAD_HALF + 1.7 + 0.5 + 0.8);
        sr.group.position.set(pose.x, 0, pose.z);
        sr.group.rotation.y = -pose.psi;
        root.add(sr.group);
        stopRigs.push({ rig: sr, s: sp.s, name: sp.name, arrivedAt: -1, state: 'before' });
      });
    }

    // ---- NPC traffic: one instanced mesh per kind (buses are the yellow-and-red ECTS ones)
    const npcMats = vmat();
    const npcs: Npc[] = [];
    const nCars = low ? 9 : 16;
    const perLane = [Math.ceil(nCars * 0.4), Math.floor(nCars * 0.6)];
    const lanes = [-LANE_IN, -LANE_OUT];
    const speeds = [-15, -12];
    for (let li = 0; li < 2; li++) {
      for (let i = 0; i < perLane[li]; i++) {
        const k = NPC_KINDS[(i * 3 + li * 5 + (P.current.seed ?? 7)) % NPC_KINDS.length];
        const col = k === 'keke' ? '#e3b53c' : k === 'bus' ? '#ffffff' : NPC_COLORS[(i * 7 + li * 3) % NPC_COLORS.length];
        npcs.push({ kind: k, lane: lanes[li], v: speeds[li], z: 30 - (i + 0.2 + li * 0.45) * (RING_LEN / perLane[li]), color: new Color(col) });
      }
    }
    const kinds = [...new Set(npcs.map((n) => n.kind))];
    const npcMesh = new Map<NpcKind, InstancedMesh>();
    for (const k of kinds) {
      const count = npcs.filter((n) => n.kind === k).length;
      const im = new InstancedMesh(vehicleGeometry(k, 2), npcMats, count);
      im.frustumCulled = false;
      root.add(im);
      npcMesh.set(k, im);
    }
    const dummy = new Object3D();
    const steerStats: SteerStats = newStats();

    // ---- slow traffic in the player's own two lanes: the vehicles you overtake (the autopilot steers round them)
    const slowDefs: { kind: NpcKind; col: string }[] = [
      { kind: 'keke', col: '#e3b53c' },
      { kind: 'sedan', col: '#9a7650' },
      { kind: 'pickup', col: '#5a8068' },
      { kind: 'keke', col: '#e3b53c' },
      { kind: 'sedan', col: '#7d8ca0' },
    ];
    const nSlow = isBus ? 0 : low ? 3 : 5;
    let rs = (hash(P.current.dest.id) | 1) >>> 0;
    const rnd = () => {
      rs = (Math.imul(rs, 1664525) + 1013904223) >>> 0;
      return rs / 4294967296;
    };
    const slow: SlowNpc[] = slowDefs.slice(0, nSlow).map((d, i) => ({
      kind: d.kind,
      half: HALF_LEN[d.kind],
      lane: i % 2 === 0 ? LANE_OFFSET : LANE_IN,
      v: 5 + rnd() * 3.5,
      s: 0,
      hit: false,
      passed: false,
      vis: false,
      color: new Color(d.col),
    }));
    const slowMesh = new Map<NpcKind, InstancedMesh>();
    for (const k of new Set(slow.map((n) => n.kind))) {
      const im = new InstancedMesh(vehicleGeometry(k, lodTraffic), npcMats, slow.filter((n) => n.kind === k).length);
      im.frustumCulled = false;
      im.count = 0;
      root.add(im);
      slowMesh.set(k, im);
    }
    const slowMeshes = [...slowMesh.values()];
    const respawnSlow = (n: SlowNpc, from: number, ahead: number) => {
      n.s = from + ahead;
      n.lane = rnd() < 0.55 ? LANE_OFFSET : LANE_IN;
      n.v = 5 + rnd() * 3.5;
      n.hit = false;
      n.passed = false;
    };
    const inSlowWindow = (sx: number) => track.slows.some((sl) => sx > sl.sa - 50 && sx < sl.sb + 70);

    // ---- night glow of other vehicles: tail lights (same direction) and headlights (oncoming), one instanced mesh, none by day
    const glowMax = (nCars + nSlow) * 2 + 4;
    const glow = new InstancedMesh(
      own(new PlaneGeometry(0.46, 0.2)),
      own(new MeshBasicMaterial({ color: '#ffffff', transparent: true, opacity: 0.9, depthWrite: false, blending: AdditiveBlending, side: DoubleSide })),
      glowMax,
    );
    glow.frustumCulled = false;
    glow.count = 0;
    root.add(glow);
    const tailCol = new Color('#ff3a2a');
    const headCol = new Color('#ffe9b0');
    const pushGlow = (x: number, z: number, ry: number, kindName: string, front: boolean) => {
      const hl = HALF_LEN[kindName] ?? 2.3;
      const hw = HALF_WID[kindName] ?? 0.7;
      const narrow = hw < 0.3;
      const cs = Math.cos(ry);
      const sn = Math.sin(ry);
      for (let k = 0; k < (narrow ? 1 : 2); k++) {
        if (glow.count >= glowMax) return;
        const lx = narrow ? 0 : (k === 0 ? -1 : 1) * hw * 0.78;
        const lz = front ? -hl : hl;
        dummy.position.set(x + lx * cs + lz * sn, 0.72, z - lx * sn + lz * cs);
        dummy.rotation.set(0, ry, 0);
        dummy.scale.setScalar(1);
        dummy.updateMatrix();
        glow.setMatrixAt(glow.count, dummy.matrix);
        glow.setColorAt(glow.count, front ? headCol : tailCol);
        glow.count++;
      }
    };

    // ---- rain: streaks on the camera (two periodic copies scrolled by moving the object: no per-vertex work), off by default
    const rainSegs = low ? 46 : 96;
    const rainPos = new Float32Array(rainSegs * 2 * 6);
    for (let i = 0; i < rainSegs; i++) {
      const x = (rnd() - 0.5) * 17;
      const y = rnd() * 9;
      const z = -(1.5 + rnd() * 20);
      const len = 0.8 + rnd() * 0.5;
      for (let c = 0; c < 2; c++) {
        const o = (c * rainSegs + i) * 6;
        rainPos[o] = x;
        rainPos[o + 1] = y + c * 9;
        rainPos[o + 2] = z;
        rainPos[o + 3] = x - 0.06;
        rainPos[o + 4] = y + c * 9 - len;
        rainPos[o + 5] = z;
      }
    }
    const rainGeo = own(new BufferGeometry());
    rainGeo.setAttribute('position', new Float32BufferAttribute(rainPos, 3));
    const rainStreaks = new LineSegments(rainGeo, own(new LineBasicMaterial({ color: '#d4e3f2', transparent: true, opacity: 0.4, depthWrite: false })));
    rainStreaks.frustumCulled = false;
    rainStreaks.visible = false;
    rainStreaks.rotation.x = 0.14;
    cam.add(rainStreaks);
    const juncMat = junc ? (((junc.group.children[0] as Mesh | undefined)?.material as MeshLambertMaterial | undefined) ?? null) : null;
    let wetNow = 0;

    // a slow vehicle ahead in our lane during the traffic slow-downs
    const lead = new Mesh(vehicleGeometry('suv', lodTraffic), vmat('#8d96a3', true));
    lead.visible = false;
    root.add(lead);
    const leadBus = isBus ? null : new Mesh(vehicleGeometry('bus', lodTraffic), vmat('#ffffff'));
    if (leadBus) {
      leadBus.visible = false;
      root.add(leadBus);
    }

    // ---- other players' cars (a pool of 8) and their name tags
    const otherPool = Array.from({ length: 8 }, () => {
      const m = new Mesh(vehicleGeometry('sedan', lodTraffic), vmat());
      m.visible = false;
      root.add(m);
      return { mesh: m, id: '' as string, z: 0 };
    });
    const tagLayer = gl.domElement.closest('.drive-canvas')?.querySelector('.drive-tags') as HTMLElement | null;

    // ---- signs
    const SIGN_GAP = 130;
    const signs = [0, 1, 2].map((i) => {
      const s = buildSign();
      root.add(s.group);
      return { s, at: 45 + i * SIGN_GAP, key: '' };
    });

    // ---- stars
    let stars: Points | null = null;
    if (!low) {
      const pts: number[] = [];
      for (let i = 0; i < 120; i++) {
        const a = Math.random() * Math.PI * 2;
        const e = 0.25 + Math.random() * 1.1;
        pts.push(Math.cos(a) * Math.cos(e) * 300, Math.sin(e) * 300, -Math.abs(Math.sin(a)) * Math.cos(e) * 300 - 30);
      }
      const g = own(new BufferGeometry());
      g.setAttribute('position', new Float32BufferAttribute(pts, 3));
      stars = new Points(g, own(new PointsMaterial({ color: '#dfe6ff', size: 1.6, sizeAttenuation: false, transparent: true, opacity: 0, fog: false })));
      stars.frustumCulled = false;
      root.add(stars);
    }

    // ---- destination (the model the city map shows there), built a moment after the first frame
    let place: PlaceModel | null = null;
    let placeFailed = false;
    const placeGroup = new Group();
    placeGroup.visible = false;
    root.add(placeGroup);
    const lastIdx = track.straights.length - 1;
    const lastS = track.straights[lastIdx];
    const placeU = track.L - lastS.sa + 2;
    let placeCenter = new Vector3();
    let placeTimer: number | null = window.setTimeout(() => {
      placeTimer = null;
      try {
        const m = buildPlaceModel(P.current.dest);
        place = m;
        const lat = ROAD_HALF + 3.4 + 5 + m.depth / 2;
        const ps = track.at(track.L + 2, lat);
        m.group.position.set(ps.x, 0, ps.z);
        // the model's front (+z) faces the road (to the left of the heading)
        m.group.rotation.y = Math.atan2(-Math.cos(ps.psi), -Math.sin(ps.psi));
        placeGroup.add(m.group);
        placeGroup.visible = true;
        placeCenter.set(ps.x, Math.min(5, m.top * 0.4), ps.z);
        // the entrance sign on two posts, in front of the model, facing the road
        const sg = buildSign();
        sg.setText(P.current.dest.name.length > 28 ? P.current.dest.name.slice(0, 27) + '…' : P.current.dest.name, '', 'green');
        const sp = track.at(track.L + 2, ROAD_HALF + 3.4 + 2.2);
        sg.group.position.set(sp.x, 0, sp.z);
        sg.group.rotation.y = Math.atan2(-Math.cos(sp.psi), -Math.sin(sp.psi));
        sg.group.scale.setScalar(0.85);
        placeGroup.add(sg.group);
        m.setDark(dark);
        // keep the frontage clear on the last street
        specs[lastIdx].plot = [placeU - m.width / 2 - 3, placeU + m.width / 2 + 3];
      } catch {
        placeFailed = true;
      }
    }, 30);

    // ---- state
    const startS = P.current.startAt?.s ?? track.sOfT(clamp(P.current.live.current.progress, 0, 1) * track.total);
    let sCar = clamp(startS, 0, track.L);
    let speed = P.current.startAt?.stopped ? 0 : Math.min(track.vRef(sCar) || 0, 14);
    let pinS: number | null = null;
    let holdV: number | null = null;
    let topH: number | null = null;
    let latCar = 0;
    let latBase = LANE_OFFSET;
    let laneIdx = 2;
    let manualAt = -1e9;
    let nowManual = false;
    let hitSeq = 0;
    let offSeq = 0;
    let offT = 0;
    let offNext = 0.35;
    let shake = 0;
    let tiltSm = 0;
    let brakeLit = 0;
    let sig: -1 | 0 | 1 = 0;
    let t = 0;
    let skyTex: CanvasTexture | null = null;
    let lastLightKey = '';
    let dark = 0;
    let ev: { id: number; kind: DriveKind; props: EventProps; S: number; t0: number; stopped: boolean; released: boolean; fwd: number; ok: boolean; seed: number } | null = null;
    let pendingEv: { id: number; kind: DriveKind; since: number } | null = null;
    let evSeen = 0;
    let gate: { g: Gate; open: number } | null = null;
    let camSnap = 3;
    let steerSm = 0;
    let accSm = 0;
    let pitchSm = 0;
    let rollSm = 0;
    let spin = 0;
    let doorOpen = 0;
    let lastV = speed;
    const camPos = new Vector3(0, 3, 8);
    const camLook = new Vector3(0, 1, -10);
    const wantPos = new Vector3();
    const wantLook = new Vector3();
    let othersKey = '';
    let hideOthers = false;
    let othersResetAt = -1;
    const slotOf = new Map<string, number>();
    const wheelO = new Object3D();
    slow.forEach((n, i) => respawnSlow(n, sCar, 70 + i * 46 + rnd() * 20));

    const applyLight = (hour: number) => {
      const c = cityLight(hour);
      dark = c.dark;
      for (const vm of vmats) setVehicleLight(vm, c.dark);
      const wet = P.current.rain ? 1 : 0;
      const key = `${Math.round(c.dark * 20)}|${c.sky}|${wet}`;
      if (key === lastLightKey) return;
      lastLightKey = key;
      // rain: a greyer, flatter light, shorter fog, a wet road
      const sky = wet ? `#${new Color(c.sky).lerp(new Color(c.dark > 0.5 ? '#141a26' : '#929ca7'), 0.6).getHexString()}` : c.sky;
      wetNow = wet;
      fog.near = (low ? 24 : 32) * (1 - 0.25 * wet);
      fog.far = (low ? 105 : 150) * (1 - 0.32 * wet);
      for (const e of pool) e.street?.setWet(wet);
      if (juncMat) {
        juncMat.color.setScalar(1 - 0.3 * wet);
        juncMat.emissive.set('#6d8aa6').multiplyScalar(0.13 * wet);
      }
      rainStreaks.visible = wet > 0;
      hemi.color.set(c.hemiSky);
      hemi.groundColor.set(c.hemiGround).lerp(new Color(c.hemiSky), 0.3);
      hemi.intensity = c.hemi * 1.3 * (1 - 0.12 * wet);
      fill.intensity = 0.2 + (1 - c.dark) * 0.55;
      sun.color.set(c.sun);
      sun.intensity = c.sunI * 0.6 * (1 - 0.55 * wet);
      sun.position.set(c.sunDir[0] * 60, Math.max(20, c.sunDir[1] * 60), c.sunDir[2] * 60 + 10);
      fog.color.set(sky);
      skyTex?.dispose();
      skyTex = skyTexture(wet ? { ...c, sky } : c);
      scene.background = skyTex;
      for (const e of pool) e.street?.setDark(c.dark);
      beamMat.opacity = Math.max(0, (c.dark - 0.25) / 0.75) * 0.72;
      if (stars) (stars.material as PointsMaterial).opacity = Math.max(0, (c.dark - 0.55) / 0.45) * 0.9;
      cockpit.setLook(P.current.vehicle.color, c.dark);
      gate?.g.setDark(c.dark);
      place?.setDark(c.dark);
      roundMuseum?.setDark(c.dark);
    };
    applyLight(P.current.hour);

    const roadName = (s: number) => roadAt(track.roads, clamp(s / track.L, 0, 1)).name;
    const signFor = (s: number) => {
      const nj = track.nextJunction(s);
      const ahead = nj ? nj.sa - s : 999;
      if (nj && ahead > 12 && ahead < 120) {
        return { l1: nj.kind === 'round' ? `Roundabout · ${nj.into}` : `${nj.dir > 0 ? '→' : '←'} ${nj.into}`, l2: `${roadName(s)} · Benin City` };
      }
      return { l1: roadName(s), l2: `Benin City · ${P.current.dest.name}` };
    };
    const hasStreet = (s: number, margin: number) => {
      const i = track.straightAt(s);
      const sg = track.straights[i];
      return s > sg.sa + margin && s < sg.sb - margin && s < track.L - 30;
    };

    // ---- the street pool: which straights are near the car, filled around it
    const updateStreets = () => {
      const want: number[] = [];
      track.straights.forEach((s, i) => {
        if (s.sb > sCar - 80 && s.sa < sCar + 240) want.push(i);
      });
      // free slots whose straight is no longer wanted
      for (const e of pool) {
        if (e.idx >= 0 && !want.includes(e.idx)) {
          if (e.street) e.street.group.visible = false;
          e.idx = -1;
        }
      }
      for (const i of want) {
        let slot = pool.find((e) => e.idx === i);
        if (!slot) {
          slot = pool.find((e) => e.idx < 0);
          if (!slot) continue;
          slot.idx = i;
          if (!slot.street) {
            slot.street = buildStreet(density);
            slot.street.setDark(dark);
            slot.street.setWet(wetNow);
            root.add(slot.street.group);
          }
          const s = track.straights[i];
          slot.street.group.position.set(s.ox, 0, s.oz);
          slot.street.group.rotation.y = -s.psi;
        }
        const s = track.straights[i];
        slot.street!.group.visible = true;
        const uRef = clamp(sCar - s.sa, 0, s.sb - s.sa);
        const k0 = Math.floor((uRef - 85) / PERIOD);
        slot.street!.fill(specs[i], k0); // cheap when nothing changed (key check)
      }
    };
    updateStreets();

    const spawnGate = () => {
      const g = buildGate(P.current.dest.name, gateAccent(P.current.dest.scene));
      g.setDark(dark);
      const gp = track.at(track.L + 14, 0);
      g.group.position.set(gp.x, 0, gp.z);
      g.group.rotation.y = -gp.psi;
      root.add(g.group);
      gate = { g, open: 0 };
    };

    const stats = () => ({ calls: gl.info.render.calls, triangles: gl.info.render.triangles, geometries: gl.info.memory.geometries });
    const api: DriveApi = {
      stats,
      track,
      state: () => ({
        s: sCar,
        v: speed,
        cx: car.position.x,
        cz: car.position.z,
        cy: car.rotation.y,
        px: cam.position.x,
        py: cam.position.y,
        pz: cam.position.z,
        carVisible: carMesh.visible,
        hold: holdV ?? -1,
        stop: stopRigs.map((r) => r.state + ':' + r.s).join(','),
        lane: laneIdx,
        latBase,
        manual: nowManual,
        passes: steerStats.passes,
        gaps: steerStats.gaps,
        hits: steerStats.hits,
        offroad: steerStats.offroad,
        slow: slow.filter((n) => n.vis).map((n) => `${Math.round(n.s - sCar)}@${n.lane}`).join(','),
      }),
      dev(patch) {
        const target = patch.s ?? patch.dist;
        if (target !== undefined) {
          sCar = clamp(target, 0, track.L);
          if (patch.pin === undefined && patch.hold === undefined) pinS = sCar;
          camSnap = 2;
        }
        if (patch.pin !== undefined) pinS = patch.pin;
        if (patch.hold !== undefined) holdV = patch.hold;
        if (patch.top !== undefined) topH = patch.top;
        if (patch.speed !== undefined) speed = patch.speed;
      },
    };

    const inJunction = (s: number, pad: number) => track.junctions.some((j) => s > j.sa - pad && s < j.sb + pad);
    const nearLane = (lat: number, from: number, to: number) => {
      for (const n of slow) if (n.vis && Math.abs(n.lane - lat) < 0.5 && n.s - sCar > from && n.s - sCar < to) return true;
      return false;
    };
    const squeezed = (n: SlowNpc) => {
      for (const m of slow) if (m !== n && m.vis && Math.abs(m.s - sCar) < 12 && Math.abs(m.lane - n.lane) > 1) return true;
      return false;
    };
    const hitNow = (counts: boolean) => {
      if (counts) steerStats.hits++;
      hitSeq++;
      speed *= 0.5;
      shake = 0.45;
    };
    const tmpV = new Vector3();

    const tick = (dtRaw: number) => {
      const dt = Math.min(0.05, dtRaw);
      t += dt;
      const props = P.current;
      const live = props.live.current;
      applyLight(props.hour);

      // ---- steering input, the autopilot and the slow traffic (drive 3)
      const inp = props.steer?.current;
      const evHold = Boolean(ev && !ev.released);
      const steerOn = Boolean(inp) && !live.arrived && !props.entering && !evHold;
      const nowMs = performance.now();
      if (inp && steerOn) {
        if (inp.lane !== 0) {
          laneIdx = clamp(laneIdx + Math.sign(inp.lane), 0, 3);
          inp.lane = 0;
          manualAt = nowMs;
        }
        if (inp.brake || inp.boost) manualAt = nowMs;
      } else if (inp) inp.lane = 0;
      const manual = steerOn && nowMs - manualAt < MANUAL_MS;
      nowManual = manual;
      const cnd = props.cond ?? 100;
      const topMult = 1 - 0.22 * clamp((50 - cnd) / 50, 0, 1);
      for (const n of slow) {
        n.s += n.v * dt;
        if (n.s < sCar - 45 || n.s > sCar + 330) respawnSlow(n, sCar, 150 + rnd() * 90);
        n.vis = !evHold && !live.arrived && !props.entering && !hideOthers && n.s > 14 && n.s < track.L - 28 && !inJunction(n.s, 24) && !inSlowWindow(n.s);
      }
      if (!manual) {
        // the autopilot: round slower vehicles through the free lane, back to the outer lane when it is clear
        if (laneIdx === 0) laneIdx = 1;
        else if (laneIdx === 3) laneIdx = 2;
        else if (laneIdx === 2) {
          if (nearLane(LANE_OFFSET, -2, 34 + speed) && !nearLane(LANE_IN, -8, 24)) laneIdx = 1;
        } else if (!nearLane(LANE_OFFSET, -7, 22) && !(nearLane(LANE_IN, -2, 30) && nearLane(LANE_OFFSET, -7, 44))) laneIdx = 2;
      }
      latBase += (LANE_LAT[laneIdx] - latBase) * Math.min(1, dt * 3.4);
      const myLat = latBase + latCar;
      const offroad = myLat > ROAD_HALF + 0.35;
      shake = Math.max(0, shake - dt * 1.9);

      // ---- events: a new request waits for a straight stretch, then puts the props ahead
      if (props.event && props.event.id !== evSeen) {
        evSeen = props.event.id;
        pendingEv = { id: evSeen, kind: props.event.kind, since: t };
      }
      if (pendingEv && (track.straightAhead(sCar, 80) || t - pendingEv.since > 14)) {
        ev?.props.dispose();
        if (ev) root.remove(ev.props.group);
        const ep = buildEventProps(pendingEv.kind, pendingEv.id);
        root.add(ep.group);
        ev = { id: pendingEv.id, kind: pendingEv.kind, props: ep, S: Math.min(sCar + (pendingEv.kind === 'dry' ? 19 : 62), track.L - (pendingEv.kind === 'dry' ? 12 : 26)), t0: t, stopped: false, released: false, fwd: 0, ok: true, seed: pendingEv.id };
        pendingEv = null;
        hideOthers = true;
      }
      if (ev && props.resolved && props.resolved.id === ev.id && !ev.released) {
        ev.released = true;
        ev.ok = props.resolved.ok;
        othersResetAt = t + 1.2;
      }
      if (othersResetAt > 0 && t > othersResetAt) {
        othersResetAt = -1;
        hideOthers = false;
        otherPool.forEach((o, i) => (o.z = 14 + i * 24));
      }

      // ---- the fallback gate (only when a place has no model)
      if (!gate && placeFailed && (live.arrived || (live.left <= 6 && live.progress > 0.5)) && !props.entering) spawnGate();

      // ---- where should the car be (server clock), and how fast
      const arrived = live.arrived || props.entering;
      const sStar = pinS ?? (live.arrived ? track.L : track.sOfT(clamp(live.progress, 0, 1) * track.total));
      const vl = track.vLim(sCar + 0.8);
      const gap = sStar - sCar;
      const boost = live.arrived ? 2.4 : clamp(1 + gap * 0.025, 1, 1.8);
      let vcmd = track.vRef(sStar) + 0.55 * gap;
      vcmd = clamp(vcmd, 0, Math.max(vl * boost, 0));
      if (gap < -1) vcmd = Math.min(vcmd, vl * 0.5);
      let braking = false;
      if (steerOn && inp) {
        if (inp.brake) {
          vcmd *= 0.3;
          braking = true;
        } else if (inp.boost) vcmd = Math.min(Math.max(vcmd, vl * 0.95), vl * 1.35 * topMult);
      }
      if (!(steerOn && inp?.boost)) {
        // keep behind a slower vehicle in our own lane (emergency braking: no bump unless you drive into it)
        let lim = 99;
        for (const n of slow) {
          if (!n.vis || n.hit) continue;
          const d = n.s - sCar - n.half - 2.3;
          if (d > -1 && d < 16 && Math.abs(n.lane - myLat) < 1.8) lim = Math.min(lim, n.v + Math.max(0, d - 4) * 0.35);
        }
        vcmd = Math.min(vcmd, lim);
      }
      if (offroad) vcmd = Math.min(vcmd, 7);
      if (ev && !ev.released) {
        const stopD = ev.S - ev.props.gap - 2.4;
        const rem = stopD - sCar;
        vcmd = rem < 0.15 ? 0 : Math.min(vcmd, Math.sqrt(2 * 8 * Math.max(0, rem)) + 0.2);
      }
      if (gate && !props.entering) {
        const rem = track.L + 14 - 15 - sCar;
        vcmd = rem < 0.15 ? 0 : Math.min(vcmd, Math.sqrt(2 * 7 * Math.max(0, rem)) + 0.2);
      }
      if (props.entering) vcmd = 0;
      if (holdV !== null) vcmd = holdV;
      const dv = vcmd - speed;
      speed += clamp(dv, -6.5 * dt, 3.1 * dt);
      if (speed < 0.02 && vcmd === 0) speed = 0;
      sCar += speed * dt;
      if (!gate) sCar = Math.min(sCar, track.L);
      if (ev && !ev.stopped && !ev.released && speed < 0.4 && ev.S - ev.props.gap - 2.4 - sCar < 1) {
        ev.stopped = true;
        props.onStopped?.(ev.id);
      }
      const acc = (speed - lastV) / Math.max(dt, 0.001);
      lastV = speed;
      accSm += (acc - accSm) * Math.min(1, dt * 5);
      live.s = sCar;
      live.v = speed;

      // ---- collisions, overtakes and off-road moments: only COUNTED here, the server decides what they are worth
      if (steerOn) {
        for (const n of slow) {
          if (!n.vis) continue;
          const ds = n.s - sCar;
          const reach = n.half + 2.3;
          if (!n.hit && Math.abs(ds) < reach && Math.abs(n.lane - myLat) < 1.75 && speed > 1.2) {
            n.hit = true;
            hitNow(manual);
          }
          if (!n.passed && !n.hit && ds < -(reach + 1.5)) {
            n.passed = true;
            if (manual) {
              steerStats.passes++;
              if (squeezed(n)) steerStats.gaps++;
            }
          }
        }
        for (const n of npcs) {
          if (n.v >= 0) continue;
          if (Math.abs(n.z) < 4.4 && Math.abs(n.lane - myLat) < 1.75 && t > (n.hitT ?? 0) && speed > 1.2) {
            n.hitT = t + 5;
            hitNow(manual);
          }
        }
        if (offroad) {
          offT += dt;
          if (offT > offNext) {
            if (manual) {
              steerStats.offroad++;
              offSeq++;
            }
            offNext = offT + 2.4;
          }
        } else {
          offT = 0;
          offNext = 0.35;
        }
      } else {
        offT = 0;
        offNext = 0.35;
      }
      // turn signal: at junctions (the turn itself, or the exit of a roundabout)
      sig = 0;
      {
        const nj = track.nextJunction(sCar);
        if (nj) {
          if (nj.kind === 'turn' && sCar > nj.sa - 42) sig = nj.dir;
          else if (nj.kind === 'round' && sCar > nj.sb - 30) sig = 1;
        }
      }
      brakeLit += ((braking || accSm < -2.2 ? 1 : 0) - brakeLit) * Math.min(1, dt * 12);
      live.lane = laneIdx;
      live.manual = manual;
      live.stats = steerStats;
      live.hitSeq = hitSeq;
      live.offSeq = offSeq;
      live.signal = sig;
      live.braking = brakeLit > 0.5;

      // ---- bus stops: pull in to the kerb, doors, the people
      let dwellName: string | null = null;
      let curbWant = 0;
      for (const sr of stopRigs) {
        const near = sCar - sr.s;
        if (near > -34 && near < 14) curbWant = 0.5;
        if (sr.state === 'before' && Math.abs(near) < 1.6 && speed < 0.35) {
          sr.state = 'dwell';
          sr.arrivedAt = t;
        }
        if (sr.state === 'dwell') {
          dwellName = sr.name;
          if (near > 6) sr.state = 'after';
        }
        sr.rig.update(sr.state === 'before' ? -1 : sr.state === 'after' ? 99 : t - sr.arrivedAt);
      }
      live.stop = dwellName;
      let doorWant = 0;
      for (const sr of stopRigs) {
        if (sr.state === 'dwell') {
          const td = t - sr.arrivedAt;
          doorWant = td < 0.4 ? 0 : td > 4.6 ? 0 : 1;
        }
      }
      doorOpen += (doorWant - doorOpen) * Math.min(1, dt * 4);
      busRig?.setDoor(doorOpen);
      latCar += (curbWant - latCar) * Math.min(1, dt * 1.2);

      // ---- streets
      updateStreets();

      // ---- ground colour follows the district
      {
        const [mx, my] = track.mapAt(sCar);
        const sty: Style = districtAt(mx, my);
        groundWant.set(STYLE_GROUND[sty]);
        groundCol.lerp(groundWant, Math.min(1, dt * 0.6));
        groundMat.color.copy(groundCol);
      }

      // ---- player pose: on the lane path, leaning into the turn, nose dipping under braking, a little bob
      const here = track.at(sCar, latBase + latCar);
      const kap = track.kap[Math.min(track.kap.length - 1, Math.round(sCar))] ?? 0;
      const wb = WHEELBASE[kind] ?? 2.7;
      const steerTarget = clamp(Math.atan(wb * kap) * 1.4, -0.6, 0.6);
      steerSm += (steerTarget - steerSm) * Math.min(1, dt * 7);
      const sway = speed > 1 && Math.abs(kap) < 0.002 ? Math.sin(t * 0.55) * 0.1 + Math.sin(t * 1.3) * 0.035 : 0;
      const yawJit = sway * 0.05;
      car.position.set(here.x + Math.cos(here.psi) * sway, 0, here.z + Math.sin(here.psi) * sway);
      const yawLane = clamp((LANE_LAT[laneIdx] - latBase) * 0.045, -0.12, 0.12);
      car.rotation.y = -here.psi - yawJit - yawLane;
      const roll = clamp(speed * speed * kap * (isBus ? 0.013 : 0.02), -0.1, 0.1);
      const pitch = clamp(accSm * 0.0055, -0.05, 0.05);
      rollSm += (roll - rollSm) * Math.min(1, dt * 5);
      pitchSm += (pitch - pitchSm) * Math.min(1, dt * 6);
      const vf = Math.min(1, speed / 8);
      const bob = (Math.sin(t * 11) * 0.5 + Math.sin(t * 17.3 + 1) * 0.5) * 0.007 * vf + (Math.sin(t * 2.1) * 0.004 + 0.004) * vf;
      rig.position.y = bob;
      tiltSm += ((cnd < 30 ? 0.028 : 0) - tiltSm) * Math.min(1, dt * 2);
      rig.rotation.z = rollSm + tiltSm;
      rig.rotation.x = pitchSm;
      // wheels
      spin += speed * dt;
      kit.wheels.forEach((w, i) => {
        wheelO.position.set(w.x, w.r, w.z);
        wheelO.rotation.set(-spin / w.r, w.front ? -steerSm : 0, 0, 'YXZ');
        wheelO.scale.set(w.wid, w.r, w.r);
        wheelO.updateMatrix();
        wheels.setMatrixAt(i, wheelO.matrix);
      });
      wheels.instanceMatrix.needsUpdate = true;
      cockpit.steer(clamp(steerSm / 0.45, -1, 1));

      // ---- drive 3: brake and tail lights, turn signal, smoke and rain streaks
      {
        const nightK = clamp((dark - 0.25) / 0.75, 0, 1);
        tailMat.opacity = Math.max(nightK * 0.6, brakeLit * 0.95);
        const blink = Math.floor(t * 2.7) % 2 === 0;
        for (const sg of sigs) sg.m.visible = sig !== 0 && sg.side === sig && blink;
        const smokeBelow = props.smokeBelow ?? 40;
        const amt = cnd < smokeBelow ? clamp(((smokeBelow - cnd) / smokeBelow) * 1.2 + 0.35, 0.35, 1) : 0;
        smoke.visible = amt > 0;
        if (smoke.visible) {
          for (let i = 0; i < smokeN; i++) {
            smokeAge[i] += dt;
            const o = i * 3;
            if (smokeAge[i] > 1.5) {
              smokeAge[i] = 0;
              if (i < smokeN * amt) {
                smokePos[o] = (Math.random() - 0.5) * 0.5;
                smokePos[o + 1] = bb.min.y + bh * 0.62;
                smokePos[o + 2] = bb.min.z + 0.9;
              } else smokePos[o + 1] = -50;
            } else if (smokePos[o + 1] > -40) {
              smokePos[o] += Math.sin(t * 3 + i) * 0.18 * dt;
              smokePos[o + 1] += 0.85 * dt;
              smokePos[o + 2] += (0.9 + speed * 0.12) * dt;
            }
          }
          smokeAttr.needsUpdate = true;
        }
        if (rainStreaks.visible) rainStreaks.position.y = -4 - ((t * 14) % 9);
        groundMat.color.multiplyScalar(1 - 0.16 * wetNow);
      }

      // ---- event props
      if (ev) {
        if (ev.released) ev.fwd += ev.props.leaves * dt;
        const pe = track.at(ev.S + ev.fwd, 0);
        ev.props.group.position.set(pe.x, 0, pe.z);
        ev.props.group.rotation.y = -pe.psi;
        ev.props.update(dt, t - ev.t0, ev.released, ev.ok);
        if (ev.released && (ev.S + ev.fwd - sCar > 200 || ev.S + ev.fwd - sCar < -50)) {
          ev.props.dispose();
          root.remove(ev.props.group);
          ev = null;
        }
      }
      if (gate) {
        const tgt = props.entering ? 1 : 0;
        gate.open += (tgt - gate.open) * Math.min(1, dt * 4);
        gate.g.setOpen(gate.open);
      }

      // ---- NPC traffic (ring buffer around the car, mapped onto the track; none inside junctions)
      for (const n of npcs) {
        n.z += (speed - n.v) * dt;
        if (n.z > 45) n.z -= RING_LEN;
        else if (n.z < RING_FAR) n.z += RING_LEN;
      }
      for (const k of kinds) npcMesh.get(k)!.count = 0;
      glow.count = 0;
      const night = dark > 0.3;
      for (const n of npcs) {
        const s = sCar - n.z;
        if (s < 0 || s > track.L - 8 || inJunction(s, 22)) continue;
        const pn = track.at(s, n.lane);
        const im = npcMesh.get(n.kind)!;
        dummy.position.set(pn.x, 0, pn.z);
        dummy.rotation.set(0, -pn.psi + (n.v < 0 ? Math.PI : 0), 0);
        dummy.scale.setScalar(1);
        dummy.updateMatrix();
        const i = im.count++;
        im.setMatrixAt(i, dummy.matrix);
        im.setColorAt(i, n.color);
        if (night) pushGlow(pn.x, pn.z, -pn.psi + (n.v < 0 ? Math.PI : 0), n.kind, n.v < 0);
      }
      for (const k of kinds) {
        const im = npcMesh.get(k)!;
        im.instanceMatrix.needsUpdate = true;
        if (im.instanceColor) im.instanceColor.needsUpdate = true;
      }
      // slow vehicles in our two lanes
      for (const im of slowMeshes) im.count = 0;
      for (const n of slow) {
        if (!n.vis) continue;
        const pn = track.at(n.s, n.lane);
        const im = slowMesh.get(n.kind)!;
        dummy.position.set(pn.x, 0, pn.z);
        dummy.rotation.set(0, -pn.psi, 0);
        dummy.scale.setScalar(1);
        dummy.updateMatrix();
        const i = im.count++;
        im.setMatrixAt(i, dummy.matrix);
        im.setColorAt(i, n.color);
        if (night) pushGlow(pn.x, pn.z, -pn.psi, n.kind, false);
      }
      for (const im of slowMeshes) {
        im.instanceMatrix.needsUpdate = true;
        if (im.instanceColor) im.instanceColor.needsUpdate = true;
      }
      glow.instanceMatrix.needsUpdate = true;
      if (glow.instanceColor) glow.instanceColor.needsUpdate = true;

      // ---- slow-downs: a vehicle ahead in our lane closes in, we sit behind it, then it pulls away
      {
        let gapAhead = 999;
        let leadKind = 0;
        track.slows.forEach((sl, i) => {
          const d1 = sl.sa - 40;
          const d2 = sl.sb + 55;
          if (sCar < d1 || sCar > d2) return;
          leadKind = i;
          if (sCar < sl.sa) gapAhead = 11 + (1 - smooth((sCar - d1) / 40)) * 62;
          else if (sCar <= sl.sb) gapAhead = 11;
          else gapAhead = 11 + smooth((sCar - sl.sb) / 55) * 80;
        });
        const showLead = gapAhead < 88 && !(ev && !ev.released);
        const lv = leadKind % 2 === 0 || !leadBus ? lead : leadBus;
        lead.visible = false;
        if (leadBus) leadBus.visible = false;
        if (showLead && !inJunction(sCar + gapAhead, 6)) {
          const pl = track.at(sCar + gapAhead + 2.6, LANE_OFFSET);
          lv.position.set(pl.x, 0, pl.z);
          lv.rotation.y = -pl.psi;
          lv.visible = true;
        }
      }

      // ---- other players: overtake us in the fast lane
      const ok = props.others.map((o) => `${o.id}:${o.look.kind}:${o.look.color}`).join('|');
      if (ok !== othersKey) {
        othersKey = ok;
        const keep = new Set(props.others.map((o) => o.id));
        for (const [id, s] of slotOf) if (!keep.has(id)) { slotOf.delete(id); otherPool[s].id = ''; otherPool[s].mesh.visible = false; }
        props.others.slice(0, 8).forEach((o) => {
          let s = slotOf.get(o.id);
          if (s === undefined) {
            s = otherPool.findIndex((x) => !x.id);
            if (s < 0) return;
            slotOf.set(o.id, s);
            otherPool[s].id = o.id;
            otherPool[s].z = -(16 + s * 21 + (hash(o.id) % 5));
          }
          const sl = otherPool[s];
          sl.mesh.geometry = vehicleGeometry(o.look.kind === 'bike' ? 'moto' : o.look.kind, lodTraffic);
          (sl.mesh.material as unknown as VehicleMaterial).color.set(o.look.kind === 'bus' ? '#ffffff' : o.look.color);
        });
      }
      const tagEls = tagLayer ? (Array.from(tagLayer.children) as HTMLElement[]) : [];
      const tagById = new Map(tagEls.map((e) => [e.dataset.id ?? '', e]));
      const sz = gl.domElement.clientWidth;
      const sh = gl.domElement.clientHeight;
      const tagPlaced: { x: number; y: number; z: number; el: HTMLElement; op: number }[] = [];
      for (const o of props.others) {
        const s = slotOf.get(o.id);
        if (s === undefined) continue;
        const sl = otherPool[s];
        const vo = 15 + 4 + (hash(o.id) % 5) * 0.2;
        if (!hideOthers) sl.z += (speed - vo) * dt;
        if (sl.z < RING_FAR) sl.z += RING_LEN * 0.8;
        if (sl.z > 45) sl.z = 45 - (sl.z - 45);
        const so = sCar - sl.z;
        const show = !hideOthers && sl.z < 30 && sl.z > -120 && !(sl.z > -6 && sl.z < 6) && so > 0 && so < track.L - 8 && !inJunction(so, 22);
        sl.mesh.visible = show;
        const po = track.at(so, LANE_OFFSET - (LANE_OFFSET - LANE_IN));
        sl.mesh.position.set(po.x, 0, po.z);
        sl.mesh.rotation.y = -po.psi;
        const el = tagById.get(o.id);
        if (el) {
          if (show && sl.z < 4 && sl.z > -48) {
            _tmp.set(po.x, 2.1, po.z).project(cam);
            if (_tmp.z < 1) {
              const tx = (_tmp.x * 0.5 + 0.5) * sz;
              const ty = (-_tmp.y * 0.5 + 0.5) * sh;
              el.style.transform = `translate(${tx}px, ${ty}px) translate(-50%, -100%)`;
              tagPlaced.push({ x: tx, y: ty, z: sl.z, el, op: Math.max(0, Math.min(1, (48 + sl.z) / 16)) });
            } else el.style.opacity = '0';
          } else el.style.opacity = '0';
        }
      }
      tagPlaced.sort((a, b) => b.z - a.z);
      const tagShown: { x: number; y: number; w: number }[] = [];
      for (const tg of tagPlaced) {
        if (!tg.el.dataset.w) tg.el.dataset.w = String(tg.el.offsetWidth || 80);
        const w = Number(tg.el.dataset.w);
        const clash = tagShown.some((q) => Math.abs(q.x - tg.x) < (q.w + w) / 2 + 4 && Math.abs(q.y - tg.y) < 26);
        tg.el.style.opacity = clash ? '0' : String(tg.op);
        if (!clash) tagShown.push({ x: tg.x, y: tg.y, w });
      }

      // ---- signs on the right-hand verge, facing the driver
      for (const sg of signs) {
        while (sg.at < sCar - 16) sg.at += SIGN_GAP * signs.length;
        while (sg.at > sCar + SIGN_GAP * signs.length) sg.at -= SIGN_GAP * signs.length;
        const sv = hasStreet(sg.at, 20) && !inJunction(sg.at, 30);
        sg.s.group.visible = sv;
        if (sv) {
          const f = signFor(sg.at);
          const key = f.l1 + '|' + f.l2;
          if (key !== sg.key) {
            sg.key = key;
            sg.s.setText(f.l1, f.l2);
          }
          const ps = track.at(sg.at, 8.9);
          sg.s.group.position.set(ps.x, 0, ps.z);
          sg.s.group.rotation.y = -ps.psi;
        }
      }

      // ---- cameras (all in the track's own frame so the view swings through the turns)
      const mode = props.cam;
      const small = kind === 'moto' || kind === 'bike' || kind === 'keke';
      const asp = Math.max(0.3, cam.aspect);
      const vfov = (hdeg: number) => Math.min(88, (2 * Math.atan(Math.tan((hdeg * Math.PI) / 360) / asp) * 180) / Math.PI);
      const sp = clamp(speed / 16, 0, 1);
      let fov = vfov(54) + sp * 3;
      let snapInside = false;
      const arrivedShot = arrived && (place || gate);
      if (arrivedShot) {
        // arrival shot: behind and to the left of the car, the destination ahead on the right
        const carNow = track.at(sCar, LANE_OFFSET + latCar);
        const fx = Math.sin(carNow.psi);
        const fz = -Math.cos(carNow.psi);
        const rx = Math.cos(carNow.psi);
        const rz = Math.sin(carNow.psi);
        const back = isBus ? 17 : 13;
        const left = isBus ? 3.2 : 2.2;
        wantPos.set(carNow.x - fx * back - rx * left + Math.sin(t * 0.25) * 0.4 * rx, isBus ? 5.6 : 4.8, carNow.z - fz * back - rz * left);
        if (place && !gate) {
          // look between the car and the destination, so both stay in the picture
          wantLook.set(carNow.x * 0.62 + placeCenter.x * 0.38 + fx * 2.5, 1.7, carNow.z * 0.62 + placeCenter.z * 0.38 + fz * 2.5);
        } else {
          const gp = track.at(track.L + 14, 0);
          wantLook.set(gp.x, 3.0, gp.z);
        }
        fov = vfov(isBus ? 78 : 72);
        if (props.entering) {
          // push in on the entrance
          wantPos.set(carNow.x + fx * 7 + rx * 6, 2.6, carNow.z + fz * 7 + rz * 6);
          wantLook.set(placeCenter.x + fx * 2, 2.8, placeCenter.z + fz * 2);
          fov = vfov(58);
        }
      } else if (mode === 'chase') {
        const back = isBus ? 15.5 : small ? 7.8 : 10;
        const camLat = LANE_OFFSET + (latBase - LANE_OFFSET) * 0.7;
        const pb = track.at(sCar - back, camLat + latCar - 0.35);
        wantPos.set(pb.x, (isBus ? 5.2 : small ? 2.6 : 3.4) + Math.abs(rollSm) * 3, pb.z);
        // look between the car and the road ahead, so a turn swings the view without losing the car
        const pl = track.at(sCar + 12, LANE_OFFSET - 1.0 + (latBase - LANE_OFFSET) * 0.6);
        const w = 0.42;
        wantLook.set(car.position.x + (pl.x - car.position.x) * w, isBus ? 1.6 : 1.0, car.position.z + (pl.z - car.position.z) * w);
        fov = vfov(small ? 50 : isBus ? 62 : 56) + sp * 3;
      } else if (mode === 'side') {
        const pb = track.at(sCar - (isBus ? 6.5 : 3.2) + Math.sin(t * 0.4) * 0.3, 0.3);
        wantPos.set(pb.x, isBus ? 2.4 : 1.5, pb.z);
        wantLook.set(car.position.x, isBus ? 1.7 : 1.1, car.position.z);
        fov = Math.min(100, (2 * Math.atan(Math.tan(((small ? 40 : isBus ? 62 : 52) * Math.PI) / 360) / asp) * 180) / Math.PI);
      } else if (isBus) {
        // passenger seat: the aisle seat of the first row on the right, looking down the aisle and out of the windscreen
        car.updateMatrixWorld(true);
        tmpV.set(0.56, 1.95, -2.64);
        rig.localToWorld(tmpV);
        wantPos.copy(tmpV);
        const pl = track.at(sCar + 26, LANE_OFFSET - 1.1 + steerSm * 1.5);
        wantLook.set(pl.x, 1.66, pl.z);
        fov = vfov(40);
        snapInside = true;
      } else {
        car.updateMatrixWorld(true);
        tmpV.set(small ? 0 : -0.38, small ? 1.45 : 1.24, small ? 0.15 : 0.35);
        rig.localToWorld(tmpV);
        wantPos.copy(tmpV);
        const pl = track.at(sCar + 24, LANE_OFFSET - (small ? 0 : 0.38) + steerSm * 1.2 + (latBase - LANE_OFFSET));
        wantLook.set(pl.x, small ? 1.2 : 1.1, pl.z);
        fov = vfov(small ? 62 : 66) + sp * 2;
        snapInside = true;
      }
      if (topH !== null) {
        wantPos.set(car.position.x, topH, car.position.z + 0.01);
        wantLook.set(car.position.x, 0, car.position.z);
        cam.up.set(0, 0, -1);
        camSnap = 1;
      } else cam.up.set(0, 1, 0);
      const kk = 1 - Math.exp(-dt * (camSnap > 0 ? 14 : snapInside ? 14 : 5.5));
      camSnap = Math.max(0, camSnap - dt);
      if (snapInside && camSnap <= 0) camPos.copy(wantPos);
      else camPos.lerp(wantPos, kk);
      camLook.lerp(wantLook, 1 - Math.exp(-dt * (camSnap > 0 ? 14 : snapInside ? 10 : 6)));
      cam.position.copy(camPos);
      if (snapInside && !arrivedShot) cam.position.y += Math.sin(t * 13) * 0.003 * Math.min(1, speed / 6);
      if (shake > 0) {
        cam.position.x += Math.sin(t * 61) * shake * 0.16;
        cam.position.y += Math.cos(t * 53) * shake * 0.1;
      }
      cam.lookAt(camLook);
      if (Math.abs(cam.fov - fov) > 0.05) {
        cam.fov += (fov - cam.fov) * kk;
        cam.updateProjectionMatrix();
      }
      const inside = snapInside && !arrivedShot;
      cockpit.group.visible = inside && !isBus;
      carMesh.visible = !inside;
      wheels.visible = carMesh.visible;
      if (busRig) {
        busRig.interior.visible = inside;
        busRig.doors.visible = !inside;
        if (board) board.mesh.visible = !inside;
      }
      shadow.visible = !inside;
      beams.forEach((b, i) => (b.visible = wide ? i === 0 : true));
      tails.forEach((m) => (m.visible = !inside));
      dents.forEach((d) => (d.visible = !inside && cnd < 60));
      smokeMat.opacity = inside ? 0.35 : 0.75;
      if (stars) stars.position.copy(cam.position);
      ground.position.x = cam.position.x;
      ground.position.z = cam.position.z;
    };

    st.current = {
      tick,
      api,
      dispose() {
        if (placeTimer !== null) window.clearTimeout(placeTimer);
        scene.remove(root);
        cam.remove(cockpit.group);
        scene.fog = null;
        scene.background = null;
        skyTex?.dispose();
        ev?.props.dispose();
        gate?.g.dispose();
        cockpit.dispose();
        pool.forEach((e) => e.street?.dispose());
        place?.dispose();
        roundMuseum?.dispose();
        busRig?.dispose();
        board?.dispose();
        stopRigs.forEach((s) => s.rig.dispose());
        owned.forEach((o) => o.dispose());
        npcMesh.forEach((m) => m.dispose());
        slowMeshes.forEach((m) => m.dispose());
        glow.dispose();
        cam.remove(rainStreaks);
        wheels.dispose();
        signs.forEach((sg) => sg.s.board.geometry.dispose());
      },
    };
    P.current.onReady?.(api);
    return () => {
      st.current?.dispose();
      st.current = null;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [lookKey, scene, camera, gl]);

  // context loss
  useEffect(() => {
    const el = gl.domElement;
    const lost = (e: Event) => {
      e.preventDefault();
      P.current.onLost?.();
    };
    el.addEventListener('webglcontextlost', lost);
    return () => el.removeEventListener('webglcontextlost', lost);
  }, [gl]);

  useFrame((_, dt) => {
    st.current?.tick(dt);
  });
  return null;
}

export default function DriveScene(props: DriveSceneProps) {
  return (
    <div className="drive-canvas">
      <Canvas
        key={props.tier}
        dpr={props.tier === 'low' ? [1, 1.1] : [1, 1.6]}
        frameloop={props.paused ? 'never' : 'always'}
        camera={{ fov: 55, near: 0.1, far: 400, position: [0, 3, 8] }}
        gl={{ antialias: props.tier === 'high', powerPreference: 'low-power', alpha: false }}
      >
        <Rig {...props} />
      </Canvas>
      <div className="drive-tags" aria-hidden="true">
        {props.others.slice(0, 8).map((o) => (
          <div key={o.id} data-id={o.id} className="drive-tag">
            {o.name}
          </div>
        ))}
      </div>
    </div>
  );
}

