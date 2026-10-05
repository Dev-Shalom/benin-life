// Still image of a look (head-and-shoulders or full body). Rendered once by the shared offscreen renderer,
// then cached in memory and sessionStorage by look hash, so lists of players never open extra WebGL contexts.
// This file must not import three.js: the renderer is loaded on first use.
import { useEffect, useState, type CSSProperties } from 'react';
import type { AvatarConfig } from '../../lib/types';
import { avatarKey, skinTone } from './catalog';

export type PortraitView = 'portrait' | 'full';

const MEM = new Map<string, string>();
const PENDING = new Map<string, Promise<string>>();
const PREFIX = 'bl.av1.';
const INDEX = 'bl.av1.index';
const MAX_STORED = 80;

function cacheKey(cfg: AvatarConfig, view: PortraitView, px: number, yaw: number) {
  return `${avatarKey(cfg)}.${view}.${px}${yaw ? '.' + yaw.toFixed(2) : ''}`;
}

function peek(key: string): string | undefined {
  const m = MEM.get(key);
  if (m) return m;
  try {
    const s = sessionStorage.getItem(PREFIX + key);
    if (s) {
      MEM.set(key, s);
      return s;
    }
  } catch {
    /* storage blocked */
  }
  return undefined;
}

function store(key: string, url: string) {
  MEM.set(key, url);
  try {
    const idx: string[] = JSON.parse(sessionStorage.getItem(INDEX) || '[]');
    const next = [...idx.filter((k) => k !== key), key];
    while (next.length > MAX_STORED) {
      const old = next.shift()!;
      sessionStorage.removeItem(PREFIX + old);
    }
    sessionStorage.setItem(PREFIX + key, url);
    sessionStorage.setItem(INDEX, JSON.stringify(next));
  } catch {
    /* quota or blocked: memory cache still works */
  }
}

/** Pixel size bucket so nearby sizes share one cached image. */
function bucket(view: PortraitView, size: number): number {
  const dpr = typeof window !== 'undefined' ? Math.min(2, window.devicePixelRatio || 1) : 1;
  const want = size * dpr;
  if (view === 'portrait') return want <= 96 ? 96 : want <= 160 ? 160 : 256;
  return want <= 200 ? 200 : want <= 320 ? 320 : 480;
}

/** Renders (or returns the cached) image for a look. Usable outside React. */
export function getAvatarImage(cfg: AvatarConfig, view: PortraitView = 'portrait', size = 48, yaw = 0): Promise<string> {
  const px = bucket(view, size);
  const key = cacheKey(cfg, view, px, yaw);
  const hit = peek(key);
  if (hit) return Promise.resolve(hit);
  let p = PENDING.get(key);
  if (!p) {
    p = import('./engine/portrait')
      .then((m) => m.renderAvatarImage(cfg, { view, width: px, height: view === 'full' ? px * 2 : px, yaw }))
      .then((url) => {
        store(key, url);
        PENDING.delete(key);
        return url;
      })
      .catch((e) => {
        PENDING.delete(key);
        throw e;
      });
    PENDING.set(key, p);
  }
  return p;
}

export interface AvatarPortraitProps {
  config: AvatarConfig;
  /** Display size in CSS px (portrait: width = height; full: width, height is twice). */
  size?: number;
  view?: PortraitView;
  yaw?: number;
  className?: string;
  style?: CSSProperties;
  alt?: string;
}

export function AvatarPortrait({ config, size = 48, view = 'portrait', yaw = 0, className, style, alt = '' }: AvatarPortraitProps) {
  const px = bucket(view, size);
  const key = cacheKey(config, view, px, yaw);
  const [state, setState] = useState<{ key: string; url?: string; failed?: boolean }>(() => ({ key, url: peek(key) }));
  const current = state.key === key ? state : { key, url: peek(key) };

  useEffect(() => {
    if (current.url) return;
    let live = true;
    getAvatarImage(config, view, size, yaw).then(
      (url) => live && setState({ key, url }),
      () => live && setState({ key, failed: true }),
    );
    return () => {
      live = false;
    };
    // config identity is covered by key
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key]);

  const w = size;
  const h = view === 'full' ? size * 2 : size;
  const cls = `avatar-img avatar-img--${view}${className ? ' ' + className : ''}`;
  if (current.url) {
    return <img src={current.url} width={w} height={h} alt={alt} className={cls} style={style} draggable={false} decoding="async" />;
  }
  // light placeholder in the Sim's skin tone while the image renders
  const tone = skinTone(config.skin).base;
  return (
    <span className={`${cls} avatar-ph${current.failed ? ' is-failed' : ''}`} style={{ width: w, height: h, ...style, ['--ph-skin' as string]: tone }} role={alt ? 'img' : undefined} aria-label={alt || undefined} />
  );
}
