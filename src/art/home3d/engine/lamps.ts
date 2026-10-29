// L1 lamps: the home's light fixtures as a small runtime system (docs/HUD_HOME.md "Lighting").
//
// Every fixture is drawn with the room (its shade / bulb in the merged 'glow' mesh, its floor pool in the merged
// 'light' mesh, both tagged by piece id in build.ts), so switching one on or off only rewrites a few vertex colours.
// On top of that:
//  - at most `maxReal` shared PointLights go to the nearest / brightest lit fixtures (re-picked ~5x a second, faded in
//    and out so nothing pops); every other lit fixture is glow only (emissive shade, floor pool, halo sprite);
//  - one extra draw call: a Points sprite per fixture for the soft bulb halo;
//  - the electric indicator LEDs (AC, fridge ...: build.ts LED_ID) go out with the power.
// No per-frame allocations: every array is made once in the constructor.
import { AdditiveBlending, BufferAttribute, BufferGeometry, CanvasTexture, Color, Float32BufferAttribute, Group, PointLight, Points, PointsMaterial, type Camera, type OrthographicCamera, type Scene, type WebGLRenderer } from 'three';
import { LED_ID, type LampRuns } from './build';
import { kelvinHex, lampTarget, type LampSwitch } from './light';
import type { BuiltRoom, RoomLight } from './room';

/** PointLight intensity per brightness point, and the light's reach (m) = REACH_BASE + brightness * REACH_PER_B. */
const INTENSITY_PER_B = 1.35;
const REACH_BASE = 3.0;
const REACH_PER_B = 0.75;
const DECAY = 1.35;
/** How a switched-off shade looks (fraction of its lit colour) by kind; the default is a pale lamp shade. */
const OFF_K: Record<string, number> = { candle: 0.08, lantern: 0.3, led_strip: 0.4 };
const OFF_DEFAULT = 0.5;
/** Seconds for a light to come up / go down. */
const FADE_S = 0.28;
/** Seconds between picks of the real lights. */
const PICK_S = 0.2;

function haloTexture(): CanvasTexture {
  const c = document.createElement('canvas');
  c.width = c.height = 64;
  const g = c.getContext('2d')!;
  const gr = g.createRadialGradient(32, 32, 0, 32, 32, 32);
  gr.addColorStop(0, 'rgba(255,255,255,0.95)');
  gr.addColorStop(0.18, 'rgba(255,255,255,0.55)');
  gr.addColorStop(0.5, 'rgba(255,255,255,0.14)');
  gr.addColorStop(1, 'rgba(255,255,255,0)');
  g.fillStyle = gr;
  g.fillRect(0, 0, 64, 64);
  return new CanvasTexture(c);
}

const _c = new Color();

export interface LampEnv {
  /** 0 day .. 1 night (homeLight().dark). */
  dark: number;
  powered: boolean;
  switches: Record<string, LampSwitch>;
}

export class LampSystem {
  readonly group = new Group();
  readonly fixtures: RoomLight[];
  /** Index of a fixture by piece id. */
  readonly index = new Map<string, number>();
  /** 0..1 how lit each fixture is now / wants to be. */
  private level: Float32Array;
  private target: Float32Array;
  private colour: Float32Array; // r,g,b of each fixture's lamp colour
  private ranges: (LampRuns | undefined)[];
  private offK: Float32Array;
  private led: LampRuns | undefined;
  private ledLevel = 1;
  private ledTarget = 1;
  private glow: BufferAttribute | null;
  private light: BufferAttribute | null;
  private baseGlow: Float32Array | null;
  private baseLight: Float32Array | null;
  // real lights
  private lights: PointLight[] = [];
  private slotFx: Int32Array;
  private slotFade: Uint8Array;
  private slotI: Float32Array;
  private pick: Int32Array;
  private picked: Uint8Array;
  private pickT = 0;
  private maxReal: number;
  // halos
  private halo: Points | null = null;
  private haloMat: PointsMaterial | null = null;
  private haloCol: Float32Array | null = null;
  private haloAttr: BufferAttribute | null = null;
  private uPx = { value: 1 };
  private dirty = true;
  /** Overall lit-ness of the room 0..1 (sum of brightness, for the ambient light). */
  litness = 0;
  private envDark = 0;
  /** Real PointLights currently shining (> 0.01): HomeScene shows / hides the whole set from this. */
  active = 0;
  private shown = false;

