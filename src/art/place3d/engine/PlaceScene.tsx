// L2: the live 3D interior of a place (react-three-fiber). Lazy-loaded through ../PlaceView.tsx.
//
// One orthographic canvas, frameloop="demand", same frame budget as the home (docs/HUD_HOME.md "M1"): every
// frame only while the Sim walks / blends / the camera moves; ~24 fps for idle life and the crowd; 12 fps
// under reduced motion; nothing when hidden. The room + all zone props are 4 merged meshes (props.ts), the
// background crowd is 3 instanced meshes (torso, legs, head) whatever its size, plus one sign plane and the
// player's Sim (~35 calls). Tap the floor to walk (M1 pathing), tap a zone to pick it (the card shows its
// actions) and walk there; queued tasks (M2) walk to their zone, then call onTaskArrive.
import { Canvas, useFrame, useThree, type ThreeEvent } from '@react-three/fiber';
import { useEffect, useMemo, useRef, useState, type CSSProperties } from 'react';
import {
  BoxGeometry,
  CanvasTexture,
  Color,
  CylinderGeometry,
  DirectionalLight,
  DoubleSide,
  Float32BufferAttribute,
  Group,
  HemisphereLight,
  InstancedMesh,
  Matrix4,
  Mesh,
  MeshBasicMaterial,
  MeshLambertMaterial,
  OrthographicCamera,
  PlaneGeometry,
  PointLight,
  Quaternion,
  RingGeometry,
  SRGBColorSpace,
  Vector3,
} from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import type { PlaceZone } from '../../../api/places';
import { mixHex } from '../../../lib/daylight';
import type { AvatarConfig } from '../../../lib/types';
import { avatarKey } from '../../avatar3d/catalog';
import { buildCharacter } from '../../avatar3d/engine/character';
import { applyPose, capturePose, DEFAULT_WALK, gaitFor, mixPose, poseGait, poseLife, POSE_SIZE, resetRig, stepLength } from '../../avatar3d/engine/anim';
import { makeShadow } from '../../avatar3d/engine/scene';
import { homeLight } from '../../home3d/engine/light';
import { poseLie, poseSit, sitRootY } from '../../home3d/engine/poses';
import { planPath, randomFree, type P2 } from '../../sim/nav';
import { angleTo, DEFAULT_GAIT, makeWalker, place, stepWalker, stopWalk, walkPath, type Gait, type Walker } from '../../sim/locomotion';
import { buildPlaceGrid, propMeta, roomFor, zoneSpot, type NpcPlan, type Room, type ZonePose } from '../model';
import { buildPlace } from './props';

export interface PlaceApi {
  snapshot(): string | null;
  stats(): { calls: number; triangles: number; roomTriangles: number; geometries: number };
  bench(n?: number): number;
  /** Screen position (CSS px) of a zone's centre / a room point (tests). */
  screenOfZone(key: string): { x: number; y: number } | null;
  screenOfPoint(x: number, z: number, y?: number): { x: number; y: number };
}

export interface PlaceSceneProps {
  placeId: string;
  placeName: string;
  scene: string;
  zones: PlaceZone[];
  avatar: AvatarConfig;
  hour: number;
  /** Closed now (lights low, a "Closed" feel). */
  closed?: boolean;
  /** Who else is drawn (real players first, then background people), already capped. */
  crowd: NpcPlan[];
  /** The zone picked on the card (ring + marker), or null. */
  selectedZone?: string | null;
  onPickZone?: (key: string) => void;
  /** M2: walk to this zone, then onTaskArrive(key). */
  task?: { key: string; zone: string } | null;
  onTaskArrive?: (key: string) => void;
  onTaskCancel?: (key: string) => void;
  onWalkDone?: () => void;
  /** The zone whose action is running now (the Sim holds its pose), or null. */
  busyZone?: string | null;
  walkLock?: string | null;
  walk?: { speed: number; robeMult: number; tiredSlow: number };
  mood?: { tired: number; happy: number };
  paused?: boolean;
  insetTop?: number;
  insetBottom?: number;
  onReady?: (api: PlaceApi) => void;
  onLost?: () => void;
  className?: string;
  style?: CSSProperties;
}

interface View {
  yaw: number;
  zoom: number;
  dragging: boolean;
  visible: boolean;
  reduced: boolean;
}
interface Gesture {
  t: number;
  x: number;
  y: number;
  multi: boolean;
}
interface Actor {
  w: Walker;
  mode: 'idle' | 'walk' | 'pose';
  pose: ZonePose;
  zone: string | null;
  then: 'idle' | 'pose' | 'task';
  taskKey: string | null;
  manual: boolean;
  nextWander: number;
  phase: number;
  gait: number;
  idleSince: number;
  hot: boolean;
}

const TAP_MS = 550;
const TAP_PX = 8;
const BASE_YAW = Math.PI / 4;
const YAW_RANGE = 0.75;
const ZOOM_MIN = 0.8;
const ZOOM_MAX = 2.2;
const BLEND_S = 0.38;
const MARK_S = 0.7;
const _v = new Vector3();
const _r = new Vector3();
const _u = new Vector3();
const _m = new Matrix4();
const _q = new Quaternion();
const _s = new Vector3();
const _p = new Vector3();
const _yAxis = new Vector3(0, 1, 0);

function Driver({ view, actor, paused, lively }: { view: React.MutableRefObject<View>; actor: React.MutableRefObject<Actor>; paused: boolean; lively: boolean }) {
  const invalidate = useThree((s) => s.invalidate);
  useEffect(() => {
    let raf = 0;
    let last = 0;
    const loop = (now: number) => {
      raf = requestAnimationFrame(loop);
      if (document.hidden || !view.current.visible) return;
      const a = actor.current;
      const hot = a.hot || (!paused && view.current.dragging);
      if (paused && !hot) return;
      // idle life + crowd: 24 fps (dancers read fine), 12 fps reduced motion / quiet rooms
      const fps = view.current.reduced ? 12 : lively ? 24 : 20;
      if (!hot && now - last < 1000 / fps) return;
      last = now;
      invalidate();
    };
    raf = requestAnimationFrame(loop);
    return () => cancelAnimationFrame(raf);
  }, [invalidate, view, actor, paused, lively]);
  return null;
}

