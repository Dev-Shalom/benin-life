// H3: digital billboards in the 3D city (docs/BILLBOARDS.md, docs/CITY3D.md "Billboards").
// One merged mesh for every pole + frame (1 draw call) and one small screen per board (1 draw call each,
// ~10). Each screen shader holds two textures and cross-fades between them, so a rotation is ONE texture
// swap. Textures are 512×256 canvases (images are downscaled once), loaded lazily: only for boards near the
// camera; far boards keep a shared house ad. Which ad shows comes from the wall clock (everyone in sync).
import {
  BufferAttribute,
  BufferGeometry,
  CanvasTexture,
  Color,
  Group,
  LinearFilter,
  Mesh,
  MeshLambertMaterial,
  PlaneGeometry,
  ShaderMaterial,
  SRGBColorSpace,
  UniformsLib,
  UniformsUtils,
  type Texture,
} from 'three';
import { drawHouseAd, HOUSE_ADS } from '../../../lib/billboards';
import { WS } from '../model';

export interface CityBoardAd {
  id: string;
  url: string;
}
export interface CityBoard {
  id: string;
  name: string;
  x: number;
  y: number;
  yaw: number;
  kind: 'mega' | 'standard' | 'local';
  ads: CityBoardAd[];
}

const TEX_W = 512;
const TEX_H = 256;
const FADE_MS = 900;
/** Screen size in world units (mega boards are bigger) and the height of its bottom edge. */
export function boardDims(kind: CityBoard['kind']) {
  const w = kind === 'mega' ? 5.6 : kind === 'standard' ? 4.4 : 3.6;
  return { w, h: w / 2, bottom: kind === 'mega' ? 3.4 : 2.8 };
}
/** World height of the top of a board (labels sit there). */
export const boardTop = (kind: CityBoard['kind']) => {
  const d = boardDims(kind);
  return d.bottom + d.h + 0.35;
};

const vert = /* glsl */ `
#include <fog_pars_vertex>
varying vec2 vUv;
void main() {
  vUv = uv;
  vec4 mvPosition = modelViewMatrix * vec4(position, 1.0);
  gl_Position = projectionMatrix * mvPosition;
  #include <fog_vertex>
}`;
const frag = /* glsl */ `
uniform sampler2D tA;
uniform sampler2D tB;
uniform float mixv;
uniform float glow;
varying vec2 vUv;
#include <fog_pars_fragment>
void main() {
  vec4 a = texture2D(tA, vUv);
  vec4 b = texture2D(tB, vUv);
  // a short dip to dark between ads reads like a real LED screen changing
  float dip = 1.0 - 0.35 * sin(3.14159 * mixv);
  vec3 c = mix(a.rgb, b.rgb, smoothstep(0.0, 1.0, mixv)) * dip * glow;
  gl_FragColor = vec4(c, 1.0);
  #include <colorspace_fragment>
  #include <fog_fragment>
}`;

interface ScreenState {
  board: CityBoard;
  mesh: Mesh;
  mat: ShaderMaterial;
  /** url (or house:<id>) currently in tA / being faded in */
  shown: string;
  next: string | null;
  fadeT0: number;
  slot: number;
  idx: number;
}

/** Pole + frame geometry for all boards, flat-shaded vertex colours. */
function framesGeometry(boards: CityBoard[]): BufferGeometry {
  const pos: number[] = [];
  const col: number[] = [];
  const c = new Color();
  const box = (cx: number, cy: number, cz: number, w: number, h: number, d: number, yaw: number, ox: number, hex: string) => {
    c.set(hex);
    const hw = w / 2, hd = d / 2;
    const cs = Math.cos(yaw), sn = Math.sin(yaw);
    const P = (x: number, y: number, z: number): [number, number, number] => {
      const lx = x + ox, lz = z;
      return [cx + lx * cs + lz * sn, cy + y, cz - lx * sn + lz * cs];
    };
    const v = [
      P(-hw, 0, -hd), P(hw, 0, -hd), P(hw, h, -hd), P(-hw, h, -hd),
      P(-hw, 0, hd), P(hw, 0, hd), P(hw, h, hd), P(-hw, h, hd),
    ];
    const faces = [[4, 5, 6, 7], [1, 0, 3, 2], [0, 4, 7, 3], [5, 1, 2, 6], [3, 7, 6, 2], [0, 1, 5, 4]];
    faces.forEach((f, fi) => {
      const shade = fi === 4 ? 1.08 : fi === 5 ? 0.6 : fi === 1 ? 0.75 : 0.9;
      for (const i of [f[0], f[1], f[2], f[0], f[2], f[3]]) {
        pos.push(...v[i]);
        col.push(c.r * shade, c.g * shade, c.b * shade);
      }
    });
  };
  for (const b of boards) {
    const { w, h, bottom } = boardDims(b.kind);
    const x = (b.x - 500) * WS;
    const z = (b.y - 500) * WS;
    // concrete footing, two steel legs (mega: one thick mast), frame behind the screen, a little top light bar
    if (b.kind === 'mega') {
      box(x, 0, z, 1.0, 0.25, 1.0, b.yaw, 0, '#9aa1a8');
      box(x, 0, z - 0.05, 0.42, bottom + 0.2, 0.42, b.yaw, 0, '#4b5560');
    } else {
      for (const s of [-1, 1]) {
        box(x, 0, z, 0.5, 0.18, 0.5, b.yaw, s * w * 0.3, '#9aa1a8');
        box(x, 0, z - 0.05, 0.16, bottom + 0.1, 0.16, b.yaw, s * w * 0.3, '#4b5560');
      }
    }
    box(x, bottom - 0.16, z - 0.12, w + 0.32, h + 0.32, 0.22, b.yaw, 0, '#1d232b');
    box(x, bottom + h + 0.16, z - 0.12, w * 0.5, 0.1, 0.18, b.yaw, 0, '#c9d2dc');
  }
  const g = new BufferGeometry();
  g.setAttribute('position', new BufferAttribute(new Float32Array(pos), 3));
  g.setAttribute('color', new BufferAttribute(new Float32Array(col), 3));
  g.computeVertexNormals();
  return g;
}