  constructor(room: BuiltRoom, offset: [number, number], maxReal: number) {
    this.fixtures = room.fixtures;
    this.ox = offset[0];
    this.oz = offset[1];
    const n = this.fixtures.length;
    this.maxReal = Math.max(0, Math.min(maxReal, 8));
    this.level = new Float32Array(n);
    this.target = new Float32Array(n);
    this.colour = new Float32Array(n * 3);
    this.offK = new Float32Array(n);
    this.ranges = this.fixtures.map((f) => room.lamps[f.id]);
    this.led = room.lamps[LED_ID];
    this.fixtures.forEach((f, i) => {
      this.index.set(f.id, i);
      _c.set(kelvinHex(f.k));
      this.colour[i * 3] = _c.r;
      this.colour[i * 3 + 1] = _c.g;
      this.colour[i * 3 + 2] = _c.b;
      this.offK[i] = OFF_K[f.kind] ?? OFF_DEFAULT;
    });
    this.glow = (room.layers.glow?.getAttribute('color') as BufferAttribute | undefined) ?? null;
    this.light = (room.layers.light?.getAttribute('color') as BufferAttribute | undefined) ?? null;
    this.baseGlow = this.glow ? (this.glow.array as Float32Array).slice() : null;
    this.baseLight = this.light ? (this.light.array as Float32Array).slice() : null;

    this.slotFx = new Int32Array(this.maxReal).fill(-1);
    this.slotFade = new Uint8Array(this.maxReal);
    this.slotI = new Float32Array(this.maxReal);
    this.pick = new Int32Array(this.maxReal);
    this.picked = new Uint8Array(n);
    for (let s = 0; s < this.maxReal; s++) {
      const l = new PointLight('#ffd9a0', 0, 6, DECAY);
      l.visible = false;
      this.lights.push(l);
      this.group.add(l);
    }

    // halos: one Points draw call for every fixture
    if (n) {
      const geo = new BufferGeometry();
      const pos = new Float32Array(n * 3);
      const size = new Float32Array(n);
      this.fixtures.forEach((f, i) => {
        pos[i * 3] = f.x - offset[0];
        pos[i * 3 + 1] = f.y;
        pos[i * 3 + 2] = f.z - offset[1];
        size[i] = 0.5 + f.b * 0.17; // metres across (a candle ~0.7, a chandelier ~2)
      });
      this.haloCol = new Float32Array(n * 3);
      this.haloAttr = new Float32BufferAttribute(this.haloCol, 3);
      geo.setAttribute('position', new Float32BufferAttribute(pos, 3));
      geo.setAttribute('color', this.haloAttr);
      geo.setAttribute('aSize', new Float32BufferAttribute(size, 1));
      const mat = new PointsMaterial({
        map: haloTexture(), vertexColors: true, transparent: true, depthWrite: false, blending: AdditiveBlending,
        sizeAttenuation: false, toneMapped: false, fog: false,
      });
      const u = this.uPx;
      mat.onBeforeCompile = (sh) => {
        sh.uniforms.uPx = u;
        sh.vertexShader = sh.vertexShader
          .replace('#include <common>', '#include <common>\nattribute float aSize;\nuniform float uPx;')
          .replace('gl_PointSize = size;', 'gl_PointSize = aSize * uPx;');
      };
      mat.customProgramCacheKey = () => 'lampHalo';
      this.haloMat = mat;
      this.halo = new Points(geo, mat);
      this.halo.frustumCulled = false;
      this.halo.renderOrder = 3;
      this.group.add(this.halo);
    }
  }

  /** Metres -> pixels for the halos: call when the camera zoom or the canvas pixel ratio changes. */
  setScale(cam: Camera, pixelRatio: number) {
    const z = (cam as OrthographicCamera).zoom ?? 40;
    const px = z * pixelRatio;
    if (Math.abs(px - this.uPx.value) > 0.01) this.uPx.value = px;
  }