/** Where the Sim sits / lies / swims in a zone (world space), or null = stand at the spot. */
function seatOf(z: PlaceZone): { p: P2; y: number; yaw: number } | null {
  const odd = ((z.rot % 4) + 4) % 2 === 1;
  const lw = odd ? z.d : z.w;
  const ld = odd ? z.w : z.d;
  const hw = lw / 2;
  const hd = ld / 2;
  let l: [number, number, number, number] | null = null; // local x, seat y, local z, local yaw
  switch (z.prop) {
    case 'tables': {
      const nx = Math.max(1, Math.round(lw / 1.8));
      const nz = Math.max(1, Math.round(ld / 1.6));
      l = [-hw + lw / nx / 2 - 0.55, 0.45, -hd + ld / nz / 2, Math.PI / 2];
      break;
    }
    case 'vip': {
      const nx = Math.max(1, Math.round(lw / 1.8));
      const nz = Math.max(1, Math.round(ld / 1.6));
      l = [-hw + lw / nx / 2, 0.45, -hd + ld / nz / 2 - 0.45, 0];
      break;
    }
    case 'seats':
      l = [-hw + 0.3 + 0.55, 0.45, -hd + 0.4, Math.PI];
      break;
    case 'lecture':
    case 'desks': {
      const nx = Math.max(1, Math.round(lw / 1.2));
      const nz = Math.max(1, Math.round(ld / 1.1));
      l = [-hw + lw / nx / 2 + (nx > 1 ? lw / nx : 0), 0.45, -hd + (nz - 0.5) * (ld / nz) + 0.4, Math.PI];
      break;
    }
    case 'bench':
      l = [0, 0.45, 0.04, 0];
      break;
    case 'salon_chairs': {
      const n = Math.max(1, Math.round(lw / 1.4));
      l = [-hw + lw / n / 2, 0.5, 0, 0];
      break;
    }
    case 'stands':
      l = [0.35, 0.3 + 0.0, hd - ld / 8, 0];
      break;
    case 'cinema_hall': {
      const rows = Math.max(2, Math.round(ld / 0.9));
      const r = rows - 1;
      l = [-hw + 0.3 + 0.6 * Math.floor(lw / 1.2), r * 0.12 + 0.42, -hd + 0.6 + r * 0.9, Math.PI];
      break;
    }
    case 'trees':
      l = [0.1, 0.06, hd * 0.2, Math.PI];
      break;
    case 'beds':
    case 'bed_lux': {
      const n = Math.max(1, Math.round(lw / 1.4));
      l = [-hw + lw / n / 2, z.prop === 'bed_lux' ? 0.64 : 0.62, 0.85, 0];
      break;
    }
    case 'pool':
      l = [0, -0.62, 0, Math.PI];
      break;
    default:
      return null;
  }
  const yaw = (z.rot * Math.PI) / 2;
  const c = Math.cos(yaw);
  const s = Math.sin(yaw);
  return { p: [z.x + l[0] * c + l[2] * s, z.z - l[0] * s + l[2] * c], y: l[1], yaw: yaw + l[3] };
}

/** Name sign over the back wall (outdoor: on two posts). One plane, one canvas texture. */
function makeSign(name: string, bg: string, ink: string): { mesh: Mesh; dispose: () => void; aspect: number } {
  const c = document.createElement('canvas');
  const ctx = c.getContext('2d')!;
  const label = name.replace(/\s*\(.*\)\s*$/, '').toUpperCase();
  ctx.font = '800 64px Outfit, "Segoe UI", system-ui, sans-serif';
  const tw = Math.ceil(ctx.measureText(label).width);
  c.width = Math.min(2048, tw + 96);
  c.height = 112;
  ctx.fillStyle = bg;
  ctx.fillRect(0, 0, c.width, c.height);
  ctx.fillStyle = 'rgba(255,255,255,0.14)';
  ctx.fillRect(0, 0, c.width, 8);
  ctx.font = '800 64px Outfit, "Segoe UI", system-ui, sans-serif';
  ctx.fillStyle = ink;
  ctx.textBaseline = 'middle';
  ctx.textAlign = 'center';
  ctx.fillText(label, c.width / 2, c.height / 2 + 4, c.width - 48);
  const tex = new CanvasTexture(c);
  tex.colorSpace = SRGBColorSpace;
  tex.anisotropy = 2;
  const mat = new MeshBasicMaterial({ map: tex, side: DoubleSide });
  const geo = new PlaneGeometry(1, 1);
  const mesh = new Mesh(geo, mat);
  return { mesh, aspect: c.width / c.height, dispose: () => { tex.dispose(); mat.dispose(); geo.dispose(); } };
}

/** Low-poly background people: 3 shared geometries for instancing (torso+arms, legs, head+hair). */
function crowdGeometry() {
  const paint = (g: BoxGeometry | CylinderGeometry, col: string) => {
    const c = new Color(col);
    const n = g.attributes.position.count;
    const a = new Float32Array(n * 3);
    for (let i = 0; i < n; i++) { a[i * 3] = c.r; a[i * 3 + 1] = c.g; a[i * 3 + 2] = c.b; }
    g.setAttribute('color', new Float32BufferAttribute(a, 3));
    g.deleteAttribute('uv');
    return g;
  };
  const torso = paint(new BoxGeometry(0.36, 0.55, 0.22).translate(0, 0.275, 0), '#ffffff');
  const armL = paint(new BoxGeometry(0.09, 0.5, 0.11).translate(-0.23, 0.24, 0.0), '#ffffff');
  const armR = paint(new BoxGeometry(0.09, 0.5, 0.11).translate(0.23, 0.24, 0.0), '#ffffff');
  const torsoG = mergeGeometries([torso, armL, armR])!;
  const legL = paint(new BoxGeometry(0.13, 0.78, 0.15).translate(-0.08, 0.39, 0), '#ffffff');
  const legR = paint(new BoxGeometry(0.13, 0.78, 0.15).translate(0.08, 0.39, 0), '#ffffff');
  const legsG = mergeGeometries([legL, legR])!;
  const head = paint(new CylinderGeometry(0.12, 0.11, 0.24, 8).translate(0, 0.12, 0), '#ffffff');
  const hair = paint(new CylinderGeometry(0.125, 0.125, 0.07, 8).translate(0, 0.24, -0.005), '#3a2a22');
  const headG = mergeGeometries([head, hair])!;
  for (const g of [torso, armL, armR, legL, legR, head, hair]) g.dispose();
  return { torsoG, legsG, headG };
}

