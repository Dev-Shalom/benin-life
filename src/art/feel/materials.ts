// F1 materials shared by the home and the places:
// - feelSolid: Lambert + vertex colours (baked AO already in them) × the shared atlas tile picked per
//   vertex (`feelTile`), sampled with world-metre UVs (`feelUv`) that repeat inside the tile (textureGrad
//   keeps mip selection seam-free).
// - feelLight: additive light pools / beams / LED glow with an optional slow colour cycle + sweep (club).
// - blob: soft round contact shadow (people).
import {
  AdditiveBlending,
  CanvasTexture,
  LinearMipmapLinearFilter,
  MeshBasicMaterial,
  MeshStandardMaterial,
  SRGBColorSpace,
  type Material,
  type Texture,
} from 'three';
import { atlasCanvas, FEEL_GAIN } from './atlas';

let atlasTex: { tex: Texture; size: number } | null = null;

export function atlasTexture(size: number): Texture {
  if (atlasTex && atlasTex.size >= size) return atlasTex.tex;
  const tex = new CanvasTexture(atlasCanvas(size));
  tex.colorSpace = SRGBColorSpace;
  tex.generateMipmaps = true;
  tex.minFilter = LinearMipmapLinearFilter;
  tex.anisotropy = size >= 1024 ? 4 : 1;
  atlasTex?.tex.dispose();
  atlasTex = { tex, size };
  return tex;
}

export interface CycleUniforms {
  uTime: { value: number };
  /** 0 = steady colours, 1 = slow hue cycle + sweep (club). */
  uCycle: { value: number };
  /** Overall strength (closed place / day = dim). */
  uGain: { value: number };
}

/** PBR solid with the shared atlas detail. One material keeps all home/place geometry merged. */
export function feelSolid(size: number): MeshStandardMaterial {
  const m = new MeshStandardMaterial({ vertexColors: true, flatShading: true, roughness: 0.82, metalness: 0.025 });
  const map = atlasTexture(size);
  m.onBeforeCompile = (sh) => {
    sh.uniforms.feelMap = { value: map };
    sh.vertexShader = sh.vertexShader
      .replace('#include <common>', '#include <common>\nattribute vec2 feelUv;\nattribute float feelTile;\nvarying vec2 vFeelUv;\nvarying float vFeelTile;')
      .replace('#include <begin_vertex>', '#include <begin_vertex>\nvFeelUv = feelUv;\nvFeelTile = feelTile;');
    sh.fragmentShader = sh.fragmentShader
      .replace('#include <common>', '#include <common>\nuniform sampler2D feelMap;\nvarying vec2 vFeelUv;\nvarying float vFeelTile;')
      .replace(
        '#include <color_fragment>',
        `#include <color_fragment>
        {
          float ft = floor(vFeelTile + 0.5);
          vec2 cell = vec2(mod(ft, 4.0), 3.0 - floor(ft / 4.0));
          vec2 f = fract(vFeelUv);
          const float INSET = 0.012;
          vec2 auv = (cell + INSET + f * (1.0 - 2.0 * INSET)) * 0.25;
          vec2 gx = dFdx(vFeelUv) * 0.25 * (1.0 - 2.0 * INSET);
          vec2 gy = dFdy(vFeelUv) * 0.25 * (1.0 - 2.0 * INSET);
          diffuseColor.rgb *= textureGrad(feelMap, auv, gx, gy).rgb * ${FEEL_GAIN.toFixed(3)};
        }`,
      );
    sh.fragmentShader = sh.fragmentShader.replace(
      '#include <roughnessmap_fragment>',
      `#include <roughnessmap_fragment>
      {
        float ft = floor(vFeelTile + 0.5);
        vec2 feelCell = vec2(mod(ft, 4.0), 3.0 - floor(ft / 4.0));
        vec2 feelF = fract(vFeelUv);
        vec2 feelAtlasUv = (feelCell + 0.012 + feelF * 0.976) * 0.25;
        vec2 feelDx = dFdx(vFeelUv) * 0.244;
        vec2 feelDy = dFdy(vFeelUv) * 0.244;
        float surfaceRoughness = 0.92;
        if (ft < 1.5) surfaceRoughness = 0.9;
        else if (ft < 2.5) surfaceRoughness = 0.48;
        else if (ft < 3.5) surfaceRoughness = 0.68;
        else if (ft < 4.5) surfaceRoughness = 0.96;
        else if (ft < 5.5) surfaceRoughness = 0.94;
        else if (ft < 6.5) surfaceRoughness = 0.62;
        else if (ft < 7.5) surfaceRoughness = 0.98;
        else if (ft < 8.5) surfaceRoughness = 0.56;
        else if (ft < 10.5) surfaceRoughness = 0.46;
        float surfaceGrain = textureGrad(feelMap, feelAtlasUv, feelDx, feelDy).r;
        roughnessFactor = clamp(surfaceRoughness + (0.86 - surfaceGrain) * 0.24, 0.32, 1.0);
      }`,
    );
  };
  m.customProgramCacheKey = () => 'feelSolid';
  return m;
}

