// Free roam: the live 3D city scene (react-three-fiber). Lazy-loaded through ../RoamView.tsx.
// One frame loop does everything with refs (no React state per frame): fixed 60 Hz physics steps (player or car, traffic, pedestrians,
// collision), then the visuals (camera with collision, character poses, instanced traffic, day/night, rain). The city is streamed in
// chunks (stream.ts): a few milliseconds a frame build the next chunk, chunks left behind are disposed; see docs/ROAM.md.
import { Canvas, useFrame, useThree } from '@react-three/fiber';
import { useEffect, useRef, type MutableRefObject } from 'react';
import {
  AdditiveBlending,
  BackSide,
  BufferGeometry,
  Color,
  CylinderGeometry,
  DirectionalLight,
  DynamicDrawUsage,
  Float32BufferAttribute,
  Fog,
  Group,
  HemisphereLight,
  InstancedMesh,
  LineBasicMaterial,
  LineSegments,
  Matrix4,
  Mesh,
  MeshBasicMaterial,
  MeshLambertMaterial,
  PerspectiveCamera,
  PlaneGeometry,
  PointLight,
  Quaternion,
  SphereGeometry,
  Vector3,
} from 'three';
import type { AvatarConfig } from '../../../lib/types';
import { defaultAvatar, randomAvatar } from '../../avatar3d/catalog';
import { applyPose, capturePose, gaitFor, mixPose, poseGait, poseIdle, POSE_SIZE, resetRig, stepLength } from '../../avatar3d/engine/anim';
import { buildCrowdRig, type CrowdRig } from '../../avatar3d/engine/crowd';
import { cityLight } from '../../city3d/engine/light';
import { roadRoute } from '../../city3d/route';
import { ROAD_NAME, type VehicleKind } from '../../drive3d/model';
import { AREA, PLAYER_R, SPEED } from '../area';
import { bodyClear, CAR_SPECS, makeCarState, parkLegal, stepCar, takeReport, type CarInput, type CarKind, type CarState } from '../carphys';
import { planRoute, routeProgress, type GpsRoute } from '../gps';
import { BUSY, Peds } from '../peds';
import { makePlayer, placePlayer, stepPlayer, type PlayerState } from '../player';
import { SPAWN_SAFE, Traffic } from '../traffic';
import { SHOP_NAMES, type RoamWorld } from '../world';
import { busGeometry, carGeometry, kekeGeometry, okadaGeometry } from './cars';
import { CarRig, KIND_OF } from './carview';
import { Soup } from './soup';
import { Streamer, type StreamStats } from './stream';
import { makeKit, makeSignAtlas } from './street';

export interface RoamInput {
  /** Stick: x right, y forward (-1..1). */
  sx: number;
  sy: number;
  run: boolean;
  /** Camera look deltas (radians), consumed by the scene. */
  lookX: number;
  lookY: number;
  /** Driving: the hand brake button. */
  brake: boolean;
}

export interface CarLive {
  /** The player's vehicle stands in the street (parked or being driven). */
  here: boolean;
  driving: boolean;
  /** Standing at the driver's door (can get in). */
  nearDoor: boolean;
  /** Metres to the driver's door / to the car. */
  doorDist: number;
  /** Speed (m/s, signed) and metres driven since the last report. */
  v: number;
  /** Hits since the last report (the view sends them to the server). */
  pendingDist: number;
  pendingHits: number;
  /** Stopped at a legal spot (may get out). */
  canPark: boolean;
  /** Seconds since the last crash (camera shake / HUD flash). */
  sinceHit: number;
  /** The car is moving fast enough to rain-skid etc. */
  braking: boolean;
  /** Car position (map units) for the mini-map. */
  x: number;
  y: number;
  h: number;
  /** Rolled to a stop with an empty tank this frame. */
  dry: boolean;
}

export interface RoamLive {
  x: number;
  y: number;
  h: number;
  speed: number;
  /** Place whose door the player is at (or null) and the distance to its standing spot. */
  nearId: string | null;
  nearDist: number;
  /** Street name under the player ('' when none). */
  street: string;
  /** Metres left on the GPS route (null = no route). */
  left: number | null;
  /** The GPS route as map points (null = none). */
  route: [number, number][] | null;
  /** A seller or neighbour is close enough to talk to. */
  nearTalk: boolean;
  /** Camera look direction (map angle) for the mini-map. */
  camYaw: number;
  running: boolean;
  /** Seconds since the scene started (for tests). */
  t: number;
  ready: boolean;
  /** Chunks built / queued (loading screen). */
  loaded: number;
  car: CarLive;
  /** Standing on a pavement beside a road a keke can stop at (hail keke is offered). */
  atKerb: boolean;
}

export interface CarApi {
  has(): boolean;
  /** Bring the car to the nearest free kerb 8..45 m away (it fades in there). */
  summon(): 'ok' | 'none' | 'no_spot';
  /** Park the car at an exact pose (restore / dev). */
  place(x: number, y: number, h: number): void;
  /** Get in (must be at the driver's door). */
  enter(): boolean;
  /** Get out at a legal spot. */
  exit(): 'ok' | 'moving' | 'illegal' | 'blocked' | 'none';
  /** Metres driven, hits and the car's pose since the last call. */
  takeReport(): { dist: number; light: number; hard: number; x: number; y: number; a: number };
  /** Roll to a stop and park at the side wherever it is (out of fuel: pushed to the kerb). */
  pushToKerb(): void;
  /** Remove the car from the street (taken away, mechanic gone). */
  remove(): void;
  state(): { x: number; y: number; h: number; v: number };
}

export interface RoamApi {
  stats(): { calls: number; triangles: number; geometries: number; textures: number; staticTris: number; rigs: number; cars: number; programs: number };
  stream(): StreamStats & { geometries: number; textures: number; heapMB: number; tickAvgMs: number; tickMaxMs: number; tickOver8: number; ticks: number };
  resetPerf(): void;
  teleport(x: number, y: number, h?: number): void;
  cam(p: { yaw?: number; pitch?: number; dist?: number }): void;
  state(): Record<string, number | string | boolean>;
  setDebug(on: boolean): void;
  car: CarApi;
  /** Dev: make sure the chunks round the player are built now (screenshots, scripted walks). */
  settle(maxMs?: number): void;
  /** Dev / tests: run the physics for this many simulated seconds right now (no rendering in between). */
  advance(sec: number): void;
  /** Dev / tests: set the stick (x right, y forward) and the hand brake. */
  setInput(sx: number, sy: number, brake?: boolean): void;
  /** Dev / tests: a scripted walker or driver that follows a route to random places (walk: the GPS route, drive: the road network), forever. null = off. */
  auto(o: { mode: 'walk' | 'drive'; run?: boolean; speed?: number; dest?: { x: number; y: number } } | null): void;
  world: RoamWorld;
}

export interface RoamSceneProps {
  world: RoamWorld;
  avatar: AvatarConfig | null;
  hour: number;
  tier: 'low' | 'high';
  start: { x: number; y: number; h: number; camYaw?: number };
  input: MutableRefObject<RoamInput>;
  live: MutableRefObject<RoamLive>;
  dest: { x: number; y: number } | null;
  firstPerson: boolean;
  paused?: boolean;
  debug?: boolean;
  /** Dev: seconds of simulated time to run before the first frame (traffic spread). */
  warm?: number;
  seed?: number;
  /** Dev (screenshots): camera yaw / pitch at the start. */
  cam?: { yaw?: number; pitch?: number; dist?: number };
  /** The player's own vehicle (null = none). */
  vehicle?: { kind: VehicleKind; color: number } | null;
  /** Where the car stands when the street opens (null = it is at home: Get my car brings it). */
  carStart?: { x: number; y: number; h: number } | null;
  /** The engine can run (fuel left, not wrecked). */
  engine?: boolean;
  /** Raining. */
  wet?: boolean;
  /** Driving camera. */
  camMode?: 'chase' | 'inside';
  /** Condition 0..100 (smoke, warning). */
  cond?: number;
  /** Dev: start in the driver's seat. */
  startDriving?: boolean;
  /** Streaming radius for the detailed chunks (m, the server's roam.chunk.load_m). */
  loadM?: number;
  onReady?: (api: RoamApi) => void;
  onLost?: () => void;
}

const clamp = (v: number, a: number, b: number) => Math.max(a, Math.min(b, v));
const FIXED = 1 / 60;
/** JS time of the scene's own frame work (physics, streaming slice, poses), not the GPU: read through api.stream(). */
const perfStat = { n: 0, sum: 0, max: 0, over8: 0 };

interface RigSlot {
  rig: CrowdRig | null;
  g: Group;
  bufA: Float32Array;
  bufB: Float32Array;
  salt: number;
  kind: 'player' | 'ped';
  ped: number;
  frame: number;
}

