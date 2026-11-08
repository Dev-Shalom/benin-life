// Live players: what the 3D scene and the HUD share (plain mutable objects, no React state per frame).
import type { LiveClient } from './client';

/** A screen-space name tag for one player, written by the scene every frame and read by the HUD overlay. */
export interface LiveTag {
  id: string;
  /** CSS pixels from the top-left of the canvas. */
  x: number;
  y: number;
  /** 0..1 opacity (fades with distance and while arriving / leaving). */
  a: number;
  /** Metres from me. */
  d: number;
  /** 0.7..1 size by distance. */
  s: number;
}

export interface LiveBridge {
  client: LiveClient | null;
  tags: LiveTag[];
  /** Where my own bubble goes (above my head), null when I am not drawn. */
  myTag: LiveTag | null;
  /** Players within reach of a wave (the HUD offers Wave). */
  nearCount: number;
  /** Players drawn right now (debug). */
  drawn: number;
}

export function makeBridge(): LiveBridge {
  return { client: null, tags: [], myTag: null, nearCount: 0, drawn: 0 };
}
