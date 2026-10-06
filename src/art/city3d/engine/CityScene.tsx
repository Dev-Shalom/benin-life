// R5: the live 3D city (react-three-fiber). Lazy-loaded through ../CityView.tsx.
//
// One perspective canvas, frameloop="demand". It redraws every frame while the camera moves (drag,
// pinch, fly-to, inertia) and ~15 fps otherwise for the traffic and pulses (not at all when paused,
// hidden or with reduced motion). Place labels are an HTML overlay positioned from the camera in the
// same frame (no React re-render per frame).
import { Canvas, useFrame, useThree } from '@react-three/fiber';
import { memo, useCallback, useEffect, useMemo, useRef, useState, type CSSProperties, type MutableRefObject } from 'react';
import {
  Color,
  DirectionalLight,
  Fog,
  Group,
  HemisphereLight,
  InstancedMesh,
  Matrix4,
  Mesh,
  MeshBasicMaterial,
  MeshLambertMaterial,
  PerspectiveCamera,
  PlaneGeometry,
  Plane,
  Quaternion,
  Raycaster,
  Vector2,
  Vector3,
  type BufferGeometry,
} from 'three';
import type { Location } from '../../../lib/types';
import { toast } from '../../../ui';
import {
  COMING_SOON, DISTRICT_NAMES, EXIT_SIGNS, FILTERS, FILTER_COLOR, GO_SLOW_MIN, isNightRisky, matchesFilter, placeEmoji,
  placeTier, shortName, toMap, WS, type CityFilter,
} from '../model';
import { roadRoute } from '../route';
import { buildCity, kekeGeometry, pinGeometry, radialTexture, ringGeometry, routeGeometry } from './build';
import { getCityLayout } from './layout';
import { cityLight } from './light';
import { mixHex, smoothstep } from '../../../lib/daylight';
import { at, ROADS, type Pt } from '../../map/mapGeo';
import '../city3d.css';

export interface CityApi {
  snapshot(): string | null;
  stats(): { calls: number; triangles: number; geometries: number; buildings: number; trees: number; vehicles: number; layoutMs: number };
  bench(n?: number): number;
  /** Fly the camera to a map-space point (zoom = visible size of the short screen side, world units). */
  flyTo(mx: number, my: number, zoom?: number): void;
  screenOf(id: string): { x: number; y: number } | null;
}

export interface CitySceneProps {
  locations: Location[];
  currentId?: string;
  selectedId?: string;
  onSelect: (id: string) => void;
  /** Game hour as a float (14.5 = 2:30 pm). */
  hour: number;
  travel?: { from: string; to: string; progress: number; mode?: string } | null;
  crowd?: Record<string, number>;
  paused?: boolean;
  onReady?: (api: CityApi) => void;
  onLost?: () => void;
  /** Pixels covered by HUD chrome at the top / bottom. */
  insetTop?: number;
  insetBottom?: number;
  /** Dev page: start the camera here instead of on the player. */
  initial?: { x: number; y: number; zoom: number };
  /** Hide the filter chips (dev close-ups). */
  hideChrome?: boolean;
  /** Dev page: start with these filters on. */
  initialFilters?: CityFilter[];
  className?: string;
  style?: CSSProperties;
}

/* ------------------------------------------------------------------ */
/* Camera state                                                         */
/* ------------------------------------------------------------------ */
interface View {
  tx: number;
  tz: number;
  /** visible size of the short screen side at the target, in world units */
  zoom: number;
  anim: { fx: number; fz: number; fzoom: number; tx: number; tz: number; tzoom: number; t0: number; dur: number } | null;
  vx: number;
  vz: number;
  dragging: boolean;
  visible: boolean;
  dirty: boolean;
}

const FOV = 34;
const ZOOM_MIN = 5;
const ZOOM_MAX = 80;
/** S3: how far the target may pan from King's Square; tighter when zoomed out so the city fills the screen. */
const bnd = (zoom: number) => clamp(47 - zoom * 0.4, 14, 45);
const reduceMotion = () => typeof matchMedia !== 'undefined' && matchMedia('(prefers-reduced-motion: reduce)').matches;
const clamp = (v: number, a: number, b: number) => (v < a ? a : v > b ? b : v);
const easeOut = (t: number) => 1 - Math.pow(1 - t, 3);

/** "cover" on phones: the short side shows about as much of the city as the 2D map's cover zoom. */
function coverZoom(w: number, h: number): number {
  const aspect = w / Math.max(1, h);
  // S3: desktop opens a little closer (was 100 / aspect) so streets and road names read at once
  return clamp(aspect < 1 ? 100 * aspect * 0.92 : (100 / aspect) * 0.78, 18, 70);
}

/** Filters survive the canvas being unmounted (suspend) within a session. */
let savedFilters: CityFilter[] = [];
/** Where the camera was when the canvas last unmounted (suspend, or leaving the map view). */
let savedView: { tx: number; tz: number; zoom: number } | null = null;

interface Controller {
  groundAt(cx: number, cy: number, out: Vector3): boolean;
  apply(): void;
  project(mx: number, my: number, y?: number): { x: number; y: number; ok: boolean };
}

/* ------------------------------------------------------------------ */
/* Label overlay                                                        */
/* ------------------------------------------------------------------ */
type LabelKind = 'place' | 'soon' | 'exit' | 'district' | 'me' | 'road';
interface LabelItem {
  key: string;
  kind: LabelKind;
  x: number;
  y: number;
  /** lower = placed first */
  prio: number;
  tier: 1 | 2;
  must: boolean;
  /** road names: a second point further along the road (screen angle) and the text */
  x2?: number;
  y2?: number;
  text?: string;
}

interface LabelState {
  els: Map<string, HTMLElement>;
  sizes: Map<string, [number, number]>;
  items: LabelItem[];
  state: Map<string, string>;
  /** travel marker position (map space) for the "On the way" tag */
  me: { x: number; y: number } | null;
  /** S3: the current place's label sits on top of the 3D pin (world height of the pin head) */
  curKey?: string;
  curTop: number;
}

/* ------------------------------------------------------------------ */
/* Scene contents                                                       */
/* ------------------------------------------------------------------ */
interface InnerProps extends CitySceneProps {
  view: MutableRefObject<View>;
  ctl: MutableRefObject<Controller | null>;
  labels: MutableRefObject<LabelState>;
  filters: CityFilter[];
  motion: boolean;
}

function Driver({ view, paused, motion }: { view: MutableRefObject<View>; paused: boolean; motion: boolean }) {
  const invalidate = useThree((s) => s.invalidate);
  useEffect(() => {
    if (paused) return;
    let raf = 0;
    let last = 0;
    const loop = (now: number) => {
      raf = requestAnimationFrame(loop);
      if (document.hidden || !view.current.visible) return;
      const v = view.current;
      const moving = v.dragging || v.anim || Math.abs(v.vx) + Math.abs(v.vz) > 1e-4 || v.dirty;
      if (!moving && (!motion || now - last < 1000 / 15)) return;
      last = now;
      invalidate();
    };
    raf = requestAnimationFrame(loop);
    return () => cancelAnimationFrame(raf);
  }, [invalidate, view, paused, motion]);
  return null;
}

const _v = new Vector3();
const _s = new Vector3();
const _q = new Quaternion();
const _mat = new Matrix4();
const _ndc = new Vector2();
const _ray = new Raycaster();
const GROUND = new Plane(new Vector3(0, 1, 0), 0);
const W = (m: number) => (m - 500) * WS;

