// F1 runtime helpers shared by HomeScene and PlaceScene: the material set (atlas Lambert, cycling glow,
// additive light), ACES tone mapping + fog, the ceiling fan, steam over pots, and the frame-time sample
// for the Auto graphics tier. No per-frame allocations: everything animates through uniforms / transforms.
import {
  ACESFilmicToneMapping,
  AdditiveBlending,
  BufferAttribute,
  BufferGeometry,
  Color,
  Fog,
  Mesh,
  Points,
  PointsMaterial,
  type Scene,
  type WebGLRenderer,
  type Camera,
} from 'three';
import { HomeBuilder } from '../home3d/engine/build';
import { blobTexture, cycleUniforms, feelGlow, feelLight, feelSolid, type CycleUniforms } from './materials';
import type { FeelQuality } from './quality';
import { reportFrameSample } from './quality';
import type { Rig } from './rigs';

export interface FeelMats {
  u: CycleUniforms;
  solid: ReturnType<typeof feelSolid>;
  glow: ReturnType<typeof feelGlow>;
  light: ReturnType<typeof feelLight>;
}

export function makeFeelMats(q: FeelQuality): FeelMats {
  const u = cycleUniforms();
  return { u, solid: feelSolid(q.atlas), glow: feelGlow(u), light: feelLight(u) };
}

const _fog = new Color();
/** ACES + exposure, and fog (or none on Low / the dollhouse). `depth` = camera distance to the room centre. */
export function applyFeelRender(gl: WebGLRenderer, scene: Scene, o: { fog: boolean; color: string; depth: number; radius: number; exposure: number }) {
  gl.toneMapping = ACESFilmicToneMapping;
  gl.toneMappingExposure = o.exposure;
  if (!o.fog) {
    scene.fog = null;
    return;
  }
  _fog.set(o.color);
  const near = o.depth;
  const far = o.depth + o.radius * 1.6 + 10;
  if (scene.fog instanceof Fog) {
    scene.fog.color.copy(_fog);
    scene.fog.near = near;
    scene.fog.far = far;
  } else scene.fog = new Fog(_fog.getHex(), near, far);
}

/** A ceiling fan (hub, rod, 3 blades) as its own small mesh so it can spin; origin at the hub. */
export function makeFan(mat: FeelMats['solid'], col = '#f1ede4'): Mesh {
  const b = new HomeBuilder();
  b.ao = false;
  b.box(0.02, 0.3, 0.02, 0, 0, 0, '#5a5a5a', { mat: 'metal' });
  b.cyl(0.09, 0.1, 0.08, 0, -0.06, 0, col, { mat: 'metal', seg: 10 });
  for (let i = 0; i < 3; i++) b.box(0.62, 0.012, 0.11, 0.36 * Math.cos((i * 2 * Math.PI) / 3), -0.03, -0.36 * Math.sin((i * 2 * Math.PI) / 3), col, { ry: (i * 2 * Math.PI) / 3, mat: 'wood' });
  const g = b.finish().solid!;
  const m = new Mesh(g, mat);
  m.name = 'fan';
  return m;
}

/** Steam over pots: a few soft white points that rise and fade (positions updated in place). */
export function makeSteam(spots: [number, number, number][], perSpot = 5) {
  const n = Math.max(1, spots.length * perSpot);
  const pos = new Float32Array(n * 3);
  const geo = new BufferGeometry();
  geo.setAttribute('position', new BufferAttribute(pos, 3));
  const mat = new PointsMaterial({ size: 26, sizeAttenuation: false, map: blobTexture(), transparent: true, opacity: 0.32, depthWrite: false, blending: AdditiveBlending, color: '#ffffff', fog: false });
  // the blob texture is black: invert into white puffs via the colour + additive (alpha carries the shape)
  mat.onBeforeCompile = (sh) => {
    sh.fragmentShader = sh.fragmentShader.replace('#include <map_particle_fragment>', '#include <map_particle_fragment>\n diffuseColor.rgb = vec3(1.0) * diffuseColor.a;');
  };
  const pts = new Points(geo, mat);
  pts.frustumCulled = false;
  const update = (t: number) => {
    for (let s = 0; s < spots.length; s++)
      for (let k = 0; k < perSpot; k++) {
        const i = (s * perSpot + k) * 3;
        const ph = (t * 0.35 + k / perSpot + s * 0.37) % 1;
        pos[i] = spots[s][0] + Math.sin(t * 1.3 + k * 2.1) * 0.08 * ph;
        pos[i + 1] = spots[s][1] + ph * 0.9;
        pos[i + 2] = spots[s][2] + Math.cos(t * 1.1 + k) * 0.06 * ph;
      }
    geo.attributes.position.needsUpdate = true;
  };
  update(0);
  return { pts, update, dispose: () => { geo.dispose(); mat.dispose(); } };
}

/** Per-frame feel animation: club cycle, fluorescent flicker, light gain. Allocation-free. */
export function tickFeel(m: FeelMats, rig: Rig, t: number, gain: number, motion: boolean) {
  m.u.uTime.value = t;
  m.u.uCycle.value = rig.cycle && motion ? 1 : 0;
  let g = gain;
  if (rig.flicker && motion) {
    // a tube that catches now and then: two quick dips every ~9 s
    const p = t % 9.3;
    if (p < 0.08 || (p > 0.16 && p < 0.22)) g *= 0.55;
  }
  m.u.uGain.value = g;
}

/** Auto tier: a synced 5-frame render sample once the first scene is ready. */
let sampledOnce = false;
export function sampleFrames(gl: WebGLRenderer, scene: Scene, camera: Camera) {
  if (sampledOnce) return;
  sampledOnce = true;
  window.setTimeout(() => {
    try {
      const ctx = gl.getContext();
      gl.render(scene, camera);
      ctx.finish();
      const t0 = performance.now();
      for (let i = 0; i < 5; i++) gl.render(scene, camera);
      const px = new Uint8Array(4);
      ctx.readPixels(0, 0, 1, 1, ctx.RGBA, ctx.UNSIGNED_BYTE, px);
      reportFrameSample((performance.now() - t0) / 5);
    } catch {
      /* lost context etc.: keep the guess */
    }
  }, 1500);
}