function Rig(props: RoamSceneProps) {
  const { gl, scene, camera } = useThree();
  const P = useRef(props);
  P.current = props;
  const ref = useRef<{ tick(dt: number): void; dispose(): void; setHour(h: number): void } | null>(null);

  useEffect(() => {
    const W = props.world;
    const low = props.tier === 'low';
    const root = new Group();
    scene.add(root);
    const owned: { dispose(): void }[] = [];
    const own = <T extends { dispose(): void }>(o: T) => (owned.push(o), o);
    const cam = camera as PerspectiveCamera;
    cam.near = 0.15;
    cam.far = 560;
    cam.fov = 62;
    cam.updateProjectionMatrix();
    scene.add(cam);

    /* ---------- lights, fog, sky ---------- */
    const hemi = new HemisphereLight('#ffffff', '#b7a58f', 1.5);
    const sun = new DirectionalLight('#fff1dc', 2);
    const fill = new DirectionalLight('#dfe8ff', 0.5);
    // a soft warm light that walks with the player at night (the street lamps are few)
    const glowLight = new PointLight('#ffe2b8', 0, 15, 1.5);
    root.add(hemi, sun, sun.target, fill, glowLight);
    const fogNear = low ? 45 : 60;
    const fogFar = low ? 270 : 340;
    const fog = new Fog('#cfe5f1', fogNear, fogFar);
    scene.fog = fog;
    scene.background = new Color('#cfe5f1');
    const skyGeo = own(new SphereGeometry(500, 18, 10));
    const skyCols = new Float32Array(skyGeo.attributes.position.count * 3);
    skyGeo.setAttribute('color', new Float32BufferAttribute(skyCols, 3));
    const sky = new Mesh(skyGeo, own(new MeshBasicMaterial({ vertexColors: true, side: BackSide, fog: false, depthWrite: false })));
    sky.renderOrder = -10;
    sky.frustumCulled = false;
    root.add(sky);
    // the land beyond the city edge (the fog hides where it ends)
    const plainMat = own(new MeshLambertMaterial({ color: '#a8b378' }));
    const plain = new Mesh(own(new PlaneGeometry(2600, 2600).rotateX(-Math.PI / 2)), plainMat);
    plain.position.y = -0.12;
    plain.frustumCulled = false;
    root.add(plain);

    /* ---------- the city, streamed ---------- */
    const signs = typeof document !== 'undefined' ? makeSignAtlas([...W.places.map((p) => ({ label: p.label, accent: p.accent })), ...SHOP_NAMES.map((n, i) => ({ label: n, accent: i >= 8 ? '#8d5a2b' : ['#c0643f', '#2e9d58', '#5c7fb5', '#d9822b', '#7a4ac8', '#3f7f9c', '#c0643f', '#2e9d58'][i] })), { label: 'Under construction', accent: '#c9882b' }]) : null;
    const kit = makeKit(W, { tier: props.tier, signs, uncIdx: W.places.length + SHOP_NAMES.length });
    const streamer = new Streamer(W, kit, low, P.current.loadM ?? 200);
    root.add(streamer.root);

    /* ---------- traffic ---------- */
    const traffic = new Traffic(W.L);
    const vMat = own(new MeshLambertMaterial({ vertexColors: true, flatShading: true }));
    const kinds = ['car', 'bus', 'keke', 'okada'] as const;
    const geos = { car: own(carGeometry()), bus: own(busGeometry()), keke: own(kekeGeometry()), okada: own(okadaGeometry()) };
    const inst = {} as Record<(typeof kinds)[number], InstancedMesh>;
    for (const k of kinds) {
      const n = traffic.cars.filter((c) => c.kind === k).length;
      const m = new InstancedMesh(geos[k], vMat, Math.max(1, n));
      m.instanceMatrix.setUsage(DynamicDrawUsage);
      m.frustumCulled = false;
      m.count = 0;
      root.add(m);
      inst[k] = m;
    }
    const carColor = new Color();

    /* ---------- people ---------- */
    const peds = new Peds(W, { walkers: low ? 8 : 16, sellers: low ? 4 : 8, idlers: low ? 1 : 3, seed: (props.seed ?? 1) * 7 + 3, around: { x: props.start.x, y: props.start.y } });
    const player: PlayerState = makePlayer(props.start.x, props.start.y, props.start.h);
    placePlayer(player, W.col, props.start.x, props.start.y, props.start.h);
    const slots: RigSlot[] = [];
    const wantAvatar = (i: number): AvatarConfig => {
      const female = i % 2 === 1;
      try {
        return randomAvatar(female ? 'female' : 'male');
      } catch {
        return defaultAvatar(female ? 'female' : 'male');
      }
    };
    const makeSlot = (kind: 'player' | 'ped', ped: number, avatar: AvatarConfig, detail: number): RigSlot => {
      const g = new Group();
      const slot: RigSlot = { rig: null, g, bufA: new Float32Array(POSE_SIZE), bufB: new Float32Array(POSE_SIZE), salt: Math.random() * 10, kind, ped, frame: 0 };
      try {
        slot.rig = buildCrowdRig(avatar, detail);
        g.add(slot.rig.ch.root);
      } catch {
        slot.rig = null;
      }
      g.visible = false;
      root.add(g);
      slots.push(slot);
      return slot;
    };
    const playerSlot = makeSlot('player', -1, P.current.avatar ?? defaultAvatar('male'), low ? 0.4 : 0.65);
    const pending: number[] = [];
    peds.list.forEach((_, i) => pending.push(i));
    pending.sort((a, b) => Math.hypot(peds.list[a].x - props.start.x, peds.list[a].y - props.start.y) - Math.hypot(peds.list[b].x - props.start.x, peds.list[b].y - props.start.y));
    let lastBuild = 0;
    const tune = playerSlot.rig ? gaitFor(playerSlot.rig.ch, { speed: SPEED.walk, robeMult: 0.7 }) : { cruise: 1.9, strideScale: 1 };

    /* ---------- the player's own vehicle ---------- */
    const veh = P.current.vehicle ?? null;
    const carKind: CarKind = veh ? KIND_OF[veh.kind] : 'sedan';
    const spec = CAR_SPECS[carKind];
    const carRig = veh ? new CarRig(veh.kind, veh.color) : null;
    if (carRig) {
      root.add(carRig.group);
      carRig.group.visible = false;
      cam.add(carRig.cockpit.group);
      carRig.cockpit.group.visible = false;
    }
    const car: CarState = makeCarState(0, 0, 0);
    const drv = { here: false, driving: false, fade: 1, parkedBox: { x: 0, y: 0, hl: spec.len / 2, hw: spec.wid / 2, a: 0, id: 777000, v: 0 }, sinceHit: 9, dry: false, pendDist: 0, pendHits: 0, lastKmh: 0 };
    const input0: CarInput = { steer: 0, throttle: 0, brake: 0 };
    const carEnv = { engine: true, wet: Boolean(P.current.wet), people: [] as { x: number; y: number; r: number }[], roadClear: (x: number, y: number) => W.L.net.clear(x, y, false, 6) };
    // the car as circles for the traffic to brake for
    const carPeople: { x: number; y: number; r: number }[] = [];
    for (let i = 0; i < 3; i++) carPeople.push({ x: 0, y: 0, r: spec.wid / 2 * 1.08 });
    const carDoor = { x: 0, y: 0 };
    const updateDoor = () => {
      const lx = Math.sin(car.h), ly = -Math.cos(car.h);
      const fx = Math.cos(car.h), fy = Math.sin(car.h);
      carDoor.x = car.x + lx * (spec.wid / 2 + 0.75) + fx * 0.35;
      carDoor.y = car.y + ly * (spec.wid / 2 + 0.75) + fy * 0.35;
    };
    const placeCar = (x: number, y: number, h: number) => {
      car.x = x; car.y = y; car.h = h; car.v = 0; car.steer = 0; car.yaw = 0; car.roll = 0; car.pitch = 0;
      drv.here = true;
      drv.fade = 0;
      if (carRig) carRig.group.visible = true;
      updateDoor();
    };
    if (veh && P.current.carStart) placeCar(P.current.carStart.x, P.current.carStart.y, P.current.carStart.h);
    if (drv.here) drv.fade = 1;

    /* ---------- GPS ---------- */
    const routeMat = own(new MeshBasicMaterial({ color: '#1fc27e', transparent: true, opacity: 0.92, depthWrite: false }));
    const routeMesh = new Mesh(new BufferGeometry(), routeMat);
    routeMesh.frustumCulled = false;
    routeMesh.renderOrder = 4;
    root.add(routeMesh);
    const beamGeo = own(new CylinderGeometry(0.7, 0.7, 14, 12, 1, true));
    beamGeo.translate(0, 7, 0);
    const beamMat = own(new MeshBasicMaterial({ color: '#ffb703', transparent: true, opacity: 0.28, depthWrite: false, blending: AdditiveBlending }));
    const beam = new Mesh(beamGeo, beamMat);
    beam.visible = false;
    beam.renderOrder = 5;
    root.add(beam);
    // a marker over the parked car so it can be found
    const carBeamMat = own(new MeshBasicMaterial({ color: '#3da9fc', transparent: true, opacity: 0.35, depthWrite: false, blending: AdditiveBlending }));
    const carBeam = new Mesh(beamGeo, carBeamMat);
    carBeam.visible = false;
    carBeam.renderOrder = 5;
    root.add(carBeam);
    let route: GpsRoute | null = null;
    let routeSeg = -1;
    let routeFor = '';
    let replanAt = 0;

    /* ---------- rain streaks (one line mesh on the camera) ---------- */
    const RAIN_N = low ? 46 : 96;
    const rainPos = new Float32Array(RAIN_N * 6);
    const rainSeed = new Float32Array(RAIN_N * 3);
    for (let i = 0; i < RAIN_N; i++) {
      rainSeed[i * 3] = (Math.random() - 0.5) * 16;
      rainSeed[i * 3 + 1] = Math.random() * 9;
      rainSeed[i * 3 + 2] = -1 - Math.random() * 12;
    }
    const rainGeo = own(new BufferGeometry());
    rainGeo.setAttribute('position', new Float32BufferAttribute(rainPos, 3).setUsage(DynamicDrawUsage));
    const rain = new LineSegments(rainGeo, own(new LineBasicMaterial({ color: '#d4e3f2', transparent: true, opacity: 0.4, depthWrite: false })));
    rain.frustumCulled = false;
    rain.visible = false;
    cam.add(rain);

    /* ---------- debug overlay ---------- */
    let dbg: LineSegments | null = null;
    let dbgOn = Boolean(props.debug);
    let dbgAt = -1;
    const dbgBuf = new Float32Array(3 * 2 * 9000);
    const setDebug = (on: boolean) => {
      dbgOn = on;
      if (!on && dbg) dbg.visible = false;
    };

    /* ---------- camera state ---------- */
    const camSt = { yaw: props.cam?.yaw ?? -Math.PI / 2, pitch: props.cam?.pitch ?? 0.3, dist: props.cam?.dist ?? 5.2, d: 5.2, x: 0, y: 2, z: 0, init: false, hideBody: false, cx: 0, cz: 0, cy: 3, lx: 0, lz: 0, drvInit: false };
    if (props.cam?.yaw === undefined) camSt.yaw = props.start.camYaw ?? props.start.h;
    const live = P.current.live;
    const roadGrid = new Map<number, { id: string; x: number; y: number; hw: number }[]>();
    for (const ri of W.roadIdx) {
      const r = W.L.roads[ri];
      for (let i = 0; i < r.sp.samples.length; i += 2) {
        const s = r.sp.samples[i];
        const k = Math.floor(s.x / 24) * 1000 + Math.floor(s.y / 24);
        const arr = roadGrid.get(k);
        const e = { id: r.id, x: s.x, y: s.y, hw: r.hw };
        if (arr) arr.push(e);
        else roadGrid.set(k, [e]);
      }
    }
    const streetAt = (x: number, y: number): string => {
      let best = 1e9, name = '';
      const cx = Math.floor(x / 24), cy = Math.floor(y / 24);
      for (let j = -1; j <= 1; j++)
        for (let i = -1; i <= 1; i++) {
          const arr = roadGrid.get((cx + i) * 1000 + (cy + j));
          if (!arr) continue;
          for (const e of arr) {
            const d = Math.hypot(e.x - x, e.y - y) - e.hw;
            if (d < best) { best = d; name = e.id; }
          }
        }
      if (best < 7) return ROAD_NAME[name] ?? '';
      if (Math.hypot(x - 500, y - 500) < 52) return "King's Square";
      return '';
    };

    /* ---------- day / night ---------- */
    let lastLight = '';
    let dark = 0;
    let wetNow = 0;
    const tmpC = new Color();
    const mixC = (a: string, b: string, t: number) => tmpC.set(a).lerp(new Color(b), t);
    const applyLight = (hour: number) => {
      const c = cityLight(hour);
      const wet = P.current.wet ? 1 : 0;
      const key = `${Math.round(c.dark * 40)}|${c.sky}|${wet}`;
      if (key === lastLight) return;
      lastLight = key;
      dark = c.dark;
      wetNow = wet;
      hemi.color.set(c.hemiSky);
      hemi.groundColor.set(c.hemiGround).lerp(new Color(c.hemiSky), 0.3);
      hemi.intensity = c.hemi * (1.25 + 0.9 * c.dark) * (wet ? 0.82 : 1);
      glowLight.intensity = clamp((c.dark - 0.3) / 0.5, 0, 1) * 7.5;
      fill.intensity = 0.2 + (1 - c.dark) * 0.5 + c.dark * 0.35;
      sun.color.set(c.sun);
      sun.intensity = c.sunI * 0.62 * (wet ? 0.55 : 1);
      const skyCol = wet ? new Color(c.sky).lerp(new Color(c.dark > 0.5 ? '#10131c' : '#8f9aa6'), 0.55) : tmpC.set(c.sky);
      fog.color.copy(skyCol);
      fog.far = (low ? 270 : 340) * (wet ? 0.7 : 1);
      (scene.background as Color).copy(skyCol);
      const top = new Color(skyCol).lerp(new Color(c.dark > 0.5 ? '#0b1030' : wet ? '#7d8791' : '#6fa6dc'), c.dark > 0.5 ? 0.8 : 0.6);
      const hor = new Color(skyCol);
      const pos = skyGeo.attributes.position;
      const colAttr = skyGeo.attributes.color as Float32BufferAttribute;
      for (let i = 0; i < pos.count; i++) {
        const t = clamp((pos.getY(i) / 500) * 1.6, 0, 1);
        tmpC.copy(hor).lerp(top, t * t);
        colAttr.setXYZ(i, tmpC.r, tmpC.g, tmpC.b);
      }
      colAttr.needsUpdate = true;
      const night = clamp((c.dark - 0.3) / 0.4, 0, 1);
      kit.mats.glassLit.color.copy(mixC('#78a0b6', '#ffd27a', night));
      kit.mats.glow.color.copy(mixC('#cfc9bb', '#fff1c2', night));
      kit.mats.glowLand.color.copy(mixC('#9db4c4', '#ffd27a', night));
      kit.mats.sign.color.copy(mixC('#ffffff', '#e9e3d4', night));
      kit.mats.solid.color.set(wet ? '#d3d8dc' : '#ffffff');
      streamer.poolMat.opacity = clamp((c.dark - 0.25) / 0.5, 0, 1) * 0.85;
      streamer.poolMat.visible = streamer.poolMat.opacity > 0.01;
      streamer.blobMat.opacity = 1 - 0.5 * night;
      plainMat.color.set(wet ? '#8f9a6c' : '#a8b378').multiplyScalar(1 - 0.55 * c.dark);
    };
    applyLight(props.hour);

    /* ---------- dynamic blob shadows for people and cars ---------- */
    const MAX_BLOBS = 90;
    const blobs = new InstancedMesh(streamer.flat, streamer.blobMat, MAX_BLOBS);
    blobs.instanceMatrix.setUsage(DynamicDrawUsage);
    blobs.frustumCulled = false;
    blobs.renderOrder = 2;
    blobs.count = 0;
    root.add(blobs);

    /* ---------- the frame ---------- */
    const m4 = new Matrix4();
    const q = new Quaternion();
    const v3 = new Vector3();
    const s3 = new Vector3();
    const yAxis = new Vector3(0, 1, 0);
    const people: { x: number; y: number; r: number }[] = [];
    const trafficPeople: { x: number; y: number; r: number }[] = [];
    const focus = { x: props.start.x, y: props.start.y };
    const carObs = { x: 0, y: 0, a: 0, speed: 0 };
    let acc = 0;
    let simT = 0;
    let frameN = 0;
    let lastDestKey = '';
    let lastNearAt = 0;
    let lastStreetAt = 0;
    let lastRecycle = 0;
    let streetName = '';
    let gaitRun = 0;
    let ready = false;
    let headDirX = Math.cos(props.start.h), headDirY = Math.sin(props.start.h);

    const syncTrafficPeople = () => {
      trafficPeople.length = 0;
      for (let i = 0; i < people.length; i++) trafficPeople.push(people[i]);
      if (drv.here) {
        const ch = Math.cos(car.h), sh = Math.sin(car.h);
        for (let i = 0; i < 3; i++) {
          const u = (i - 1) * (spec.len / 2 - spec.wid / 2);
          carPeople[i].x = car.x + ch * u;
          carPeople[i].y = car.y + sh * u;
          trafficPeople.push(carPeople[i]);
        }
      }
    };

    const stepSim = (dt: number) => {
      const I = P.current.input.current;
      peds.people(people);
      if (drv.driving) {
        // ---- in the car
        input0.steer = I.sx;
        input0.throttle = Math.max(0, I.sy);
        input0.brake = Math.max(I.brake ? 1 : 0, Math.max(0, -I.sy));
        carEnv.engine = P.current.engine !== false;
        carEnv.wet = Boolean(P.current.wet);
        carEnv.people = people;
        syncTrafficPeople();
        traffic.step(dt, trafficPeople, focus);
        traffic.publish(W.col, car.x, car.y, 70);
        carObs.x = car.x; carObs.y = car.y; carObs.a = car.h; carObs.speed = Math.abs(car.v);
        peds.step(dt, W.col, car, carObs);
        const hardBefore = car.hard + car.light;
        stepCar(car, spec, W.col, dt, input0, carEnv);
        if (car.hard + car.light > hardBefore) drv.sinceHit = 0;
        player.x = car.x; player.y = car.y; player.h = car.h; player.speed = Math.abs(car.v);
        // out of fuel: it rolls to a stop
        drv.dry = !carEnv.engine && Math.abs(car.v) < 0.3;
      } else {
        people.push({ x: player.x, y: player.y, r: PLAYER_R });
        syncTrafficPeople();
        traffic.step(dt, trafficPeople, focus);
        traffic.publish(W.col, player.x, player.y, 45);
        if (drv.here) {
          // the parked car is a solid box for the player (and a circle row for the traffic)
          drv.parkedBox.x = car.x; drv.parkedBox.y = car.y; drv.parkedBox.a = car.h;
          W.col.dynBoxes.push(drv.parkedBox);
        }
        peds.step(dt, W.col, player);
        const wx = Math.cos(camSt.yaw) * I.sy + -Math.sin(camSt.yaw) * I.sx;
        const wy = Math.sin(camSt.yaw) * I.sy + Math.cos(camSt.yaw) * I.sx;
        stepPlayer(player, W.col, dt, wx, wy, I.run);
        // a parked car rolls on its own if somebody left it moving: settle it
        if (drv.here && Math.abs(car.v) > 0.01) car.v = 0;
      }
      drv.sinceHit += dt;
      simT += dt;
    };

    const pose = (slot: RigSlot, t: number, x: number, y: number, h: number, speed: number, moved: number, gait: number, ps: { phase: number }, runK: number, cheap: boolean) => {
      const rig = slot.rig;
      slot.g.position.set(x, 0, y);
      slot.g.rotation.y = Math.PI / 2 - h;
      if (!rig) return;
      const ch = rig.ch;
      if (cheap) return;
      if (gait > 0.02) {
        const ss = (slot.kind === 'player' ? tune.strideScale : 0.9) * (1 + 0.7 * runK);
        ps.phase += moved / (2 * stepLength(ch, Math.max(0.3, gait), ss));
        resetRig(ch);
        poseGait(ch, ps.phase, gait, { strideScale: ss });
        if (runK > 0.05) {
          const r = ch.rig;
          r.chest.rotation.x += 0.2 * runK;
          r.armL.rotation.x *= 1 + 0.9 * runK;
          r.armR.rotation.x *= 1 + 0.9 * runK;
          r.foreL.rotation.x -= 0.8 * runK;
          r.foreR.rotation.x -= 0.8 * runK;
          r.body.rotation.x = 0.08 * runK;
        }
        if (gait < 0.98) {
          // blend from the idle pose while speeding up / stopping
          capturePose(ch, slot.bufB);
          poseIdle(ch, t, slot.salt);
          capturePose(ch, slot.bufA);
          const e = gait * gait * (3 - 2 * gait);
          applyPose(ch, mixPose(slot.bufB, slot.bufA, slot.bufB, e));
        }
      } else {
        poseIdle(ch, t, slot.salt);
      }
      void speed;
    };
    const pedPhase: { phase: number }[] = peds.list.map((p) => ({ phase: p.phase }));
    const playerPhase = { phase: 0 };

    // a phone held upright sees a narrow slice: widen the vertical field of view when the screen is taller than wide
    const fovBase = (first: boolean) => {
      const asp = cam.aspect || 1;
      return asp < 1 ? (first ? 84 : 74) : first ? 76 : 62;
    };
    const vfov = (hDeg: number) => {
      const asp = cam.aspect || 1;
      return asp >= 1 ? hDeg : (2 * Math.atan(Math.tan((hDeg * Math.PI) / 360) / asp) * 180) / Math.PI;
    };
    const tmpV = new Vector3();

    /* ---------- car actions ---------- */
    const freeOfPeople = (x: number, y: number, rad: number): boolean => {
      for (const p of people) if ((p.x - x) ** 2 + (p.y - y) ** 2 < (rad + p.r) ** 2) return false;
      if (!drv.driving && (player.x - x) ** 2 + (player.y - y) ** 2 < rad * rad) return false;
      for (const c of traffic.cars) if ((c.x - x) ** 2 + (c.y - y) ** 2 < (rad + 2) ** 2) return false;
      return true;
    };
    /** Nearest free kerb spot at 8..45 m from (px, py), car parallel to the road, clear of everything. */
    const findKerb = (px: number, py: number): { x: number; y: number; h: number } | null => {
      let best: { x: number; y: number; h: number } | null = null, bd = Infinity;
      const L = W.L;
      for (const ri of W.roadIdx) {
        const rd = L.roads[ri];
        if (rd.kind === 'dirt' && rd.hw < 3) continue;
        const S = rd.sp.samples;
        for (let i = 0; i < S.length; i += 2) {
          const s = S[i];
          if (Math.abs(s.x - px) > 60 || Math.abs(s.y - py) > 60) continue;
          for (const side of [1, -1]) {
            const off = rd.hw - spec.wid / 2 - 0.15;
            const x = s.x - Math.sin(s.a) * off * side, y = s.y + Math.cos(s.a) * off * side;
            const d = Math.hypot(x - px, y - py);
            if (d < 8 || d > 45 || d >= bd) continue;
            if (L.net.clear(x, y, false, 8, ri) < 3.5) continue; // not at a junction
            // parked in the direction of the traffic of that side (drive on the right)
            const h = s.a + (side > 0 ? 0 : Math.PI);
            if (!bodyClear(W.col, spec, x, y, h, 0.25)) continue;
            if (!freeOfPeople(x, y, SPAWN_SAFE)) continue;
            bd = d;
            best = { x, y, h };
          }
        }
      }
      return best;
    };
    const exitSpot = (): { x: number; y: number } | null => {
      const lx = Math.sin(car.h), ly = -Math.cos(car.h);
      const fx = Math.cos(car.h), fy = Math.sin(car.h);
      const tries: [number, number][] = [];
      for (const along of [0.35, -0.6, 1.2]) {
        tries.push([car.x + lx * (spec.wid / 2 + 0.75) + fx * along, car.y + ly * (spec.wid / 2 + 0.75) + fy * along]);
      }
      for (const along of [0.35, -0.8]) tries.push([car.x - lx * (spec.wid / 2 + 0.75) + fx * along, car.y - ly * (spec.wid / 2 + 0.75) + fy * along]);
      tries.push([car.x - fx * (spec.len / 2 + 0.9), car.y - fy * (spec.len / 2 + 0.9)]);
      for (const [x, y] of tries) if (W.col.clear(x, y, PLAYER_R + 0.12, -1, false)) return { x, y };
      return null;
    };
    const carApi: CarApi = {
      has: () => Boolean(veh),
      summon: () => {
        if (!veh || !carRig) return 'none';
        const k = findKerb(player.x, player.y);
        if (!k) return 'no_spot';
        placeCar(k.x, k.y, k.h);
        return 'ok';
      },
      place: (x, y, h) => { if (veh) placeCar(x, y, h); drv.fade = 1; },
      enter: () => {
        if (!veh || !drv.here || drv.driving) return false;
        if (Math.hypot(player.x - carDoor.x, player.y - carDoor.y) > 3.2) return false;
        drv.driving = true;
        camSt.drvInit = false;
        return true;
      },
      exit: () => {
        if (!drv.driving) return 'none';
        if (Math.abs(car.v) > 1.6) return 'moving';
        if (!parkLegal(carEnv.roadClear(car.x, car.y))) return 'illegal';
        const sp = exitSpot();
        if (!sp) return 'blocked';
        car.v = 0;
        drv.driving = false;
        placePlayer(player, W.col, sp.x, sp.y, Math.atan2(-Math.cos(car.h), Math.sin(car.h)) + Math.PI);
        player.h = car.h - Math.PI / 2;
        camSt.yaw = car.h;
        camSt.init = false;
        updateDoor();
        return 'ok';
      },
      takeReport: () => {
        const r = takeReport(car);
        return { dist: r.dist, light: r.light, hard: r.hard, x: car.x, y: car.y, a: car.h };
      },
      pushToKerb: () => {
        // the car is pushed to the side of the road where it stopped
        car.v = 0;
        const rc = carEnv.roadClear(car.x, car.y);
        if (rc < -0.9) {
          const k = findKerb(car.x, car.y);
          if (k) { car.x = k.x; car.y = k.y; car.h = k.h; }
        }
        updateDoor();
      },
      remove: () => {
        drv.here = false;
        drv.driving = false;
        if (carRig) { carRig.group.visible = false; carRig.cockpit.group.visible = false; }
      },
      state: () => ({ x: car.x, y: car.y, h: car.h, v: car.v }),
    };
    if (P.current.startDriving && veh && drv.here) {
      placePlayer(player, W.col, carDoor.x, carDoor.y);
      drv.driving = true;
    }

    /* ---------- scripted walker / driver (dev and tests) ---------- */
    const autoS = { on: false, mode: 'walk' as 'walk' | 'drive', run: false, speed: 13, pts: [] as [number, number][], i: 0, stuck: 0, rev: 0, dest: null as { x: number; y: number } | null, picks: 0, plan: 0 };
    const autoPick = () => {
      const pl = W.places[(autoS.picks++ * 7 + 3) % W.places.length];
      autoS.dest = { x: pl.door.sx, y: pl.door.sy };
    };
    const autoPlan = () => {
      const fx = drv.driving ? car.x : player.x, fy = drv.driving ? car.y : player.y;
      if (!autoS.dest) autoPick();
      const d = autoS.dest!;
      if (autoS.mode === 'walk') {
        autoS.pts = planRoute(W, [fx, fy], [d.x, d.y]).pts.map((q2) => [q2[0], q2[1]] as [number, number]);
      } else {
        // along the road network, shifted into the right-hand lane
        const r = roadRoute({ x: fx, y: fy }, { x: d.x, y: d.y });
        const out: [number, number][] = [];
        for (let k = 0; k < r.length; k++) {
          const a = r[Math.max(0, k - 1)], b = r[Math.min(r.length - 1, k + 1)];
          const l = Math.hypot(b[0] - a[0], b[1] - a[1]) || 1;
          out.push([r[k][0] - ((b[1] - a[1]) / l) * 2.4, r[k][1] + ((b[0] - a[0]) / l) * 2.4]);
        }
        autoS.pts = out;
      }
      autoS.i = 0;
    };
    const autoStep = (dt: number) => {
      const I = P.current.input.current;
      const driving = drv.driving;
      const px = driving ? car.x : player.x, py = driving ? car.y : player.y;
      if (!autoS.pts.length || autoS.plan <= 0) { autoPlan(); autoS.plan = 12; }
      autoS.plan -= dt;
      const pts = autoS.pts;
      // closest point ahead, then a look-ahead target
      let best = autoS.i, bd = Infinity;
      for (let k = Math.max(0, autoS.i - 2); k < Math.min(pts.length, autoS.i + 12); k++) {
        const dd = Math.hypot(pts[k][0] - px, pts[k][1] - py);
        if (dd < bd) { bd = dd; best = k; }
      }
      autoS.i = best;
      const look = driving ? 10 + Math.abs(car.v) * 0.5 : 5;
      let ti = best;
      while (ti < pts.length - 1 && Math.hypot(pts[ti][0] - px, pts[ti][1] - py) < look) ti++;
      const tx = pts[ti][0], ty = pts[ti][1];
      const left = Math.hypot(pts[pts.length - 1][0] - px, pts[pts.length - 1][1] - py);
      if (left < (driving ? 14 : 3) || (ti >= pts.length - 1 && left < look)) { autoPick(); autoPlan(); return; }
      const want = Math.atan2(ty - py, tx - px);
      if (!driving) {
        camSt.yaw = want;
        I.sx = 0; I.sy = 1; I.run = autoS.run; I.brake = false;
        return;
      }
      let d = want - car.h;
      d = Math.atan2(Math.sin(d), Math.cos(d));
      const vt = autoS.speed * (1 - Math.min(0.65, Math.abs(d) * 0.8));
      if (autoS.rev > 0) {
        autoS.rev -= dt;
        I.sx = -Math.sign(d || 1) * 0.8; I.sy = -1; I.brake = false;
        return;
      }
      I.sx = Math.max(-1, Math.min(1, d * 1.8));
      I.sy = car.v < vt ? 1 : 0;
      I.brake = car.v > vt + 2;
      if (Math.abs(car.v) < 0.4 && I.sy > 0) autoS.stuck += dt; else autoS.stuck = 0;
      if (autoS.stuck > 1.5) { autoS.stuck = 0; autoS.rev = 1.1; }
    };

    const tick = (delta: number) => {
      const p = P.current;
      if (p.paused) return;
      frameN++;
      const dt = Math.min(0.1, delta);
      const driving = drv.driving;
      // the focus of the streaming and the far traffic: the player or the car
      focus.x = driving ? car.x : player.x;
      focus.y = driving ? car.y : player.y;
      if (driving && Math.abs(car.v) > 2) { headDirX = Math.cos(car.h) * Math.sign(car.v); headDirY = Math.sin(car.h) * Math.sign(car.v); }
      else if (!driving && player.speed > 0.6) { headDirX = Math.cos(player.h); headDirY = Math.sin(player.h); }
      // stream the city: a small slice of the frame (more until the first chunks are in)
      const speedNow = driving ? Math.abs(car.v) : player.speed;
      streamer.update(focus.x, focus.y, headDirX, headDirY, ready ? (low ? 3 : 4) + (speedNow > 12 ? 2 : 0) : 14);
      if (!ready) {
        if (streamer.ready(focus.x, focus.y, 70)) ready = true;
        live.current.loaded = streamer.stats().detail;
        cam.position.set(focus.x - Math.cos(camSt.yaw) * 6, 3, focus.y - Math.sin(camSt.yaw) * 6);
        cam.lookAt(focus.x, 1.5, focus.y);
        sun.position.set(focus.x + 40, 60, focus.y + 30);
        sun.target.position.set(focus.x, 0, focus.y);
        sun.target.updateMatrixWorld();
        sky.position.copy(cam.position);
        return;
      }
      if (autoS.on) autoStep(dt);
      // physics: fixed steps
      acc += dt;
      let n = 0;
      while (acc >= FIXED && n < 6) {
        stepSim(FIXED);
        acc -= FIXED;
        n++;
      }
      if (acc > FIXED * 6) acc = 0;
      const I = p.input.current;
      // look input (on foot; the driving cameras follow the car)
      if (!driving) {
        camSt.yaw += I.lookX;
        camSt.pitch = clamp(camSt.pitch + I.lookY, p.firstPerson ? -0.95 : -0.1, p.firstPerson ? 0.95 : 1.15);
      }
      I.lookX = 0;
      I.lookY = 0;
      const t = simT;
      applyLight(p.hour);

      // the crowd follows the player round a city much bigger than the screen
      if (t - lastRecycle > 0.6) {
        lastRecycle = t;
        const vx = driving ? Math.cos(car.h) : Math.cos(camSt.yaw), vy = driving ? Math.sin(car.h) : Math.sin(camSt.yaw);
        peds.recycle(focus.x, focus.y, { dx: vx, dy: vy });
      }
      void BUSY;

      /* the car on its own: fade-in after being called, lights, pose */
      if (carRig && drv.here) {
        if (drv.fade < 1) drv.fade = Math.min(1, drv.fade + dt / 0.7);
        const k = Math.max(0.01, drv.fade * drv.fade * (3 - 2 * drv.fade));
        carRig.group.scale.setScalar(k);
        carRig.setPose(car, dark, dark > 0.35);
        carRig.group.visible = !(driving && p.camMode === 'inside' && false);
        updateDoor();
      }

      /* player rig + camera */
      const fp = p.firstPerson;
      const speed = player.speed;
      const runK = clamp((speed - 2.6) / (SPEED.run - 2.6), 0, 1);
      gaitRun += (runK - gaitRun) * Math.min(1, dt * 6);
      const ps = playerSlot;
      ps.g.visible = !driving && !fp && !camSt.hideBody && Boolean(ps.rig);
      pose(ps, t, player.x, player.y, player.h, speed, player.moved * (acc >= 0 ? n : 1), player.gait, playerPhase, gaitRun, false);

      if (driving && carRig) {
        // ---- driving cameras: chase (behind, above, swings with the turn) or the driver's seat with the dashboard
        const inside = p.camMode === 'inside';
        const small = carKind === 'moto' || carKind === 'bike';
        const sp = Math.abs(car.v);
        if (inside) {
          carRig.group.updateMatrixWorld(true);
          tmpV.set(small ? 0 : -0.38, small ? 1.45 : 1.24, small ? 0.15 : 0.35);
          carRig.group.localToWorld(tmpV);
          cam.position.copy(tmpV);
          const look = 24;
          const ang = car.h + car.steer * 0.35;
          cam.lookAt(cam.position.x + Math.cos(ang) * look, small ? 1.2 : 1.1, cam.position.z + Math.sin(ang) * look);
          cam.fov += (vfov(small ? 62 : 66) + sp * 0.3 - cam.fov) * Math.min(1, dt * 6);
          carRig.cockpit.group.visible = !small || true;
          carRig.cockpit.steer(clamp(car.steer / 0.5, -1, 1));
          carRig.body.visible = false;
          camSt.drvInit = false;
        } else {
          carRig.cockpit.group.visible = false;
          carRig.body.visible = true;
          const back = small ? 7.2 : 9.4 + sp * 0.07;
          // the camera swings behind the car's heading with a little lag
          const wantH = car.h;
          if (!camSt.drvInit) { camSt.lx = Math.cos(wantH); camSt.lz = Math.sin(wantH); camSt.drvInit = true; }
          const kk = 1 - Math.exp(-dt * 3.6);
          camSt.lx += (Math.cos(wantH) - camSt.lx) * kk;
          camSt.lz += (Math.sin(wantH) - camSt.lz) * kk;
          const ll = Math.hypot(camSt.lx, camSt.lz) || 1;
          const bx = camSt.lx / ll, bz = camSt.lz / ll;
          // pull in where a building would be in the way
          const ex = car.x - bx * back, ez = car.y - bz * back;
          const f = W.col.rayTall(car.x, car.y, ex, ez, 0.4, 1.4, 3.4);
          const dd = Math.max(2.2, back * f);
          const ch = clamp(small ? 2.5 : 3.3, 0, 5);
          cam.position.set(car.x - bx * dd, ch + Math.abs(car.roll) * 3, car.y - bz * dd);
          cam.lookAt(car.x + bx * 5, 1.1, car.y + bz * 5);
          cam.fov += (vfov(small ? 52 : 58) + sp * 0.35 - cam.fov) * Math.min(1, dt * 5);
          camSt.hideBody = false;
        }
        // a crash shakes the camera
        if (drv.sinceHit < 0.4) {
          const sk = (0.4 - drv.sinceHit) * 0.14;
          cam.position.x += Math.sin(t * 61) * sk;
          cam.position.y += Math.cos(t * 53) * sk * 0.6;
        }
        cam.updateProjectionMatrix();
        camSt.init = false;
      } else if (carRig) {
        carRig.cockpit.group.visible = false;
        carRig.body.visible = true;
      }

      if (!driving) {
        // camera on foot
        const bobY = fp ? Math.sin(playerPhase.phase * Math.PI * 2 * 2) * 0.03 * player.gait : 0;
        if (fp) {
          const eye = 1.62 + bobY;
          const cx = player.x, cz = player.y;
          const dirx = Math.cos(camSt.yaw) * Math.cos(camSt.pitch * 0.9), dirz = Math.sin(camSt.yaw) * Math.cos(camSt.pitch * 0.9);
          const diry = -Math.sin(camSt.pitch * 0.9);
          cam.position.set(cx, eye, cz);
          cam.lookAt(cx + dirx, eye + diry, cz + dirz);
          cam.fov += (fovBase(true) + 4 * gaitRun - cam.fov) * Math.min(1, dt * 6);
          camSt.hideBody = true;
          camSt.init = false;
        } else {
          // over the shoulder: pivot above the right shoulder, camera behind along the look direction, pulled in by walls
          const rx = -Math.sin(camSt.yaw), rz = Math.cos(camSt.yaw);
          const dirx = Math.cos(camSt.yaw), dirz = Math.sin(camSt.yaw);
          const cp = Math.cos(camSt.pitch), sp = Math.sin(camSt.pitch);
          const want = camSt.dist + gaitRun * 0.5;
          // the ray starts at the body, so a wall right behind the player pulls the camera in at once
          const ex = player.x - dirx * want * cp + rx * 0.42, ez = player.y - dirz * want * cp + rz * 0.42;
          const f = W.col.rayTall(player.x, player.y, ex, ez, 0.3, 1.5, Math.max(0.5, 1.5 + Math.sin(camSt.pitch) * want));
          const free = Math.max(0.55, want * f);
          if (!camSt.init || free < camSt.d) camSt.d = free;
          else camSt.d = Math.min(free, camSt.d + (free - camSt.d) * Math.min(1, dt * 4));
          const off = 0.42 * Math.min(1, camSt.d / 2.2);
          const pivX = player.x + rx * off, pivZ = player.y + rz * off, pivY = 1.5;
          camSt.x = pivX - dirx * camSt.d * cp;
          camSt.z = pivZ - dirz * camSt.d * cp;
          camSt.y = Math.max(0.5, pivY + sp * camSt.d);
          camSt.init = true;
          cam.position.set(camSt.x, camSt.y, camSt.z);
          cam.lookAt(pivX + dirx * 2.5, pivY - 0.1, pivZ + dirz * 2.5);
          cam.fov += (fovBase(false) + 6 * gaitRun - cam.fov) * Math.min(1, dt * 5);
          camSt.hideBody = camSt.d < 1.0;
        }
        cam.updateProjectionMatrix();
      }

      // trees between the camera and the player (or round the camera) fade out so foliage never fills the screen
      {
        const cx = cam.position.x, cz = cam.position.z, ppx = focus.x, ppz = focus.y;
        const sdx = ppx - cx, sdz = ppz - cz;
        const sl2 = sdx * sdx + sdz * sdz || 1;
        streamer.eachTreeNear(ppx, ppz, 20, (g, tx, ty, tr) => {
          const tt = Math.max(0, Math.min(1, ((tx - cx) * sdx + (ty - cz) * sdz) / sl2));
          const dseg = Math.hypot(cx + sdx * tt - tx, cz + sdz * tt - ty);
          const dcam = Math.hypot(cx - tx, cz - ty);
          streamer.treeFade(g, dseg < tr * 0.95 + 0.3 || dcam < tr * 1.25 + 1);
        });
      }

      // rain on the camera
      {
        const raining = Boolean(p.wet);
        rain.visible = raining;
        if (raining) {
          const rp = rainGeo.attributes.position.array as Float32Array;
          const fall = 14 * dt;
          for (let i = 0; i < RAIN_N; i++) {
            rainSeed[i * 3 + 1] -= fall;
            if (rainSeed[i * 3 + 1] < -3) rainSeed[i * 3 + 1] += 9;
            const x = rainSeed[i * 3], y = rainSeed[i * 3 + 1], z = rainSeed[i * 3 + 2];
            rp[i * 6] = x; rp[i * 6 + 1] = y; rp[i * 6 + 2] = z;
            rp[i * 6 + 3] = x + 0.03; rp[i * 6 + 4] = y - 0.55; rp[i * 6 + 5] = z;
          }
          (rainGeo.attributes.position as Float32BufferAttribute).needsUpdate = true;
        }
      }

      // sun + sky follow the player
      {
        const c = cityLight(p.hour);
        sun.position.set(focus.x + c.sunDir[0] * 60, Math.max(25, c.sunDir[1] * 60), focus.y + c.sunDir[2] * 60);
        sun.target.position.set(focus.x, 0, focus.y);
        sun.target.updateMatrixWorld();
      }
      sky.position.copy(cam.position);
      plain.position.x = cam.position.x;
      plain.position.z = cam.position.z;
      glowLight.position.set(focus.x, 3.2, focus.y);

      /* pedestrians: build rigs in the background, pose by distance */
      if (pending.length && performance.now() - lastBuild > 40) {
        const i = pending.shift()!;
        const pd = peds.list[i];
        if (pd) {
          const s = makeSlot('ped', i, wantAvatar(pd.look), low ? 0.25 : 0.3);
          s.g.position.set(pd.x, 0, pd.y);
        }
        lastBuild = performance.now();
      }
      let nearRigs = 0;
      for (const sl of slots) {
        if (sl.kind !== 'ped') continue;
        const pd = peds.list[sl.ped];
        if (!pd || !sl.rig) continue;
        const d2 = (pd.x - focus.x) ** 2 + (pd.y - focus.y) ** 2;
        const vis = d2 < 95 * 95;
        sl.g.visible = vis;
        if (!vis) continue;
        const near = d2 < 28 * 28;
        if (near) nearRigs++;
        const every = near ? 1 : d2 < 55 * 55 ? 2 : 4;
        const cheap = (frameN + sl.ped) % every !== 0;
        const wasMoved = pd.moved;
        pose(sl, t, pd.x, pd.y, pd.h, pd.v, wasMoved * n, pd.gait, pedPhase[sl.ped], 0, cheap);
      }

      /* traffic instances */
      const cnt = { car: 0, bus: 0, keke: 0, okada: 0 };
      for (const c of traffic.cars) {
        if (Math.abs(c.x - focus.x) > 170 || Math.abs(c.y - focus.y) > 170) continue;
        const m = inst[c.kind];
        const i = cnt[c.kind]++;
        if (i >= m.instanceMatrix.count) continue;
        q.setFromAxisAngle(yAxis, -c.a);
        const k = Math.max(0.001, c.k);
        m4.compose(v3.set(c.x, 0.02, c.y), q, s3.set(k, k, k));
        m.setMatrixAt(i, m4);
        carColor.set(c.color);
        m.setColorAt(i, carColor);
      }
      for (const k of kinds) {
        inst[k].count = Math.min(cnt[k], inst[k].instanceMatrix.count);
        inst[k].instanceMatrix.needsUpdate = true;
        if (inst[k].instanceColor) inst[k].instanceColor.needsUpdate = true;
      }

      /* blob shadows for people + cars */
      {
        let bi = 0;
        const put = (x: number, z: number, sx: number, sz: number, a: number) => {
          if (bi >= MAX_BLOBS) return;
          q.setFromAxisAngle(yAxis, -a);
          m4.compose(v3.set(x, 0.09, z), q, s3.set(sx, 1, sz));
          blobs.setMatrixAt(bi++, m4);
        };
        if (!fp && !driving) put(player.x, player.y, 1.1, 1.1, 0);
        for (const sl of slots) if (sl.kind === 'ped' && sl.g.visible) put(peds.list[sl.ped].x, peds.list[sl.ped].y, 1.0, 1.0, 0);
        for (const c of traffic.cars) {
          if (Math.abs(c.x - focus.x) > 60 || Math.abs(c.y - focus.y) > 60 || c.k < 0.5) continue;
          put(c.x, c.y, c.len * 1.15, c.wid * 1.5, c.a);
        }
        blobs.count = bi;
        blobs.instanceMatrix.needsUpdate = true;
      }

      /* nearest place door, street name, the kerb, the car */
      if (t - lastNearAt > 0.1) {
        lastNearAt = t;
        let best: string | null = null, bd = driving ? 15 : 3.4;
        for (const pl of W.places) {
          if (Math.abs(pl.door.sx - focus.x) > 20) continue;
          const d = Math.hypot(pl.door.sx - focus.x, pl.door.sy - focus.y);
          if (d < bd) { bd = d; best = pl.id; }
        }
        live.current.nearId = best && (!driving || Math.abs(car.v) < 5) ? best : null;
        live.current.nearDist = bd;
        let talk = false;
        if (!driving) for (const pd of peds.list) if (pd.kind !== 'walker' && (pd.x - player.x) ** 2 + (pd.y - player.y) ** 2 < 2.8 * 2.8) talk = true;
        live.current.nearTalk = talk;
        // standing on a pavement beside a road: a keke can stop here
        live.current.atKerb = !driving && W.L.net.clear(player.x, player.y, true, 5) < 2.2 && W.L.net.clear(player.x, player.y, false, 5) > -0.5;
      }
      if (t - lastStreetAt > 0.4) {
        lastStreetAt = t;
        streetName = streetAt(focus.x, focus.y);
      }
      const L = live.current;
      L.x = focus.x; L.y = focus.y; L.h = driving ? car.h : player.h; L.speed = driving ? Math.abs(car.v) : speed; L.street = streetName; L.camYaw = driving ? car.h : camSt.yaw;
      L.running = I.run && speed > 1 && !driving; L.t = t; L.ready = true; L.loaded = streamer.stats().detail;
      const C = L.car;
      C.here = drv.here; C.driving = driving; C.v = car.v; C.x = car.x; C.y = car.y; C.h = car.h; C.braking = car.braking; C.sinceHit = drv.sinceHit; C.dry = drv.dry;
      C.doorDist = drv.here ? Math.hypot(player.x - carDoor.x, player.y - carDoor.y) : 99;
      C.nearDoor = drv.here && !driving && C.doorDist < 3.0;
      C.canPark = driving && Math.abs(car.v) < 1.6 && parkLegal(carEnv.roadClear(car.x, car.y));
      C.pendingDist = car.odo; C.pendingHits = car.light + car.hard;
      carBeam.visible = drv.here && !driving && Math.hypot(player.x - car.x, player.y - car.y) > 7 && Math.hypot(player.x - car.x, player.y - car.y) < 140;
      if (carBeam.visible) carBeam.position.set(car.x, 0, car.y);

      /* GPS route */
      const dest = p.dest;
      const dkey = dest ? `${dest.x.toFixed(1)},${dest.y.toFixed(1)}` : '';
      if (dkey !== lastDestKey) {
        lastDestKey = dkey;
        route = null;
        routeFor = '';
        routeSeg = -1;
        replanAt = 0;
        routeMesh.visible = false;
        beam.visible = Boolean(dest);
        if (dest) beam.position.set(dest.x, 0, dest.y);
      }
      if (dest) {
        if (t >= replanAt && (!route || routeFor !== dkey || routeProgress(route.pts, focus.x, focus.y).off > 8)) {
          route = planRoute(W, [focus.x, focus.y], [dest.x, dest.y]);
          L.route = route.pts.map((q2) => [q2[0], q2[1]] as [number, number]);
          routeFor = dkey;
          routeSeg = -1;
          replanAt = t + 2.5;
        }
        if (route) {
          const pr = routeProgress(route.pts, focus.x, focus.y);
          L.left = pr.left;
          if (pr.seg !== routeSeg) {
            routeSeg = pr.seg;
            const sp = new Soup();
            const pts = route.pts;
            for (let i = Math.max(0, pr.seg); i + 1 < pts.length; i++) {
              const a = pts[i], b = pts[i + 1];
              const len = Math.hypot(b[0] - a[0], b[1] - a[1]);
              const nseg = Math.max(1, Math.floor(len / 1.4));
              for (let k = 0; k < nseg; k++) {
                const t0 = (k + 0.1) / nseg, t1 = (k + 0.78) / nseg;
                sp.strip(a[0] + (b[0] - a[0]) * t0, a[1] + (b[1] - a[1]) * t0, a[0] + (b[0] - a[0]) * t1, a[1] + (b[1] - a[1]) * t1, driving ? 0.9 : 0.5, 0.14, '#ffffff');
              }
            }
            routeMesh.geometry.dispose();
            routeMesh.geometry = sp.geometry();
            routeMesh.visible = true;
          }
        }
      } else {
        L.left = null;
        L.route = null;
      }
      beamMat.opacity = 0.2 + 0.1 * Math.sin(t * 3) + dark * 0.15;
      carBeamMat.opacity = 0.25 + 0.12 * Math.sin(t * 2.4);

      /* debug overlay */
      if (dbgOn && t - dbgAt > 0.04) {
        dbgAt = t;
        if (!dbg) {
          const g = own(new BufferGeometry());
          g.setAttribute('position', new Float32BufferAttribute(new Float32Array(dbgBuf.length), 3).setUsage(DynamicDrawUsage));
          dbg = new LineSegments(g, own(new LineBasicMaterial({ color: '#22d3ee', depthTest: false, transparent: true })));
          dbg.renderOrder = 20;
          dbg.frustumCulled = false;
          root.add(dbg);
        }
        let n2 = 0;
        const arr = (dbg.geometry.attributes.position as Float32BufferAttribute).array as Float32Array;
        const seg = (ax: number, ay: number, bx: number, by: number) => {
          if (n2 + 6 > arr.length) return;
          arr[n2++] = ax; arr[n2++] = 0.35; arr[n2++] = ay; arr[n2++] = bx; arr[n2++] = 0.35; arr[n2++] = by;
        };
        const R = 38;
        for (const pl of W.col.polys) {
          const pts = pl.pts;
          let near = false;
          for (const pt of pts) if (Math.abs(pt[0] - focus.x) < R && Math.abs(pt[1] - focus.y) < R) { near = true; break; }
          if (!near) continue;
          for (let i = 0; i < pts.length; i++) seg(pts[i][0], pts[i][1], pts[(i + 1) % pts.length][0], pts[(i + 1) % pts.length][1]);
        }
        for (const c of W.col.circs) {
          if (Math.abs(c.x - focus.x) > R || Math.abs(c.y - focus.y) > R) continue;
          for (let k = 0; k < 8; k++) seg(c.x + Math.cos((k / 8) * 6.283) * c.r, c.y + Math.sin((k / 8) * 6.283) * c.r, c.x + Math.cos(((k + 1) / 8) * 6.283) * c.r, c.y + Math.sin(((k + 1) / 8) * 6.283) * c.r);
        }
        for (const b of W.col.dynBoxes) {
          const c = Math.cos(b.a), s = Math.sin(b.a);
          const P4 = [[-b.hl, -b.hw], [b.hl, -b.hw], [b.hl, b.hw], [-b.hl, b.hw]].map(([u, v]) => [b.x + u * c - v * s, b.y + u * s + v * c]);
          for (let i = 0; i < 4; i++) seg(P4[i][0], P4[i][1], P4[(i + 1) % 4][0], P4[(i + 1) % 4][1]);
        }
        for (const c of W.col.dynCircles) for (let k = 0; k < 8; k++) seg(c.x + Math.cos((k / 8) * 6.283) * c.r, c.y + Math.sin((k / 8) * 6.283) * c.r, c.x + Math.cos(((k + 1) / 8) * 6.283) * c.r, c.y + Math.sin(((k + 1) / 8) * 6.283) * c.r);
        if (driving) {
          const ch = Math.cos(car.h), sh = Math.sin(car.h);
          const P4 = [[-spec.len / 2, -spec.wid / 2], [spec.len / 2, -spec.wid / 2], [spec.len / 2, spec.wid / 2], [-spec.len / 2, spec.wid / 2]].map(([u, v]) => [car.x + u * ch - v * sh, car.y + u * sh + v * ch]);
          for (let i = 0; i < 4; i++) seg(P4[i][0], P4[i][1], P4[(i + 1) % 4][0], P4[(i + 1) % 4][1]);
        } else for (let k = 0; k < 12; k++) seg(player.x + Math.cos((k / 12) * 6.283) * PLAYER_R, player.y + Math.sin((k / 12) * 6.283) * PLAYER_R, player.x + Math.cos(((k + 1) / 12) * 6.283) * PLAYER_R, player.y + Math.sin(((k + 1) / 12) * 6.283) * PLAYER_R);
        const g = dbg.geometry;
        (g.attributes.position as Float32BufferAttribute).needsUpdate = true;
        g.setDrawRange(0, n2 / 3);
        dbg.visible = true;
      }
      void nearRigs;
      void AREA;
      void wetNow;
    };

    // warm the traffic so cars are spread out on the first frame
    const warm = props.warm ?? 6;
    for (let i = 0; i < warm * 60; i++) {
      peds.people(people);
      people.push({ x: player.x, y: player.y, r: PLAYER_R });
      traffic.step(FIXED, people, focus);
    }
    peds.step(FIXED, W.col, player);

    ref.current = {
      tick,
      setHour: applyLight,
      dispose() {
        scene.remove(root);
        scene.remove(cam);
        scene.fog = null;
        scene.background = null;
        streamer.dispose();
        for (const sl of slots) sl.rig?.dispose();
        for (const o of owned) o.dispose();
        routeMesh.geometry.dispose();
        for (const k of kinds) inst[k].dispose();
        blobs.dispose();
        if (carRig) {
          cam.remove(carRig.cockpit.group);
          carRig.dispose();
        }
        cam.remove(rain);
      },
    };

    const heapMB = () => {
      const m = (performance as unknown as { memory?: { usedJSHeapSize: number } }).memory;
      return m ? m.usedJSHeapSize / 1048576 : 0;
    };
    const api: RoamApi = {
      world: W,
      stats: () => ({
        calls: gl.info.render.calls,
        triangles: gl.info.render.triangles,
        geometries: gl.info.memory.geometries,
        textures: gl.info.memory.textures,
        staticTris: Math.round(streamer.stats().tris),
        rigs: slots.filter((s) => s.g.visible).length,
        cars: inst.car.count + inst.bus.count + inst.keke.count + inst.okada.count,
        programs: gl.info.programs?.length ?? 0,
      }),
      stream: () => ({ ...streamer.stats(), geometries: gl.info.memory.geometries, textures: gl.info.memory.textures, heapMB: heapMB(), tickAvgMs: perfStat.n ? perfStat.sum / perfStat.n : 0, tickMaxMs: perfStat.max, tickOver8: perfStat.over8, ticks: perfStat.n }),
      resetPerf: () => { perfStat.n = 0; perfStat.sum = 0; perfStat.max = 0; perfStat.over8 = 0; streamer.resetSliceStats(); },
      teleport: (x, y, h) => {
        placePlayer(player, W.col, x, y, h);
        camSt.init = false;
        if (drv.driving) { car.x = x; car.y = y; if (h !== undefined) car.h = h; car.v = 0; }
      },
      cam: (c) => {
        if (c.yaw !== undefined) camSt.yaw = c.yaw;
        if (c.pitch !== undefined) camSt.pitch = c.pitch;
        if (c.dist !== undefined) camSt.dist = c.dist;
      },
      state: () => ({ x: player.x, y: player.y, h: player.h, speed: player.speed, yaw: camSt.yaw, pitch: camSt.pitch, camDist: camSt.d, ready, driving: drv.driving, carX: car.x, carY: car.y, carH: car.h, carV: car.v, fogFar: fog.far, ...Object.fromEntries(Object.entries(streamer.stats()).map(([k, v]) => ['s_' + k, typeof v === 'number' ? Math.round(v * 100) / 100 : v])) }),
      setDebug,
      car: carApi,
      auto: (o) => {
        if (!o) { autoS.on = false; const I = P.current.input.current; I.sx = 0; I.sy = 0; I.brake = false; return; }
        autoS.on = true;
        autoS.mode = o.mode;
        autoS.run = Boolean(o.run);
        autoS.speed = o.speed ?? 13;
        autoS.dest = o.dest ?? null;
        autoS.pts = [];
        autoS.plan = 0;
      },
      setInput: (sx, sy, brake = false) => {
        const I = P.current.input.current;
        I.sx = sx; I.sy = sy; I.brake = brake;
      },
      advance: (sec) => {
        const n = Math.round(sec * 60);
        for (let i = 0; i < n; i++) {
          if (autoS.on) autoStep(FIXED);
          stepSim(FIXED);
          if (i % 30 === 29) streamer.update(drv.driving ? car.x : player.x, drv.driving ? car.y : player.y, headDirX, headDirY, 25);
        }
      },
      settle: (maxMs = 60000) => {
        const t0 = performance.now();
        while (performance.now() - t0 < maxMs) {
          streamer.update(focus.x, focus.y, headDirX, headDirY, 40);
          if (streamer.ready(focus.x, focus.y, low ? 150 : 195) && !streamer.stats().building) break;
        }
      },
    };
    (window as unknown as { __roam?: RoamApi }).__roam = api;
    // first frames: the camera has to be placed before the first render
    camSt.init = false;
    P.current.onReady?.(api);

    const lost = (e: Event) => {
      e.preventDefault();
      P.current.onLost?.();
    };
    gl.domElement.addEventListener('webglcontextlost', lost);
    return () => {
      gl.domElement.removeEventListener('webglcontextlost', lost);
      ref.current?.dispose();
      ref.current = null;
      if ((window as unknown as { __roam?: RoamApi }).__roam === api) delete (window as unknown as { __roam?: RoamApi }).__roam;
    };
    // the world, the tier and the vehicle define the scene; everything else is read through P
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [props.world, props.tier, props.vehicle?.kind, props.vehicle?.color]);

  useFrame((_, delta) => {
    const t0 = performance.now();
    ref.current?.tick(delta);
    const dt = performance.now() - t0;
    perfStat.n++;
    perfStat.sum += dt;
    if (dt > perfStat.max) perfStat.max = dt;
    if (dt > 8) perfStat.over8++;
  });
  return null;
}

export default function RoamScene(props: RoamSceneProps) {
  return (
    <div className="roam-canvas">
      <Canvas
        key={props.tier}
        dpr={props.tier === 'low' ? [1, 1.1] : [1, 1.6]}
        frameloop={props.paused ? 'never' : 'always'}
        camera={{ fov: 62, near: 0.15, far: 560, position: [0, 3, 8] }}
        gl={{ antialias: props.tier === 'high', powerPreference: 'low-power', alpha: false }}
      >
        <Rig {...props} />
      </Canvas>
    </div>
  );
}
