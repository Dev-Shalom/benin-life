// The live 3D drive (react-three-fiber). Lazy-loaded through ../DriveView.tsx.
//
// The car stays at the origin of the world's z axis while the street scrolls past (src/art/drive3d/engine/world.ts is
// periodic), so it is endless and cheap: a handful of instanced meshes, no shadows, no external assets. Three cameras
// (chase, side, driver), a day/night look from the game clock, NPC traffic, other players' cars with name tags, road-event
// props that stop the car, and the destination gate. All React state stays outside the frame loop (refs only).
import { Canvas, useFrame, useThree } from '@react-three/fiber';
import { useEffect, useRef, type MutableRefObject } from 'react';
import {
  AdditiveBlending,
  CanvasTexture,
  Color,
  DirectionalLight,
  Fog,
  Group,
  HemisphereLight,
  InstancedMesh,
  Mesh,
  MeshBasicMaterial,
  MeshLambertMaterial,
  Object3D,
  PerspectiveCamera,
  PlaneGeometry,
  SRGBColorSpace,
  Vector3,
  BufferGeometry,
  Float32BufferAttribute,
  Points,
  PointsMaterial,
} from 'three';
import type { DriveKind } from '../../../api/drive';
import { cityLight } from '../../city3d/engine/light';
import { CRUISE, roadAt, type CamMode, type RoadSeg, type VehicleKind, type VehicleLook } from '../model';
import { buildCockpit, buildEventProps, buildGate, buildSign, gateAccent, type Cockpit, type EventProps, type Gate } from './props';
import { vehicleGeometry } from './vehicles';
import { buildWorld, LANE_IN, LANE_OUT, PERIOD } from './world';

/** The player's lane: the outer lane, by the pavement. */
export const MY_LANE = LANE_OUT;

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
  /** The trip has arrived (the server moved the player): park at the gate. */
  arrived: boolean;
}

export interface DriveApi {
  stats(): { calls: number; triangles: number; geometries: number };
  /** Dev: jump the car forward / set the speed (screenshots). */
  dev(patch: { dist?: number; speed?: number }): void;
}

export interface DriveSceneProps {
  hour: number;
  tier: 'low' | 'high';
  vehicle: VehicleLook;
  cam: CamMode;
  roads: RoadSeg[];
  destName: string;
  destScene: string;
  live: MutableRefObject<DriveLive>;
  /** Stop the car for a road event (a new `id` per event). */
  event: { id: number; kind: DriveKind } | null;
  /** The player chose: let the props react and drive on. */
  resolved: { id: number; ok: boolean } | null;
  /** "Go in": open the barrier and drive through the gate. */
  entering: boolean;
  others: OtherCar[];
  seed?: number;
  paused?: boolean;
  /** Dev (screenshots): start at this distance and speed. */
  startAt?: { dist?: number; stopped?: boolean };
  onStopped?: (id: number) => void;
  onReady?: (api: DriveApi) => void;
  onLost?: () => void;
}

type NpcKind = VehicleKind | 'okada2';
interface Npc {
  kind: NpcKind;
  lane: number;
  v: number;
  z: number;
  idx: number;
  color: Color;
}

const NPC_KINDS: NpcKind[] = ['sedan', 'sedan', 'suv', 'keke', 'okada2', 'moto', 'bus', 'pickup', 'sedan', 'keke', 'moto'];
const NPC_COLORS = ['#c3c7cd', '#4a5d7a', '#a23c36', '#efebe0', '#5a8068', '#6c7480', '#aab3bd', '#7d8ca0', '#9a7650', '#d6d1c2'];
const RING_LEN = 210;
const RING_FAR = -160;