/** Hue rotation + sweep for unlit glow (vertex colours). Shares `u` between materials. */
function patchCycle(m: Material, u: CycleUniforms, key: string) {
  m.onBeforeCompile = (sh) => {
    Object.assign(sh.uniforms, u);
    sh.vertexShader = sh.vertexShader
      .replace('#include <common>', '#include <common>\nattribute vec2 feelUv;\nvarying vec2 vFeelUv;')
      .replace('#include <begin_vertex>', '#include <begin_vertex>\nvFeelUv = feelUv;');
    sh.fragmentShader = sh.fragmentShader
      .replace('#include <common>', '#include <common>\nuniform float uTime;\nuniform float uCycle;\nuniform float uGain;\nvarying vec2 vFeelUv;')
      .replace(
        '#include <color_fragment>',
        `#include <color_fragment>
        if (uCycle > 0.5) {
          // slow hue rotation (YIQ), phase by position so the room never shows one flat colour
          // P1: gentler: a slower hue drift, a softer sweep, a little less saturation
          float a = uTime * 0.14 + vFeelUv.x * 0.25 + vFeelUv.y * 0.15;
          float ca = cos(a), sa = sin(a);
          vec3 c = diffuseColor.rgb;
          float Y = dot(c, vec3(0.299, 0.587, 0.114));
          float I = dot(c, vec3(0.596, -0.274, -0.322));
          float Q = dot(c, vec3(0.211, -0.523, 0.312));
          float I2 = I * ca - Q * sa, Q2 = I * sa + Q * ca;
          diffuseColor.rgb = max(vec3(0.0), vec3(Y + 0.956 * I2 + 0.621 * Q2, Y - 0.272 * I2 - 0.647 * Q2, Y - 1.106 * I2 + 1.703 * Q2));
          // a slow sweep travelling across the floor
          float sweep = 0.86 + 0.14 * sin(uTime * 0.7 + vFeelUv.x * 0.9 - vFeelUv.y * 0.6);
          diffuseColor.rgb = mix(vec3(dot(diffuseColor.rgb, vec3(0.299, 0.587, 0.114))), diffuseColor.rgb, 0.78) * sweep;
        }
        diffuseColor.rgb *= uGain;`,
      );
  };
  m.customProgramCacheKey = () => key;
}

export function cycleUniforms(): CycleUniforms {
  return { uTime: { value: 0 }, uCycle: { value: 0 }, uGain: { value: 1 } };
}

/** Additive light pools / beams (vertex colour = light colour × falloff). */
export function feelLight(u: CycleUniforms): MeshBasicMaterial {
  const m = new MeshBasicMaterial({ vertexColors: true, transparent: true, blending: AdditiveBlending, depthWrite: false, fog: false, toneMapped: false });
  patchCycle(m, u, 'feelLight');
  return m;
}

/** Unlit glow (lamps, LED strips, light-up floor) with the same cycle. */
export function feelGlow(u: CycleUniforms): MeshBasicMaterial {
  const m = new MeshBasicMaterial({ vertexColors: true, toneMapped: false });
  patchCycle(m, u, 'feelGlow');
  return m;
}

let blobTex: Texture | null = null;
/** Soft round shadow texture (64 px, made once). */
export function blobTexture(): Texture {
  if (blobTex) return blobTex;
  const c = document.createElement('canvas');
  c.width = c.height = 64;
  const g = c.getContext('2d')!;
  const gr = g.createRadialGradient(32, 32, 0, 32, 32, 32);
  gr.addColorStop(0, 'rgba(0,0,0,0.55)');
  gr.addColorStop(0.5, 'rgba(0,0,0,0.3)');
  gr.addColorStop(1, 'rgba(0,0,0,0)');
  g.fillStyle = gr;
  g.fillRect(0, 0, 64, 64);
  blobTex = new CanvasTexture(c);
  return blobTex;
}

export function blobMaterial(): MeshBasicMaterial {
  return new MeshBasicMaterial({ map: blobTexture(), transparent: true, depthWrite: false, toneMapped: false, fog: false, color: '#ffffff' });
}
