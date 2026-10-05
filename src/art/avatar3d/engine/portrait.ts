// One shared offscreen WebGL renderer that turns looks into still images (HUD, lists, chat, cards).
// Renders are queued one at a time; the renderer is released after a short idle period.
import { NoToneMapping, PerspectiveCamera, Scene, SRGBColorSpace, WebGLRenderer } from 'three';
import type { AvatarConfig } from '../../../lib/types';
import { buildCharacter } from './character';
import { poseIdle, poseWalk } from './anim';
import { makeLights, makeShadow } from './scene';

export type ImageView = 'portrait' | 'full';

export interface ImageOpts {
  view: ImageView;
  /** Output size in pixels. Portrait is square; full is width x 2*width unless height is given. */
  width: number;
  height?: number;
  /** Turn the character (radians, 0 = facing the camera). */
  yaw?: number;
  /** Dev/testing: pose at time t of the walk cycle instead of standing. */
  walkT?: number;
}

let renderer: WebGLRenderer | null = null;
let scene: Scene | null = null;
let camera: PerspectiveCamera | null = null;
let idleTimer: ReturnType<typeof setTimeout> | null = null;
let webp: boolean | null = null;
let chain: Promise<unknown> = Promise.resolve();

/** Render timings (ms) of the most recent jobs, for the dev gallery. */
export const portraitStats: { ms: number; tris: number }[] = [];

function ensure() {
  if (idleTimer) clearTimeout(idleTimer);
  idleTimer = setTimeout(release, 12000);
  if (renderer) return;
  renderer = new WebGLRenderer({ antialias: true, alpha: true, preserveDrawingBuffer: true, powerPreference: 'low-power' });
  renderer.setPixelRatio(1);
  renderer.outputColorSpace = SRGBColorSpace;
  renderer.toneMapping = NoToneMapping;
  renderer.setClearColor(0x000000, 0);
  scene = new Scene();
  scene.add(makeLights());
  camera = new PerspectiveCamera(22, 1, 0.05, 20);
}

function release() {
  if (!renderer) return;
  renderer.dispose();
  renderer.forceContextLoss();
  renderer = null;
  scene = null;
  camera = null;
}

function encode(canvas: HTMLCanvasElement): string {
  if (webp === null) webp = canvas.toDataURL('image/webp').startsWith('data:image/webp');
  return webp ? canvas.toDataURL('image/webp', 0.9) : canvas.toDataURL('image/png');
}

function renderNow(cfg: AvatarConfig, o: ImageOpts): string {
  ensure();
  const t0 = performance.now();
  const r = renderer!;
  const s = scene!;
  const cam = camera!;
  const ch = buildCharacter(cfg);
  if (o.walkT !== undefined) poseWalk(ch, o.walkT);
  else {
    poseIdle(ch, 0);
    ch.rig.head.rotation.set(0, 0, 0);
    ch.rig.neck.rotation.set(0, 0, 0);
  }
  ch.root.rotation.y = o.yaw ?? 0;
  s.add(ch.root);
  const w = o.width;
  const h = o.height ?? (o.view === 'portrait' ? w : w * 2);
  r.setSize(w, h, false);
  cam.aspect = w / h;
  let shadow = null;
  if (o.view === 'portrait') {
    cam.fov = 22;
    const top = ch.topY + 0.02;
    const bottom = ch.headY - 0.205 * ch.dims.scale;
    const H = Math.max(top - bottom, 0.36);
    const cy = (top + bottom) / 2;
    const dist = H / 2 / Math.tan((cam.fov * Math.PI) / 360) * 1.02;
    cam.position.set(0, cy + 0.03, dist);
    cam.lookAt(0, cy, 0);
  } else {
    cam.fov = 24;
    shadow = makeShadow(0.38);
    s.add(shadow);
    const top = ch.topY + 0.05;
    const bottom = -0.04;
    const H = top - bottom;
    const W = 0.95;
    const tanH = Math.tan((cam.fov * Math.PI) / 360);
    const dist = Math.max(H / 2 / tanH, W / 2 / (tanH * cam.aspect));
    const cy = (top + bottom) / 2;
    cam.position.set(0, cy + 0.22, dist);
    cam.lookAt(0, cy, 0);
  }
  cam.updateProjectionMatrix();
  r.render(s, cam);
  const url = encode(r.domElement);
  s.remove(ch.root);
  if (shadow) {
    s.remove(shadow);
    shadow.geometry.dispose();
  }
  ch.dispose();
  portraitStats.push({ ms: performance.now() - t0, tris: ch.stats.tris });
  if (portraitStats.length > 50) portraitStats.shift();
  return url;
}

/** Queues a render; resolves with a data URL (webp when supported). */
export function renderAvatarImage(cfg: AvatarConfig, o: ImageOpts): Promise<string> {
  const job = chain.then(
    () =>
      new Promise<string>((resolve, reject) => {
        // yield to the browser between renders so a long list never blocks input
        const run = () => {
          try {
            resolve(renderNow(cfg, o));
          } catch (e) {
            reject(e);
          }
        };
        if (typeof requestIdleCallback === 'function') requestIdleCallback(run, { timeout: 120 });
        else setTimeout(run, 0);
      }),
  );
  chain = job.catch(() => undefined);
  return job;
}