function Interior(props: PlaceSceneProps & {
  view: React.MutableRefObject<View>;
  actorRef: React.MutableRefObject<Actor>;
  gesture: React.MutableRefObject<Gesture | null>;
  onHint: (text: string, x: number, y: number) => void;
  pillRefs: React.MutableRefObject<Map<string, HTMLSpanElement>>;
}) {
  const { zones, scene: sceneType, hour, view, actorRef, insetTop = 0, insetBottom = 0 } = props;
  const { gl, scene, camera, size, invalidate } = useThree();
  const room: Room = useMemo(() => roomFor(sceneType, zones), [sceneType, zones]);
  const cx = room.W / 2;
  const cz = room.D / 2;
  const grid = useMemo(() => buildPlaceGrid(room, zones), [room, zones]);
  const zoneByKey = useMemo(() => new Map(zones.map((z) => [z.key, z])), [zones]);

  // ---- static room + props: 4 merged meshes
  const built = useMemo(() => buildPlace(room, zones), [room, zones]);
  const mats = useMemo(
    () => ({
      solid: new MeshLambertMaterial({ vertexColors: true, flatShading: true }),
      glow: new MeshBasicMaterial({ vertexColors: true }),
      glass: new MeshBasicMaterial({ color: '#bfe3f7', transparent: true, opacity: 0.78 }),
      screen: new MeshBasicMaterial({ color: '#7ec8ff' }),
      pick: new MeshBasicMaterial({ visible: false }),
      ring: new MeshBasicMaterial({ color: '#17a05c', transparent: true, opacity: 0.32, depthWrite: false }),
      tap: new MeshBasicMaterial({ color: '#17a05c', transparent: true, opacity: 0, depthWrite: false }),
      crowd: new MeshLambertMaterial({ vertexColors: true, flatShading: true }),
    }),
    [],
  );
  const group = useMemo(() => {
    const g = new Group();
    for (const k of ['solid', 'glow', 'glass', 'screen'] as const) {
      const geo = built.layers[k];
      if (!geo) continue;
      const m = new Mesh(geo, mats[k]);
      m.matrixAutoUpdate = false;
      m.updateMatrix();
      g.add(m);
    }
    return g;
  }, [built, mats]);
  useEffect(() => () => { for (const k of ['solid', 'glow', 'glass', 'screen'] as const) built.layers[k]?.dispose(); }, [built]);
  useEffect(() => () => { for (const m of Object.values(mats)) m.dispose(); }, [mats]);

  // ---- sign
  const sign = useMemo(() => makeSign(props.placeName, room.kit.signBg, room.kit.signInk), [props.placeName, room.kit.signBg, room.kit.signInk]);
  useEffect(() => {
    const h = 0.62;
    const w = Math.min(room.W * 0.7, h * sign.aspect);
    sign.mesh.scale.set(w, w / sign.aspect, 1);
    if (room.kit.kind === 'outdoor') sign.mesh.position.set(room.W / 2, 2.35, -0.3);
    else sign.mesh.position.set(Math.min(room.W - w / 2 - 0.3, Math.max(w / 2 + 0.3, room.W * 0.42)), room.kit.wallH - 0.05 + w / sign.aspect / 2, 0.02);
    sign.mesh.updateMatrix();
    invalidate();
  }, [sign, room, invalidate]);
  useEffect(() => () => sign.dispose(), [sign]);

  // ---- zone tap boxes
  const pickGeo = useMemo(() => new BoxGeometry(1, 1, 1), []);
  const picks = useMemo(() => {
    const g = new Group();
    for (const z of zones) {
      const h = propMeta(z.prop).h;
      const m = new Mesh(pickGeo, mats.pick);
      m.scale.set(Math.max(0.6, z.w), h, Math.max(0.6, z.d));
      m.position.set(z.x, h / 2, z.z);
      m.userData.zone = z.key;
      g.add(m);
    }
    return g;
  }, [zones, pickGeo, mats.pick]);
  useEffect(() => () => pickGeo.dispose(), [pickGeo]);

  // ---- selection ring
  const ringGeo = useMemo(() => new PlaneGeometry(1, 1), []);
  const ring = useMemo(() => {
    const m = new Mesh(ringGeo, mats.ring);
    m.rotation.x = -Math.PI / 2;
    m.renderOrder = 2;
    m.visible = false;
    return m;
  }, [ringGeo, mats.ring]);
  useEffect(() => () => ringGeo.dispose(), [ringGeo]);
  useEffect(() => {
    const z = props.selectedZone ? zoneByKey.get(props.selectedZone) : null;
    if (z) {
      ring.scale.set(z.w + 0.4, z.d + 0.4, 1);
      ring.position.set(z.x, 0.03, z.z);
      ring.visible = true;
    } else ring.visible = false;
    invalidate();
  }, [props.selectedZone, zoneByKey, ring, invalidate]);

  // ---- lights: daylight from Benin time; indoor kits keep their lamps on, clubs go dark + party colours
  const lights = useMemo(() => {
    const g = new Group();
    const hemi = new HemisphereLight('#f2f7ff', '#b7a58f', 1.5);
    const sun = new DirectionalLight('#fff1dc', 2);
    const lamp = new PointLight('#ffcf8a', 0, Math.max(room.W, room.D) * 1.6, 1);
    lamp.position.set(room.W / 2 - cx, 2.6, room.D * 0.45 - cz);
    g.add(hemi, sun, lamp);
    return { g, hemi, sun, lamp };
  }, [room, cx, cz]);
  const hourKey = Math.round(hour * 60);
  const closed = Boolean(props.closed);
  useEffect(() => {
    const lt = homeLight(hourKey / 60);
    const kit = room.kit;
    const indoor = kit.kind === 'indoor';
    // indoors the room stays lit: only part of the night darkness comes through
    const dark = indoor ? lt.dark * kit.dimAtNight : lt.dark;
    const base = homeLight(dark >= 0.5 ? 23 : 12);
    const mixT = indoor ? Math.min(1, dark) : 0;
    lights.hemi.color.set(indoor ? mixHex(homeLight(12).hemiSky, base.hemiSky, mixT) : lt.hemiSky);
    lights.hemi.groundColor.set(lt.hemiGround);
    lights.hemi.intensity = kit.party ? (closed ? 1.25 : 0.8 + 0.4 * (1 - lt.dark)) : indoor ? Math.max(1.15, lt.hemi) : lt.hemi;
    lights.sun.color.set(lt.sun);
    lights.sun.intensity = indoor ? Math.max(0.9, lt.sunI * 0.8) : lt.sunI;
    lights.sun.position.set(lt.sunDir[0] * 20, lt.sunDir[1] * 20, lt.sunDir[2] * 20);
    lights.sun.target.position.set(0, 0, 0);
    lights.sun.target.updateMatrixWorld();
    lights.lamp.intensity = kit.party ? (closed ? 0.6 : 2.4) : indoor ? 1.2 + lt.dark * 1.6 : lt.lamp * 0.6;
    lights.lamp.color.set(kit.party && !closed ? '#ff8ad0' : '#ffcf8a');
    mats.glass.color.set(indoor ? lt.glass : '#3fb1d9');
    // screens / light-up floors: off-ish while a party place is closed
    mats.screen.color.set(kit.party ? (closed ? '#3a3350' : '#ff4fa3') : '#7ec8ff');
    mats.glow.color.set(mixHex('#e2dccf', '#ffffff', Math.max(lt.dark, kit.party ? 1 : 0)));
    invalidate();
  }, [hourKey, lights, mats, room, closed, invalidate]);

  // ---- floor tap target + tap marker
  const floorGeo = useMemo(() => new PlaneGeometry(1, 1), []);
  const floor = useMemo(() => {
    const m = new Mesh(floorGeo, mats.pick);
    m.rotation.x = -Math.PI / 2;
    m.scale.set(room.W, room.D, 1);
    m.position.set(room.W / 2, 0, room.D / 2);
    return m;
  }, [floorGeo, mats.pick, room]);
  useEffect(() => () => floorGeo.dispose(), [floorGeo]);
  const tapGeo = useMemo(() => new RingGeometry(0.16, 0.25, 32), []);
  const tapMark = useMemo(() => {
    const m = new Mesh(tapGeo, mats.tap);
    m.rotation.x = -Math.PI / 2;
    m.renderOrder = 3;
    m.visible = false;
    return m;
  }, [tapGeo, mats.tap]);
  useEffect(() => () => tapGeo.dispose(), [tapGeo]);
  const markT0 = useRef(-1);

  // ---- the background crowd (instanced; players first, capped by the parent)
  const crowdGeo = useMemo(() => crowdGeometry(), []);
  useEffect(() => () => { crowdGeo.torsoG.dispose(); crowdGeo.legsG.dispose(); crowdGeo.headG.dispose(); }, [crowdGeo]);
  const crowd = props.crowd;
  const inst = useMemo(() => {
    const n = Math.max(1, crowd.length);
    const torso = new InstancedMesh(crowdGeo.torsoG, mats.crowd, n);
    const legs = new InstancedMesh(crowdGeo.legsG, mats.crowd, n);
    const head = new InstancedMesh(crowdGeo.headG, mats.crowd, n);
    const c = new Color();
    crowd.forEach((p, i) => {
      torso.setColorAt(i, c.set(p.color));
      legs.setColorAt(i, c.set(p.legs));
      head.setColorAt(i, c.set(p.skin));
    });
    for (const m of [torso, legs, head]) {
      m.count = crowd.length;
      m.frustumCulled = false;
      if (m.instanceColor) m.instanceColor.needsUpdate = true;
    }
    const g = new Group();
    g.add(torso, legs, head);
    return { g, torso, legs, head };
  }, [crowd, crowdGeo, mats.crowd]);
  useEffect(() => () => { inst.torso.dispose(); inst.legs.dispose(); inst.head.dispose(); }, [inst]);
  const lively = crowd.some((p) => p.lively) && !closed;
  // pill priority: real players, then standing people nearest the camera (front of the room)
  const crowdOrder = useMemo(() => [...crowd].sort((a, b) => Number(b.player) - Number(a.player) || Number(a.seated) - Number(b.seated) || b.p[1] + b.p[0] * 0.5 - (a.p[1] + a.p[0] * 0.5)), [crowd]);
  const placed = useMemo<[number, number, number, number][]>(() => [], []);
  const salts = useMemo(() => crowd.map((_, i) => (i * 1.7) % 6.28), [crowd]);
  const placeCrowd = (t: number) => {
    crowd.forEach((p, i) => {
      const bounce = p.lively && !view.current.reduced ? Math.abs(Math.sin(t * 5.2 + salts[i])) * 0.09 : 0;
      const sway = p.lively && !view.current.reduced ? Math.sin(t * 2.6 + salts[i]) * 0.35 : 0;
      const breathe = 1 + Math.sin(t * 1.6 + salts[i]) * 0.012;
      _q.setFromAxisAngle(_yAxis, p.yaw + sway);
      const legH = p.seated ? 0.42 : 0.78;
      // legs (seated: short, as if bent under the seat)
      _m.compose(_p.set(p.p[0], bounce, p.p[1]), _q, _s.set(p.female ? 1.12 : 1, p.seated ? 0.54 : 1, p.seated ? 1.6 : 1));
      inst.legs.setMatrixAt(i, _m);
      _m.compose(_p.set(p.p[0], legH + bounce, p.p[1]), _q, _s.set(p.female ? 0.92 : 1, breathe, 1));
      inst.torso.setMatrixAt(i, _m);
      _m.compose(_p.set(p.p[0], legH + 0.6 + bounce, p.p[1]), _q, _s.set(1, 1, 1));
      inst.head.setMatrixAt(i, _m);
    });
    inst.torso.instanceMatrix.needsUpdate = true;
    inst.legs.instanceMatrix.needsUpdate = true;
    inst.head.instanceMatrix.needsUpdate = true;
  };
  useEffect(() => {
    placeCrowd(0);
    invalidate();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [inst]);

  // ---- the Sim
  const key = avatarKey(props.avatar);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  const ch = useMemo(() => buildCharacter(props.avatar), [key]);
  const actorObj = useMemo(() => {
    const g = new Group();
    g.add(makeShadow(0.36));
    return g;
  }, []);
  useEffect(() => {
    actorObj.add(ch.root);
    invalidate();
    return () => ch.dispose();
  }, [ch, actorObj, invalidate]);
  const tune = useMemo(() => gaitFor(ch, { speed: props.walk?.speed ?? DEFAULT_WALK.speed, robeMult: props.walk?.robeMult ?? DEFAULT_WALK.robeMult }), [ch, props.walk?.speed, props.walk?.robeMult]);
  const gait = useMemo<Gait>(() => ({ ...DEFAULT_GAIT, cruise: tune.cruise, brake: 1.5 * Math.max(1, tune.cruise / 1.15) }), [tune]);
  const propsRef = useRef(props);
  propsRef.current = props;
  const buf = useMemo(
    () => ({
      idle: new Float32Array(POSE_SIZE),
      walk: new Float32Array(POSE_SIZE),
      from: new Float32Array(POSE_SIZE),
      prev: new Float32Array(POSE_SIZE),
      fromXf: [0, 0, 0, 0, 0, 0],
      prevXf: [0, 0, 0, 0, 0, 0],
      havePrev: false,
      blendT0: -1,
      key: '',
    }),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [ch],
  );
  const salt = useMemo(() => Math.random() * 10, []);
  const rnd = useMemo(() => {
    let s = 7654321;
    return () => (s = (s * 16807) % 2147483647) / 2147483647;
  }, []);
  const slowMo = () => (import.meta.env.DEV ? Number((window as { __blSlowMo?: number }).__blSlowMo) || 1 : 1);
  const clockRef = useRef({ real: performance.now() / 1000, virt: performance.now() / 1000 });
  const nowS = () => {
    const c = clockRef.current;
    const r = performance.now() / 1000;
    c.virt += (r - c.real) * slowMo();
    c.real = r;
    return c.virt;
  };

  const walkTo = (to: P2, opts: { snap?: boolean; faceTo?: number | null; then?: 'idle' | 'pose' | 'task'; manual?: boolean } = {}) => {
    const a = actorRef.current;
    const plan = planPath(grid, a.w.pos, to, { snapEnd: opts.snap ?? true, round: 0.22 });
    walkPath(a.w, plan.points, opts.faceTo ?? null);
    a.mode = 'walk';
    a.then = opts.then ?? 'idle';
    a.manual = Boolean(opts.manual);
    if (a.then !== 'task') a.taskKey = null;
    return plan;
  };

  // arrival: walk in from the entrance (or stay where we were if the busy zone is known)
  useEffect(() => {
    const a = actorRef.current;
    a.idleSince = nowS();
    const busy = propsRef.current.busyZone ? zoneByKey.get(propsRef.current.busyZone) : null;
    if (busy) {
      const s = zoneSpot(busy, room);
      place(a.w, s.p, s.yaw);
      a.mode = 'pose';
      a.zone = busy.key;
      a.pose = propMeta(busy.prop).pose;
      invalidate();
      return;
    }
    const start: P2 = [room.entry[0], room.D + 0.4];
    place(a.w, start, Math.PI);
    const target: P2 = [room.W / 2 + (rnd() - 0.5) * 2, room.D - 2.2];
    const plan = planPath(grid, start, target, { snapEnd: true, round: 0.22 });
    walkPath(a.w, plan.points, Math.PI);
    a.mode = 'walk';
    a.then = 'idle';
    a.nextWander = performance.now() + 18000;
    invalidate();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [room, grid]);

  // the running action's zone: hold its pose (the Sim already walked there)
  const busyZone = props.busyZone ?? null;
  useEffect(() => {
    const a = actorRef.current;
    const z = busyZone ? zoneByKey.get(busyZone) : null;
    if (z) {
      a.taskKey = null;
      const s = zoneSpot(z, room);
      if (Math.hypot(a.w.pos[0] - s.p[0], a.w.pos[1] - s.p[1]) > 0.6 && a.mode !== 'pose') {
        walkTo(s.p, { faceTo: s.yaw, then: 'pose' });
      } else {
        if (a.mode !== 'pose') place(a.w, s.p, s.yaw);
        a.mode = 'pose';
      }
      a.zone = z.key;
      a.pose = propMeta(z.prop).pose;
    } else if (a.mode === 'pose' || (a.mode === 'walk' && a.then === 'pose')) {
      const was = a.zone ? zoneByKey.get(a.zone) : null;
      if (was && a.mode === 'pose') {
        const s = zoneSpot(was, room);
        place(a.w, s.p, s.yaw);
      }
      a.mode = 'idle';
      a.zone = null;
      a.idleSince = nowS();
      a.nextWander = Math.max(a.nextWander, performance.now() + 12000);
    }
    invalidate();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [busyZone, zoneByKey, room]);

  // M2: walk to the next queued task's zone; the action starts on arrival
  const task = props.task ?? null;
  const taskKey = task?.key ?? null;
  useEffect(() => {
    const a = actorRef.current;
    if (!task) {
      if (a.mode === 'walk' && a.then === 'task') {
        stopWalk(a.w);
        a.then = 'idle';
      }
      a.taskKey = null;
      invalidate();
      return;
    }
    if (a.taskKey === task.key) return;
    const z = zoneByKey.get(task.zone);
    if (a.mode === 'pose') {
      const was = a.zone ? zoneByKey.get(a.zone) : null;
      if (was) place(a.w, zoneSpot(was, room).p, a.w.yaw);
      a.mode = 'idle';
      a.zone = null;
    }
    if (!z) {
      a.taskKey = null;
      propsRef.current.onTaskArrive?.(task.key);
      return;
    }
    const s = zoneSpot(z, room);
    a.taskKey = task.key;
    a.nextWander = performance.now() + 45000;
    if (Math.hypot(a.w.pos[0] - s.p[0], a.w.pos[1] - s.p[1]) < 0.08 && a.mode !== 'walk') {
      a.taskKey = null;
      propsRef.current.onTaskArrive?.(task.key);
      return;
    }
    walkTo(s.p, { faceTo: s.yaw, then: 'task' });
    a.taskKey = task.key;
    invalidate();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [taskKey, zoneByKey, room]);

  // ---- camera: orthographic, isometric from the south-east, the room framed between the HUD insets
  useEffect(() => {
    const cam = camera as OrthographicCamera;
    const v = view.current;
    const d = 40;
    cam.position.set(Math.sin(v.yaw) * d, d * 0.82, Math.cos(v.yaw) * d);
    cam.lookAt(0, 0, 0);
    cam.updateMatrixWorld();
    let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
    for (const x of [0, room.W]) for (const z of [0, room.D]) for (const y of [0, room.kit.wallH]) {
      _v.set(x - cx, y, z - cz).applyMatrix4(cam.matrixWorldInverse);
      minX = Math.min(minX, _v.x); maxX = Math.max(maxX, _v.x);
      minY = Math.min(minY, _v.y); maxY = Math.max(maxY, _v.y);
    }
    const availH = Math.max(120, size.height - insetTop - insetBottom);
    const fit = Math.min(size.width / ((maxX - minX) * 1.06), availH / ((maxY - minY) * 1.08));
    cam.zoom = fit * v.zoom;
    _r.setFromMatrixColumn(cam.matrixWorld, 0).multiplyScalar((minX + maxX) / 2);
    _u.setFromMatrixColumn(cam.matrixWorld, 1).multiplyScalar((minY + maxY) / 2);
    cam.position.add(_r).add(_u);
    cam.updateMatrixWorld();
    const shift = (insetTop - insetBottom) / 2;
    if (Math.abs(shift) > 1) cam.setViewOffset(size.width, size.height, 0, -shift, size.width, size.height);
    else cam.clearViewOffset();
    cam.updateProjectionMatrix();
    invalidate();
  });

  // ---- per frame
  const partyT = useRef(0);
  useFrame((state, dt) => {
    const a = actorRef.current;
    const t = state.clock.elapsedTime;
    const now = nowS();
    const step = Math.min(dt, 0.1) * slowMo();
    const root = ch.root;
    root.rotation.set(0, 0, 0);
    root.position.set(0, 0, 0);
    const mood = propsRef.current.mood;
    const tired = mood?.tired ?? 0;
    const happy = mood?.happy ?? 0;

    // idle wander (short, rarely)
    if (a.mode === 'idle' && !propsRef.current.busyZone && !propsRef.current.task && !propsRef.current.walkLock && performance.now() > a.nextWander && now - a.idleSince > 6) {
      const p = randomFree(grid, rnd, [0.6, 0.6, room.W - 0.6, room.D - 0.6]);
      a.nextWander = performance.now() + 18000 + rnd() * 20000;
      if (p) walkTo(p);
    }

    if (a.mode === 'walk') {
      const tiredSlow = Math.max(0, Math.min(0.8, propsRef.current.walk?.tiredSlow ?? 0.18));
      const r = stepWalker(a.w, step, gait, 1 - tiredSlow * tired + 0.05 * happy);
      a.phase += r.moved / (2 * stepLength(ch, Math.max(0.25, a.gait), tune.strideScale));
      if (a.w.turning) a.phase += (r.turned * 0.16) / (2 * stepLength(ch, 0.3));
      if (r.arrived) {
        const then = a.then;
        const k = a.taskKey;
        const manual = a.manual;
        a.mode = then === 'pose' ? 'pose' : 'idle';
        a.then = 'idle';
        a.manual = false;
        a.idleSince = now;
        if (then === 'task' && k) {
          a.taskKey = null;
          window.setTimeout(() => propsRef.current.onTaskArrive?.(k), 0);
        } else if (manual) window.setTimeout(() => propsRef.current.onWalkDone?.(), 0);
      }
    }
    const gaitTarget = a.mode === 'walk' ? Math.max(Math.min(1, a.w.speed / gait.cruise), a.w.turning ? 0.3 : 0) : 0;
    a.gait += (gaitTarget - a.gait) * (1 - Math.exp(-step * 9));
    if (a.gait < 0.004) a.gait = 0;

    let x = a.w.pos[0];
    let y = 0;
    let z = a.w.pos[1];
    let yaw = a.w.yaw;
    const life = { tired, happy, reduced: view.current.reduced, idleFor: a.mode === 'walk' ? 0 : now - a.idleSince };
    const zone = a.mode === 'pose' && a.zone ? zoneByKey.get(a.zone) : null;
    if (zone && (a.pose === 'sit' || a.pose === 'lie' || a.pose === 'swim')) {
      const seat = seatOf(zone);
      resetRig(ch);
      if (seat) {
        [x, z] = seat.p;
        yaw = seat.yaw;
      }
      if (a.pose === 'lie' && seat) {
        y = seat.y;
        root.rotation.x = -Math.PI / 2;
        poseLie(ch, t);
      } else if (a.pose === 'swim') {
        y = seat ? seat.y : -0.6;
        poseLife(ch, t, salt, life);
        ch.rig.armL.rotation.z = 1.1 + Math.sin(t * 2) * 0.3;
        ch.rig.armR.rotation.z = -1.1 - Math.sin(t * 2) * 0.3;
      } else {
        poseSit(ch, t, salt);
        root.position.y = sitRootY(ch, seat ? seat.y : 0.45);
      }
    } else if (zone && a.pose === 'dance' && !view.current.reduced) {
      // dance in place: the walk cycle without moving, plus a bounce and a slow turn
      a.phase += step * 1.5;
      poseGait(ch, a.phase, 0.75, { ...life, strideScale: 0.6 });
      root.position.y = Math.abs(Math.sin(a.phase * Math.PI * 2)) * 0.05;
      ch.rig.armL.rotation.x = -1.2 + Math.sin(t * 6) * 0.5;
      ch.rig.armR.rotation.x = -1.2 - Math.sin(t * 6) * 0.5;
      yaw = a.w.yaw + Math.sin(t * 0.9) * 0.6;
    } else if (a.gait <= 0) {
      poseLife(ch, t, salt, life);
    } else if (a.gait >= 0.995) {
      poseGait(ch, a.phase, 1, { ...life, strideScale: tune.strideScale });
    } else {
      poseLife(ch, t, salt, life);
      capturePose(ch, buf.idle);
      poseGait(ch, a.phase, a.gait, { ...life, strideScale: tune.strideScale });
      capturePose(ch, buf.walk);
      const g = a.gait;
      applyPose(ch, mixPose(buf.walk, buf.idle, buf.walk, g * g * (3 - 2 * g)));
    }

    // blend between states (sit down, stand up, start dancing)
    const stateKey = a.mode === 'pose' ? `pose:${a.pose}:${a.zone ?? ''}` : 'free';
    if (stateKey !== buf.key) {
      if (buf.havePrev && !view.current.reduced) {
        buf.from.set(buf.prev);
        for (let i = 0; i < 6; i++) buf.fromXf[i] = buf.prevXf[i];
        buf.blendT0 = now;
      } else buf.blendT0 = -1;
      buf.key = stateKey;
    }
    let rootRotX = root.rotation.x;
    let rootY = root.position.y;
    let blending = false;
    if (buf.blendT0 >= 0) {
      const u = (now - buf.blendT0) / BLEND_S;
      if (u >= 1) buf.blendT0 = -1;
      else {
        blending = true;
        const e = u * u * (3 - 2 * u);
        capturePose(ch, buf.walk);
        applyPose(ch, mixPose(buf.walk, buf.from, buf.walk, e));
        const f = buf.fromXf;
        x = f[0] + (x - f[0]) * e;
        y = f[1] + (y - f[1]) * e;
        z = f[2] + (z - f[2]) * e;
        yaw = f[3] + angleTo(f[3], yaw) * e;
        rootRotX = f[4] + (rootRotX - f[4]) * e;
        rootY = f[5] + (rootY - f[5]) * e;
      }
    }
    root.rotation.x = rootRotX;
    root.position.y = rootY;
    capturePose(ch, buf.prev);
    const px = buf.prevXf;
    px[0] = x; px[1] = y; px[2] = z; px[3] = yaw; px[4] = rootRotX; px[5] = rootY;
    buf.havePrev = true;

    let marking = false;
    if (markT0.current >= 0) {
      const u = (now - markT0.current) / MARK_S;
      if (u >= 1) {
        markT0.current = -1;
        tapMark.visible = false;
      } else {
        marking = true;
        const e = 1 - Math.pow(1 - u, 3);
        tapMark.scale.setScalar(0.7 + 0.55 * e);
        mats.tap.opacity = 0.95 * (1 - u * u);
      }
    }
    actorObj.position.set(x, y, z);
    actorObj.rotation.y = yaw;
    const shadow = actorObj.children[0];
    shadow.position.y = -y + 0.002;
    shadow.visible = rootRotX > -0.5 && a.pose !== 'swim';

    // crowd + party lights
    if (crowd.length && (lively || !view.current.reduced)) placeCrowd(t);
    if (room.kit.party && !closed && !view.current.reduced) {
      partyT.current += step;
      const h = (partyT.current * 0.12) % 1;
      mats.screen.color.setHSL(h, 0.85, 0.6);
    }

    // name pills follow their heads (DOM transforms, no React render)
    // players first, then people nearest the camera; a pill that would overlap one already placed hides
    const pills = props.pillRefs.current;
    if (pills.size) {
      placed.length = 0;
      for (const p of crowdOrder) {
        const el = pills.get(p.id);
        if (!el) continue;
        _v.set(p.p[0] - cx, (p.seated ? 1.38 : 1.82) + 0.12, p.p[1] - cz).project(camera);
        const sx = ((_v.x + 1) / 2) * size.width;
        const sy = ((1 - _v.y) / 2) * size.height;
        const w = (el.offsetWidth || 60) + 4;
        const h = (el.offsetHeight || 18) + 2;
        const hit = placed.some((r) => Math.abs(r[0] - sx) < (r[2] + w) / 2 && Math.abs(r[1] - sy) < (r[3] + h) / 2);
        if (!hit) placed.push([sx, sy, w, h]);
        el.style.opacity = hit ? '0' : '1';
        el.style.transform = `translate3d(${sx}px, ${sy}px, 0) translate(-50%, -100%)`;
      }
    }
    a.hot = a.mode === 'walk' || a.gait > 0 || blending || marking;
  });

  // ---- API
  useEffect(() => {
    const api: PlaceApi = {
      snapshot() {
        try {
          gl.render(scene, camera);
          return gl.domElement.toDataURL('image/jpeg', 0.82);
        } catch {
          return null;
        }
      },
      stats() {
        gl.render(scene, camera);
        return { calls: gl.info.render.calls, triangles: gl.info.render.triangles, roomTriangles: built.tris, geometries: gl.info.memory.geometries };
      },
      bench(n = 60) {
        const ctx = gl.getContext();
        gl.render(scene, camera);
        ctx.finish();
        const t0 = performance.now();
        for (let i = 0; i < n; i++) gl.render(scene, camera);
        ctx.finish();
        return (performance.now() - t0) / n;
      },
      screenOfZone(k) {
        const zz = zoneByKey.get(k);
        if (!zz) return null;
        _v.set(zz.x - cx, propMeta(zz.prop).h * 0.5, zz.z - cz).project(camera);
        return { x: ((_v.x + 1) / 2) * size.width, y: ((1 - _v.y) / 2) * size.height };
      },
      screenOfPoint(px, pz, py = 0) {
        _v.set(px - cx, py, pz - cz).project(camera);
        return { x: ((_v.x + 1) / 2) * size.width, y: ((1 - _v.y) / 2) * size.height };
      },
    };
    props.onReady?.(api);
    if (import.meta.env.DEV) Object.assign(window, { __place: api, __placeActor: actorRef.current, __placeRoom: room, __placeGrid: grid });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [gl, scene, camera, built, actorRef, room, grid, cx, cz, size, zoneByKey]);

  const isTap = (e: ThreeEvent<MouseEvent>) => {
    const g = props.gesture.current;
    if (e.delta > TAP_PX) return false;
    if (!g) return true;
    return !g.multi && performance.now() - g.t < TAP_MS && Math.hypot(e.nativeEvent.clientX - g.x, e.nativeEvent.clientY - g.y) <= TAP_PX;
  };
  const hint = (e: ThreeEvent<MouseEvent>, text: string) => {
    const r = gl.domElement.getBoundingClientRect();
    const half = Math.min(120, r.width / 2);
    props.onHint(text, Math.max(half, Math.min(r.width - half, e.nativeEvent.clientX - r.left)), Math.max(48, e.nativeEvent.clientY - r.top));
  };

  const onZone = (e: ThreeEvent<MouseEvent>) => {
    if (!isTap(e)) return;
    e.stopPropagation();
    const k = e.object.userData.zone as string | undefined;
    if (!k) return;
    props.onPickZone?.(k);
    const a = actorRef.current;
    if (props.walkLock || props.task || a.mode === 'pose') return;
    const zz = zoneByKey.get(k);
    if (!zz) return;
    const s = zoneSpot(zz, room);
    walkTo(s.p, { faceTo: s.yaw, manual: true });
    a.nextWander = performance.now() + 45000;
    invalidate();
  };

  const onFloor = (e: ThreeEvent<MouseEvent>) => {
    if (!isTap(e)) return;
    e.stopPropagation();
    const a = actorRef.current;
    if (props.walkLock || a.mode === 'pose') {
      hint(e, props.walkLock || 'Busy right now');
      return;
    }
    if (a.mode === 'walk' && a.then === 'task' && a.taskKey) {
      const k = a.taskKey;
      a.taskKey = null;
      props.onTaskCancel?.(k);
    }
    const to: P2 = [e.point.x + cx, e.point.z + cz];
    const plan = walkTo(to, { snap: true, manual: true });
    a.nextWander = performance.now() + 45000;
    tapMark.position.set(plan.end[0], 0.035, plan.end[1]);
    tapMark.visible = true;
    markT0.current = nowS();
    invalidate();
  };

  return (
    <>
      <Driver view={view} actor={actorRef} paused={Boolean(props.paused)} lively={lively} />
      <primitive object={lights.g} />
      <group position={[-cx, 0, -cz]}>
        <primitive object={group} />
        <primitive object={sign.mesh} />
        <primitive object={ring} />
        <primitive object={inst.g} />
        <primitive object={actorObj} />
        <primitive object={tapMark} />
        <primitive object={floor} onClick={onFloor} />
        <primitive object={picks} onClick={onZone}
          onPointerOver={() => { document.body.style.cursor = 'pointer'; }}
          onPointerOut={() => { document.body.style.cursor = ''; }} />
      </group>
    </>
  );
}

export default function PlaceScene(props: PlaceSceneProps) {
  const view = useRef<View>({
    yaw: BASE_YAW,
    zoom: 1,
    dragging: false,
    visible: true,
    reduced: typeof window !== 'undefined' && !!window.matchMedia?.('(prefers-reduced-motion: reduce)').matches,
  });
  const actor = useRef<Actor>({
    w: makeWalker(),
    mode: 'idle',
    pose: 'stand',
    zone: null,
    then: 'idle',
    taskKey: null,
    manual: false,
    nextWander: 0,
    phase: 0,
    gait: 0,
    idleSince: 0,
    hot: false,
  });
  const gesture = useRef<Gesture | null>(null);
  const pillRefs = useRef(new Map<string, HTMLSpanElement>());
  const [tapHint, setTapHint] = useState<{ text: string; x: number; y: number; n: number } | null>(null);
  const hintTimer = useRef(0);
  const onHint = (text: string, x: number, y: number) => {
    setTapHint((h) => ({ text, x, y, n: (h?.n ?? 0) + 1 }));
    window.clearTimeout(hintTimer.current);
    hintTimer.current = window.setTimeout(() => setTapHint(null), 1600);
  };
  useEffect(() => () => window.clearTimeout(hintTimer.current), []);
  const wrap = useRef<HTMLDivElement>(null);
  const pointers = useRef(new Map<number, { x: number; y: number }>());
  const pinch = useRef<{ d: number; zoom: number } | null>(null);
  const [, force] = useState(0);
  const kick = () => force((n) => n + 1);

  useEffect(() => {
    const el = wrap.current;
    if (!el || typeof IntersectionObserver === 'undefined') return;
    const io = new IntersectionObserver((e) => {
      view.current.visible = e.some((x) => x.isIntersecting);
    });
    io.observe(el);
    return () => io.disconnect();
  }, []);
  const alive = useRef(true);
  useEffect(() => {
    alive.current = true;
    return () => {
      alive.current = false;
      document.body.style.cursor = '';
    };
  }, []);
  useEffect(() => {
    const el = wrap.current;
    if (!el) return;
    const onWheel = (e: WheelEvent) => {
      e.preventDefault();
      const v = view.current;
      v.zoom = Math.min(ZOOM_MAX, Math.max(ZOOM_MIN, v.zoom * Math.exp(-e.deltaY * 0.0015)));
      kick();
    };
    el.addEventListener('wheel', onWheel, { passive: false });
    return () => el.removeEventListener('wheel', onWheel);
  }, []);

  const onDown = (e: React.PointerEvent) => {
    pointers.current.set(e.pointerId, { x: e.clientX, y: e.clientY });
    if (pointers.current.size === 1) gesture.current = { t: performance.now(), x: e.clientX, y: e.clientY, multi: false };
    else if (gesture.current) gesture.current.multi = true;
    if (pointers.current.size === 2) {
      const [a, b] = [...pointers.current.values()];
      pinch.current = { d: Math.hypot(a.x - b.x, a.y - b.y), zoom: view.current.zoom };
    }
  };
  const onMove = (e: React.PointerEvent) => {
    const prev = pointers.current.get(e.pointerId);
    if (!prev) return;
    const cur = { x: e.clientX, y: e.clientY };
    pointers.current.set(e.pointerId, cur);
    const v = view.current;
    if (pointers.current.size === 2 && pinch.current) {
      const [a, b] = [...pointers.current.values()];
      const d = Math.hypot(a.x - b.x, a.y - b.y);
      v.zoom = Math.min(ZOOM_MAX, Math.max(ZOOM_MIN, pinch.current.zoom * (d / Math.max(1, pinch.current.d))));
      v.dragging = true;
      kick();
      return;
    }
    const dx = cur.x - prev.x;
    if (Math.abs(dx) > 0 && (e.buttons & 1 || e.pointerType !== 'mouse')) {
      const width = wrap.current?.clientWidth || 360;
      v.yaw = Math.min(BASE_YAW + YAW_RANGE, Math.max(BASE_YAW - YAW_RANGE, v.yaw - (dx / width) * Math.PI * 0.9));
      v.dragging = true;
      kick();
    }
  };
  const onUp = (e: React.PointerEvent) => {
    pointers.current.delete(e.pointerId);
    if (pointers.current.size < 2) pinch.current = null;
    if (pointers.current.size === 0) view.current.dragging = false;
  };

  return (
    <div ref={wrap} className={`place3d${props.className ? ' ' + props.className : ''}`} style={props.style}
      onPointerDown={onDown} onPointerMove={onMove} onPointerUp={onUp} onPointerCancel={onUp} onPointerLeave={onUp}>
      <Canvas
        orthographic
        dpr={[1, 1.5]}
        frameloop="demand"
        flat
        gl={{ antialias: true, alpha: true, powerPreference: 'low-power' }}
        camera={{ position: [28, 22, 28], zoom: 40, near: 0.1, far: 200 }}
        style={{ touchAction: 'none' }}
        onCreated={({ gl }) => {
          gl.domElement.addEventListener('webglcontextlost', (ev) => {
            ev.preventDefault();
            window.setTimeout(() => {
              if (alive.current && wrap.current?.isConnected) props.onLost?.();
            }, 60);
          });
        }}
      >
        <Interior {...props} view={view} actorRef={actor} gesture={gesture} onHint={onHint} pillRefs={pillRefs} />
      </Canvas>
      <div className="place3d__pills" aria-hidden>
        {props.crowd.map((p) => (
          <span key={p.id} ref={(el) => { if (el) pillRefs.current.set(p.id, el); else pillRefs.current.delete(p.id); }}
            className={`place3d__pill${p.player ? ' is-player' : ''}${p.seated && !p.player ? ' is-seated' : ''}`}>
            {p.player && <i className="place3d__dot" />}{p.name}
          </span>
        ))}
      </div>
      {tapHint && (
        <span key={tapHint.n} className="home3d__hint" role="status" style={{ left: tapHint.x, top: tapHint.y }}>
          {tapHint.text}
        </span>
      )}
    </div>
  );
}
