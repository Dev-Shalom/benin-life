// The live 3D home (react-three-fiber). Lazy-loaded through ../HomeView.tsx.
//
// One orthographic canvas, frameloop="demand": it redraws every frame only while the Sim walks or
// the player drags; otherwise ~24 fps for the idle sway (12 fps asleep), and not at all when paused
// (an overlay with its own 3D is open), off-screen or in a hidden tab.
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
  Vector3,
} from 'three';
import type { AvatarConfig } from '../../../lib/types';
import { avatarKey } from '../../avatar3d/catalog';
import { buildCharacter } from '../../avatar3d/engine/character';
import { poseIdle, poseWalk } from '../../avatar3d/engine/anim';
import { makeShadow } from '../../avatar3d/engine/scene';
import { actorFor, furnishLayout, GROUP_META, itemGroup, KINDS, LAYOUTS, type FurnitureItem, type HomeGroup, type HomeLayoutId, type HomePose } from '../model';
import { buildGrid, findPath, footprint, randomFree, toLayout, type P2 } from '../nav';
import { homeLight } from './light';
import { poseCook, poseLie, poseScrub, poseSit, sitRootY } from './poses';
import { buildRoom } from './room';

export interface HomeApi {
  /** Render once and return the frame as an image (to show while the canvas is unmounted). */
  snapshot(): string | null;
  stats(): { calls: number; triangles: number; roomTriangles: number; geometries: number };
  /** Render n frames back to back; returns the average ms per frame. */
  bench(n?: number): number;
  /** Screen position (CSS px, relative to the canvas) of a furniture piece's centre, for tests/tutorials. */
  screenOf(id: string): { x: number; y: number } | null;
}

export interface HomeSceneProps {
  layoutId: HomeLayoutId;
  /** The player's furniture ids (server `profiles.furniture`); null/undefined = the classic full room. */
  owned?: readonly string[] | null;
  avatar: AvatarConfig;
  /**
   * The home activity running now (key changes with each new run), or null. `seconds` = real seconds
   * left when it started: a short action gets a quick walk (or none) so the Sim isn't walking for most of it.
   */
  busy: { group: HomeGroup; key: string; seconds?: number } | null;
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
}

interface View {
  yaw: number;
  zoom: number;
  dragging: boolean;
  visible: boolean;
}

const BASE_YAW = Math.PI / 4;
const YAW_RANGE = 0.75;
const ZOOM_MIN = 0.85;
const ZOOM_MAX = 1.9;
const WALK_SPEED = 1.15; // m/s
/** Short actions: the walk to the furniture may use at most this share of the action's time... */
const WALK_SHARE = 0.2;
/** ...and never more than this many seconds; faster than MAX_HURRY x walking speed -> just appear there. */
const WALK_MAX_S = 2.5;
const MAX_HURRY = 3;
/** Where the Sim was when the canvas last unmounted (so a short suspend doesn't replay the arrival). */
let memory: { layout: string; pos: P2; yaw: number; at: number } | null = null;
const _v = new Vector3();
const _r = new Vector3();
const _u = new Vector3();

interface Actor {
  pos: P2;
  yaw: number;
  mode: 'idle' | 'walk' | 'pose';
  path: P2[];
  seg: number;
  pose: HomePose;
  item: FurnitureItem | null;
  /** After the walk: what to do on arrival. */
  then: 'idle' | 'pose';
  nextWander: number;
  faceTo: number | null;
  /** Walking speed for the current path (m/s). */
  speed: number;
}

function pathLength(path: P2[]): number {
  let len = 0;
  for (let i = 1; i < path.length; i++) len += Math.hypot(path[i][0] - path[i - 1][0], path[i][1] - path[i - 1][1]);
  return len;
}

function Driver({ view, actor, paused }: { view: React.MutableRefObject<View>; actor: React.MutableRefObject<Actor>; paused: boolean }) {
  const invalidate = useThree((s) => s.invalidate);
  useEffect(() => {
    if (paused) return;
    let raf = 0;
    let last = 0;
    const loop = (now: number) => {
      raf = requestAnimationFrame(loop);
      if (document.hidden || !view.current.visible) return;
      const a = actor.current;
      const busy = view.current.dragging || a.mode === 'walk';
      const fps = a.mode === 'pose' && a.pose === 'lie' ? 12 : 24;
      if (!busy && now - last < 1000 / fps) return;
      last = now;
      invalidate();
    };
    raf = requestAnimationFrame(loop);
    return () => cancelAnimationFrame(raf);
  }, [invalidate, view, actor, paused]);
  return null;
}