  /** The state of the world changed (time of day, power, a switch): recompute where every light wants to be. */
  setEnv(env: LampEnv) {
    this.envDark = env.dark;
    for (let i = 0; i < this.fixtures.length; i++) {
      const f = this.fixtures[i];
      this.target[i] = lampTarget(f, env.dark, env.powered, env.switches[f.id]);
    }
    this.ledTarget = env.powered ? 1 : 0;
    this.dirty = true;
  }

  /** Is this fixture on (or coming on) right now? */
  isOn(id: string): boolean {
    const i = this.index.get(id);
    return i !== undefined && this.target[i] > 0.5;
  }

  /** Advance fades and the real-light pick. Returns true while something is still moving (ask for another frame). */
  update(dt: number, simX: number, simZ: number, instant = false): boolean {
    const n = this.fixtures.length;
    let moving = false;
    let changed = false;
    const step = instant ? 1 : Math.min(1, dt / FADE_S);
    for (let i = 0; i < n; i++) {
      const d = this.target[i] - this.level[i];
      if (d === 0) continue;
      this.level[i] = Math.abs(d) < 0.004 ? this.target[i] : this.level[i] + d * step;
      changed = true;
      if (this.level[i] !== this.target[i]) moving = true;
    }
    let ledChanged = false;
    if (this.ledLevel !== this.ledTarget) {
      const d = this.ledTarget - this.ledLevel;
      this.ledLevel = Math.abs(d) < 0.004 ? this.ledTarget : this.ledLevel + d * step;
      ledChanged = true;
      if (this.ledLevel !== this.ledTarget) moving = true;
    }
    if (changed || this.dirty) this.paintFixtures(changed);
    if (ledChanged || this.dirty) this.paintLeds();
    this.dirty = false;

    // lit-ness for the ambient light
    let sum = 0;
    for (let i = 0; i < n; i++) sum += this.level[i] * Math.min(1, this.fixtures[i].b / 6);
    this.litness = Math.min(1, sum / 2.2);

    // the real lights
    if (this.maxReal > 0) {
      this.pickT += dt;
      if (this.pickT >= PICK_S || changed) {
        this.pickT = 0;
        this.assign(simX, simZ);
      }
      let live = 0;
      const k = instant ? 1 : Math.min(1, dt * 7);
      for (let s = 0; s < this.maxReal; s++) {
        const fx = this.slotFx[s];
        const want = fx >= 0 && !this.slotFade[s] ? this.fixtures[fx].b * INTENSITY_PER_B * this.level[fx] : 0;
        const cur = this.slotI[s];
        const next = Math.abs(want - cur) < 0.01 ? want : cur + (want - cur) * k;
        if (next !== cur) moving = true;
        this.slotI[s] = next;
        this.lights[s].intensity = next;
        if (next > 0.01) live++;
        if (this.slotFade[s] && next <= 0.02) {
          this.slotFx[s] = -1;
          this.slotFade[s] = 0;
          this.slotI[s] = 0;
          this.lights[s].intensity = 0;
        }
      }
      this.active = live;
      // the lights only exist for the shader while one shines (no per-pixel cost by day); hysteresis keeps it from flapping
      let any = live > 0;
      if (!any) for (let s = 0; s < this.maxReal; s++) if (this.slotFx[s] >= 0) { any = true; break; }
      this.show(any);
    }
    return moving;
  }

  private show(v: boolean) {
    if (v === this.shown) return;
    this.shown = v;
    for (const l of this.lights) l.visible = v;
  }

  /** Compile the shader variant with the real lights on once, while the room is idle, so dusk does not hitch. */
  prewarm(gl: WebGLRenderer, scene: Scene, camera: Camera) {
    if (!this.maxReal) return;
    const was = this.shown;
    for (const l of this.lights) l.visible = true;
    try { gl.compile(scene, camera); } catch { /* a lost context: nothing to warm */ }
    for (const l of this.lights) l.visible = was;
  }

