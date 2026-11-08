// Free roam: the live 3D street scene (react-three-fiber). Lazy-loaded through ../RoamView.tsx.
// One frame loop does everything with refs (no React state per frame): fixed 60 Hz physics steps (player, traffic, pedestrians,
// collision), then the visuals (camera with collision, character poses, instanced traffic, day/night). Static streets are merged
// into a handful of meshes (street.ts); see docs/ROAM.md.
import { Canvas, useFrame, useThree } from '@react-three/fiber';
import { useEffect, useRef, type MutableRefObject } from 'react';
import {
  BufferGeometry,
  Color,
  CylinderGeometry,
  DirectionalLight,
  Float32BufferAttribute,
  Fog,
  Group,
  HemisphereLight,
  PointLight,
  InstancedMesh,
  LineBasicMaterial,
  LineSegments,
  Matrix4,
  Mesh,
  MeshBasicMaterial,
  MeshLambertMaterial,
  PerspectiveCamera,
  Quaternion,
  SphereGeometry,
  Vector3,
  AdditiveBlending,
  BackSide,
  DynamicDrawUsage,
} from 'three';
import type { AvatarConfig } from '../../../lib/types';
import { defaultAvatar, randomAvatar } from '../../avatar3d/catalog';
import { applyPose, capturePose, gaitFor, mixPose, poseGait, poseIdle, POSE_SIZE, resetRig, stepLength } from '../../avatar3d/engine/anim';
import { buildCrowdRig, type CrowdRig } from '../../avatar3d/engine/crowd';
import { cityLight } from '../../city3d/engine/light';
import { ROAD_NAME } from '../../drive3d/model';
import { PLAYER_R, SPEED } from '../area';
import { planRoute, routeProgress, type GpsRoute } from '../gps';
import { Peds } from '../peds';
import { makePlayer, placePlayer, stepPlayer, type PlayerState } from '../player';
import { Traffic } from '../traffic';
import { SHOP_NAMES, type RoamWorld } from '../world';
import { busGeometry, carGeometry, kekeGeometry, okadaGeometry } from './cars';
import { Soup } from './soup';
import { buildStreet, makeSignAtlas, type Street } from './street';

export interface RoamInput {
  /** Stick: x right, y forward (-1..1). */
  sx: number;
  sy: number;
  run: boolean;
  /** Camera look deltas (radians), consumed by the scene. */
  lookX: number;
  lookY: number;
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
}

export interface RoamApi {
  stats(): { calls: number; triangles: number; geometries: number; textures: number; staticTris: number; rigs: number; cars: number };
  teleport(x: number, y: number, h?: number): void;
  cam(p: { yaw?: number; pitch?: number; dist?: number }): void;
  state(): Record<string, number | string | boolean>;
  setDebug(on: boolean): void;
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
  onReady?: (api: RoamApi) => void;
  onLost?: () => void;
}

