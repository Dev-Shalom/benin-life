// Shared vehicle library: the part collector. A vehicle model draws parts (geometry + a ROLE) into a Kit; baking turns the kit into ONE
// merged BufferGeometry with vertex colours plus an `aPart` attribute (x = how much the part glows at night, y = 1 for body paint),
// or hands the parts out by role (the place scenes feed them to their own merged layers).
// Vehicles face -z, stand on y = 0, x is the right-hand side. Metres.
import {
  BackSide,
  BufferAttribute,
  BufferGeometry,
  Color,
  Float32BufferAttribute,
  Mesh,
  MeshBasicMaterial,
  MeshLambertMaterial,
  MeshStandardMaterial,
  PMREMGenerator,
  Scene,
  SphereGeometry,
  type ColorRepresentation,
  type Texture,
  type WebGLRenderer,
} from 'three';
import { mergeGeometries } from 'three/examples/jsm/utils/BufferGeometryUtils.js';

export type Role = 'body' | 'glass' | 'trim' | 'tyre' | 'rim' | 'disc' | 'chrome' | 'head' | 'tail' | 'amber' | 'plate' | 'plateband' | 'seat' | 'accent' | 'skin' | 'cloth' | 'metal';

/** Colour, glow (0..1, scaled by the material's night level) and whether the instance / material tint applies. */
export const ROLES: Record<Role, { hex: number; glow: number; body: boolean }> = {
  body: { hex: 0xffffff, glow: 0, body: true },
  glass: { hex: 0x3d5469, glow: 0, body: false },
  trim: { hex: 0x1d1f24, glow: 0, body: false },
  tyre: { hex: 0x18191d, glow: 0, body: false },
  rim: { hex: 0xcdd2d9, glow: 0, body: false },
  disc: { hex: 0x2c3037, glow: 0, body: false },
  chrome: { hex: 0xe2e6ea, glow: 0, body: false },
  head: { hex: 0xfff3d2, glow: 1, body: false },
  tail: { hex: 0xe0281f, glow: 0.9, body: false },
  amber: { hex: 0xffa526, glow: 0.7, body: false },
  plate: { hex: 0xf3f2ea, glow: 0, body: false },
  plateband: { hex: 0x2a8a4a, glow: 0, body: false },
  seat: { hex: 0x2e3238, glow: 0, body: false },
  accent: { hex: 0x2f7d4a, glow: 0, body: false },
  skin: { hex: 0x7a5236, glow: 0, body: false },
  cloth: { hex: 0x4d6a8f, glow: 0, body: false },
  metal: { hex: 0x8b929b, glow: 0, body: false },
};

/** Surface of each role for the paint-quality material: [roughness, metalness]. */
export const SURFACE: Record<Role, [number, number]> = {
  body: [0.3, 0.3],
  glass: [0.07, 0.7],
  trim: [0.65, 0],
  tyre: [0.92, 0],
  rim: [0.22, 0.85],
  disc: [0.7, 0.2],
  chrome: [0.12, 1],
  head: [0.2, 0],
  tail: [0.25, 0],
  amber: [0.3, 0],
  plate: [0.5, 0],
  plateband: [0.5, 0],
  seat: [0.8, 0],
  accent: [0.45, 0.1],
  skin: [0.8, 0],
  cloth: [0.9, 0],
  metal: [0.35, 0.8],
};

/** 0 = near (player's vehicle, garage, showroom), 1 = traffic, 2 = far / Graphics Low traffic, 3 = map marker (about 130 triangles). */
export type Lod = 0 | 1 | 2 | 3;

export interface WheelSpec {
  x: number;
  z: number;
  r: number;
  wid: number;
  /** Front wheels steer. */
  front: boolean;
  /** 'car' = tyre with a sidewall and an alloy rim; 'spoke' = thin tyre, wire spokes (bicycle, motorcycle). */
  style?: 'car' | 'spoke';
}

export interface Part {
  g: BufferGeometry;
  role: Role;
  hex?: number;
}

export class Kit {
  parts: Part[] = [];
  wheels: WheelSpec[] = [];
  readonly lod: Lod;
  /** The player's vehicle draws its wheels separately (they steer and spin): wheel() records a spec instead of a mesh. */
  readonly separateWheels: boolean;
  /** Draw the people on motorcycles, bicycles and kekes (off for showroom bikes). */
  rider = true;
  constructor(lod: Lod, separateWheels: boolean) {
    this.lod = lod;
    this.separateWheels = separateWheels;
  }