export class BoardsLayer {
  group = new Group();
  private frames: Mesh | null = null;
  private framesMat = new MeshLambertMaterial({ vertexColors: true, flatShading: true });
  private plane = new PlaneGeometry(1, 1);
  private screens: ScreenState[] = [];
  private tex = new Map<string, { t: Texture; used: number }>();
  private loading = new Set<string>();
  private houseTex: Texture[] = [];
  /** called when a board (on screen, close enough) starts showing a player ad */
  onView: ((adId: string) => void) | null = null;
  onChange: (() => void) | null = null;

  constructor() {
    this.houseTex = HOUSE_ADS.map((ad) => {
      const c = document.createElement('canvas');
      c.width = TEX_W;
      c.height = TEX_H;
      const ctx = c.getContext('2d');
      if (ctx) drawHouseAd(ctx, ad, TEX_W, TEX_H);
      return this.canvasTex(c);
    });
  }

  private canvasTex(c: HTMLCanvasElement): Texture {
    const t = new CanvasTexture(c);
    t.colorSpace = SRGBColorSpace;
    t.minFilter = LinearFilter;
    t.generateMipmaps = false;
    t.anisotropy = 2;
    return t;
  }

  setBoards(boards: CityBoard[]) {
    const sameLayout = boards.length === this.screens.length
      && boards.every((b, i) => this.screens[i].board.id === b.id && this.screens[i].board.x === b.x && this.screens[i].board.y === b.y
        && this.screens[i].board.yaw === b.yaw && this.screens[i].board.kind === b.kind);
    if (sameLayout) {
      boards.forEach((b, i) => { this.screens[i].board = b; this.screens[i].slot = -1; });
      return;
    }
    for (const s of this.screens) {
      this.group.remove(s.mesh);
      s.mat.dispose();
    }
    if (this.frames) {
      this.group.remove(this.frames);
      this.frames.geometry.dispose();
    }
    this.screens = [];
    if (!boards.length) return;
    this.frames = new Mesh(framesGeometry(boards), this.framesMat);
    this.group.add(this.frames);
    boards.forEach((b, i) => {
      const { w, h, bottom } = boardDims(b.kind);
      const house = this.houseTex[i % this.houseTex.length];
      const mat = new ShaderMaterial({
        uniforms: UniformsUtils.merge([UniformsLib.fog, { tA: { value: null }, tB: { value: null }, mixv: { value: 0 }, glow: { value: 1 } }]),
        vertexShader: vert,
        fragmentShader: frag,
        fog: true,
      });
      mat.uniforms.tA.value = house;
      mat.uniforms.tB.value = house;
      const mesh = new Mesh(this.plane, mat);
      mesh.scale.set(w, h, 1);
      mesh.position.set((b.x - 500) * WS, bottom + h / 2, (b.y - 500) * WS);
      mesh.rotation.y = b.yaw;
      mesh.userData.board = b.id;
      this.group.add(mesh);
      this.screens.push({ board: b, mesh, mat, shown: 'house:' + (i % this.houseTex.length), next: null, fadeT0: 0, slot: -1, idx: -1 });
    });
  }

  /** Night: screens a touch brighter than the dark city around them. */
  setGlow(g: number) {
    for (const s of this.screens) s.mat.uniforms.glow.value = g;
  }