/** Memory key: the layout plus its pieces (a different furniture set starts fresh at the door). */
function memKey(L: { id: string; furniture: FurnitureItem[] }): string {
  return `${L.id}:${L.furniture.length}:${L.furniture.map((f) => f.id).join(',')}`;
}

function spotOf(item: FurnitureItem): { p: P2; yaw: number } {
  const k = KINDS[item.kind];
  const [lx, lz, ly] = k.spot ?? [0, k.d / 2 + 0.35, Math.PI];
  const p = toLayout(item, lx, lz);
  return { p, yaw: ((item.rot ?? 0) * Math.PI) / 2 + ly };
}

function House(props: HomeSceneProps & { view: React.MutableRefObject<View>; actorRef: React.MutableRefObject<Actor> }) {
  const { layoutId, owned, avatar, busy, hour, selectedId, onPick, onReady, insetTop = 0, insetBottom = 0, view, actorRef } = props;
  const ownedKey = owned ? [...owned].sort().join(',') : null;
  // eslint-disable-next-line react-hooks/exhaustive-deps
  const L = useMemo(() => furnishLayout(LAYOUTS[layoutId], owned), [layoutId, ownedKey]);
  const { gl, scene, camera, size, invalidate } = useThree();
  const cx = (L.lot[0] + L.lot[2]) / 2;
  const cz = (L.lot[1] + L.lot[3]) / 2;

  // ---- static room (rebuilt only when the layout changes)
  const room = useMemo(() => buildRoom(L), [L]);
  const grid = useMemo(() => buildGrid(L), [L]);
  const mats = useMemo(
    () => ({
      solid: new MeshLambertMaterial({ vertexColors: true, flatShading: true }),
      glow: new MeshBasicMaterial({ vertexColors: true }),
      glass: new MeshBasicMaterial({ color: '#bfe3f7', transparent: true, opacity: 0.82 }),
      screen: new MeshBasicMaterial({ color: '#15181d' }),
      pick: new MeshBasicMaterial({ visible: false }),
      ring: new MeshBasicMaterial({ color: '#17a05c', transparent: true, opacity: 0.38, depthWrite: false }),
      mark: new MeshLambertMaterial({ color: '#2fbf77', emissive: '#0e874e', flatShading: true }),
    }),
    [],
  );
  const group = useMemo(() => {
    const g = new Group();
    for (const k of ['solid', 'glow', 'glass', 'screen'] as const) {
      const geo = room.layers[k];
      if (geo) {
        const m = new Mesh(geo, mats[k]);
        m.name = k;
        m.matrixAutoUpdate = false;
        m.updateMatrix();
        g.add(m);
      }
    }
    return g;
  }, [room, mats]);
  useEffect(
    () => () => {
      for (const k of ['solid', 'glow', 'glass', 'screen'] as const) room.layers[k]?.dispose();
    },
    [room],
  );
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
      const h = f.kind.includes('stall') || f.kind === 'bucket_bath' || f.kind === 'pit_toilet' || f.kind === 'shower' ? 1.8 : 1.1;
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
  const hourKey = Math.round(hour * 6); // re-light every 10 game minutes
  useEffect(() => {
    const lt = homeLight(hourKey / 6);
    lights.hemi.color.set(lt.hemiSky);
    lights.hemi.groundColor.set(lt.hemiGround);
    lights.hemi.intensity = lt.hemi;
    lights.sun.color.set(lt.sun);
    lights.sun.intensity = lt.sunI;
    lights.sun.position.set(lt.sunDir[0] * 20 + cx, lt.sunDir[1] * 20, lt.sunDir[2] * 20 + cz);
    lights.sun.target.position.set(cx, 0, cz);
    lights.sun.target.updateMatrixWorld();
    lights.lamp.intensity = lt.lamp;
    mats.glass.color.set(lt.glass);
    mats.glow.color.set(lt.night ? '#ffffff' : '#e9e2d4');
    invalidate();
  }, [hourKey, lights, mats, cx, cz, invalidate]);

  // ---- TV on while watching
  useEffect(() => {
    mats.screen.color.set(busy?.group === 'media' ? '#7ec8ff' : '#15181d');
    invalidate();
  }, [busy?.group, mats, invalidate]);

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

  const salt = useMemo(() => Math.random() * 10, []);
  const rnd = useMemo(() => {
    let s = 1234567;
    return () => ((s = (s * 16807) % 2147483647) / 2147483647);
  }, []);

  // first arrival: from the door to the idle spot (or back where the Sim was, if the canvas was
  // only unmounted for a moment, e.g. while the Sim sheet turntable was open)
  useEffect(() => {
    const a = actorRef.current;
    const mem = memory && memory.layout === memKey(L) && performance.now() - memory.at < 10 * 60_000 ? memory : null;
    if (mem) {
      a.pos = mem.pos;
      a.yaw = mem.yaw;
      a.mode = 'idle';
      a.item = null;
      a.path = [];
      a.nextWander = performance.now() + 15000;
      invalidate();
      return;
    }
    const d = L.doors[0];
    const doorPt: P2 = d ? (d[0] === 'e' ? [L.w + 0.7, (d[1] + d[2]) / 2] : [(d[1] + d[2]) / 2, L.d + 0.7]) : [L.home[0], L.home[1]];
    a.pos = doorPt;
    a.mode = 'idle';
    a.item = null;
    a.path = findPath(grid, doorPt, [L.home[0], L.home[1]]);
    a.seg = 1;
    a.mode = 'walk';
    a.speed = WALK_SPEED;
    a.then = 'idle';
    a.faceTo = L.home[2];
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
      memory = { layout: memKey(L), pos: a.mode === 'pose' && a.item ? spotOf(a.item).p : a.pos, yaw: a.yaw, at: performance.now() };
    };
  }, [L, actorRef]);

  // a home activity started or ended
  const busyKey = busy ? `${busy.group}:${busy.key}` : null;
  const firstBusy = useRef(true);
  useEffect(() => {
    const a = actorRef.current;
    const first = firstBusy.current;
    firstBusy.current = false;
    if (busy) {
      const item = actorFor(L, busy.group);
      a.pose = GROUP_META[busy.group].pose;
      if (!item) {
        a.mode = 'pose';
        a.item = null;
        a.pose = 'stand';
      } else {
        const s = spotOf(item);
        const from = a.mode === 'pose' && a.item ? spotOf(a.item).p : a.pos;
        a.pos = from;
        a.item = item;
        a.path = findPath(grid, from, s.p);
        a.seg = 1;
        a.mode = 'walk';
        a.then = 'pose';
        a.faceTo = s.yaw;
        a.speed = WALK_SPEED;
        // short action: hurry (or just be there) so the Sim spends the action at the piece, not walking to it
        const secs = busy.seconds;
        if (secs !== undefined && Number.isFinite(secs)) {
          const len = pathLength(a.path);
          const budget = Math.min(WALK_MAX_S, Math.max(0, secs) * WALK_SHARE);
          if (len / WALK_SPEED > budget) {
            if (budget <= 0.05 || len / budget > WALK_SPEED * MAX_HURRY) {
              a.pos = s.p;
              a.yaw = s.yaw;
              a.mode = 'pose';
            } else {
              a.speed = len / budget;
            }
          }
        }
        if (first) {
          // the activity was already running when the home opened: be there already
          a.pos = s.p;
          a.yaw = s.yaw;
          a.mode = 'pose';
        }
      }
    } else if (a.mode === 'pose' || (a.mode === 'walk' && a.then === 'pose')) {
      // stand up next to the piece
      if (a.item) {
        const s = spotOf(a.item);
        a.pos = s.p;
        a.yaw = s.yaw;
      }
      a.mode = 'idle';
      a.item = null;
      a.nextWander = performance.now() + 12000;
    }
    invalidate();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [busyKey, L, grid]);

  // ---- camera: orthographic, isometric from the south-east, framed between the HUD insets
  useEffect(() => {
    const cam = camera as OrthographicCamera;
    const v = view.current;
    const d = 40;
    cam.position.set(Math.sin(v.yaw) * d, d * 0.78, Math.cos(v.yaw) * d);
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

  // ---- per frame: walk, pose, place
  useFrame((state, dt) => {
    const a = actorRef.current;
    const t = state.clock.elapsedTime;
    const step = Math.min(dt, 0.1);
    const root = ch.root;
    root.rotation.set(0, 0, 0);
    root.position.set(0, 0, 0);

    if (a.mode === 'idle' && !busy && performance.now() > a.nextWander) {
      const p = randomFree(grid, rnd, [0.4, 0.4, L.w - 0.4, L.d - 0.4]);
      a.nextWander = performance.now() + 16000 + rnd() * 18000;
      if (p) {
        a.path = findPath(grid, a.pos, p);
        a.seg = 1;
        a.mode = 'walk';
        a.speed = WALK_SPEED;
        a.then = 'idle';
        a.faceTo = null;
      }
    }

    if (a.mode === 'walk') {
      let move = a.speed * step;
      while (move > 0 && a.seg < a.path.length) {
        const tgt = a.path[a.seg];
        const dx = tgt[0] - a.pos[0];
        const dz = tgt[1] - a.pos[1];
        const dist = Math.hypot(dx, dz);
        if (dist < 1e-4) {
          a.seg++;
          continue;
        }
        const want = Math.atan2(dx, dz);
        let dy = want - a.yaw;
        dy = Math.atan2(Math.sin(dy), Math.cos(dy));
        a.yaw += dy * Math.min(1, step * 10);
        if (dist <= move) {
          a.pos = [tgt[0], tgt[1]];
          move -= dist;
          a.seg++;
        } else {
          a.pos = [a.pos[0] + (dx / dist) * move, a.pos[1] + (dz / dist) * move];
          move = 0;
        }
      }
      if (a.seg >= a.path.length) {
        a.mode = a.then === 'pose' ? 'pose' : 'idle';
        if (a.faceTo !== null) a.yaw = a.faceTo;
      }
      poseWalk(ch, t, Math.min(2, a.speed / WALK_SPEED));
    }

    let x = a.pos[0];
    let y = 0;
    let z = a.pos[1];
    let yaw = a.yaw;
    if (a.mode === 'pose') {
      const item = a.item;
      const k = item ? KINDS[item.kind] : null;
      const base = item ? ((item.rot ?? 0) * Math.PI) / 2 : a.yaw;
      if (a.pose === 'lie' && item && k?.seat) {
        const [sx, sy, sz] = k.seat;
        [x, z] = toLayout(item, sx, sz);
        y = sy + (item.y ?? 0);
        yaw = base;
        root.rotation.x = -Math.PI / 2;
        poseLie(ch, t);
      } else if (a.pose === 'sit' && item && k?.seat) {
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
    } else if (a.mode === 'idle') {
      poseIdle(ch, t, salt);
    }
    if (marker.visible) {
      marker.rotation.y = t * 1.6;
      marker.position.y += Math.sin(t * 3) * 0.002;
    }
    actorObj.position.set(x, y, z);
    actorObj.rotation.y = yaw;
    // the blob shadow stays on the floor
    const shadow = actorObj.children[0];
    shadow.visible = a.pose !== 'lie' || a.mode !== 'pose';
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
        _v.set((x0 + x1) / 2 - cx, (f.y ?? 0) + 0.45, (z0 + z1) / 2 - cz).project(camera);
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
    if (import.meta.env.DEV) Object.assign(window, { __home: api, __homeActor: actorRef.current });
  }, [gl, scene, camera, room, onReady, actorRef, L, cx, cz, size]);

  const onClick = (e: ThreeEvent<MouseEvent>) => {
    if (e.delta > 8) return; // it was a drag
    e.stopPropagation();
    const item = e.object.userData.item as FurnitureItem | undefined;
    if (item) onPick?.(item);
  };

  return (
    <>
      <primitive object={lights.g} />
      <group position={[-cx, 0, -cz]}>
        <primitive object={group} />
        <primitive object={ring} />
        <primitive object={marker} />
        <primitive object={actorObj} />
        <primitive
          object={picks}
          onClick={onClick}
          onPointerOver={() => {
            document.body.style.cursor = 'pointer';
          }}
          onPointerOut={() => {
            document.body.style.cursor = '';
          }}
        />
      </group>
    </>
  );
}

export default function HomeScene(props: HomeSceneProps) {
  const view = useRef<View>({ yaw: BASE_YAW, zoom: 1, dragging: false, visible: true });
  const actor = useRef<Actor>({ pos: [0, 0], yaw: 0, mode: 'idle', path: [], seg: 0, pose: 'stand', item: null, then: 'idle', nextWander: 0, faceTo: null, speed: WALK_SPEED });
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
        dpr={[1, 1.5]}
        frameloop="demand"
        flat
        gl={{ antialias: true, alpha: true, powerPreference: 'low-power' }}
        camera={{ position: [28, 22, 28], zoom: 40, near: 0.1, far: 200 }}
        style={{ touchAction: 'none' }}
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
        <Driver view={view} actor={actor} paused={Boolean(props.paused)} />
        <House {...props} view={view} actorRef={actor} />
      </Canvas>
    </div>
  );
}