  /** Put a geometry (already in the vehicle frame) into the kit. */
  add(g: BufferGeometry | null | undefined, role: Role, hex?: number) {
    if (g) this.parts.push({ g, role, hex });
  }

  /** Place a primitive: position, rotations (radians, applied x then y then z in three's default order), role, optional colour override. */
  put(g: BufferGeometry, role: Role, x: number, y: number, z: number, o: { rx?: number; ry?: number; rz?: number; hex?: number; sx?: number; sy?: number; sz?: number } = {}) {
    if (o.sx !== undefined || o.sy !== undefined || o.sz !== undefined) g.scale(o.sx ?? 1, o.sy ?? 1, o.sz ?? 1);
    if (o.rx) g.rotateX(o.rx);
    if (o.ry) g.rotateY(o.ry);
    if (o.rz) g.rotateZ(o.rz);
    g.translate(x, y, z);
    this.add(g, role, o.hex);
  }
}

const _c = new Color();

/** Merge a kit into one BufferGeometry: position, normal, color (RGB), aPart (glow, bodyMask). */
export function bake(parts: Part[]): BufferGeometry {
  const list: BufferGeometry[] = [];
  for (const p of parts) {
    const src = p.g;
    const g = src.index ? src.toNonIndexed() : src;
    if (g !== src) src.dispose();
    if (!g.getAttribute('normal')) g.computeVertexNormals();
    g.deleteAttribute('uv');
    const info = ROLES[p.role];
    _c.setHex(p.hex ?? info.hex);
    const n = g.getAttribute('position').count;
    const col = new Float32Array(n * 3);
    const part = new Float32Array(n * 4);
    let y0 = Infinity;
    let y1 = -Infinity;
    const pos = g.getAttribute('position');
    if (p.role === 'glass' || p.role === 'body') {
      for (let i = 0; i < n; i++) {
        const y = pos.getY(i);
        if (y < y0) y0 = y;
        if (y > y1) y1 = y;
      }
    }
    for (let i = 0; i < n; i++) {
      let k = 1;
      if (p.role === 'glass') {
        // a darker tint low down, the sky mirrored in the top of the glass
        const t = y1 > y0 ? (pos.getY(i) - y0) / (y1 - y0) : 0.5;
        k = 0.7 + 0.8 * t * t;
      } else if (p.role === 'body') {
        // a baked contact shade along the sills so the car sits on the road
        const y = pos.getY(i);
        k = 0.78 + 0.22 * Math.min(1, Math.max(0, (y - 0.18) / 0.42));
      }
      col[i * 3] = Math.min(1.4, _c.r * k);
      col[i * 3 + 1] = Math.min(1.4, _c.g * k);
      col[i * 3 + 2] = Math.min(1.4, _c.b * k);
      part[i * 4] = info.glow;
      part[i * 4 + 1] = info.body ? 1 : 0;
      part[i * 4 + 2] = SURFACE[p.role][0];
      part[i * 4 + 3] = SURFACE[p.role][1];
    }
    g.setAttribute('color', new BufferAttribute(col, 3));
    g.setAttribute('aPart', new Float32BufferAttribute(part, 4));
    list.push(g);
  }
  const out = mergeGeometries(list, false);
  list.forEach((g) => g.dispose());
  out.computeBoundingSphere();
  out.computeBoundingBox();
  return out;
}

export interface VehicleMaterial extends MeshStandardMaterial {
  /** Night level of the lamps: ~0.5 by day (a faint glow), up to 1.6 in the dark. */
  glow: { value: number };
}

/* ---------------------------------------------------------------- the cheap sky for paint and glass reflections */

let envRenderer: WebGLRenderer | null = null;
const envCache = new WeakMap<WebGLRenderer, Texture>();