const clamp = (v: number, a: number, b: number) => Math.max(a, Math.min(b, v));
const FIXED = 1 / 60;

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
    cam.far = 520;
    cam.fov = 62;
    cam.updateProjectionMatrix();

    /* ---------- lights, fog, sky ---------- */
    const hemi = new HemisphereLight('#ffffff', '#b7a58f', 1.5);
    const sun = new DirectionalLight('#fff1dc', 2);
    const fill = new DirectionalLight('#dfe8ff', 0.5);
    // a soft warm light that walks with the player at night (the street lamps are few)
    const glowLight = new PointLight('#ffe2b8', 0, 15, 1.5);
    root.add(hemi, sun, sun.target, fill, glowLight);
    const fogNear = low ? 40 : 55;
    const fogFar = low ? 190 : 250;
    const fog = new Fog('#cfe5f1', fogNear, fogFar);
    scene.fog = fog;
    scene.background = new Color('#cfe5f1');
    const skyGeo = own(new SphereGeometry(480, 18, 10));
    const skyCols = new Float32Array(skyGeo.attributes.position.count * 3);
    skyGeo.setAttribute('color', new Float32BufferAttribute(skyCols, 3));
    const sky = new Mesh(skyGeo, own(new MeshBasicMaterial({ vertexColors: true, side: BackSide, fog: false, depthWrite: false })));
    sky.renderOrder = -10;
    sky.frustumCulled = false;
    root.add(sky);

    /* ---------- static streets ---------- */
    const signs = typeof document !== 'undefined' ? makeSignAtlas([...W.places.map((p) => ({ label: p.label, accent: p.accent })), ...SHOP_NAMES.map((n, i) => ({ label: n, accent: i >= 8 ? '#8d5a2b' : ['#c0643f', '#2e9d58', '#5c7fb5', '#d9822b', '#7a4ac8', '#3f7f9c', '#b5407a', '#4a6a3a'][i] }))]) : null;
    const street: Street = buildStreet(W, { tier: props.tier, signs });
    root.add(street.group);

    /* ---------- traffic ---------- */
    const traffic = new Traffic(W.L, W.box);
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
    let route: GpsRoute | null = null;
    let routeSeg = -1;
    let routeFor = '';
    let replanAt = 0;

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
    const camSt = { yaw: props.cam?.yaw ?? -Math.PI / 2, pitch: props.cam?.pitch ?? 0.3, dist: props.cam?.dist ?? 5.2, d: 5.2, x: 0, y: 2, z: 0, init: false, hideBody: false };
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
    const tmpC = new Color();
    const mixC = (a: string, b: string, t: number) => tmpC.set(a).lerp(new Color(b), t);
    const applyLight = (hour: number) => {
      const c = cityLight(hour);
      const key = `${Math.round(c.dark * 40)}|${c.sky}`;
      if (key === lastLight) return;
      lastLight = key;
      dark = c.dark;
      hemi.color.set(c.hemiSky);
      hemi.groundColor.set(c.hemiGround).lerp(new Color(c.hemiSky), 0.3);
      hemi.intensity = c.hemi * (1.25 + 0.9 * c.dark);
      glowLight.intensity = clamp((c.dark - 0.3) / 0.5, 0, 1) * 7.5;
      fill.intensity = 0.2 + (1 - c.dark) * 0.5 + c.dark * 0.35;
      sun.color.set(c.sun);
      sun.intensity = c.sunI * 0.62;
      fog.color.set(c.sky);
      (scene.background as Color).set(c.sky);
      const top = new Color(c.sky).lerp(new Color(c.dark > 0.5 ? '#0b1030' : '#6fa6dc'), c.dark > 0.5 ? 0.8 : 0.6);
      const hor = new Color(c.sky);
      const pos = skyGeo.attributes.position;
      const colAttr = skyGeo.attributes.color as Float32BufferAttribute;
      for (let i = 0; i < pos.count; i++) {
        const t = clamp((pos.getY(i) / 480) * 1.6, 0, 1);
        tmpC.copy(hor).lerp(top, t * t);
        colAttr.setXYZ(i, tmpC.r, tmpC.g, tmpC.b);
      }
      colAttr.needsUpdate = true;
      const night = clamp((c.dark - 0.3) / 0.4, 0, 1);
      street.mats.glassLit.color.copy(mixC('#78a0b6', '#ffd27a', night));
      street.mats.glow.color.copy(mixC('#cfc9bb', '#fff1c2', night));
      street.mats.glowLand.color.copy(mixC('#9db4c4', '#ffd27a', night));
      street.mats.sign.color.copy(mixC('#ffffff', '#e9e3d4', night));
      street.mats.pool.opacity = clamp((c.dark - 0.25) / 0.5, 0, 1) * 0.85;
      street.mats.pool.visible = street.mats.pool.opacity > 0.01;
      (street.blobs.material as MeshBasicMaterial).opacity = 1 - 0.5 * night;
    };
    applyLight(props.hour);

    /* ---------- the frame ---------- */
    const m4 = new Matrix4();
    const q = new Quaternion();
    const v3 = new Vector3();
    const s3 = new Vector3();
    const yAxis = new Vector3(0, 1, 0);
    const people: { x: number; y: number; r: number }[] = [];
    let acc = 0;
    let simT = 0;
    let frameN = 0;
    let lastDestKey = '';
    let lastNearAt = 0;
    let lastStreetAt = 0;
    let streetName = '';
    let gaitRun = 0;

    const stepSim = (dt: number) => {
      const I = P.current.input.current;
      const fx = Math.cos(camSt.yaw), fy = Math.sin(camSt.yaw);
      // stick: forward along the camera, right = (-sin, cos)
      const wx = fx * I.sy + -fy * I.sx;
      const wy = fy * I.sy + fx * I.sx;
      peds.people(people);
      people.push({ x: player.x, y: player.y, r: PLAYER_R });
      traffic.step(dt, people);
      traffic.publish(W.col, player.x, player.y, 45);
      peds.step(dt, W.col, player);
      stepPlayer(player, W.col, dt, wx, wy, I.run);
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
    const tick = (delta: number) => {
      const p = P.current;
      if (p.paused) return;
      frameN++;
      const dt = Math.min(0.1, delta);
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
      // look input
      camSt.yaw += I.lookX;
      camSt.pitch = clamp(camSt.pitch + I.lookY, p.firstPerson ? -0.95 : -0.1, p.firstPerson ? 0.95 : 1.15);
      I.lookX = 0;
      I.lookY = 0;
      const t = simT;
      applyLight(p.hour);

      /* player rig + camera */
      const fp = p.firstPerson;
      const speed = player.speed;
      const runK = clamp((speed - 2.6) / (SPEED.run - 2.6), 0, 1);
      gaitRun += (runK - gaitRun) * Math.min(1, dt * 6);
      const ps = playerSlot;
      ps.g.visible = !fp && !camSt.hideBody && Boolean(ps.rig);
      pose(ps, t, player.x, player.y, player.h, speed, player.moved * (acc >= 0 ? n : 1), player.gait, playerPhase, gaitRun, false);

      // camera
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

      // trees between the camera and the player (or round the camera) fade out so foliage never fills the screen
      {
        const ti = street.treeInfo;
        const cx = cam.position.x, cz = cam.position.z, ppx = player.x, ppz = player.y;
        const sdx = ppx - cx, sdz = ppz - cz;
        const sl2 = sdx * sdx + sdz * sdz || 1;
        for (let i = 0; i < ti.length; i++) {
          const tr = ti[i];
          if (Math.abs(tr.x - ppx) > 18 || Math.abs(tr.y - ppz) > 18) { street.treeFade(i, false); continue; }
          const tt = Math.max(0, Math.min(1, ((tr.x - cx) * sdx + (tr.y - cz) * sdz) / sl2));
          const dseg = Math.hypot(cx + sdx * tt - tr.x, cz + sdz * tt - tr.y);
          const dcam = Math.hypot(cx - tr.x, cz - tr.y);
          street.treeFade(i, dseg < tr.r * 0.95 + 0.3 || dcam < tr.r * 1.25 + 1);
        }
      }

      // sun + sky follow the player
      sun.position.set(player.x + 60 * 0.8, 70, player.y + 40);
      sun.target.position.set(player.x, 0, player.y);
      sun.target.updateMatrixWorld();
      {
        const c = cityLight(p.hour);
        sun.position.set(player.x + c.sunDir[0] * 60, Math.max(25, c.sunDir[1] * 60), player.y + c.sunDir[2] * 60);
      }
      sky.position.copy(cam.position);
      glowLight.position.set(player.x, 3.2, player.y);

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
        const d2 = (pd.x - player.x) ** 2 + (pd.y - player.y) ** 2;
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
        if (Math.abs(c.x - player.x) > 150 || Math.abs(c.y - player.y) > 150) continue;
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
        let bi = street.staticBlobs;
        const blobs = street.blobs;
        const put = (x: number, z: number, sx: number, sz: number, a: number) => {
          if (bi >= blobs.instanceMatrix.count) return;
          q.setFromAxisAngle(yAxis, -a);
          m4.compose(v3.set(x, 0.09, z), q, s3.set(sx, 1, sz));
          blobs.setMatrixAt(bi++, m4);
        };
        if (!fp) put(player.x, player.y, 1.1, 1.1, 0);
        for (const sl of slots) if (sl.kind === 'ped' && sl.g.visible) put(peds.list[sl.ped].x, peds.list[sl.ped].y, 1.0, 1.0, 0);
        for (const c of traffic.cars) {
          if (Math.abs(c.x - player.x) > 60 || Math.abs(c.y - player.y) > 60 || c.k < 0.5) continue;
          put(c.x, c.y, c.len * 1.15, c.wid * 1.5, c.a);
        }
        blobs.count = bi;
        blobs.instanceMatrix.needsUpdate = true;
      }

      /* nearest place door, street name */
      if (t - lastNearAt > 0.1) {
        lastNearAt = t;
        let best: string | null = null, bd = 3.4;
        for (const pl of W.places) {
          const d = Math.hypot(pl.door.sx - player.x, pl.door.sy - player.y);
          if (d < bd) { bd = d; best = pl.id; }
        }
        live.current.nearId = best;
        live.current.nearDist = bd;
        let talk = false;
        for (const pd of peds.list) if (pd.kind !== 'walker' && (pd.x - player.x) ** 2 + (pd.y - player.y) ** 2 < 2.8 * 2.8) talk = true;
        live.current.nearTalk = talk;
      }
      if (t - lastStreetAt > 0.4) {
        lastStreetAt = t;
        streetName = streetAt(player.x, player.y);
      }
      const L = live.current;
      L.x = player.x; L.y = player.y; L.h = player.h; L.speed = speed; L.street = streetName; L.camYaw = camSt.yaw;
      L.running = I.run && speed > 1; L.t = t; L.ready = true;

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
        if (t >= replanAt && (!route || routeFor !== dkey || routeProgress(route.pts, player.x, player.y).off > 6)) {
          route = planRoute(W, [player.x, player.y], [dest.x, dest.y]);
          L.route = route.pts.map((q) => [q[0], q[1]] as [number, number]);
          routeFor = dkey;
          routeSeg = -1;
          replanAt = t + 2;
        }
        if (route) {
          const pr = routeProgress(route.pts, player.x, player.y);
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
                sp.strip(a[0] + (b[0] - a[0]) * t0, a[1] + (b[1] - a[1]) * t0, a[0] + (b[0] - a[0]) * t1, a[1] + (b[1] - a[1]) * t1, 0.5, 0.14, '#ffffff');
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
          for (const pt of pts) if (Math.abs(pt[0] - player.x) < R && Math.abs(pt[1] - player.y) < R) { near = true; break; }
          if (!near) continue;
          for (let i = 0; i < pts.length; i++) seg(pts[i][0], pts[i][1], pts[(i + 1) % pts.length][0], pts[(i + 1) % pts.length][1]);
        }
        for (const c of W.col.circs) {
          if (Math.abs(c.x - player.x) > R || Math.abs(c.y - player.y) > R) continue;
          for (let k = 0; k < 8; k++) seg(c.x + Math.cos((k / 8) * 6.283) * c.r, c.y + Math.sin((k / 8) * 6.283) * c.r, c.x + Math.cos(((k + 1) / 8) * 6.283) * c.r, c.y + Math.sin(((k + 1) / 8) * 6.283) * c.r);
        }
        for (const b of W.col.dynBoxes) {
          const c = Math.cos(b.a), s = Math.sin(b.a);
          const P4 = [[-b.hl, -b.hw], [b.hl, -b.hw], [b.hl, b.hw], [-b.hl, b.hw]].map(([u, v]) => [b.x + u * c - v * s, b.y + u * s + v * c]);
          for (let i = 0; i < 4; i++) seg(P4[i][0], P4[i][1], P4[(i + 1) % 4][0], P4[(i + 1) % 4][1]);
        }
        for (const c of W.col.dynCircles) for (let k = 0; k < 8; k++) seg(c.x + Math.cos((k / 8) * 6.283) * c.r, c.y + Math.sin((k / 8) * 6.283) * c.r, c.x + Math.cos(((k + 1) / 8) * 6.283) * c.r, c.y + Math.sin(((k + 1) / 8) * 6.283) * c.r);
        for (let k = 0; k < 12; k++) seg(player.x + Math.cos((k / 12) * 6.283) * PLAYER_R, player.y + Math.sin((k / 12) * 6.283) * PLAYER_R, player.x + Math.cos(((k + 1) / 12) * 6.283) * PLAYER_R, player.y + Math.sin(((k + 1) / 12) * 6.283) * PLAYER_R);
        const g = dbg.geometry;
        (g.attributes.position as Float32BufferAttribute).needsUpdate = true;
        g.setDrawRange(0, n2 / 3);
        dbg.visible = true;
      }
      void nearRigs;
    };

    // warm the traffic so cars are spread out on the first frame
    const warm = props.warm ?? 6;
    for (let i = 0; i < warm * 60; i++) {
      peds.people(people);
      people.push({ x: player.x, y: player.y, r: PLAYER_R });
      traffic.step(FIXED, people);
    }
    peds.step(FIXED, W.col, player);

    ref.current = {
      tick,
      setHour: applyLight,
      dispose() {
        scene.remove(root);
        scene.fog = null;
        scene.background = null;
        street.dispose();
        for (const sl of slots) sl.rig?.dispose();
        for (const o of owned) o.dispose();
        routeMesh.geometry.dispose();
        for (const k of kinds) inst[k].dispose();
      },
    };

    const api: RoamApi = {
      world: W,
      stats: () => ({
        calls: gl.info.render.calls,
        triangles: gl.info.render.triangles,
        geometries: gl.info.memory.geometries,
        textures: gl.info.memory.textures,
        staticTris: Math.round(street.tris),
        rigs: slots.filter((s) => s.g.visible).length,
        cars: inst.car.count + inst.bus.count + inst.keke.count + inst.okada.count,
      }),
      teleport: (x, y, h) => {
        placePlayer(player, W.col, x, y, h);
        camSt.init = false;
      },
      cam: (c) => {
        if (c.yaw !== undefined) camSt.yaw = c.yaw;
        if (c.pitch !== undefined) camSt.pitch = c.pitch;
        if (c.dist !== undefined) camSt.dist = c.dist;
      },
      state: () => ({ ...Object.fromEntries(Object.entries(street.meshTris).map(([k, v]) => ['tris_' + k, Math.round(v)])), x: player.x, y: player.y, h: player.h, speed: player.speed, yaw: camSt.yaw, pitch: camSt.pitch, camDist: camSt.d, t: simT, bumped: player.bumped }),
      setDebug,
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
    // the world and tier define the scene; everything else is read through P
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [props.world, props.tier]);

  useFrame((_, delta) => {
    ref.current?.tick(delta);
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
        camera={{ fov: 62, near: 0.15, far: 520, position: [0, 3, 8] }}
        gl={{ antialias: props.tier === 'high', powerPreference: 'low-power', alpha: false }}
      >
        <Rig {...props} />
      </Canvas>
    </div>
  );
}
