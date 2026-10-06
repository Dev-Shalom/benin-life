// F1 quality tiers (docs/FEEL_PLAN.md "Quality tiers"). Settings "Graphics: Auto / Low / High" (prefs.graphics).
// Low: no fog, no light pools, half the clutter, DPR capped at 1.25, small atlas, no ambient motion.
// Auto: a first guess from the device (memory, cores, DPR), then a short frame-time sample after the first
// scene renders (window `__gfxSample`), which can only step DOWN to Low for the rest of the session.
import { create } from 'zustand';
import { usePrefs } from '../../lib/prefs';

export type Tier = 'low' | 'high';
export type GraphicsPref = 'auto' | 'low' | 'high';

const useSample = create<{ sampled: Tier | null }>(() => ({ sampled: null }));

function guess(): Tier {
  try {
    const n = navigator as unknown as { deviceMemory?: number; hardwareConcurrency?: number };
    const mem = n.deviceMemory ?? 4;
    const cores = n.hardwareConcurrency ?? 4;
    const dpr = window.devicePixelRatio || 1;
    if (mem <= 2 || cores <= 2) return 'low';
    if (dpr >= 3 && cores <= 4) return 'low';
    return 'high';
  } catch {
    return 'high';
  }
}

export function resolveTier(pref: GraphicsPref, sampled: Tier | null = useSample.getState().sampled): Tier {
  if (pref === 'low' || pref === 'high') return pref;
  const dev = import.meta.env.DEV && typeof window !== 'undefined' ? new URLSearchParams(window.location.search).get('gfx') : null;
  if (dev === 'low' || dev === 'high') return dev;
  return sampled ?? guess();
}

/** The tier to draw with, live from Settings. */
export function useTier(): Tier {
  const pref = usePrefs((s) => s.graphics);
  const sampled = useSample((s) => s.sampled);
  return resolveTier(pref, sampled);
}

/** Called once by a scene after it is ready: `msPerFrame` from a synced render sample. Auto only. */
export function reportFrameSample(msPerFrame: number): boolean {
  if (useSample.getState().sampled || usePrefs.getState().graphics !== 'auto') return false;
  const t: Tier = msPerFrame > 18 ? 'low' : 'high';
  // only ever step down from the first guess (never surprise a weak phone with High)
  useSample.setState({ sampled: t === 'low' ? 'low' : guess() });
  return t === 'low';
}

export interface FeelQuality {
  tier: Tier;
  fog: boolean;
  pools: boolean;
  /** Clutter density 0..1. */
  clutter: number;
  motion: boolean;
  dprMax: number;
  atlas: number;
}

export function feelQuality(tier: Tier): FeelQuality {
  return tier === 'low'
    ? { tier, fog: false, pools: false, clutter: 0.5, motion: false, dprMax: 1.25, atlas: 512 }
    : { tier, fog: true, pools: true, clutter: 1, motion: true, dprMax: 1.5, atlas: 1024 };
}