  /** Give the real lights to the best lit fixtures (nearest the Sim, brightest), keep the ones that already shine. */
  private assign(simX: number, simZ: number) {
    const n = this.fixtures.length;
    const M = this.maxReal;
    this.picked.fill(0);
    let count = 0;
    for (let m = 0; m < M; m++) {
      let best = -1;
      let bestS = 0.02;
      for (let i = 0; i < n; i++) {
        if (this.picked[i]) continue;
        const l = this.level[i];
        if (l < 0.03) continue;
        const f = this.fixtures[i];
        const dx = f.x - simX, dz = f.z - simZ;
        let s = (l * (0.4 + f.b)) / (1 + 0.35 * (dx * dx + dz * dz));
        // keep a light that already has a real light (no flicker between two equals)
        for (let k = 0; k < M; k++) if (this.slotFx[k] === i && !this.slotFade[k]) { s *= 1.35; break; }
        if (s > bestS) { bestS = s; best = i; }
      }
      if (best < 0) break;
      this.picked[best] = 1;
      this.pick[count++] = best;
    }
    // slots whose fixture is no longer wanted fade out
    for (let s = 0; s < M; s++) {
      const fx = this.slotFx[s];
      if (fx >= 0 && !this.picked[fx]) this.slotFade[s] = 1;
      else if (fx >= 0 && this.picked[fx]) this.slotFade[s] = 0;
    }
    // wanted fixtures without a slot take a free one
    for (let c = 0; c < count; c++) {
      const i = this.pick[c];
      let has = false;
      for (let s = 0; s < M; s++) if (this.slotFx[s] === i) { has = true; break; }
      if (has) continue;
      for (let s = 0; s < M; s++) {
        if (this.slotFx[s] >= 0) continue;
        this.slotFx[s] = i;
        this.slotFade[s] = 0;
        this.slotI[s] = 0;
        const f = this.fixtures[i];
        const l = this.lights[s];
        l.position.set(f.x - this.ox, f.y, f.z - this.oz);
        l.color.setRGB(this.colour[i * 3], this.colour[i * 3 + 1], this.colour[i * 3 + 2]);
        l.distance = REACH_BASE + f.b * REACH_PER_B;
        break;
      }
    }
  }

  private ox = 0;
  private oz = 0;

  /** Rewrite the colours of every fixture's shade, floor pool and halo from its level. */
  private paintFixtures(any: boolean) {
    if (!any && !this.dirty) return;
    const n = this.fixtures.length;
    const gainDay = 0.3 + 0.7 * this.envDark; // halos and pools read stronger at night
    for (let i = 0; i < n; i++) {
      const lv = this.level[i];
      const runs = this.ranges[i];
      if (runs && this.glow && this.baseGlow) {
        const k = this.offK[i] + (1 - this.offK[i]) * lv;
        this.scaleRuns(this.glow, this.baseGlow, runs.glow, k);
      }
      if (runs && this.light && this.baseLight) this.scaleRuns(this.light, this.baseLight, runs.light, lv);
      if (this.haloCol) {
        const hk = lv * gainDay * 0.9;
        this.haloCol[i * 3] = this.colour[i * 3] * hk;
        this.haloCol[i * 3 + 1] = this.colour[i * 3 + 1] * hk;
        this.haloCol[i * 3 + 2] = this.colour[i * 3 + 2] * hk;
      }
    }
    if (this.glow) this.glow.needsUpdate = true;
    if (this.light) this.light.needsUpdate = true;
    if (this.haloAttr) this.haloAttr.needsUpdate = true;
  }

  private paintLeds() {
    if (!this.led || !this.glow || !this.baseGlow) return;
    this.scaleRuns(this.glow, this.baseGlow, this.led.glow, 0.06 + 0.94 * this.ledLevel);
    this.glow.needsUpdate = true;
  }

  private scaleRuns(attr: BufferAttribute, base: Float32Array, runs: [number, number][], k: number) {
    const a = attr.array as Float32Array;
    for (const [start, count] of runs) {
      const e = (start + count) * 3;
      for (let j = start * 3; j < e; j++) a[j] = base[j] * k;
    }
  }

  dispose() {
    this.halo?.geometry.dispose();
    this.haloMat?.map?.dispose();
    this.haloMat?.dispose();
    for (const l of this.lights) l.dispose();
  }
}