function City(props: InnerProps) {
  const { locations, currentId, selectedId, hour, travel, crowd, filters, view, ctl, labels, motion, onReady, insetTop = 0, insetBottom = 0 } = props;
  const { gl, scene, camera, size, invalidate } = useThree();
  const cam = camera as PerspectiveCamera;

  const layout = useMemo(() => getCityLayout(), []);
  const city = useMemo(() => buildCity(layout), [layout]);
  useEffect(() => () => city.dispose(), [city]);

  const byId = useMemo(() => new Map(locations.map((l) => [l.id, l])), [locations]);

  /* ---------- lights, sky, fog ---------- */
  const lights = useMemo(() => {
    const g = new Group();
    const hemi = new HemisphereLight('#f2f7ff', '#b7a58f', 1.5);
    const sun = new DirectionalLight('#fff1dc', 2);
    g.add(hemi, sun, sun.target);
    return { g, hemi, sun };
  }, []);
  const hourKey = Math.round(hour * 60); // S1: re-light every minute (continuous curve, one redraw)
  const lt = useMemo(() => cityLight(hourKey / 60), [hourKey]);
  useEffect(() => {
    lights.hemi.color.set(lt.hemiSky);
    lights.hemi.groundColor.set(lt.hemiGround);
    lights.hemi.intensity = lt.hemi;
    lights.sun.color.set(lt.sun);
    lights.sun.intensity = lt.sunI;
    lights.sun.position.set(lt.sunDir[0] * 40, lt.sunDir[1] * 40, lt.sunDir[2] * 40);
    city.mats.glow.color.set(lt.glow);
    city.mats.water.color.set(lt.water);
    city.mats.bulbs.color.set(lt.bulbs);
    city.mats.shadow.opacity = 0.16 * (1 - lt.dark * 0.6);
    // street-light pools fade in/out; window bands go from unlit glass to warm light (no pop)
    const glowK = smoothstep(0.08, 0.85, lt.dark);
    for (const o of city.nightOnly) o.visible = lt.dark > 0.08;
    city.mats.pools.opacity = 0.8 * glowK;
    city.mats.windows.color.set(mixHex('#56606e', '#ffdc8a', glowK));
    const sky = new Color(lt.sky);
    scene.background = sky;
    if (!scene.fog) scene.fog = new Fog(sky, 50, 200);
    else (scene.fog as Fog).color.copy(sky);
    invalidate();
  }, [lt, lights, city, scene, invalidate]);

  /* ---------- shared marker geometry/materials ---------- */
  const fx = useMemo(() => {
    const ring = ringGeometry(0.7);
    const thin = ringGeometry(0.86);
    const pin = pinGeometry();
    const keke = kekeGeometry();
    const plane = new PlaneGeometry(1, 1);
    plane.rotateX(-Math.PI / 2);
    const glowTex = radialTexture('rgba(255,255,255,1)', 'rgba(255,255,255,0.45)');
    const m = {
      me: new MeshLambertMaterial({ color: '#17a05c', emissive: '#0b6b3c', flatShading: true }),
      meRing: new MeshBasicMaterial({ color: '#17a05c', transparent: true, opacity: 0.8, depthWrite: false }),
      sel: new MeshBasicMaterial({ color: '#ffffff', transparent: true, opacity: 0.95, depthWrite: false }),
      filt: new MeshBasicMaterial({ transparent: true, opacity: 0.85, depthWrite: false }),
      danger: new MeshBasicMaterial({ color: '#ff3b30', map: glowTex, transparent: true, opacity: 0.7, depthWrite: false }),
      jam: new MeshBasicMaterial({ color: '#ff3b30', transparent: true, opacity: 0.55, depthWrite: false }),
      done: new MeshBasicMaterial({ color: '#17a05c', depthWrite: false, transparent: true, opacity: 0.95 }),
      todo: new MeshBasicMaterial({ color: '#ffffff', depthWrite: false, transparent: true, opacity: 0.9 }),
      dest: new MeshBasicMaterial({ color: '#e5484d', transparent: true, opacity: 0.9, depthWrite: false }),
      keke: new MeshLambertMaterial({ vertexColors: true, flatShading: true }),
      kekeBase: new MeshBasicMaterial({ color: '#ffffff', transparent: true, opacity: 0.9, depthWrite: false }),
    };
    return { ring, thin, pin, keke, plane, glowTex, m };
  }, []);
  useEffect(
    () => () => {
      for (const g of [fx.ring, fx.thin, fx.pin, fx.keke, fx.plane]) g.dispose();
      fx.glowTex.dispose();
      for (const m of Object.values(fx.m)) m.dispose();
    },
    [fx],
  );

  // you are here: green pin + pulsing ring
  const me = useMemo(() => {
    const g = new Group();
    const pin = new Mesh(fx.pin, fx.m.me);
    pin.scale.setScalar(0.55);
    const ring = new Mesh(fx.ring, fx.m.meRing);
    ring.position.y = 0.1;
    ring.renderOrder = 4;
    g.add(pin, ring);
    g.visible = false;
    return { g, pin, ring };
  }, [fx]);
  const sel = useMemo(() => {
    const m = new Mesh(fx.thin, fx.m.sel);
    m.position.y = 0.11;
    m.renderOrder = 5;
    m.visible = false;
    return m;
  }, [fx]);

  const cur = currentId ? byId.get(currentId) : undefined;
  useEffect(() => {
    me.g.visible = Boolean(cur);
    if (cur) me.g.position.set(W(cur.x), 0, W(cur.y));
    invalidate();
  }, [cur, me, invalidate]);
  const selLoc = selectedId ? byId.get(selectedId) : undefined;
  useEffect(() => {
    sel.visible = Boolean(selLoc) && selLoc !== cur;
    if (selLoc) sel.position.set(W(selLoc.x), 0.11, W(selLoc.y));
    invalidate();
  }, [selLoc, cur, sel, invalidate]);

  /* ---------- filters: rings, danger glow, go-slow roads ---------- */
  const filterRings = useMemo(() => {
    const im = new InstancedMesh(fx.ring, fx.m.filt, Math.max(1, locations.length));
    im.count = 0;
    im.renderOrder = 4;
    return im;
  }, [fx, locations.length]);
  useEffect(() => () => filterRings.dispose(), [filterRings]);
  useEffect(() => {
    let n = 0;
    const c = new Color();
    for (const l of locations) {
      const f = filters.find((ff) => matchesFilter(ff, l, crowd));
      if (!f) continue;
      const s = f === 'goslow' ? 0.8 + (l.congestion - 1) * 1.1 : f === 'danger' ? 1.6 : 1.1;
      filterRings.setMatrixAt(n, _mat.compose(_v.set(W(l.x), 0.1, W(l.y)), _q, _s.set(s, 1, s)));
      filterRings.setColorAt(n++, c.set(FILTER_COLOR[f]));
    }
    filterRings.count = n;
    filterRings.instanceMatrix.needsUpdate = true;
    if (filterRings.instanceColor) filterRings.instanceColor.needsUpdate = true;
    invalidate();
  }, [filters, locations, crowd, filterRings, invalidate]);

  const risky = useMemo(() => locations.filter(isNightRisky), [locations]);
  const danger = useMemo(() => {
    const im = new InstancedMesh(fx.plane, fx.m.danger, Math.max(1, risky.length));
    risky.forEach((l, i) => {
      im.setMatrixAt(i, _mat.compose(_v.set(W(l.x), 0.075, W(l.y)), _q, _s.set(11, 1, 11)));
    });
    im.count = risky.length;
    im.renderOrder = 3;
    im.visible = false;
    return im;
  }, [fx, risky]);
  useEffect(() => () => danger.dispose(), [danger]);

  const jamRoads = useMemo(() => {
    const congested = locations.filter((l) => l.congestion >= GO_SLOW_MIN);
    const segs: [Pt[], number][] = [];
    for (const r of layout.roads) {
      if (r.kind === 'spur' || r.kind === 'dirt') continue;
      let run: Pt[] = [];
      for (let s = 0; s <= r.sp.length; s += 3) {
        const p = at(r.sp, s);
        const near = congested.some((l) => Math.hypot(p.x - l.x, p.y - l.y) < 26 + (l.congestion - GO_SLOW_MIN) * 60);
        if (near) run.push([p.x, p.y]);
        else if (run.length) {
          if (run.length > 1) segs.push([run, r.hw]);
          run = [];
        }
      }
      if (run.length > 1) segs.push([run, r.hw]);
    }
    const geos: BufferGeometry[] = segs.map(([s, hw]) => routeGeometry(s, hw + 0.8).geo);
    const g = new Group();
    for (const geo of geos) {
      const m = new Mesh(geo, fx.m.jam);
      m.position.y = -0.025;
      m.renderOrder = 3;
      g.add(m);
    }
    g.visible = false;
    return { g, geos };
  }, [layout, locations, fx]);
  useEffect(() => () => jamRoads.geos.forEach((g) => g.dispose()), [jamRoads]);

  const dangerOn = filters.includes('danger');
  const jamOn = filters.includes('goslow');
  useEffect(() => {
    jamRoads.g.visible = jamOn;
    invalidate();
  }, [jamOn, jamRoads, invalidate]);

  /* ---------- travel overlay ---------- */
  const tFrom = travel ? byId.get(travel.from) : undefined;
  const tTo = travel ? byId.get(travel.to) : undefined;
  const route = useMemo(() => {
    if (!tFrom || !tTo) return null;
    const pts = roadRoute(tFrom, tTo);
    const { geo, lengths } = routeGeometry(pts, 2.4);
    const mesh = new Mesh(geo, [fx.m.done, fx.m.todo]);
    mesh.renderOrder = 4;
    const keke = new Group();
    const body = new Mesh(fx.keke, fx.m.keke);
    body.scale.setScalar(0.85);
    const base = new Mesh(fx.ring, fx.m.kekeBase);
    base.scale.setScalar(0.75);
    base.position.y = 0.1;
    keke.add(base, body);
    const dest = new Mesh(fx.ring, fx.m.dest);
    dest.position.set(W(tTo.x), 0.12, W(tTo.y));
    dest.renderOrder = 5;
    return { pts, geo, lengths, total: lengths[lengths.length - 1] || 1, mesh, keke, dest, shown: -1 };
  }, [tFrom, tTo, fx]);
  useEffect(() => () => route?.geo.dispose(), [route]);
  // a new trip: frame the whole route
  useEffect(() => {
    if (!route) return;
    let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
    for (const [x, y] of route.pts) {
      x0 = Math.min(x0, x); y0 = Math.min(y0, y); x1 = Math.max(x1, x); y1 = Math.max(y1, y);
    }
    const span = Math.max(x1 - x0, (y1 - y0) * 0.8) * WS;
    flyTo(view.current, W((x0 + x1) / 2), W((y0 + y1) / 2), clamp(span * 1.5, 14, 80));
    invalidate();
  }, [route, view, invalidate]);
  const targetProgress = travel?.progress ?? 0;
  const progressRef = useRef(targetProgress);
  useEffect(() => {
    if (!route) return;
    // jump straight to the current progress when a new trip appears (e.g. on reload mid-trip)
    progressRef.current = targetProgress;
    route.shown = -1;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [route]);

  /* ---------- camera ---------- */
  const shift = (insetTop - insetBottom) / 2;
  const apply = useCallback(() => {
    const v = view.current;
    const aspect = size.width / Math.max(1, size.height);
    const pitch = ((46 + 14 * clamp((v.zoom - 10) / 70, 0, 1)) * Math.PI) / 180;
    const d = v.zoom / (2 * Math.tan(((FOV / 2) * Math.PI) / 180) * Math.min(1, aspect));
    cam.fov = FOV;
    cam.position.set(v.tx, Math.sin(pitch) * d, v.tz + Math.cos(pitch) * d);
    cam.lookAt(v.tx, 0, v.tz);
    cam.near = Math.max(0.3, d * 0.15);
    cam.far = d * 6;
    if (Math.abs(shift) > 1) cam.setViewOffset(size.width, size.height, 0, -shift, size.width, size.height);
    else cam.clearViewOffset();
    cam.updateProjectionMatrix();
    cam.updateMatrixWorld();
    const fog = scene.fog as Fog | null;
    if (fog) {
      fog.near = d * 1.35;
      fog.far = d * 3.4;
    }
  }, [cam, size, shift, view, scene]);

  useEffect(() => {
    ctl.current = {
      apply,
      groundAt(cx, cy, out) {
        const r = gl.domElement.getBoundingClientRect();
        _ndc.set(((cx - r.left) / r.width) * 2 - 1, -((cy - r.top) / r.height) * 2 + 1);
        _ray.setFromCamera(_ndc, cam);
        return _ray.ray.intersectPlane(GROUND, out) !== null;
      },
      project(mx, my, y = 0) {
        _v.set(W(mx), y, W(my)).project(cam);
        return { x: ((_v.x + 1) / 2) * size.width, y: ((1 - _v.y) / 2) * size.height, ok: _v.z < 1 && _v.z > -1 };
      },
    };
    view.current.dirty = true;
    invalidate();
  }, [apply, gl, cam, size, ctl, view, invalidate]);

  /* ---------- per frame ---------- */
  const t0 = useRef(performance.now());
  useFrame((_s, dt) => {
    const v = view.current;
    const now = performance.now();
    if (v.anim) {
      const a = v.anim;
      const k = clamp((now - a.t0) / a.dur, 0, 1);
      const e = easeOut(k);
      v.tx = a.fx + (a.tx - a.fx) * e;
      v.tz = a.fz + (a.tz - a.fz) * e;
      v.zoom = a.fzoom + (a.tzoom - a.fzoom) * e;
      if (k >= 1) v.anim = null;
    } else if (!v.dragging && Math.abs(v.vx) + Math.abs(v.vz) > 1e-4) {
      const step = Math.min(dt, 0.05) * 1000;
      v.tx += v.vx * step;
      v.tz += v.vz * step;
      const decay = Math.exp(-step / 260);
      v.vx *= decay;
      v.vz *= decay;
      if (Math.abs(v.vx) + Math.abs(v.vz) < 2e-4) v.vx = v.vz = 0;
    }
    v.zoom = clamp(v.zoom, ZOOM_MIN, ZOOM_MAX);
    v.tx = clamp(v.tx, -bnd(v.zoom), bnd(v.zoom));
    v.tz = clamp(v.tz, -bnd(v.zoom), bnd(v.zoom));
    v.dirty = false;
    apply();

    const t = motion ? (now - t0.current) / 1000 : 0;
    if (motion) city.animate(t);
    // pulses
    const pulse = motion ? 0.5 + 0.5 * Math.sin(t * 3) : 0.6;
    if (me.g.visible) {
      const s = Math.max(0.9, v.zoom * 0.028);
      me.pin.scale.setScalar(0.7 * s);
      labels.current.curTop = 1.5 * 0.7 * s;
      me.pin.position.y = motion ? Math.sin(t * 2.4) * 0.08 * s : 0;
      me.ring.scale.setScalar((0.9 + pulse * 0.5) * s);
      fx.m.meRing.opacity = 0.85 - pulse * 0.45;
    }
    if (sel.visible) sel.scale.setScalar(Math.max(1, v.zoom * 0.03) * 1.3);
    const night = lt.dark > 0.45;
    danger.visible = risky.length > 0 && (night || dangerOn);
    if (danger.visible) fx.m.danger.opacity = night ? 0.42 + pulse * 0.2 : 0.35;
    if (jamOn) fx.m.jam.opacity = 0.5 + pulse * 0.3;
    filterRings.visible = filterRings.count > 0;

    // travel marker
    labels.current.me = null;
    if (route) {
      const p = progressRef.current + (targetProgress - progressRef.current) * Math.min(1, dt * 2.5);
      progressRef.current = p;
      const sAt = p * route.total;
      let i = 0;
      while (i < route.lengths.length - 2 && route.lengths[i + 1] < sAt) i++;
      if (i !== route.shown) {
        route.geo.clearGroups();
        route.geo.addGroup(0, i * 6, 0);
        route.geo.addGroup(i * 6, (route.lengths.length - 1 - i) * 6, 1);
        route.shown = i;
      }
      const a = route.pts[i];
      const b = route.pts[Math.min(route.pts.length - 1, i + 1)];
      const seg = Math.max(1e-6, route.lengths[i + 1] - route.lengths[i]);
      const f = clamp((sAt - route.lengths[i]) / seg, 0, 1);
      const mx = a[0] + (b[0] - a[0]) * f;
      const my = a[1] + (b[1] - a[1]) * f;
      const s = Math.max(1, v.zoom * 0.03);
      route.keke.position.set(W(mx), 0.06, W(my));
      route.keke.rotation.y = -Math.atan2(b[1] - a[1], b[0] - a[0]);
      route.keke.scale.setScalar(s);
      route.dest.scale.setScalar((1 + pulse * 0.6) * s);
      labels.current.me = { x: mx, y: my };
    }

    placeLabels(labels.current, ctl.current, size, v.zoom, { top: insetTop + (props.hideChrome ? 0 : 50), bottom: insetBottom + (props.hideChrome ? 0 : 56) });
  });

  /* ---------- API ---------- */
  useEffect(() => {
    const api: CityApi = {
      snapshot() {
        try {
          gl.render(scene, camera);
          return gl.domElement.toDataURL('image/jpeg', 0.8);
        } catch {
          return null;
        }
      },
      stats() {
        gl.render(scene, camera);
        return {
          calls: gl.info.render.calls,
          triangles: gl.info.render.triangles,
          geometries: gl.info.memory.geometries,
          buildings: layout.buildings.length,
          trees: layout.trees.length,
          vehicles: layout.vehicles.length,
          layoutMs: layout.ms,
        };
      },
      bench(n = 60) {
        // readPixels forces the GPU to finish, so the time covers the real draw work
        const ctx = gl.getContext();
        const px = new Uint8Array(4);
        gl.render(scene, camera);
        ctx.readPixels(0, 0, 1, 1, ctx.RGBA, ctx.UNSIGNED_BYTE, px);
        const s = performance.now();
        for (let i = 0; i < n; i++) {
          gl.render(scene, camera);
          ctx.readPixels(0, 0, 1, 1, ctx.RGBA, ctx.UNSIGNED_BYTE, px);
        }
        return (performance.now() - s) / n;
      },
      flyTo(mx, my, zoom) {
        flyTo(view.current, W(mx), W(my), zoom ?? view.current.zoom);
        invalidate();
      },
      screenOf(id) {
        const l = byId.get(id);
        if (!l) return null;
        _v.set(W(l.x), 0, W(l.y)).project(camera);
        return { x: ((_v.x + 1) / 2) * size.width, y: ((1 - _v.y) / 2) * size.height };
      },
    };
    onReady?.(api);
    if (import.meta.env.DEV) Object.assign(window, { __city: api, __cityView: view.current, __cityGl: { gl, scene, camera } });
  }, [gl, scene, camera, layout, onReady, byId, size, view, invalidate]);

  return (
    <>
      <primitive object={lights.g} />
      <primitive object={city.group} />
      <primitive object={danger} />
      <primitive object={jamRoads.g} />
      <primitive object={filterRings} />
      <primitive object={me.g} />
      <primitive object={sel} />
      {route && <primitive object={route.mesh} />}
      {route && <primitive object={route.keke} />}
      {route && <primitive object={route.dest} />}
    </>
  );
}

function flyTo(v: View, tx: number, tz: number, zoom: number) {
  zoom = clamp(zoom, ZOOM_MIN, ZOOM_MAX);
  tx = clamp(tx, -bnd(zoom), bnd(zoom));
  tz = clamp(tz, -bnd(zoom), bnd(zoom));
  v.vx = v.vz = 0;
  if (reduceMotion()) {
    v.tx = tx;
    v.tz = tz;
    v.zoom = zoom;
    v.anim = null;
  } else {
    const dist = Math.hypot(tx - v.tx, tz - v.tz);
    v.anim = { fx: v.tx, fz: v.tz, fzoom: v.zoom, tx, tz, tzoom: zoom, t0: performance.now(), dur: clamp(320 + dist * 6, 360, 700) };
  }
  v.dirty = true;
}

/* ------------------------------------------------------------------ */
/* Label placement (greedy, screen space, every rendered frame)         */
/* ------------------------------------------------------------------ */
type Box = [number, number, number, number];
const hit = (a: Box, b: Box) => a[0] < b[2] && a[2] > b[0] && a[1] < b[3] && a[3] > b[1];

function placeLabels(L: LabelState, ctl: Controller | null, size: { width: number; height: number }, zoom: number, reserve: { top: number; bottom: number }) {
  if (!ctl) return;
  // screen areas covered by the HUD, the filter chips and the zoom buttons
  const blocked: Box[] = [
    [-1e4, -1e4, 1e4, reserve.top],
    [-1e4, size.height - reserve.bottom, 1e4, 1e4],
    [size.width - 64, size.height / 2 - 84, 1e4, size.height / 2 + 84],
  ];
  const taken: Box[] = [...blocked];
  const dots: Box[] = [];
  // road names already placed (text -> screen points), so one name does not repeat close by
  roadSeen.clear();
  const order = L.items;
  const W0 = size.width;
  for (const it of order) {
    const el = L.els.get(it.key);
    if (!el) continue;
    let mx = it.x;
    let my = it.y;
    if (it.kind === 'me') {
      if (!L.me) {
        setState(L, it.key, el, 'hidden');
        continue;
      }
      mx = L.me.x;
      my = L.me.y;
    }
    if (it.kind === 'road') {
      placeRoad(L, ctl, it, el, size, zoom, taken);
      continue;
    }
    const lift = it.key === L.curKey ? L.curTop : it.kind === 'place' || it.kind === 'me' ? 0.15 : 0;
    const p = ctl.project(mx, my, lift);
    const off = !p.ok || p.x < -60 || p.x > W0 + 60 || p.y < -40 || p.y > size.height + 60;
    if (off) {
      setState(L, it.key, el, 'hidden');
      continue;
    }
    let sz = L.sizes.get(it.key);
    const inner = el.firstElementChild as HTMLElement | null;
    if (!sz && inner && el.dataset.s !== 'hidden') {
      sz = [inner.offsetWidth, inner.offsetHeight];
      if (sz[0] > 0) L.sizes.set(it.key, sz);
    }
    const [w, h] = sz ?? [it.kind === 'district' ? 90 : 120, 30];
    // S3: a pill that would be cut off by the screen edge slides back in (the ones that must show)
    // or turns into a dot (the rest)
    let px = p.x;
    const pillish = it.kind === 'place' || it.kind === 'soon' || it.kind === 'me';
    const edgeL = 6 + w / 2;
    const edgeR = W0 - 6 - w / 2;
    const clipped = pillish && (px < edgeL || px > edgeR);
    if (clipped && it.must) px = clamp(px, edgeL, Math.max(edgeL, edgeR));
    el.style.transform = `translate3d(${px.toFixed(1)}px, ${p.y.toFixed(1)}px, 0)`;
    let box: Box;
    if (it.kind === 'district' || it.kind === 'exit') box = [px - w / 2, p.y - h / 2, px + w / 2, p.y + h / 2];
    else box = [px - w / 2, p.y - h - 8, px + w / 2, p.y - 4];
    // the "You are here" / "Heading here" tag sits above the pill: keep its space free too
    if (it.must && it.kind === 'place') box[1] -= 22;
    // visibility by zoom
    let want = 'full';
    if (it.kind === 'district') want = zoom > 18 && zoom < 70 ? 'full' : 'hidden';
    else if (it.kind === 'soon') want = zoom < 70 ? 'full' : 'hidden';
    else if (it.kind === 'place' && !it.must) {
      if (it.tier === 2 && zoom > 44) want = 'dot';
      if (zoom > 70) want = 'dot';
      if (clipped) want = 'dot';
    } else if (clipped && !it.must) want = 'hidden';
    if (want === 'full' && taken.some((t) => hit(t, box))) want = it.kind === 'place' ? 'dot' : 'hidden';
    if (want === 'full' || (it.must && want !== 'hidden')) {
      taken.push(box);
      setState(L, it.key, el, 'full');
      continue;
    }
    if (want === 'dot') {
      const d: Box = [p.x - 13, p.y - 13, p.x + 13, p.y + 13];
      if (!taken.some((t) => hit(t, d)) && !dots.some((t) => hit(t, d))) {
        dots.push(d);
        setState(L, it.key, el, 'dot');
        continue;
      }
    }
    setState(L, it.key, el, 'hidden');
  }
}

const roadSeen = new Map<string, [number, number][]>();
const _rb: Box = [0, 0, 0, 0];
/** Road names lie along the road (rotated to its screen angle, kept upright) and only show up close. */
function placeRoad(L: LabelState, ctl: Controller, it: LabelItem, el: HTMLElement, size: { width: number; height: number }, zoom: number, taken: Box[]) {
  if (zoom > 50) return setState(L, it.key, el, 'hidden');
  const p = ctl.project(it.x, it.y, 0.06);
  const q = ctl.project(it.x2!, it.y2!, 0.06);
  if (!p.ok || !q.ok || p.x < 20 || p.x > size.width - 20 || p.y < 20 || p.y > size.height - 20) return setState(L, it.key, el, 'hidden');
  let ang = Math.atan2(q.y - p.y, q.x - p.x);
  if (ang > Math.PI / 2) ang -= Math.PI;
  else if (ang < -Math.PI / 2) ang += Math.PI;
  const sz = L.sizes.get(it.key) ?? measure(L, it.key, el);
  const [w, h] = sz;
  // same name nearby already? skip
  const seen = roadSeen.get(it.text!);
  if (seen && seen.some(([x, y]) => Math.hypot(x - p.x, y - p.y) < 240)) return setState(L, it.key, el, 'hidden');
  // collision: a chain of small squares along the rotated label
  const n = Math.max(2, Math.ceil(w / h));
  const c = Math.cos(ang);
  const sn = Math.sin(ang);
  const boxes: Box[] = [];
  for (let i = 0; i < n; i++) {
    const t = (i / (n - 1) - 0.5) * (w - h);
    const cx = p.x + c * t;
    const cy = p.y + sn * t;
    _rb[0] = cx - h / 2;
    _rb[1] = cy - h / 2;
    _rb[2] = cx + h / 2;
    _rb[3] = cy + h / 2;
    if (taken.some((b) => hit(b, _rb))) return setState(L, it.key, el, 'hidden');
    boxes.push([_rb[0], _rb[1], _rb[2], _rb[3]]);
  }
  for (const b of boxes) taken.push(b);
  if (seen) seen.push([p.x, p.y]);
  else roadSeen.set(it.text!, [[p.x, p.y]]);
  el.style.transform = `translate3d(${p.x.toFixed(1)}px, ${p.y.toFixed(1)}px, 0) rotate(${ang.toFixed(3)}rad)`;
  setState(L, it.key, el, 'full');
}

function measure(L: LabelState, key: string, el: HTMLElement): [number, number] {
  const inner = el.firstElementChild as HTMLElement | null;
  if (inner && el.dataset.s !== 'hidden' && inner.offsetWidth > 0) {
    const sz: [number, number] = [inner.offsetWidth, inner.offsetHeight];
    L.sizes.set(key, sz);
    return sz;
  }
  return [(L.items.find((i) => i.key === key)?.text?.length ?? 10) * 6.6 + 8, 16];
}

function setState(L: LabelState, key: string, el: HTMLElement, s: string) {
  if (L.state.get(key) === s) return;
  L.state.set(key, s);
  el.dataset.s = s;
}

/** S3: road-name candidates along the named roads (MAP_GEO names), every ~150 map units; the
 *  placement keeps the ones that fit and never repeats a name close by. */
let roadCands: LabelItem[] | null = null;
function roadLabels(): LabelItem[] {
  if (roadCands) return roadCands;
  const out: LabelItem[] = [];
  const lay = getCityLayout();
  for (const rd of ROADS) {
    if (!rd.labels?.length) continue;
    const line = lay.roads.find((r) => r.id === rd.id);
    if (!line) continue;
    const L = line.sp.length;
    const marks = new Set<number>(rd.labels.map(([, f]) => f * L));
    for (let s = 60; s < L - 40; s += 150) marks.add(s);
    for (const s of [...marks].sort((a, b) => a - b)) {
      const p = at(line.sp, s);
      if (p.x < 10 || p.x > 990 || p.y < 10 || p.y > 990) continue;
      const q = at(line.sp, Math.min(L, s + 8));
      // the name for this stretch: the label whose position is closest
      const name = rd.labels.reduce((b, l) => (Math.abs(l[1] * L - s) < Math.abs(b[1] * L - s) ? l : b))[0];
      out.push({ key: `road:${rd.id}:${Math.round(s)}`, kind: 'road', x: p.x, y: p.y, x2: q.x, y2: q.y, text: name, prio: 8.5, tier: 2, must: false });
    }
  }
  // King's Square ring
  const ring = lay.roads.find((r) => r.id === 'ring');
  if (ring) {
    for (const f of [0.12, 0.62]) {
      const p = at(ring.sp, f * ring.sp.length);
      const q = at(ring.sp, f * ring.sp.length + 6);
      out.push({ key: `road:ring:${f}`, kind: 'road', x: p.x, y: p.y, x2: q.x, y2: q.y, text: 'Ring Rd', prio: 8.4, tier: 2, must: false });
    }
  }
  return (roadCands = out);
}

/** The big landmarks win label space over other places. */
const LANDMARKS = new Set(['national_museum', 'oba_palace', 'oba_market', 'uniben', 'ubth', 'benin_airport', 'ramat_park', 'police_hq']);

const MODE_EMOJI: Record<string, string> = { walk: '🚶', keke: '🛺', bus: '🚌', drop: '🚕', car: '🚗' };

const Labels = memo(function Labels(props: {
  locations: Location[];
  currentId?: string;
  selectedId?: string;
  travelTo?: string;
  travelMode?: string;
  crowd?: Record<string, number>;
  filters: CityFilter[];
  night: boolean;
  labels: MutableRefObject<LabelState>;
  onPick: (id: string) => void;
  onItems: (items: LabelItem[]) => void;
  dragMoved: MutableRefObject<boolean>;
}) {
  const { locations, currentId, selectedId, travelTo, travelMode, crowd, filters, night, labels, onPick, onItems, dragMoved } = props;
  // priority order for the greedy placement
  const items = useMemo(() => {
    const out: LabelItem[] = [];
    out.push({ key: 'me', kind: 'me', x: 0, y: 0, prio: 0, tier: 1, must: true });
    for (const l of locations) {
      const tier = placeTier(l.id);
      const isF = filters.some((f) => matchesFilter(f, l, crowd));
      const must = l.id === selectedId || l.id === currentId || l.id === travelTo;
      const prio = l.id === selectedId ? 1 : l.id === currentId ? 2 : l.id === travelTo ? 3 : isF ? 4 : LANDMARKS.has(l.id) ? 5 : tier === 1 ? 6 : 8;
      // filter matches and tonight's danger zones label like landmarks
      const lift = isF || (night && isNightRisky(l));
      out.push({ key: l.id, kind: 'place', x: l.x, y: l.y, prio: prio + (crowd?.[l.id] ? -0.5 : 0) - (lift && prio > 4 ? 2 : 0), tier: lift ? 1 : tier, must });
    }
    for (const c of COMING_SOON) out.push({ key: 'soon:' + c.id, kind: 'soon', x: c.x, y: c.y, prio: 7, tier: 1, must: false });
    for (const e of EXIT_SIGNS) out.push({ key: 'exit:' + e.text, kind: 'exit', x: e.x, y: e.y, prio: 9, tier: 1, must: false });
    for (const d of DISTRICT_NAMES) out.push({ key: 'd:' + d.t, kind: 'district', x: d.x, y: d.y, prio: 10, tier: 2, must: false });
    out.push(...roadLabels());
    return out.sort((a, b) => a.prio - b.prio);
  }, [locations, currentId, selectedId, travelTo, crowd, filters, night]);
  useEffect(() => onItems(items), [items, onItems]);

  const reg = (key: string) => (el: HTMLElement | null) => {
    if (el) labels.current.els.set(key, el);
    else {
      labels.current.els.delete(key);
      labels.current.state.delete(key);
    }
  };
  const tap = (fn: () => void) => () => {
    if (dragMoved.current) return;
    fn();
  };
  const anyFilter = filters.length > 0;

  return (
    <div className="c3-labels" aria-label="Places">
      <div ref={reg('me')} className="c3-label c3-me" data-s="hidden">
        <span className="c3-pill c3-pill--me"><span aria-hidden>{MODE_EMOJI[travelMode ?? ''] ?? '🚶'}</span> On the way</span>
      </div>
      {locations.map((l) => {
        const f = filters.find((ff) => matchesFilter(ff, l, crowd));
        const isCur = l.id === currentId;
        const isSel = l.id === selectedId;
        const dangerNow = night && isNightRisky(l);
        const n = crowd?.[l.id] ?? 0;
        const cls = [
          'c3-label c3-place',
          isCur && 'is-current',
          isSel && 'is-selected',
          l.id === travelTo && 'is-dest',
          dangerNow && 'is-danger',
          anyFilter && (f ? 'is-match' : 'is-dim'),
        ]
          .filter(Boolean)
          .join(' ');
        return (
          <div key={l.id} ref={reg(l.id)} className={cls} data-s="hidden" style={f ? ({ '--c3-f': FILTER_COLOR[f] } as CSSProperties) : undefined}>
            <button type="button" className="c3-pill" onClick={tap(() => onPick(l.id))} aria-label={l.name}>
              {isCur && <span className="c3-pill__tag">You are here</span>}
              {l.id === travelTo && !isCur && <span className="c3-pill__tag c3-pill__tag--dest">Heading here</span>}
              <span className="c3-pill__emoji" aria-hidden>{placeEmoji(l)}</span>
              <span className="c3-pill__name">{shortName(l.id, l.name)}</span>
              {dangerNow && <span className="c3-pill__warn" aria-label="Danger at night">⚠️</span>}
              {n > 0 && <span className="c3-pill__count" aria-label={`${n} players here`}>{n}</span>}
            </button>
            <button type="button" className="c3-dot" onClick={tap(() => onPick(l.id))} aria-label={l.name} tabIndex={-1}>
              <span aria-hidden>{placeEmoji(l)}</span>
            </button>
          </div>
        );
      })}
      {COMING_SOON.map((c) => (
        <div key={c.id} ref={reg('soon:' + c.id)} className="c3-label c3-soon" data-s="hidden">
          <button type="button" className="c3-pill c3-pill--soon" onClick={tap(() => toast(c.note, 'info'))}>
            <span aria-hidden>🚧</span> <span aria-hidden>{c.emoji}</span> {c.label} · Coming soon
          </button>
        </div>
      ))}
      {EXIT_SIGNS.map((e) => (
        <div key={e.text} ref={reg('exit:' + e.text)} className="c3-label c3-exit" data-s="hidden" aria-hidden>
          <span className="c3-sign"><b>{e.arrow} {e.text}</b><small>{e.sub}</small></span>
        </div>
      ))}
      {roadLabels().map((r) => (
        <div key={r.key} ref={reg(r.key)} className="c3-label c3-road" data-s="hidden" aria-hidden>
          <span>{r.text}</span>
        </div>
      ))}
      {DISTRICT_NAMES.map((d) => (
        <div key={d.t} ref={reg('d:' + d.t)} className="c3-label c3-district" data-s="hidden" aria-hidden>
          <span>{d.t}</span>
        </div>
      ))}
    </div>
  );
});

/* ------------------------------------------------------------------ */
/* Root                                                                 */
/* ------------------------------------------------------------------ */
export default function CityScene(props: CitySceneProps) {
  const { locations, currentId, selectedId, onSelect, travel, crowd, hour } = props;
  const wrap = useRef<HTMLDivElement>(null);
  const ctl = useRef<Controller | null>(null);
  const labels = useRef<LabelState>({ els: new Map(), sizes: new Map(), items: [], state: new Map(), me: null, curTop: 1 });
  const dragMoved = useRef(false);
  const onSelectRef = useRef(onSelect);
  useEffect(() => {
    onSelectRef.current = onSelect;
  }, [onSelect]);
  const onItems = useCallback((items: LabelItem[]) => {
    labels.current.items = items;
    labels.current.sizes.clear();
  }, []);
  useEffect(() => {
    labels.current.curKey = currentId;
  }, [currentId]);
  const [filters, setFilters] = useState<CityFilter[]>(props.initialFilters ?? savedFilters);
  const motion = useMemo(() => !reduceMotion(), []);
  const night = cityLight(hour).dark > 0.45;
  const byId = useMemo(() => new Map(locations.map((l) => [l.id, l])), [locations]);

  // initial camera: the dev focus, the last view (this session), or "cover" on the player
  const [initialView] = useState<View>(() => {
    const w = typeof window !== 'undefined' ? window.innerWidth : 390;
    const h = typeof window !== 'undefined' ? window.innerHeight : 844;
    const cur = (currentId && byId.get(currentId)) || (travel && byId.get(travel.from)) || null;
    const init = props.initial
      ? { tx: W(props.initial.x), tz: W(props.initial.y), zoom: props.initial.zoom }
      : savedView ?? { tx: cur ? W(cur.x) * 0.62 : 0, tz: cur ? W(cur.y) * 0.62 : 0, zoom: coverZoom(w, h) };
    return { ...init, anim: null, vx: 0, vz: 0, dragging: false, visible: true, dirty: true };
  });
  const view = useRef<View>(initialView);
  useEffect(() => {
    const v = view.current;
    return () => {
      savedView = { tx: v.tx, tz: v.tz, zoom: v.zoom };
    };
  }, []);
  useEffect(() => {
    savedFilters = filters;
  }, [filters]);

  const kick = useCallback(() => {
    view.current.dirty = true;
  }, []);

  // off-screen: stop drawing
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
    };
  }, []);

  /* ---------- focus a place when it gets selected (sheet opens over the lower half) ---------- */
  const focusPlace = useCallback((mx: number, my: number, zoomTo?: number) => {
    const v = view.current;
    const c = ctl.current;
    const el = wrap.current;
    if (!c || !el) return;
    const zoom = zoomTo ?? Math.min(v.zoom, 34);
    // where would the place land if it were the target? shift it into the part the sheet leaves free
    const save = { tx: v.tx, tz: v.tz, zoom: v.zoom };
    v.tx = W(mx);
    v.tz = W(my);
    v.zoom = zoom;
    c.apply();
    const r = el.getBoundingClientRect();
    const g = new Vector3();
    // phones: the sheet covers the lower ~45%, so aim just above it; desktop: the sheet is a
    // 460px panel on the right, so aim at the middle of what is left
    const wide = r.width >= 900;
    const sx = wide ? (r.width - 460) / 2 : r.width / 2;
    const sy = wide ? r.height * 0.5 : Math.min(r.height * 0.4, r.height * 0.56 - 60);
    const ok = c.groundAt(r.left + sx, r.top + sy, g);
    Object.assign(v, save);
    c.apply();
    const dx = ok ? g.x - W(mx) : 0;
    const dz = ok ? g.z - W(my) : 0;
    flyTo(v, W(mx) - dx, W(my) - dz, zoom);
  }, []);

  const lastSel = useRef<string | undefined>(undefined);
  useEffect(() => {
    if (selectedId && selectedId !== lastSel.current) {
      const l = byId.get(selectedId);
      if (l) focusPlace(l.x, l.y);
    }
    lastSel.current = selectedId;
  }, [selectedId, byId, focusPlace]);

  const findMe = useCallback(() => {
    const me = labels.current.me;
    const cur = currentId ? byId.get(currentId) : undefined;
    const p = me ?? cur;
    if (p) flyTo(view.current, W(p.x), W(p.y), Math.min(view.current.zoom, 30));
    kick();
  }, [currentId, byId, kick]);

  const zoomBy = useCallback(
    (f: number) => {
      const v = view.current;
      flyTo(v, v.tx, v.tz, v.zoom * f);
      kick();
    },
    [kick],
  );

  /* ---------- gestures: drag pans, pinch/wheel zoom about the fingers, tap picks ---------- */
  useEffect(() => {
    const el = wrap.current;
    if (!el) return;
    const onWheel = (e: WheelEvent) => {
      e.preventDefault();
      const c = ctl.current;
      if (!c) return;
      const v = view.current;
      v.anim = null;
      const a = new Vector3();
      const b = new Vector3();
      const okA = c.groundAt(e.clientX, e.clientY, a);
      v.zoom = clamp(v.zoom * Math.exp(e.deltaY * 0.0016), ZOOM_MIN, ZOOM_MAX);
      c.apply();
      if (okA && c.groundAt(e.clientX, e.clientY, b)) {
        v.tx = clamp(v.tx + a.x - b.x, -bnd(v.zoom), bnd(v.zoom));
        v.tz = clamp(v.tz + a.z - b.z, -bnd(v.zoom), bnd(v.zoom));
      }
      v.dirty = true;
    };
    el.addEventListener('wheel', onWheel, { passive: false });
    return () => el.removeEventListener('wheel', onWheel);
  }, []);

  const pointers = useRef(new Map<number, { x: number; y: number }>());
  const gesture = useRef<{ x0: number; y0: number; t0: number; moved: boolean; onCanvas: boolean; last: { t: number; x: number; z: number }[] } | null>(null);

  const onDown = (e: React.PointerEvent) => {
    if (e.button !== 0 && e.pointerType === 'mouse') return;
    pointers.current.set(e.pointerId, { x: e.clientX, y: e.clientY });
    const v = view.current;
    v.anim = null;
    v.vx = v.vz = 0;
    if (pointers.current.size === 1) {
      dragMoved.current = false;
      const target = e.target as HTMLElement;
      gesture.current = { x0: e.clientX, y0: e.clientY, t0: performance.now(), moved: false, onCanvas: target.tagName === 'CANVAS', last: [] };
    }
    v.dragging = true;
  };

  useEffect(() => {
    const g = new Vector3();
    const h = new Vector3();
    const onMove = (e: PointerEvent) => {
      const map = pointers.current;
      const prev = map.get(e.pointerId);
      if (!prev) return;
      const c = ctl.current;
      const v = view.current;
      const gs = gesture.current;
      const cur = { x: e.clientX, y: e.clientY };
      if (gs && !gs.moved && Math.hypot(cur.x - gs.x0, cur.y - gs.y0) > 8) {
        gs.moved = true;
        dragMoved.current = true;
      }
      if (!c || (gs && !gs.moved && map.size === 1)) {
        map.set(e.pointerId, cur);
        return;
      }
      if (map.size >= 2) {
        if (gs) gs.moved = true;
        dragMoved.current = true;
        const pts = [...map.entries()];
        const other = pts.find(([id]) => id !== e.pointerId)![1];
        const d0 = Math.hypot(prev.x - other.x, prev.y - other.y);
        const d1 = Math.hypot(cur.x - other.x, cur.y - other.y);
        const m0x = (prev.x + other.x) / 2;
        const m0y = (prev.y + other.y) / 2;
        const m1x = (cur.x + other.x) / 2;
        const m1y = (cur.y + other.y) / 2;
        const okA = c.groundAt(m0x, m0y, g);
        v.zoom = clamp(v.zoom * (d0 / Math.max(1, d1)), ZOOM_MIN, ZOOM_MAX);
        c.apply();
        if (okA && c.groundAt(m1x, m1y, h)) {
          v.tx = clamp(v.tx + g.x - h.x, -bnd(v.zoom), bnd(v.zoom));
          v.tz = clamp(v.tz + g.z - h.z, -bnd(v.zoom), bnd(v.zoom));
        }
      } else if (c.groundAt(prev.x, prev.y, g) && c.groundAt(cur.x, cur.y, h)) {
        v.tx = clamp(v.tx + g.x - h.x, -bnd(v.zoom), bnd(v.zoom));
        v.tz = clamp(v.tz + g.z - h.z, -bnd(v.zoom), bnd(v.zoom));
        if (gs) {
          gs.last.push({ t: performance.now(), x: v.tx, z: v.tz });
          if (gs.last.length > 6) gs.last.shift();
        }
      }
      c.apply();
      map.set(e.pointerId, cur);
      v.dirty = true;
    };
    const onUp = (e: PointerEvent) => {
      const map = pointers.current;
      if (!map.has(e.pointerId)) return;
      map.delete(e.pointerId);
      const v = view.current;
      const gs = gesture.current;
      if (map.size === 0) {
        v.dragging = false;
        if (gs && !gs.moved && gs.onCanvas && performance.now() - gs.t0 < 500) pickAt(e.clientX, e.clientY);
        else if (gs && gs.moved && gs.last.length >= 2 && !reduceMotion()) {
          const a = gs.last[0];
          const b = gs.last[gs.last.length - 1];
          const dt = b.t - a.t;
          if (dt > 0 && performance.now() - b.t < 80) {
            v.vx = clamp((b.x - a.x) / dt, -0.25, 0.25);
            v.vz = clamp((b.z - a.z) / dt, -0.25, 0.25);
          }
        }
        gesture.current = null;
        v.dirty = true;
        // let the click handler of a pill see dragMoved, then reset
        window.setTimeout(() => (dragMoved.current = false), 0);
      }
    };
    const pickAt = (cx: number, cy: number) => {
      const c = ctl.current;
      const el = wrap.current;
      if (!c || !el) return;
      const r = el.getBoundingClientRect();
      let best: Location | null = null;
      let bd = 34;
      for (const l of locations) {
        const p = c.project(l.x, l.y, 0.15);
        const d = Math.hypot(p.x + r.left - cx, p.y + r.top - cy);
        if (d < bd) {
          bd = d;
          best = l;
        }
      }
      if (best) onSelectRef.current(best.id);
      else {
        // a tap on a landmark model: nearest place within a short distance on the ground
        const gp = new Vector3();
        if (c.groundAt(cx, cy, gp)) {
          const [mx, my] = toMap(gp.x, gp.z);
          let bl: Location | null = null;
          let bm = 22;
          for (const l of locations) {
            const d = Math.hypot(l.x - mx, l.y - my);
            if (d < bm) {
              bm = d;
              bl = l;
            }
          }
          if (bl) onSelectRef.current(bl.id);
        }
      }
    };
    window.addEventListener('pointermove', onMove);
    window.addEventListener('pointerup', onUp);
    window.addEventListener('pointercancel', onUp);
    return () => {
      window.removeEventListener('pointermove', onMove);
      window.removeEventListener('pointerup', onUp);
      window.removeEventListener('pointercancel', onUp);
    };
  }, [locations]);

  const toggle = (f: CityFilter) => setFilters((cur) => (cur.includes(f) ? cur.filter((x) => x !== f) : [...cur, f]));
  const counts = useMemo(() => {
    const o: Record<string, number> = {};
    for (const f of FILTERS) o[f.id] = locations.filter((l) => matchesFilter(f.id, l, crowd)).length;
    return o;
  }, [locations, crowd]);
  const caption = useMemo(() => {
    const last = filters[filters.length - 1];
    if (!last) return null;
    switch (last) {
      case 'goslow':
        return { text: 'Red roads are jammed. Ramat Park is the worst. Rides here take longer.', soon: false };
      case 'neighbours':
        return crowd ? (counts.neighbours ? null : { text: 'No other players out right now.', soon: false }) : { text: 'Live player counts per place · Coming soon', soon: true };
      case 'danger':
        return { text: night ? 'Danger zones glow red at night. Move with care.' : 'These spots turn risky after dark.', soon: false };
      case 'markets':
        return { text: 'Markets: buy, sell and find small jobs.', soon: false };
      case 'gov':
        return { text: 'Police, hospitals and the bank.', soon: false };
    }
  }, [filters, crowd, counts, night]);

  const onPick = useCallback((id: string) => onSelectRef.current(id), []);

  return (
    <div ref={wrap} className={`city3d${props.className ? ' ' + props.className : ''}`} style={props.style} onPointerDown={onDown}>
      <Canvas
        dpr={[1, 1.5]}
        frameloop="demand"
        flat
        gl={{ antialias: true, powerPreference: 'low-power' }}
        camera={{ fov: FOV, position: [0, 60, 60], near: 1, far: 1000 }}
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
        <Driver view={view} paused={Boolean(props.paused)} motion={motion} />
        <City {...props} view={view} ctl={ctl} labels={labels} filters={filters} motion={motion} />
      </Canvas>
      <Labels
        locations={locations}
        currentId={currentId}
        selectedId={selectedId}
        travelTo={travel?.to}
        travelMode={travel?.mode}
        crowd={crowd}
        filters={filters}
        night={night}
        labels={labels}
        onPick={onPick}
        onItems={onItems}
        dragMoved={dragMoved}
      />
      {!props.hideChrome && (
        <div className="c3-top" onPointerDown={(e) => e.stopPropagation()}>
          <div className="c3-chips" role="toolbar" aria-label="Map filters">
            {FILTERS.map((f) => {
              const on = filters.includes(f.id);
              return (
                <button key={f.id} type="button" className={`c3-chip${on ? ' is-on' : ''}`} aria-pressed={on} onClick={() => toggle(f.id)}
                  style={{ '--c3-f': FILTER_COLOR[f.id] } as CSSProperties}>
                  <span aria-hidden>{f.emoji}</span> {f.label}
                  {on && counts[f.id] > 0 && <span className="c3-chip__n">{counts[f.id]}</span>}
                </button>
              );
            })}
          </div>
          {caption && <div className={`c3-caption${caption.soon ? ' is-soon' : ''}`}>{caption.soon && <span aria-hidden>🚧 </span>}{caption.text}</div>}
        </div>
      )}
      <div className="c3-ctrls" onPointerDown={(e) => e.stopPropagation()}>
        <button type="button" className="c3-ctrl" aria-label="Zoom in" title="Zoom in" onClick={() => zoomBy(1 / 1.6)}>+</button>
        <button type="button" className="c3-ctrl" aria-label="Zoom out" title="Zoom out" onClick={() => zoomBy(1.6)}>−</button>
        {(currentId || travel) && (
          <button type="button" className="c3-ctrl" aria-label="Find me" title="Find me" onClick={findMe}>
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" aria-hidden>
              <circle cx="12" cy="12" r="6.5" />
              <circle cx="12" cy="12" r="2" fill="currentColor" />
              <path d="M12 2v3M12 19v3M2 12h3M19 12h3" />
            </svg>
          </button>
        )}
      </div>
    </div>
  );
}
