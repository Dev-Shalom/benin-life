// The live 3D home (react-three-fiber). Lazy-loaded through ../HomeView.tsx.
//
// One orthographic canvas, frameloop="demand": it redraws every frame only while the Sim walks,
// blends between poses, a tap marker fades or the player drags; otherwise ~24 fps for the idle life
// (12 fps asleep or under reduced motion), and not at all off-screen or in a hidden tab. Paused
// (a sheet covers it) it only finishes a walk or blend that is under way.
// M1: tap the floor to walk (A* in ../../sim/nav.ts, eased walker in ../../sim/locomotion.ts,
// walk cycle + idle life in avatar3d/engine/anim.ts). Walking is client-side only: the server
// knows nothing about where the Sim stands.
import { Canvas, useFrame, useThree, type ThreeEvent } from '@react-three/fiber';
import { useEffect, useMemo, useRef, useState, type CSSProperties } from 'react';
import {
  BoxGeometry,
  ConeGeometry,
  DirectionalLight,
  Group,
  HemisphereLight,
  Mesh,
  MeshBasicMaterial,
  MeshLambertMaterial,
  OrthographicCamera,
  PlaneGeometry,
  PointLight,
  RingGeometry,
  Vector3,
} from 'three';
import type { AvatarConfig } from '../../../lib/types';
import { avatarKey } from '../../avatar3d/catalog';
import { buildCharacter } from '../../avatar3d/engine/character';
import { applyPose, capturePose, DEFAULT_WALK, gaitFor, legRotationDiff, mixPose, poseGait, poseIdle, poseLife, POSE_SIZE, resetRig, stepLength } from '../../avatar3d/engine/anim';
import { makeShadow } from '../../avatar3d/engine/scene';
import { GROUP_META, itemGroup, KINDS, LAYOUTS, pieceFor, type FurnitureItem, type HomeGroup, type HomeLayout, type HomeLayoutId, type HomePose } from '../model';
import { buildGrid, footprint, planPath, randomFree, toLayout, type P2 } from '../nav';
import { angleTo, DEFAULT_GAIT, makeWalker, place, stepWalker, stopWalk, walkPath, type Gait, type Walker } from '../../sim/locomotion';
import { homeLight } from './light';
import { looksNight, mixHex } from '../../../lib/daylight';
import { poseCook, poseLie, poseScrub, poseSit, sitRootY } from './poses';
import { buildRoom } from './room';
import { LAYERS } from './build';
import { feelQuality, useTier } from '../../feel/quality';
import { rigFor } from '../../feel/rigs';
import { applyFeelRender, makeFan, makeFeelMats, sampleFrames, tickFeel } from '../../feel/scene';

export interface HomeApi {
  /** Render once and return the frame as an image (to show while the canvas is unmounted). */
  snapshot(): string | null;
  stats(): { calls: number; triangles: number; roomTriangles: number; geometries: number };
  /** Render n frames back to back; returns the average ms per frame. */
  bench(n?: number): number;
  /** Screen position (CSS px, relative to the canvas) of a furniture piece's centre, for tests/tutorials. */
  screenOf(id: string): { x: number; y: number } | null;
  /** Screen position of a floor point in layout space (M1 tap tests). */
  screenOfPoint(x: number, z: number, y?: number): { x: number; y: number };
}

export interface HomeSceneProps {
  layoutId: HomeLayoutId;
  /** The layout with the player's own furniture (furnishLayout); keep it memoised. Default: LAYOUTS[layoutId]. */
  layout?: HomeLayout;
  avatar: AvatarConfig;
  /** The home activity running now on the server (key changes with each new run), or null. M2: the Sim
   * normally already stands at the piece (it walked there before the action started); if not, it walks. */
  busy: { group: HomeGroup; key: string; activity?: string; seconds?: number } | null;
  /** M2: a queued task the Sim should walk to now (before its action starts), or null. The scene calls
   * `onTaskArrive(key)` on arrival (at once when the task has no piece of furniture). */
  task?: { key: string; activity: string; group: HomeGroup } | null;
  onTaskArrive?: (key: string) => void;
  /** M2: a floor tap stopped the walk to `task` (the player took over). */
  onTaskCancel?: (key: string) => void;
  /** M2: a walk the player asked for (floor tap) ended. */
  onWalkDone?: () => void;
  /** M2: walk tuning from config (sim.walk_speed, sim.robe_speed_mult, sim.tired_slowdown). */
  walk?: { speed: number; robeMult: number; tiredSlow: number };
  /** Game hour as a float (14.5 = 2:30 pm). */
  hour: number;
  paused?: boolean;
  selectedId?: string | null;
  onPick?: (item: FurnitureItem) => void;
  onReady?: (api: HomeApi) => void;
  onLost?: () => void;
  /** Pixels covered by HUD chrome at the top / bottom, so the house is framed between them. */
  insetTop?: number;
  insetBottom?: number;
  className?: string;
  style?: CSSProperties;
  /** S2 welcome back: seconds per full camera turn around the house. 0 = hold still on the same
   * framing (reduced motion). Undefined = the normal game view (fixed angle, drag ±43°). */
  orbit?: number;
  /** Orbit only: pixels covered on the left (a side card on desktop); the island centres in the rest. */
  insetLeft?: number;
  /** Low walls all round, so the inside reads from every side of the orbit. */
  dollhouse?: boolean;
  /** false = no drag, zoom, furniture or floor taps (welcome screen). Default true. */
  interactive?: boolean;
  /** M1: the Sim is busy with a server action: floor taps don't walk, they show this hint instead. */
  walkLock?: string | null;
  /** M1: mood in the posture, 0..1 each (tired = slump, happy = small bounce). */
  mood?: { tired: number; happy: number };
}

