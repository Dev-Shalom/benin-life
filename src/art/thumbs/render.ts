// H2: the ONE offscreen WebGL renderer that turns furniture and car models into small card images.
// Loaded lazily by ./thumbs.ts the first time a card needs a picture. Builds the model with the same
// HomeBuilder code as the 3D home (so the thumbnail is the real piece), renders one frame on a
// transparent background, and returns a data URL. The renderer is disposed (context released) after a
// short idle period, so phones don't keep a second GL context alive.
import {
  AmbientLight,
  BufferGeometry,
  DirectionalLight,
  HemisphereLight,
  Material,
  Mesh,
  MeshBasicMaterial,
  MeshLambertMaterial,
  PerspectiveCamera,
  Scene,
  Sphere,
  Vector3,
  WebGLRenderer,
} from 'three';
import { HomeBuilder, type Layer } from '../home3d/engine/build';
import { buildPiece } from '../home3d/engine/furniture';
import { drawVehicle } from '../home3d/engine/room';
import type { FurnitureItem, FurnitureKind } from '../home3d/model';

export type ThumbSpec =
  | { type: 'furniture'; kind: string; color?: string | null }
  | { type: 'car'; id: string };

const SIZE = 192;
const IDLE_MS = 15000;

let renderer: WebGLRenderer | null = null;
let failed = false;
let idle: ReturnType<typeof setTimeout> | null = null;
let mats: Partial<Record<Layer, Material>> | null = null;

function materials(): Partial<Record<Layer, Material>> {
  if (!mats) {
    mats = {
      solid: new MeshLambertMaterial({ vertexColors: true }),
      glow: new MeshBasicMaterial({ vertexColors: true }),
      glass: new MeshLambertMaterial({ vertexColors: true, transparent: true, opacity: 0.7 }),
      screen: new MeshBasicMaterial({ vertexColors: true }),
    };
  }
  return mats;
}

function getRenderer(): WebGLRenderer | null {
  if (failed) return null;
  if (renderer) return renderer;
  try {
    const canvas = document.createElement('canvas');
    canvas.width = SIZE;
    canvas.height = SIZE;
    renderer = new WebGLRenderer({ canvas, alpha: true, antialias: true, preserveDrawingBuffer: true, powerPreference: 'low-power' });
    renderer.setPixelRatio(1);
    renderer.setSize(SIZE, SIZE, false);
    renderer.setClearColor(0x000000, 0);
    return renderer;
  } catch {
    failed = true;
    return null;
  }
}

function scheduleDispose() {
  if (idle) clearTimeout(idle);
  idle = setTimeout(() => {
    idle = null;
    if (!renderer) return;
    renderer.dispose();
    renderer.forceContextLoss();
    renderer = null;
    for (const m of Object.values(mats ?? {})) m?.dispose();
    mats = null;
  }, IDLE_MS);
}

/** Can this device render thumbnails at all? (false after a failed context) */
export function thumbsFailed(): boolean {
  return failed;
}

function build(spec: ThumbSpec): Record<Layer, BufferGeometry | null> {
  const b = new HomeBuilder();
  b.ao = spec.type === 'furniture';
  if (spec.type === 'furniture') {
    const f: FurnitureItem = { id: 'thumb', kind: spec.kind as FurnitureKind, x: 0, z: 0, color: spec.color ?? undefined };
    buildPiece(b, f, 2.8);
  } else {
    drawVehicle(b, spec.id, 0, 0, 0);
  }
  return b.finish();
}

/** Render one model to a data URL (null when WebGL is unavailable or the model failed). */
export function renderThumb(spec: ThumbSpec): string | null {
  const r = getRenderer();
  if (!r) return null;
  const geos = (() => { try { return build(spec); } catch { return null; } })();
  if (!geos) return null;
  const scene = new Scene();
  const m = materials();
  const meshes: Mesh[] = [];
  const sphere = new Sphere();
  let first = true;
  for (const [layer, g] of Object.entries(geos) as [Layer, BufferGeometry | null][]) {
    if (!g || layer === 'light' || !m[layer]) continue;
    g.computeBoundingSphere();
    if (g.boundingSphere) {
      if (first) { sphere.copy(g.boundingSphere); first = false; } else sphere.union(g.boundingSphere);
    }
    const mesh = new Mesh(g, m[layer]);
    meshes.push(mesh);
    scene.add(mesh);
  }
  if (!meshes.length) return null;
  scene.add(new HemisphereLight('#fff6e8', '#6b5a48', 1.25));
  scene.add(new AmbientLight('#ffffff', 0.55));
  const sun = new DirectionalLight('#ffffff', 1.6);
  sun.position.set(3, 6, 5);
  scene.add(sun);
  // three-quarter view from the front right, a little above; fit the bounding sphere
  const cam = new PerspectiveCamera(30, 1, 0.05, 200);
  const dir = new Vector3(0.85, 0.62, 1.25).normalize();
  const radius = Math.max(0.2, sphere.radius);
  const dist = (radius / Math.sin((cam.fov * Math.PI) / 360)) * 1.02;
  cam.position.copy(sphere.center).addScaledVector(dir, dist);
  cam.lookAt(sphere.center);
  cam.near = Math.max(0.01, dist - radius * 2);
  cam.far = dist + radius * 2;
  cam.updateProjectionMatrix();
  let url: string | null = null;
  try {
    r.render(scene, cam);
    url = r.domElement.toDataURL('image/webp', 0.86);
    if (!url.startsWith('data:image/webp')) url = r.domElement.toDataURL('image/png');
  } catch {
    url = null;
  }
  for (const mesh of meshes) mesh.geometry.dispose();
  scheduleDispose();
  return url;
}