/** A tiny procedural sky (a vertex-coloured dome with a bright sun patch), baked once per renderer with PMREMGenerator. No network, no textures. */
function skyEnv(r: WebGLRenderer): Texture {
  let t = envCache.get(r);
  if (t) return t;
  const scene = new Scene();
  const g = new SphereGeometry(10, 24, 12);
  const pos = g.getAttribute('position');
  const col = new Float32Array(pos.count * 3);
  const top = new Color('#8dbbe8');
  const mid = new Color('#e8eef2');
  const low = new Color('#6f6e66');
  const sun = new Color('#fff6dc').multiplyScalar(3);
  const c = new Color();
  for (let i = 0; i < pos.count; i++) {
    const x = pos.getX(i) / 10;
    const y = pos.getY(i) / 10;
    const z = pos.getZ(i) / 10;
    if (y > 0.05) c.copy(mid).lerp(top, Math.min(1, y * 1.3));
    else c.copy(mid).lerp(low, Math.min(1, -y * 4 + 0.3));
    // a sun disc up and to the side, and a soft light box on the other side
    const d = Math.hypot(x + 0.45, y - 0.62, z + 0.35);
    if (d < 0.26) c.lerp(sun, 1 - d / 0.26);
    const d2 = Math.hypot(x - 0.7, y - 0.35, z - 0.2);
    if (d2 < 0.35) c.lerp(new Color('#ffffff').multiplyScalar(1.8), (1 - d2 / 0.35) * 0.7);
    col[i * 3] = c.r;
    col[i * 3 + 1] = c.g;
    col[i * 3 + 2] = c.b;
  }
  g.setAttribute('color', new BufferAttribute(col, 3));
  scene.add(new Mesh(g, new MeshBasicMaterial({ vertexColors: true, side: BackSide, toneMapped: false })));
  const pm = new PMREMGenerator(r);
  t = pm.fromScene(scene, 0.03).texture;
  pm.dispose();
  g.dispose();
  envCache.set(r, t);
  return t;
}

/** The renderer the paint-quality vehicle materials bake their reflections for (a scene calls this once, before making vehicle materials). */
export function setVehicleRenderer(r: WebGLRenderer | null) {
  envRenderer = r;
}

/** Night / day for a vehicle material: lamps glow with the dark, reflections fade (the sky is dark too). */
export function setVehicleLight(m: VehicleMaterial, dark: number) {
  m.glow.value = 0.5 + 1.1 * dark;
  m.envMapIntensity = 0.95 * (1 - dark) + 0.1;
}

/**
 * The one material every vehicle uses. The material colour / instance colour tints ONLY the body paint (aPart.y), lamps add their own
 * light (aPart.x * glow) so tail lights and headlamps shine at night, and per-vertex roughness / metalness (aPart.zw) give paint, glass,
 * chrome and rubber their own look. `cheap` (Graphics Low, far traffic, static cars) = Lambert-style shading without reflections.
 */
export function vehicleMaterial(color: ColorRepresentation = 0xffffff, o: { flatShading?: boolean; cheap?: boolean } = {}): VehicleMaterial {
  const cheap = o.cheap ?? true;
  const m = (cheap
    ? new MeshLambertMaterial({ vertexColors: true, color, flatShading: o.flatShading ?? false })
    : new MeshStandardMaterial({ vertexColors: true, color, roughness: 1, metalness: 0, flatShading: o.flatShading ?? false, envMapIntensity: 0.95 })) as unknown as VehicleMaterial;
  if (!cheap && envRenderer) m.envMap = skyEnv(envRenderer);
  const glow = { value: 0.5 };
  m.glow = glow;
  m.onBeforeCompile = (sh) => {
    sh.uniforms.uGlow = glow;
    sh.uniforms.uTint = { value: m.color };
    sh.vertexShader = sh.vertexShader
      .replace('#include <common>', '#include <common>\nattribute vec4 aPart;\nuniform vec3 uTint;\nvarying float vGlow;\nvarying vec3 vGlowCol;\nvarying vec2 vRM;')
      .replace(
        '#include <color_vertex>',
        `#include <color_vertex>
vec3 tintC = uTint;
#ifdef USE_INSTANCING_COLOR
tintC *= instanceColor.rgb;
#endif
vColor.rgb = color.rgb * mix(vec3(1.0), tintC, aPart.y);
vGlow = aPart.x;
vGlowCol = color.rgb;
vRM = aPart.zw;`,
      );
    let f = sh.fragmentShader
      .replace('#include <common>', '#include <common>\nuniform float uGlow;\nvarying float vGlow;\nvarying vec3 vGlowCol;\nvarying vec2 vRM;')
      .replace('vec4 diffuseColor = vec4( diffuse, opacity );', 'vec4 diffuseColor = vec4( 1.0, 1.0, 1.0, opacity );')
      .replace('#include <emissivemap_fragment>', '#include <emissivemap_fragment>\ntotalEmissiveRadiance += vGlowCol * vGlow * uGlow;');
    if (!cheap) {
      f = f
        .replace('#include <roughnessmap_fragment>', '#include <roughnessmap_fragment>\nroughnessFactor = vRM.x;')
        .replace('#include <metalnessmap_fragment>', '#include <metalnessmap_fragment>\nmetalnessFactor = vRM.y;');
    }
    sh.fragmentShader = f;
  };
  m.customProgramCacheKey = () => (cheap ? 'vehicle-v2c' : 'vehicle-v2');
  return m;
}