interface View {
  yaw: number;
  zoom: number;
  dragging: boolean;
  visible: boolean;
  reduced: boolean;
}

/** The pointer gesture under way (to tell a tap from a drag, an orbit or a pinch). */
interface Gesture {
  t: number;
  x: number;
  y: number;
  multi: boolean;
}
const TAP_MS = 550;
const TAP_PX = 8;

const BASE_YAW = Math.PI / 4;
/** F1: camera height / distance (was 0.78): a lower, more cinematic look into the room. */
const CAM_ELEV = 0.66;
const YAW_RANGE = 0.75;
const ZOOM_MIN = 0.85;
const ZOOM_MAX = 1.9;
/** Pre-walk to a tapped piece only when it takes at most this long (s); the sheet opens at once anyway. */
const PREWALK_MAX_S = 7;
/** Pose-to-pose blend (stand up, sit down, back to idle after a task), seconds. */
const BLEND_S = 0.42;
/** Tap marker fade, seconds. */
const MARK_S = 0.7;
/** Where the Sim was when the canvas last unmounted (so a short suspend doesn't replay the arrival). */
let memory: { layout: string; pos: P2; yaw: number; at: number } | null = null;
const _v = new Vector3();
const _r = new Vector3();
const _u = new Vector3();

interface Actor {
  w: Walker;
  mode: 'idle' | 'walk' | 'pose';
  pose: HomePose;
  item: FurnitureItem | null;
  /** After the walk: what to do on arrival ('task' = report the arrival so the action can start). */
  then: 'idle' | 'pose' | 'task';
  /** The task being walked to (M2), or null. */
  taskKey: string | null;
  /** The player asked for this walk (floor tap): report when it ends. */
  manual: boolean;
  nextWander: number;
  /** Walk-cycle phase in cycles (advanced by distance, so the feet don't slide). */
  phase: number;
  /** Smoothed walk weight 0..1 (idle <-> walk blend). */
  gait: number;
  /** performance.now()/1000 when the Sim last came to a stop (fidgets fade in after). */
  idleSince: number;
  /** Skip the pose blend on the next change (a far jump: placed at once). */
  noBlend: boolean;
  /** Needs full-rate frames (walking, blending, marker fading). */
  hot: boolean;
}

function Driver({ view, actor, paused, spin }: { view: React.MutableRefObject<View>; actor: React.MutableRefObject<Actor>; paused: boolean; spin: boolean }) {
  const invalidate = useThree((s) => s.invalidate);
  useEffect(() => {
    let raf = 0;
    let last = 0;
    const loop = (now: number) => {
      raf = requestAnimationFrame(loop);
      if (document.hidden || !view.current.visible) return;
      const a = actor.current;
      // full rate while something moves; paused (a sheet over the house) = only finish that
      const hot = a.hot || (!paused && (spin || view.current.dragging));
      if (paused && !hot) return;
      // idle life: breathing and fidgets read fine at 24 fps; asleep / reduced motion 12 fps
      const fps = (a.mode === 'pose' && a.pose === 'lie') || view.current.reduced ? 12 : 24;
      if (!hot && now - last < 1000 / fps) return;
      last = now;
      invalidate();
    };
    raf = requestAnimationFrame(loop);
    return () => cancelAnimationFrame(raf);
  }, [invalidate, view, actor, paused, spin]);
  return null;
}

/** Height of a piece's invisible tap box (tall pieces must stay tappable over what stands in front). */
function pickHeight(f: FurnitureItem): number {
  if (f.kind.includes('stall') || f.kind === 'bucket_bath' || f.kind === 'pit_toilet' || f.kind === 'shower') return 1.8;
  if (f.kind === 'fridge' || f.kind === 'wardrobe' || f.kind === 'bunk' || f.kind === 'locker') return 1.7;
  return 1.1;
}

function spotOf(item: FurnitureItem): { p: P2; yaw: number } {
  const k = KINDS[item.kind];
  const [lx, lz, ly] = k.spot ?? [0, k.d / 2 + 0.35, Math.PI];
  const p = toLayout(item, lx, lz);
  return { p, yaw: ((item.rot ?? 0) * Math.PI) / 2 + ly };
}