  private texFor(key: string, houseIdx: number): Texture | null {
    if (key.startsWith('house:')) return this.houseTex[Number(key.slice(6)) % this.houseTex.length] ?? this.houseTex[houseIdx];
    const hit = this.tex.get(key);
    if (hit) {
      hit.used = performance.now();
      return hit.t;
    }
    if (!this.loading.has(key)) this.load(key);
    return null;
  }

  private load(url: string) {
    this.loading.add(url);
    const img = new Image();
    img.crossOrigin = 'anonymous';
    img.decoding = 'async';
    img.onload = () => {
      this.loading.delete(url);
      const c = document.createElement('canvas');
      c.width = TEX_W;
      c.height = TEX_H;
      const ctx = c.getContext('2d');
      if (!ctx) return;
      ctx.fillStyle = '#0d1117';
      ctx.fillRect(0, 0, TEX_W, TEX_H);
      // contain (whole ad visible, like the sheet's 2:1 frame), centred
      const s = Math.min(TEX_W / img.naturalWidth, TEX_H / img.naturalHeight);
      const w = img.naturalWidth * s;
      const h = img.naturalHeight * s;
      ctx.drawImage(img, (TEX_W - w) / 2, (TEX_H - h) / 2, w, h);
      this.tex.set(url, { t: this.canvasTex(c), used: performance.now() });
      this.prune();
      this.onChange?.();
    };
    img.onerror = () => {
      this.loading.delete(url);
      // broken image: remember a house ad for it so we don't retry every frame
      this.tex.set(url, { t: this.houseTex[3], used: performance.now() });
    };
    img.src = url;
  }

  /** keep at most ~3 textures per board in memory */
  private prune() {
    const max = Math.max(8, this.screens.length * 3);
    if (this.tex.size <= max) return;
    const keep = new Set<string>();
    for (const s of this.screens) {
      keep.add(s.shown);
      if (s.next) keep.add(s.next);
    }
    const old = [...this.tex.entries()].filter(([k]) => !keep.has(k)).sort((a, b) => a[1].used - b[1].used);
    while (this.tex.size > max && old.length) {
      const [k, v] = old.shift()!;
      if (!this.houseTex.includes(v.t)) v.t.dispose();
      this.tex.delete(k);
    }
  }

  /**
   * Per frame (or once a second when idle). `near(board)` says whether the board is close to the camera /
   * on screen (only those load real images). Returns true while a fade is running (keep drawing).
   */
  update(nowServer: number, nowPerf: number, rotateSeconds: number, near: (b: CityBoard) => boolean, motion: boolean): boolean {
    let animating = false;
    const period = Math.max(5, rotateSeconds) * 1000;
    const slot = Math.floor(nowServer / period);
    this.screens.forEach((s, i) => {
      const ads = s.board.ads;
      const isNear = near(s.board);
      const n = ads.length;
      if (s.slot !== slot) {
        // which ad is on air: players' ads in turn; an empty board cycles the house ads
        const idx = n ? slot % n : slot % this.houseTex.length;
        const key = n ? (isNear ? ads[idx].url : 'house:' + (i % this.houseTex.length)) : 'house:' + ((idx + i) % this.houseTex.length);
        if (key !== s.shown && key !== s.next) {
          s.next = key;
          s.fadeT0 = 0;
        }
        s.slot = slot;
        s.idx = idx;
        if (n && isNear) this.onView?.(ads[idx].id);
      } else if (n && isNear && s.shown.startsWith('house:') && !s.next) {
        // came into view: switch to the real ad
        s.next = ads[s.idx % n].url;
        s.fadeT0 = 0;
      }
      if (s.next) {
        const t = this.texFor(s.next, i);
        if (!t) return; // still loading: keep the current picture
        if (!s.fadeT0) {
          s.fadeT0 = nowPerf;
          s.mat.uniforms.tB.value = t;
        }
        const k = motion ? Math.min(1, (nowPerf - s.fadeT0) / FADE_MS) : 1;
        s.mat.uniforms.mixv.value = k;
        if (k >= 1) {
          s.mat.uniforms.tA.value = t;
          s.mat.uniforms.mixv.value = 0;
          s.shown = s.next;
          s.next = null;
        } else animating = true;
      }
    });
    return animating;
  }

  /** Seconds until the next ad change (so an idle canvas can wake up for it). */
  static msToNextSlot(nowServer: number, rotateSeconds: number): number {
    const period = Math.max(5, rotateSeconds) * 1000;
    return period - (nowServer % period);
  }

  boards(): CityBoard[] {
    return this.screens.map((s) => s.board);
  }

  dispose() {
    for (const s of this.screens) s.mat.dispose();
    this.frames?.geometry.dispose();
    this.framesMat.dispose();
    this.plane.dispose();
    for (const [, v] of this.tex) if (!this.houseTex.includes(v.t)) v.t.dispose();
    for (const t of this.houseTex) t.dispose();
    this.tex.clear();
  }
}
