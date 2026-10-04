// Render context shared by all avatar part renderers. Parts are plain functions (not
// components) so the defs registry is filled synchronously before <defs> is emitted.
import type { ReactNode } from 'react';
import type { AvatarConfig } from '../../lib/types';
import type { Body } from './geometry';
import type { SkinTone } from './catalog';
import { mix, shade, light, SHADOW_TINT, LIGHT_TINT, REFLECT_TINT } from './color';

export interface Ctx {
  uid: string;
  cfg: AvatarConfig;
  b: Body;
  skin: SkinTone;
  hair: string; // hair colour
  oc: string; // outfit colour
  portrait: boolean;
  id: (name: string) => string;
  url: (name: string) => string;
  /** Register a def once (by name). */
  def: (name: string, make: (id: string) => ReactNode) => string;
  has: (a: string) => boolean;
  defs: Map<string, ReactNode>;
}

export function makeCtx(uid: string, cfg: AvatarConfig, b: Body, skin: SkinTone, portrait: boolean): Ctx {
  const defs = new Map<string, ReactNode>();
  const id = (name: string) => `${uid}-${name}`;
  const url = (name: string) => `url(#${id(name)})`;
  const c: Ctx = {
    uid, cfg, b, skin, portrait,
    hair: cfg.hairColor,
    oc: cfg.outfitColor,
    id, url, defs,
    def(name, make) {
      if (!defs.has(name)) defs.set(name, make(id(name)));
      return url(name);
    },
    has: (a) => cfg.accessories.includes(a),
  };
  baseDefs(c);
  return c;
}

function baseDefs(c: Ctx) {
  const s = c.skin;
  c.def('skinL', (id) => (
    <linearGradient id={id} x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stopColor={mix(s.base, s.shadow, 0.3)} />
      <stop offset="0.2" stopColor={s.highlight} />
      <stop offset="0.48" stopColor={s.base} />
      <stop offset="0.8" stopColor={s.shadow} />
      <stop offset="0.94" stopColor={mix(s.shadow, s.deep, 0.5)} />
      <stop offset="1" stopColor={mix(s.shadow, REFLECT_TINT, 0.18)} />
    </linearGradient>
  ));
  c.def('skinT', (id) => (
    <linearGradient id={id} x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stopColor={s.shadow} />
      <stop offset="0.16" stopColor={mix(s.base, s.highlight, 0.6)} />
      <stop offset="0.45" stopColor={s.base} />
      <stop offset="0.82" stopColor={mix(s.base, s.shadow, 0.75)} />
      <stop offset="1" stopColor={s.deep} />
    </linearGradient>
  ));
  c.def('skinFace', (id) => (
    <radialGradient id={id} cx="0.42" cy="0.4" r="0.68" fx="0.36" fy="0.32">
      <stop offset="0" stopColor={mix(s.highlight, LIGHT_TINT, 0.12)} />
      <stop offset="0.3" stopColor={mix(s.highlight, s.base, 0.45)} />
      <stop offset="0.66" stopColor={s.base} />
      <stop offset="0.9" stopColor={mix(s.base, s.shadow, 0.7)} />
      <stop offset="1" stopColor={s.shadow} />
    </radialGradient>
  ));
  // generic fabric shading overlay (applied on top of a flat / patterned fill)
  c.def('shadeH', (id) => (
    <linearGradient id={id} x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stopColor={SHADOW_TINT} stopOpacity="0.22" />
      <stop offset="0.12" stopColor={LIGHT_TINT} stopOpacity="0.2" />
      <stop offset="0.3" stopColor={LIGHT_TINT} stopOpacity="0.08" />
      <stop offset="0.55" stopColor={LIGHT_TINT} stopOpacity="0" />
      <stop offset="0.78" stopColor={SHADOW_TINT} stopOpacity="0.26" />
      <stop offset="0.94" stopColor={SHADOW_TINT} stopOpacity="0.45" />
      <stop offset="1" stopColor={REFLECT_TINT} stopOpacity="0.12" />
    </linearGradient>
  ));
  c.def('shadeV', (id) => (
    <linearGradient id={id} x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stopColor={LIGHT_TINT} stopOpacity="0.12" />
      <stop offset="0.5" stopColor={LIGHT_TINT} stopOpacity="0" />
      <stop offset="1" stopColor={SHADOW_TINT} stopOpacity="0.25" />
    </linearGradient>
  ));
  c.def('hairG', (id) => (
    <linearGradient id={id} x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stopColor={light(c.hair, 0.2)} />
      <stop offset="0.35" stopColor={c.hair} />
      <stop offset="1" stopColor={shade(c.hair, 0.35)} />
    </linearGradient>
  ));
}

/** Fabric shape: flat (or pattern) fill + shared 3D shading overlay. */
export function fab(c: Ctx, d: string, fill: string, key?: string, overlay: 'shadeH' | 'shadeV' | 'none' = 'shadeH'): ReactNode {
  return (
    <g key={key}>
      <path d={d} fill={fill} />
      {overlay !== 'none' && <path d={d} fill={c.url(overlay)} />}
    </g>
  );
}