function House(props: HomeSceneProps & {
  view: React.MutableRefObject<View>;
  actorRef: React.MutableRefObject<Actor>;
  gesture: React.MutableRefObject<Gesture | null>;
  onHint: (text: string, x: number, y: number) => void;
}) {
  const { layoutId, avatar, busy, hour, selectedId, onPick, onReady, insetTop = 0, insetBottom = 0, view, actorRef } = props;
  const L = props.layout ?? LAYOUTS[layoutId];
  const { gl, scene, camera, size, invalidate } = useThree();
  const cx = (L.lot[0] + L.lot[2]) / 2;
  const cz = (L.lot[1] + L.lot[3]) / 2;

  // ---- static room (rebuilt only when the layout changes)
  const doll = Boolean(props.dollhouse);
  const q = feelQuality(useTier());
  const room = useMemo(() => buildRoom(L, { dollhouse: doll, density: q.clutter }), [L, doll, q.clutter]);
  const rig = rigFor(room.rich ? 'home_nepo' : 'home_lapo', false);
  const grid = useMemo(() => buildGrid(L), [L]);
  const feel = useMemo(() => makeFeelMats(q), [q.atlas]); // eslint-disable-line react-hooks/exhaustive-deps
  const mats = useMemo(
    () => ({
      solid: feel.solid,
      glow: feel.glow,
      light: feel.light,
      glass: new MeshBasicMaterial({ color: '#bfe3f7', transparent: true, opacity: 0.82, vertexColors: true }),
      screen: new MeshBasicMaterial({ color: '#15181d' }),
      pick: new MeshBasicMaterial({ visible: false }),
      ring: new MeshBasicMaterial({ color: '#17a05c', transparent: true, opacity: 0.38, depthWrite: false }),
      tap: new MeshBasicMaterial({ color: '#17a05c', transparent: true, opacity: 0, depthWrite: false }),
      mark: new MeshLambertMaterial({ color: '#2fbf77', emissive: '#0e874e', flatShading: true }),
    }),
    [feel],
  );
  const group = useMemo(() => {
    const g = new Group();
    for (const k of LAYERS) {
      const geo = room.layers[k];
      if (geo) {
        const m = new Mesh(geo, mats[k]);
        m.name = k;
        m.matrixAutoUpdate = false;
        m.updateMatrix();
        if (k === 'light') {
          m.renderOrder = 1;
          m.visible = q.pools;
        }
        g.add(m);
      }
    }
    return g;
  }, [room, mats, q.pools]);
  useEffect(
    () => () => {
      for (const k of LAYERS) room.layers[k]?.dispose();
    },
    [room],
  );
  // F1: ceiling fan (spins while the scene draws; still on Low / reduced motion)
  const fan = useMemo(() => {
    if (!room.fan || !rig.fan) return null;
    const m = makeFan(mats.solid);
    m.position.set(room.fan[0], room.fan[1], room.fan[2]);
    return m;
  }, [room, rig.fan, mats.solid]);
  useEffect(() => () => fan?.geometry.dispose(), [fan]);
  useEffect(
    () => () => {
      for (const m of Object.values(mats)) m.dispose();
    },
    [mats],
  );

  // ---- pick boxes for interactive furniture (invisible, one shared box geometry)
  const pickGeo = useMemo(() => new BoxGeometry(1, 1, 1), []);
  const picks = useMemo(() => {
    const g = new Group();
    for (const f of L.furniture) {
      const grp = itemGroup(f);
      if (!grp) continue;
      const [x0, z0, x1, z1] = footprint(f);
      const m = new Mesh(pickGeo, mats.pick);
      const h = pickHeight(f);
      m.scale.set(Math.max(0.5, x1 - x0 + 0.1), h, Math.max(0.5, z1 - z0 + 0.1));
      m.position.set((x0 + x1) / 2, (f.y ?? 0) + h / 2, (z0 + z1) / 2);
      m.userData.item = f;
      g.add(m);
    }
    return g;
  }, [L, pickGeo, mats.pick]);
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
  // a green marker bobbing over the picked piece
  const markGeo = useMemo(() => new ConeGeometry(0.16, 0.32, 4), []);
  const marker = useMemo(() => {
    const m = new Mesh(markGeo, mats.mark);
    m.rotation.x = Math.PI;
    m.visible = false;
    return m;
  }, [markGeo, mats.mark]);
  useEffect(() => () => markGeo.dispose(), [markGeo]);
  useEffect(() => {
    const f = selectedId ? L.furniture.find((x) => x.id === selectedId) : null;
    if (f) {
      const [x0, z0, x1, z1] = footprint(f);
      ring.scale.set(x1 - x0 + 0.3, z1 - z0 + 0.3, 1);
      ring.position.set((x0 + x1) / 2, 0.03 + (f.y ?? 0), (z0 + z1) / 2);
      ring.visible = true;
      marker.position.set((x0 + x1) / 2, (f.y ?? 0) + (KINDS[f.kind].w > 1.5 || f.kind === 'bunk' || f.kind === 'wardrobe' || f.kind === 'fridge' ? 2.35 : 1.75), (z0 + z1) / 2);
      marker.visible = true;
    } else {
      ring.visible = false;
      marker.visible = false;
    }
    invalidate();
  }, [selectedId, L, ring, marker, invalidate]);
  useEffect(() => () => ringGeo.dispose(), [ringGeo]);

  // ---- lights
  const lights = useMemo(() => {
    const g = new Group();
    const hemi = new HemisphereLight('#f2f7ff', '#b7a58f', 1.5);
    const sun = new DirectionalLight('#fff1dc', 2);
    const lamp = new PointLight('#ffcf8a', 0, Math.max(L.w, L.d) * 1.8, 1);
    lamp.position.set(L.w * 0.5 - (L.lot[0] + L.lot[2]) / 2, 2.4, L.d * 0.55 - (L.lot[1] + L.lot[3]) / 2);
    g.add(hemi, sun, lamp);
    return { g, hemi, sun, lamp };
  }, [L]);
  const hourKey = Math.round(hour * 60); // S1: re-light every minute (continuous curve, one redraw)
  const lightGain = useRef(1);
  const radius = Math.hypot(L.lot[2] - L.lot[0], L.lot[3] - L.lot[1]) / 2;
  useEffect(() => {
    const lt = homeLight(hourKey / 60);
    lights.hemi.color.set(lt.hemiSky);
    lights.hemi.groundColor.set(lt.hemiGround);
    lights.hemi.intensity = lt.hemi;
    lights.sun.color.set(lt.sun);
    lights.sun.intensity = lt.sunI;
    lights.sun.position.set(lt.sunDir[0] * 20 + cx, lt.sunDir[1] * 20, lt.sunDir[2] * 20 + cz);
    lights.sun.target.position.set(cx, 0, cz);
    lights.sun.target.updateMatrixWorld();
    // F1 rig: darker ambient (contrast, corners), the room's own light colour, a warm lamp at night
    lights.hemi.intensity = lt.hemi * (doll ? 1 : rig.ambient + (1 - rig.ambient) * (1 - lt.dark) * 0.5);
    if (!doll) lights.hemi.color.set(mixHex(lt.hemiSky, rig.tint, rig.tintMix * (0.4 + 0.6 * lt.dark)));
    lights.lamp.color.set(rig.lamp);
    lights.lamp.intensity = doll ? lt.lamp : rig.lampDay + (rig.lampNight - rig.lampDay) * lt.dark;
    lights.lamp.position.set(room.bulb[0] - cx, room.bulb[1], room.bulb[2] - cz);
    mats.glass.color.set(lt.glass);
    mats.glow.color.set(mixHex('#ddd6c8', '#f1ece2', lt.dark)); // P1: softer lamp glow
    mats.light.color.set(rig.pool);
    lightGain.current = rig.poolDay + (rig.poolNight - rig.poolDay) * lt.dark;
    tickFeel(feel, rig, 0, lightGain.current, q.motion);
    applyFeelRender(gl, scene, { fog: q.fog && !doll, color: lt.horizon, depth: 40 * Math.hypot(1, CAM_ELEV), radius, exposure: doll ? 1.2 : rig.exposure });
    invalidate();
  }, [hourKey, lights, mats, cx, cz, invalidate, rig, room, feel, q.fog, q.motion, doll, gl, scene, radius]);

  // ---- TV on while watching
  useEffect(() => {
    mats.screen.color.set(busy?.group === 'media' ? '#7ec8ff' : '#15181d');
    invalidate();
  }, [busy?.group, mats, invalidate]);

  // ---- floor tap target (invisible, the whole lot) and the tap marker (a ring that fades)
  const floorGeo = useMemo(() => new PlaneGeometry(1, 1), []);
  const floor = useMemo(() => {
    const m = new Mesh(floorGeo, mats.pick);
    m.rotation.x = -Math.PI / 2;
    m.scale.set(L.lot[2] - L.lot[0], L.lot[3] - L.lot[1], 1);
    m.position.set((L.lot[0] + L.lot[2]) / 2, 0, (L.lot[1] + L.lot[3]) / 2);
    m.updateMatrix();
    return m;
  }, [floorGeo, mats.pick, L]);
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

  // ---- the Sim
  const key = avatarKey(avatar);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  const ch = useMemo(() => buildCharacter(avatar), [key]);
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
  // M2 the gait for this outfit (admin-tunable speed; a wrapper walks slower with short quick steps).
  // Stride and cadence grow with the speed; the phase follows the distance, so the feet never slide.
  const walkSpeed = props.walk?.speed ?? DEFAULT_WALK.speed;
  const robeMult = props.walk?.robeMult ?? DEFAULT_WALK.robeMult;
  const tune = useMemo(() => gaitFor(ch, { speed: walkSpeed, robeMult }), [ch, walkSpeed, robeMult]);
  const gait = useMemo<Gait>(() => ({ ...DEFAULT_GAIT, cruise: tune.cruise, brake: 1.5 * Math.max(1, tune.cruise / 1.15) }), [tune]);
  const propsRef = useRef(props);
  propsRef.current = props;
  // pose buffers (idle, walk, blend source, last frame) and the last frame's placement
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
      /** M2 leg check: the blend back from a task pose is under way (dev check when it ends). */
      fromTask: false,
      check: new Float32Array(POSE_SIZE),
    }),
    // a new character = new buffers (no blend from the old body)
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [ch],
  );
  const moodRef = useRef(props.mood);
  moodRef.current = props.mood;

  const salt = useMemo(() => Math.random() * 10, []);
  const rnd = useMemo(() => {
    let s = 1234567;
    return () => ((s = (s * 16807) % 2147483647) / 2147483647);
  }, []);
  // dev only: window.__blSlowMo = 0.2 slows walks, blends and the tap marker (for frame-by-frame checks)
  const slowMo = () => (import.meta.env.DEV ? Number((window as { __blSlowMo?: number }).__blSlowMo) || 1 : 1);
  const clock = useRef({ real: performance.now() / 1000, virt: performance.now() / 1000 });
  /** Seconds (performance clock; runs slower under the dev slow-motion switch, never jumps). */
  const nowS = () => {
    const c = clock.current;
    const r = performance.now() / 1000;
    c.virt += (r - c.real) * slowMo();
    c.real = r;
    return c.virt;
  };

  // first arrival: from the door to the idle spot (or back where the Sim was, if the canvas was
  // only unmounted for a moment, e.g. while the Sim sheet turntable was open)
  useEffect(() => {
    const a = actorRef.current;
    const mem = memory && memory.layout === L.id && performance.now() - memory.at < 10 * 60_000 ? memory : null;
    a.item = null;
    a.idleSince = nowS();
    if (mem) {
      place(a.w, mem.pos, mem.yaw);
      a.mode = 'idle';
      a.nextWander = performance.now() + 15000;
      invalidate();
      return;
    }
    const d = L.doors[0];
    const doorPt: P2 = d ? (d[0] === 'e' ? [L.w + 0.7, (d[1] + d[2]) / 2] : [(d[1] + d[2]) / 2, L.d + 0.7]) : [L.home[0], L.home[1]];
    const plan = planPath(grid, doorPt, [L.home[0], L.home[1]], { round: 0.22 });
    const first = plan.points[1] ?? plan.end;
    place(a.w, doorPt, Math.atan2(first[0] - doorPt[0], first[1] - doorPt[1]));
    walkPath(a.w, plan.points, L.home[2]);
    a.mode = 'walk';
    a.then = 'idle';
    a.nextWander = performance.now() + 20000;
    invalidate();
  }, [L, grid, actorRef, invalidate]);
  useEffect(() => {
    const born = performance.now();
    const holder = actorRef; // a mutable state holder, not a DOM node: read it at unmount on purpose
    return () => {
      const a = holder.current;
      // ignore StrictMode's instant remount in dev
      if (performance.now() - born < 1500) return;
      memory = { layout: L.id, pos: a.mode === 'pose' && a.item ? spotOf(a.item).p : a.w.pos, yaw: a.w.yaw, at: performance.now() };
    };
  }, [L, actorRef]);

  /** Walk to a point in layout space (client-side only). Returns where the walk ends. */
  const walkTo = (to: P2, opts: { snap?: boolean; faceTo?: number | null; then?: 'idle' | 'pose' | 'task'; manual?: boolean } = {}) => {
    const a = actorRef.current;
    const plan = planPath(grid, a.w.pos, to, { snapEnd: opts.snap, round: 0.22 });
    walkPath(a.w, plan.points, opts.faceTo ?? null);
    a.mode = 'walk';
    a.then = opts.then ?? 'idle';
    a.manual = Boolean(opts.manual);
    if (a.then !== 'task') a.taskKey = null;
    return plan;
  };

  // a home activity started or ended (M2: no more "placed there" or hurried walks; the Sim walked to
  // the piece before the action started, so it normally just sits / lies down where it stands)
  const busyKey = busy ? `${busy.group}:${busy.key}` : null;
  const firstBusy = useRef(true);
  useEffect(() => {
    const a = actorRef.current;
    const first = firstBusy.current;
    firstBusy.current = false;
    if (busy) {
      const item = pieceFor(L, busy.activity, busy.group);
      a.pose = GROUP_META[busy.group].pose;
      a.taskKey = null;
      if (!item) {
        a.mode = 'pose';
        a.item = null;
        a.pose = 'stand';
        place(a.w, a.w.pos, a.w.yaw);
      } else {
        const s = spotOf(item);
        const from = a.mode === 'pose' && a.item ? spotOf(a.item).p : a.w.pos;
        if (a.mode === 'pose') place(a.w, from, a.w.yaw);
        a.item = item;
        const far = Math.hypot(from[0] - s.p[0], from[1] - s.p[1]) > 0.35;
        if (first) {
          // already running when the home opened: be there already
          a.noBlend = true;
          place(a.w, s.p, s.yaw);
          a.mode = 'pose';
        } else if (far) {
          // started somewhere else (another device, the map): a real walk, then the pose
          walkTo(s.p, { faceTo: s.yaw, then: 'pose' });
        } else {
          place(a.w, s.p, s.yaw);
          a.mode = 'pose';
        }
      }
    } else {
      // no wandering off right after a task
      a.nextWander = Math.max(a.nextWander, performance.now() + 12000);
      if (a.mode === 'pose' || (a.mode === 'walk' && a.then === 'pose')) {
        // stand up next to the piece; the pose blend eases back to the idle (no frozen task pose)
        if (a.item) {
          const s = spotOf(a.item);
          place(a.w, s.p, s.yaw);
        }
        a.mode = 'idle';
        a.item = null;
        a.idleSince = nowS();
      }
    }
    invalidate();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [busyKey, L, grid]);

  // M2: walk to the next queued task; the action (and its timer) starts only when the Sim gets there
  const task = props.task ?? null;
  const taskKey = task?.key ?? null;
  useEffect(() => {
    const a = actorRef.current;
    if (!task) {
      // cancelled (the x on the pill): stop where the Sim is, with an eased stop
      if (a.mode === 'walk' && a.then === 'task') {
        stopWalk(a.w);
        a.then = 'idle';
      }
      a.taskKey = null;
      invalidate();
      return;
    }
    if (a.taskKey === task.key) return;
    const item = pieceFor(L, task.activity, task.group);
    if (a.mode === 'pose') {
      // still holding the last task's pose (its end not seen yet): stand up beside that piece first
      if (a.item) place(a.w, spotOf(a.item).p, a.w.yaw);
      a.mode = 'idle';
      a.item = null;
    }
    if (!item) {
      // nothing to walk to: start at once
      a.taskKey = null;
      propsRef.current.onTaskArrive?.(task.key);
      return;
    }
    const s = spotOf(item);
    a.taskKey = task.key;
    a.nextWander = performance.now() + 45000;
    if (Math.hypot(a.w.pos[0] - s.p[0], a.w.pos[1] - s.p[1]) < 0.05 && Math.abs(angleTo(a.w.yaw, s.yaw)) < 0.05 && a.mode !== 'walk') {
      a.taskKey = null;
      propsRef.current.onTaskArrive?.(task.key);
      return;
    }
    walkTo(s.p, { faceTo: s.yaw, then: 'task' });
    a.taskKey = task.key;
    invalidate();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [taskKey, L, grid]);

  // ---- S2 orbit camera: circles the whole island; one zoom that fits every angle (no pumping)
  const orbitOn = props.orbit !== undefined;
  const orbitFit = useRef<{ key: string; zoom: number } | null>(null);
  const placeOrbit = (yaw: number) => {
    const cam = camera as OrthographicCamera;
    const d = 40;
    const elev = 0.95; // ~43° down: sees over the low walls into every room
    const ty = 0.5;
    const availH = Math.max(120, size.height - insetTop - insetBottom);
    const left = Math.max(0, Math.min(size.width * 0.6, props.insetLeft ?? 0));
    const availW = Math.max(160, size.width - left);
    const fitKey = `${L.id}:${availW}x${availH}`;
    if (orbitFit.current?.key !== fitKey) {
      const pts: [number, number, number][] = [];
      const [x0, z0, x1, z1] = L.lot;
      // the lot (house + yard) up to the tallest furniture; the grass island may run off the edges
      for (const x of [x0 - 0.2, x1 + 0.2]) for (const z of [z0 - 0.2, z1 + 0.2]) pts.push([x - cx, 2.1, z - cz], [x - cx, -0.1, z - cz]);
      let best = Infinity;
      for (let i = 0; i < 24; i++) {
        const a = (i / 24) * Math.PI * 2;
        cam.position.set(Math.sin(a) * d, d * elev + ty, Math.cos(a) * d);
        cam.lookAt(0, ty, 0);
        cam.updateMatrixWorld();
        let mx = 0, my = 0;
        for (const [x, y, z] of pts) {
          _v.set(x, y, z).applyMatrix4(cam.matrixWorldInverse);
          mx = Math.max(mx, Math.abs(_v.x));
          my = Math.max(my, Math.abs(_v.y));
        }
        best = Math.min(best, availW / (2 * mx * 1.04), availH / (2 * my * 1.06));
      }
      orbitFit.current = { key: fitKey, zoom: best };
    }
    cam.position.set(Math.sin(yaw) * d, d * elev + ty, Math.cos(yaw) * d);
    cam.lookAt(0, ty, 0);
    cam.zoom = orbitFit.current.zoom;
    cam.updateMatrixWorld();
    const shift = (insetTop - insetBottom) / 2;
    if (Math.abs(shift) > 1 || left > 1) cam.setViewOffset(size.width, size.height, -left / 2, -shift, size.width, size.height);
    else cam.clearViewOffset();
    cam.updateProjectionMatrix();
  };

  // ---- camera: orthographic, isometric from the south-east, framed between the HUD insets
  useEffect(() => {
    if (orbitOn) {
      placeOrbit(view.current.yaw);
      invalidate();
      return;
    }
    const cam = camera as OrthographicCamera;
    const v = view.current;
    const d = 40;
    cam.position.set(Math.sin(v.yaw) * d, d * CAM_ELEV, Math.cos(v.yaw) * d);
    cam.lookAt(0, 0, 0);
    cam.updateMatrixWorld();
    // fit the lot (house + yard, walls included) between the HUD insets
    const [x0, z0, x1, z1] = L.lot;
    let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
    for (const x of [x0, x1]) for (const z of [z0, z1]) for (const y of [0, L.wallH]) {
      _v.set(x - cx, y, z - cz).applyMatrix4(cam.matrixWorldInverse);
      minX = Math.min(minX, _v.x); maxX = Math.max(maxX, _v.x);
      minY = Math.min(minY, _v.y); maxY = Math.max(maxY, _v.y);
    }
    const availH = Math.max(120, size.height - insetTop - insetBottom);
    const fit = Math.min(size.width / ((maxX - minX) * 1.1), availH / ((maxY - minY) * 1.12));
    cam.zoom = fit * v.zoom;
    // centre the lot on screen: slide the camera in its own plane
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

  // ---- per frame: walk, pose, blend, place
  useFrame((state, dt) => {
    const a = actorRef.current;
    const t = state.clock.elapsedTime;
    const now = nowS();
    const step = Math.min(dt, 0.1) * slowMo();
    if (orbitOn && props.orbit && props.orbit > 0) {
      // dt is clamped, so a hidden tab (no frames) resumes where it left off
      view.current.yaw = (view.current.yaw + (Math.PI * 2 * step) / props.orbit) % (Math.PI * 2);
      placeOrbit(view.current.yaw);
    }
    const root = ch.root;
    root.rotation.set(0, 0, 0);
    root.position.set(0, 0, 0);
    const mood = moodRef.current;
    const tired = mood?.tired ?? 0;
    const happy = mood?.happy ?? 0;

    if (a.mode === 'idle' && !busy && !props.task && !props.walkLock && performance.now() > a.nextWander && now - a.idleSince > 6) {
      const p = randomFree(grid, rnd, [0.4, 0.4, L.w - 0.4, L.d - 0.4]);
      a.nextWander = performance.now() + 16000 + rnd() * 18000;
      if (p) walkTo(p);
    }

    // ---- locomotion
    if (a.mode === 'walk') {
      const tiredSlow = Math.max(0, Math.min(0.8, props.walk?.tiredSlow ?? 0.18));
      const r = stepWalker(a.w, step, gait, 1 - tiredSlow * tired + 0.05 * happy);
      // the feet keep pace with the ground: phase by distance over the current stride
      a.phase += r.moved / (2 * stepLength(ch, Math.max(0.25, a.gait), tune.strideScale));
      // turning on the spot: small shuffling steps
      if (a.w.turning) a.phase += (r.turned * 0.16) / (2 * stepLength(ch, 0.3));
      if (r.arrived) {
        const then = a.then;
        const key = a.taskKey;
        const manual = a.manual;
        a.mode = then === 'pose' ? 'pose' : 'idle';
        a.then = 'idle';
        a.manual = false;
        a.idleSince = now;
        if (then === 'task' && key) {
          a.taskKey = null;
          // defer out of the frame loop (the parent starts the action: a store update + RPC)
          window.setTimeout(() => propsRef.current.onTaskArrive?.(key), 0);
        } else if (manual) window.setTimeout(() => propsRef.current.onWalkDone?.(), 0);
      }
    }
    const gaitTarget = a.mode === 'walk' ? Math.max(Math.min(1, a.w.speed / gait.cruise), a.w.turning ? 0.3 : 0) : 0;
    a.gait += (gaitTarget - a.gait) * (1 - Math.exp(-step * 9));
    if (a.gait < 0.004) a.gait = 0;

    // ---- pose
    let x = a.w.pos[0];
    let y = 0;
    let z = a.w.pos[1];
    let yaw = a.w.yaw;
    const life = { tired, happy, reduced: view.current.reduced, idleFor: a.mode === 'walk' ? 0 : now - a.idleSince };
    const item = a.mode === 'pose' ? a.item : null;
    const k = item ? KINDS[item.kind] : null;
    if (a.mode === 'pose' && item && (a.pose === 'lie' || a.pose === 'sit' || a.pose === 'cook' || a.pose === 'scrub')) {
      resetRig(ch);
      const base = ((item.rot ?? 0) * Math.PI) / 2;
      if (a.pose === 'lie' && k?.seat) {
        const [sx, sy, sz] = k.seat;
        [x, z] = toLayout(item, sx, sz);
        y = sy + (item.y ?? 0);
        yaw = base;
        root.rotation.x = -Math.PI / 2;
        poseLie(ch, t);
      } else if (a.pose === 'sit' && k?.seat) {
        const [sx, sy, sz, sYaw] = k.seat;
        [x, z] = toLayout(item, sx, sz);
        yaw = base + sYaw;
        poseSit(ch, t, salt);
        root.position.y = sitRootY(ch, sy + (item.y ?? 0));
      } else if (a.pose === 'cook') {
        poseCook(ch, t, salt);
      } else if (a.pose === 'scrub') {
        poseScrub(ch, t, salt);
      } else {
        poseIdle(ch, t, salt);
      }
    } else if (a.gait <= 0) {
      poseLife(ch, t, salt, life);
    } else if (a.gait >= 0.995) {
      poseGait(ch, a.phase, 1, { ...life, strideScale: tune.strideScale });
    } else {
      // speeding up / slowing down: idle and walk mixed by the gait weight
      poseLife(ch, t, salt, life);
      capturePose(ch, buf.idle);
      poseGait(ch, a.phase, a.gait, { ...life, strideScale: tune.strideScale });
      capturePose(ch, buf.walk);
      const g = a.gait;
      applyPose(ch, mixPose(buf.walk, buf.idle, buf.walk, g * g * (3 - 2 * g)));
    }

    // ---- blend between states (sit down, lie down, stand up, back to idle after a task)
    const stateKey = a.mode === 'pose' ? `pose:${a.pose}:${a.item?.id ?? ''}` : 'free';
    if (stateKey !== buf.key) {
      buf.fromTask = buf.key.startsWith('pose:') && stateKey === 'free';
      if (buf.havePrev && !a.noBlend && !view.current.reduced) {
        buf.from.set(buf.prev);
        for (let i = 0; i < 6; i++) buf.fromXf[i] = buf.prevXf[i];
        buf.blendT0 = now;
      } else buf.blendT0 = -1;
      buf.key = stateKey;
      a.noBlend = false;
    }
    let rootRotX = root.rotation.x;
    let rootY = root.position.y;
    let blending = false;
    if (buf.blendT0 >= 0) {
      const u = (now - buf.blendT0) / BLEND_S;
      if (u >= 1) {
        buf.blendT0 = -1;
        // M2 leg check (dev): back from a task pose and standing, the legs must be exactly the idle pose
        if (import.meta.env.DEV && buf.fromTask && a.mode === 'idle' && a.gait <= 0) {
          capturePose(ch, buf.walk);
          poseLife(ch, t, salt, life);
          capturePose(ch, buf.check);
          applyPose(ch, buf.walk);
          const diff = legRotationDiff(buf.walk, buf.check);
          (window as { __legCheck?: { diff: number; ok: boolean; at: number }[] }).__legCheck ??= [];
          (window as unknown as { __legCheck: { diff: number; ok: boolean; at: number }[] }).__legCheck.push({ diff, ok: diff < 1e-5, at: performance.now() });
          if (diff >= 1e-5) console.error(`[home] legs not back to idle after a task pose (max diff ${diff.toFixed(4)} rad)`);
        }
        buf.fromTask = false;
      } else {
        blending = true;
        const e = u * u * (3 - 2 * u); // ease in-out
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
    px[0] = x;
    px[1] = y;
    px[2] = z;
    px[3] = yaw;
    px[4] = rootRotX;
    px[5] = rootY;
    buf.havePrev = true;

    if (marker.visible) {
      marker.rotation.y = t * 1.6;
      marker.position.y += Math.sin(t * 3) * 0.002;
    }
    // tap marker: grows a little and fades (ease-out)
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
    // the blob shadow stays on the floor
    const shadow = actorObj.children[0];
    shadow.position.y = -y + 0.002;
    shadow.visible = rootRotX > -0.5;
    // F1 small motion: the ceiling fan turns (frames only come at the idle rate; none when hidden)
    if (q.motion && !view.current.reduced) {
      if (fan) fan.rotation.y = t * 3.2;
      tickFeel(feel, rig, t, lightGain.current, true);
    }
    a.hot = a.mode === 'walk' || a.gait > 0 || blending || marking;
  });

  // ---- API for the parent (snapshot while paused, stats/bench for checks)
  useEffect(() => {
    const api: HomeApi = {
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
        return { calls: gl.info.render.calls, triangles: gl.info.render.triangles, roomTriangles: room.tris, geometries: gl.info.memory.geometries };
      },
      screenOf(id) {
        const f = L.furniture.find((x) => x.id === id);
        if (!f) return null;
        const [x0, z0, x1, z1] = footprint(f);
        _v.set((x0 + x1) / 2 - cx, (f.y ?? 0) + (pickHeight(f) > 1.5 ? 1.3 : 0.45), (z0 + z1) / 2 - cz).project(camera);
        return { x: ((_v.x + 1) / 2) * size.width, y: ((1 - _v.y) / 2) * size.height };
      },
      screenOfPoint(x, z, y = 0) {
        _v.set(x - cx, y, z - cz).project(camera);
        return { x: ((_v.x + 1) / 2) * size.width, y: ((1 - _v.y) / 2) * size.height };
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
    };
    onReady?.(api);
    if (!doll) sampleFrames(gl, scene, camera);
    if (import.meta.env.DEV) Object.assign(window, { __home: api, __homeActor: actorRef.current, __homeLayout: L, __homeGrid: grid, __homeChar: ch });
  }, [gl, scene, camera, room, onReady, actorRef, L, grid, cx, cz, size, ch]);

  /** A real tap: little movement, short, one finger (not the end of a drag, orbit or pinch). */
  const isTap = (e: ThreeEvent<MouseEvent>) => {
    const g = props.gesture.current;
    if (e.delta > TAP_PX) return false;
    if (!g) return true; // a synthetic click (keyboard, tests)
    return !g.multi && performance.now() - g.t < TAP_MS && Math.hypot(e.nativeEvent.clientX - g.x, e.nativeEvent.clientY - g.y) <= TAP_PX;
  };
  const hint = (e: ThreeEvent<MouseEvent>, text: string) => {
    const r = gl.domElement.getBoundingClientRect();
    const half = Math.min(120, r.width / 2);
    props.onHint(text, Math.max(half, Math.min(r.width - half, e.nativeEvent.clientX - r.left)), Math.max(48, e.nativeEvent.clientY - r.top));
  };

  const onClick = (e: ThreeEvent<MouseEvent>) => {
    if (!isTap(e)) return; // it was a drag
    e.stopPropagation();
    const item = e.object.userData.item as FurnitureItem | undefined;
    if (!item) return;
    onPick?.(item);
    // walk over while the sheet opens (client-side only; a long walk is left for the action rule)
    const a = actorRef.current;
    if (props.walkLock || props.task || a.mode === 'pose') return;
    const s = spotOf(item);
    const plan = planPath(grid, a.w.pos, s.p, { round: 0.22 });
    if (plan.length / gait.cruise <= PREWALK_MAX_S && plan.length > 0.15) {
      walkTo(s.p, { faceTo: s.yaw });
      a.nextWander = performance.now() + 45000;
    }
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
    // a tap while walking to a task: the player takes over, that task is dropped (M2)
    if (a.mode === 'walk' && a.then === 'task' && a.taskKey) {
      const key = a.taskKey;
      a.taskKey = null;
      props.onTaskCancel?.(key);
    }
    // layout space = world + the group's centring offset
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
      <primitive object={lights.g} />
      <group position={[-cx, 0, -cz]}>
        <primitive object={group} />
        {fan && <primitive object={fan} />}
        <primitive object={ring} />
        <primitive object={marker} />
        <primitive object={actorObj} />
        <primitive object={tapMark} />
        {props.interactive !== false && <primitive object={floor} onClick={onFloor} />}
        {props.interactive !== false && <primitive
          object={picks}
          onClick={onClick}
          onPointerOver={() => {
            document.body.style.cursor = 'pointer';
          }}
          onPointerOut={() => {
            document.body.style.cursor = '';
          }}
        />}
      </group>
    </>
  );
}

export default function HomeScene(props: HomeSceneProps) {
  const gfx = feelQuality(useTier());
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
    item: null,
    then: 'idle',
    taskKey: null,
    manual: false,
    nextWander: 0,
    phase: 0,
    gait: 0,
    idleSince: 0,
    noBlend: false,
    hot: false,
  });
  const gesture = useRef<Gesture | null>(null);
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

  // wheel zoom (desktop)
  useEffect(() => {
    const el = wrap.current;
    if (!el) return;
    if (props.interactive === false) return;
    const onWheel = (e: WheelEvent) => {
      e.preventDefault();
      const v = view.current;
      v.zoom = Math.min(ZOOM_MAX, Math.max(ZOOM_MIN, v.zoom * Math.exp(-e.deltaY * 0.0015)));
      kick();
    };
    el.addEventListener('wheel', onWheel, { passive: false });
    return () => el.removeEventListener('wheel', onWheel);
  }, [props.interactive]);

  const onDown = (e: React.PointerEvent) => {
    if (props.interactive === false) return;
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
      const base = BASE_YAW;
      v.yaw = Math.min(base + YAW_RANGE, Math.max(base - YAW_RANGE, v.yaw - (dx / width) * Math.PI * 0.9));
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
    <div ref={wrap} className={`home3d${props.className ? ' ' + props.className : ''}`} style={props.style}
      onPointerDown={onDown} onPointerMove={onMove} onPointerUp={onUp} onPointerCancel={onUp} onPointerLeave={onUp}>
      <Canvas
        orthographic
        dpr={[1, gfx.dprMax]}
        frameloop="demand"
        gl={{ antialias: true, alpha: true, powerPreference: 'low-power' }}
        camera={{ position: [28, 22, 28], zoom: 40, near: 0.1, far: 200 }}
        style={{ touchAction: props.interactive === false ? 'auto' : 'none' }}
        onCreated={({ gl }) => {
          gl.domElement.addEventListener('webglcontextlost', (ev) => {
            ev.preventDefault();
            // r3f forces a context loss itself when the canvas unmounts: only a loss while we are
            // still on screen means the GPU dropped us
            window.setTimeout(() => {
              if (alive.current && wrap.current?.isConnected) props.onLost?.();
            }, 60);
          });
        }}
      >
        <Driver view={view} actor={actor} paused={Boolean(props.paused)} spin={Boolean(props.orbit && props.orbit > 0)} />
        <House {...props} view={view} actorRef={actor} gesture={gesture} onHint={onHint} />
      </Canvas>
      {!props.dollhouse && <div className={`feel-overlay${looksNight(props.hour) ? ' is-dark' : ''}${gfx.tier === 'low' ? ' is-low' : ''}`} aria-hidden />}
      {tapHint && (
        <span key={tapHint.n} className="home3d__hint" role="status" style={{ left: tapHint.x, top: tapHint.y }}>
          {tapHint.text}
        </span>
      )}
    </div>
  );
}