const hash = (s: string) => {
  let h = 2166136261;
  for (let i = 0; i < s.length; i++) h = Math.imul(h ^ s.charCodeAt(i), 16777619);
  return h >>> 0;
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

function Rig(p: DriveSceneProps) {
  const { scene, camera, gl } = useThree();
  const P = useRef(p);
  P.current = p;
  const st = useRef<{
    tick: (dt: number) => void;
    light: (hour: number) => void;
    dispose: () => void;
    api: DriveApi;
  } | null>(null);

  // build once per tier / vehicle / route; the per-frame state lives in the closure
  const lookKey = `${p.vehicle.kind}|${p.vehicle.color}|${p.tier}|${p.destName}|${p.roads.map((r) => r.name).join('>')}`;
  useEffect(() => {
    const cam = camera as PerspectiveCamera;
    const low = P.current.tier === 'low';
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
    fill.position.set(-30, 18, 26);
    root.add(hemi, sun, sun.target, fill);
    const fog = new Fog('#cfe5f1', low ? 24 : 32, low ? 105 : 150);
    scene.fog = fog;

    const world = buildWorld({ seed: P.current.seed ?? 7, density: low ? 0.6 : 1 });
    root.add(world.fixed, world.scroll);

    // ---- the player's vehicle
    const carMat = own(new MeshLambertMaterial({ vertexColors: true, color: P.current.vehicle.color }));
    const car = new Group();
    const carMesh = new Mesh(vehicleGeometry(P.current.vehicle.kind), carMat);
    car.add(carMesh);
    const shadowTex = own(radialTexture());
    const shadow = new Mesh(own(new PlaneGeometry(3.4, 6.4)), own(new MeshBasicMaterial({ map: shadowTex, transparent: true, depthWrite: false })));
    shadow.rotation.x = -Math.PI / 2;
    shadow.position.y = 0.06;
    car.add(shadow);
    const beamTex = own(beamTexture());
    const beamMat = own(new MeshBasicMaterial({ map: beamTex, transparent: true, depthWrite: false, blending: AdditiveBlending, opacity: 0 }));
    const beamGeo = own(new PlaneGeometry(2.6, 16));
    const beams = [-0.62, 0.62].map((x) => {
      const b = new Mesh(beamGeo, beamMat);
      b.rotation.x = -Math.PI / 2;
      b.position.set(x * 1.4, 0.08, -10.5);
      car.add(b);
      return b;
    });
    const wide = P.current.vehicle.kind === 'moto' || P.current.vehicle.kind === 'bike';
    if (wide) beams.forEach((b, i) => (b.visible = i === 0));
    root.add(car);

    const cockpit: Cockpit = buildCockpit(P.current.vehicle.kind);
    cam.add(cockpit.group);
    cockpit.group.visible = false;

    // ---- NPC traffic: one instanced mesh per kind
    const npcMats = own(new MeshLambertMaterial({ vertexColors: true }));
    const npcs: Npc[] = [];
    const nCars = low ? 9 : 16;
    const perLane = [Math.ceil(nCars * 0.4), Math.floor(nCars * 0.6)];
    const lanes = [-LANE_IN, -LANE_OUT];
    const speeds = [-15, -12];
    for (let li = 0; li < 2; li++) {
      for (let i = 0; i < perLane[li]; i++) {
        const k = NPC_KINDS[(i * 3 + li * 5 + (P.current.seed ?? 7)) % NPC_KINDS.length];
        const col = k === 'keke' ? '#e3b53c' : k === 'bus' ? '#e9e6dc' : NPC_COLORS[(i * 7 + li * 3) % NPC_COLORS.length];
        npcs.push({ kind: k, lane: lanes[li], v: speeds[li], z: 30 - (i + 0.2 + li * 0.45) * (RING_LEN / perLane[li]), idx: 0, color: new Color(col) });
      }
    }
    const kinds = [...new Set(npcs.map((n) => n.kind))];
    const npcMesh = new Map<NpcKind, InstancedMesh>();
    for (const k of kinds) {
      const count = npcs.filter((n) => n.kind === k).length;
      const im = new InstancedMesh(vehicleGeometry(k), npcMats, count);
      im.frustumCulled = false;
      root.add(im);
      npcMesh.set(k, im);
    }
    const dummy = new Object3D();

    // ---- other players' cars (a pool of 8) and their name tags
    const otherPool = Array.from({ length: 8 }, () => {
      const m = new Mesh(vehicleGeometry('sedan'), own(new MeshLambertMaterial({ vertexColors: true })));
      m.visible = false;
      root.add(m);
      return { mesh: m, id: '' as string, z: 0, slot: 0 };
    });
    const tagLayer = gl.domElement.closest('.drive-canvas')?.querySelector('.drive-tags') as HTMLElement | null;

    // ---- signs
    const signs = [0, 1, 2].map((i) => {
      const s = buildSign();
      s.group.position.set(ROAD_HALF_SIGN, 0, -40 - i * 130);
      root.add(s.group);
      return { s, z: -40 - i * 130, key: '' };
    });
    const SIGN_GAP = 130;

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

    // ---- state
    let dist = P.current.startAt?.dist ?? 0;
    let speed = P.current.startAt?.stopped ? 0 : CRUISE * 0.9;
    let carX = MY_LANE;
    let t = 0;
    let skyTex: CanvasTexture | null = null;
    let lastLightKey = '';
    let dark = 0;
    let ev: { id: number; kind: DriveKind; props: EventProps; D: number; t0: number; stopped: boolean; released: boolean; shift: number; ok: boolean; seed: number } | null = null;
    let evSeen = 0;
    let gate: { g: Gate; D: number; open: number } | null = null;
    let camSnap = 3;
    let lastSteer = 0;
    const camPos = new Vector3(0, 3, 8);
    const camLook = new Vector3(0, 1, -10);
    const wantPos = new Vector3();
    const wantLook = new Vector3();
    let othersKey = '';
    let hideOthers = false;
    let othersResetAt = -1;
    const slotOf = new Map<string, number>();

    const applyLight = (hour: number) => {
      const c = cityLight(hour);
      dark = c.dark;
      const key = `${Math.round(c.dark * 20)}|${c.sky}`;
      if (key === lastLightKey) return;
      lastLightKey = key;
      hemi.color.set(c.hemiSky);
      hemi.groundColor.set(c.hemiGround).lerp(new Color(c.hemiSky), 0.3);
      hemi.intensity = c.hemi * 1.3;
      fill.intensity = 0.2 + (1 - c.dark) * 0.55;
      sun.color.set(c.sun);
      sun.intensity = c.sunI * 0.6;
      sun.position.set(c.sunDir[0] * 60, Math.max(20, c.sunDir[1] * 60), c.sunDir[2] * 60 + 10);
      fog.color.set(c.sky);
      skyTex?.dispose();
      skyTex = skyTexture(c);
      scene.background = skyTex;
      world.setDark(c.dark);
      beamMat.opacity = Math.max(0, (c.dark - 0.25) / 0.75) * 0.55;
      if (stars) (stars.material as PointsMaterial).opacity = Math.max(0, (c.dark - 0.55) / 0.45) * 0.9;
      cockpit.setLook(P.current.vehicle.color, c.dark);
      gate?.g.setDark(c.dark);
    };
    applyLight(P.current.hour);

    const roadName = (f: number) => roadAt(P.current.roads, Math.min(1, Math.max(0, f))).name;
    const signText = (z: number) => {
      const live = P.current.live.current;
      const secs = Math.max(0, -z) / CRUISE;
      const f = Math.min(1, live.progress + secs / Math.max(5, live.left + 1) * (1 - live.progress));
      return { l1: roadName(f), l2: `Benin City · ${P.current.destName}` };
    };
    signs.forEach((sg, i) => {
      const f = signText(sg.z);
      sg.s.setText(f.l1, i === 0 ? '' : f.l2);
    });

    const spawnGate = (D: number) => {
      const g = buildGate(P.current.destName, gateAccent(P.current.destScene));
      g.setDark(dark);
      g.group.position.set(0, 0, 0);
      root.add(g.group);
      gate = { g, D, open: 0 };
    };

    const stats = () => ({ calls: gl.info.render.calls, triangles: gl.info.render.triangles, geometries: gl.info.memory.geometries });
    const api: DriveApi = {
      stats,
      dev(patch) {
        if (patch.dist !== undefined) dist = patch.dist;
        if (patch.speed !== undefined) speed = patch.speed;
      },
    };

    const tick = (dtRaw: number) => {
      const dt = Math.min(0.05, dtRaw);
      t += dt;
      const props = P.current;
      const live = props.live.current;
      applyLight(props.hour);

      // ---- events: a new request spawns the props ahead
      if (props.event && props.event.id !== evSeen) {
        evSeen = props.event.id;
        ev?.props.dispose();
        if (ev) root.remove(ev.props.group);
        const ep = buildEventProps(props.event.kind, evSeen);
        root.add(ep.group);
        ev = { id: evSeen, kind: props.event.kind, props: ep, D: dist + 62, t0: t, stopped: false, released: false, shift: 0, ok: true, seed: evSeen };
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

      // ---- the gate: appears as the trip ends
      if (!gate && (live.arrived || (live.left <= 6 && live.progress > 0.5)) && !props.entering) {
        spawnGate(dist + (live.arrived ? 46 : Math.min(90, Math.max(46, live.left * CRUISE * 0.85))));
      }

      // ---- speed: cruise, brake for an event or the gate, resume
      let target = CRUISE * (0.93 + Math.sin(t * 0.35) * 0.05);
      let stopD: number | null = null;
      if (ev && !ev.released) stopD = ev.D - ev.props.gap - 2.4;
      else if (gate && !props.entering) stopD = gate.D - 15;
      if (props.entering) target = 7;
      if (stopD !== null) {
        const rem = stopD - dist;
        target = rem < 0.15 ? 0 : Math.min(target, Math.sqrt(2 * 8 * Math.max(0, rem)) + 0.2);
      }
      const dv = target - speed;
      speed += Math.max(-16 * dt, Math.min(dv, 4.2 * dt));
      if (speed < 0.02 && target === 0) speed = 0;
      dist += speed * dt;
      if (ev && !ev.stopped && !ev.released && speed < 0.4 && stopD !== null && stopD - dist < 1) {
        ev.stopped = true;
        props.onStopped?.(ev.id);
      }

      // ---- world scroll
      world.scroll.position.z = dist % PERIOD;

      // ---- player
      const targetX = MY_LANE;
      const sway = speed > 1 ? Math.sin(t * 0.55) * 0.12 + Math.sin(t * 1.3) * 0.04 : 0;
      const nx = targetX + sway;
      const steer = (nx - carX) / Math.max(dt, 0.001);
      carX += (nx - carX) * Math.min(1, dt * 3);
      lastSteer += (Math.max(-1, Math.min(1, steer * 0.25)) - lastSteer) * Math.min(1, dt * 6);
      car.position.set(carX, Math.sin(t * 17) * 0.004 * Math.min(1, speed / 6), 0);
      car.rotation.y = -lastSteer * 0.05;
      cockpit.steer(lastSteer * 0.7);

      // ---- gate pose
      if (gate) {
        gate.g.group.position.set(0, 0, -(gate.D - dist));
        const tgt = props.entering ? 1 : 0;
        gate.open += (tgt - gate.open) * Math.min(1, dt * 4);
        gate.g.setOpen(gate.open);
      }
      if (ev) {
        if (ev.released) ev.shift -= ev.props.leaves * dt;
        const z = -(ev.D - dist) + ev.shift;
        ev.props.group.position.set(0, 0, z);
        ev.props.update(dt, t - ev.t0, ev.released, ev.ok);
        if (ev.released && (z > 30 || z < -200)) {
          ev.props.dispose();
          root.remove(ev.props.group);
          ev = null;
        }
      }

      // ---- NPC traffic
      for (const n of npcs) {
        n.z += (speed - n.v) * dt;
        if (n.z > 45) n.z -= RING_LEN;
        else if (n.z < RING_FAR) n.z += RING_LEN;
      }
      for (const k of kinds) npcMesh.get(k)!.count = 0;
      for (const n of npcs) {
        const im = npcMesh.get(n.kind)!;
        dummy.position.set(n.lane, 0, n.z);
        dummy.rotation.set(0, n.v < 0 ? Math.PI : 0, 0);
        dummy.scale.setScalar(1);
        dummy.updateMatrix();
        const i = im.count++;
        im.setMatrixAt(i, dummy.matrix);
        im.setColorAt(i, n.color);
      }
      for (const k of kinds) {
        const im = npcMesh.get(k)!;
        im.instanceMatrix.needsUpdate = true;
        if (im.instanceColor) im.instanceColor.needsUpdate = true;
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
          sl.mesh.geometry = vehicleGeometry(o.look.kind === 'bike' ? 'moto' : o.look.kind);
          (sl.mesh.material as MeshLambertMaterial).color.set(o.look.color);
        });
      }
      const tagEls = tagLayer ? Array.from(tagLayer.children) as HTMLElement[] : [];
      const tagById = new Map(tagEls.map((e) => [e.dataset.id ?? '', e]));
      const sz = gl.domElement.clientWidth;
      const sh = gl.domElement.clientHeight;
      const tagPlaced: { x: number; y: number; z: number; el: HTMLElement; op: number }[] = [];
      for (const o of props.others) {
        const s = slotOf.get(o.id);
        if (s === undefined) continue;
        const sl = otherPool[s];
        const vo = CRUISE + 4 + (hash(o.id) % 5) * 0.2;
        if (!hideOthers) sl.z += (speed - vo) * dt;
        if (sl.z < RING_FAR) sl.z += RING_LEN * 0.8;
        if (sl.z > 45) sl.z = 45 - (sl.z - 45);
        const show = !hideOthers && sl.z < 30 && sl.z > -120 && !(sl.z > -6 && sl.z < 6);
        sl.mesh.visible = show;
        sl.mesh.position.set(LANE_IN, 0, sl.z);
        const el = tagById.get(o.id);
        if (el) {
          if (show && sl.z < 4 && sl.z > -48) {
            _tmp.set(LANE_IN, 2.1, sl.z).project(cam);
            if (_tmp.z < 1) {
              const tx = (_tmp.x * 0.5 + 0.5) * sz;
              const ty = (-_tmp.y * 0.5 + 0.5) * sh;
              el.style.transform = `translate(${tx}px, ${ty}px) translate(-50%, -100%)`;
              tagPlaced.push({ x: tx, y: ty, z: sl.z, el, op: Math.max(0, Math.min(1, (48 + sl.z) / 16)) });
            } else el.style.opacity = '0';
          } else el.style.opacity = '0';
        }
      }
      // nearer cars keep their tag; a farther tag that would overlap one already shown is hidden
      tagPlaced.sort((a, b) => b.z - a.z);
      const tagShown: { x: number; y: number; w: number }[] = [];
      for (const t of tagPlaced) {
        if (!t.el.dataset.w) t.el.dataset.w = String(t.el.offsetWidth || 80); // measured once, not every frame
        const w = Number(t.el.dataset.w);
        const clash = tagShown.some((q) => Math.abs(q.x - t.x) < (q.w + w) / 2 + 4 && Math.abs(q.y - t.y) < 26);
        t.el.style.opacity = clash ? '0' : String(t.op);
        if (!clash) tagShown.push({ x: t.x, y: t.y, w });
      }

      // ---- signs
      for (const sg of signs) {
        sg.z += speed * dt;
        if (sg.z > 14) {
          sg.z -= SIGN_GAP * signs.length;
          const f = signText(sg.z);
          sg.s.setText(f.l1, f.l2);
        }
        sg.s.group.position.z = sg.z;
      }

      // ---- cameras
      const mode = props.cam;
      const kind = props.vehicle.kind;
      const small = kind === 'moto' || kind === 'bike' || kind === 'keke';
      const arrived = live.arrived || props.entering;
      // field of view from the horizontal view we want, so phones (tall) and desktops (wide) frame the car the same way
      const asp = Math.max(0.3, cam.aspect);
      const vf = (hdeg: number) => Math.min(88, (2 * Math.atan(Math.tan((hdeg * Math.PI) / 360) / asp) * 180) / Math.PI);
      let fov = vf(54);
      if (arrived && gate) {
        // gate shot: behind and to the left of the car, the arch ahead
        const gz = -(gate.D - dist);
        wantPos.set(carX - 4.2 + Math.sin(t * 0.25) * 0.5, 3.2, 10.5);
        wantLook.set(1.2, 3.0, gz + 2);
        fov = vf(66);
        if (props.entering) {
          wantPos.set(carX - 3.4, 2.8, 7);
          wantLook.set(1.8, 2.8, gz - 2);
        }
      } else if (mode === 'chase') {
        wantPos.set(carX - 0.35, small ? 2.6 : 3.4, small ? 7.8 : 10);
        wantLook.set(carX - 1.2, 1.0, -12);
        fov = vf(small ? 50 : 56);
      } else if (mode === 'side') {
        wantPos.set(0.3, 1.5, 3.2 + Math.sin(t * 0.4) * 0.3);
        wantLook.set(carX, 1.1, 0);
        fov = Math.min(100, (2 * Math.atan(Math.tan(((small ? 40 : 52) * Math.PI) / 360) / asp) * 180) / Math.PI);
      } else {
        wantPos.set(carX - (small ? 0 : 0.38), small ? 1.45 : 1.24, small ? 0.15 : 0.35);
        wantLook.set(carX - (small ? 0 : 0.38) + lastSteer * 1.5, small ? 1.2 : 1.1, -22);
        fov = vf(small ? 62 : 66);
      }
      const k = 1 - Math.exp(-dt * (camSnap > 0 ? 14 : mode === 'inside' ? 9 : 5));
      camSnap = Math.max(0, camSnap - dt);
      camPos.lerp(wantPos, k);
      camLook.lerp(wantLook, k);
      cam.position.copy(camPos);
      if (mode === 'inside' && !arrived) cam.position.y += Math.sin(t * 13) * 0.003 * Math.min(1, speed / 6);
      cam.lookAt(camLook);
      if (Math.abs(cam.fov - fov) > 0.05) {
        cam.fov += (fov - cam.fov) * k;
        cam.updateProjectionMatrix();
      }
      const inside = mode === 'inside' && !arrived;
      cockpit.group.visible = inside;
      carMesh.visible = !inside;
      shadow.visible = !inside;
      beams.forEach((b, i) => (b.visible = (wide ? i === 0 : true) && !inside));
      if (stars) stars.position.copy(cam.position);
    };

    st.current = {
      tick,
      light: applyLight,
      api,
      dispose() {
        scene.remove(root);
        cam.remove(cockpit.group);
        scene.fog = null;
        scene.background = null;
        skyTex?.dispose();
        ev?.props.dispose();
        gate?.g.dispose();
        cockpit.dispose();
        world.dispose();
        owned.forEach((o) => o.dispose());
        npcMesh.forEach((m) => m.dispose());
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

  // dev + context loss
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

const ROAD_HALF_SIGN = 8.9;
const _tmp = new Vector3();

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

