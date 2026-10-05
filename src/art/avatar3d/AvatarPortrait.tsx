// Still image of a look (head-and-shoulders or full body). Rendered once by the shared offscreen renderer
// (engine/portrait.ts: ONE WebGL context, jobs run one at a time), then cached by look hash in a small
// in-memory LRU and in sessionStorage, so the HUD, chat and lists never open a WebGL context of their own.
// Tiles only ask for a render once they are near the viewport, so a long list renders what you see first.
// This file must not import three.js: the renderer is loaded on first use.
import { useEffect, useMemo, useRef, useState, type CSSProperties } from 'react';
import type { AvatarConfig } from '../../lib/types';
import { avatarKey, migrateAvatar, skinTone } from './catalog';

export type PortraitView = 'portrait' | 'full';

/** In-memory LRU of data URLs (Map keeps insertion order; a hit moves the key to the end). */
const MEM = new Map<string, string>();
const MEM_MAX = 240;
const PENDING = new Map<string, Promise<string>>();
const PREFIX = 'bl.av2.';
const INDEX = 'bl.av2.index';
const MAX_STORED = 80;

function cacheKey(cfg: AvatarConfig, view: PortraitView, px: number, yaw: number) {
  return `${avatarKey(cfg)}.${view}.${px}${yaw ? '.' + yaw.toFixed(2) : ''}`;
}

function remember(key: string, url: string) {
  MEM.delete(key);
  MEM.set(key, url);
  while (MEM.size > MEM_MAX) MEM.delete(MEM.keys().next().value!);
}

let swept = false;
/** Drops images cached by older builds (bl.av1.*) once per session. */
function sweepOld() {
  if (swept) return;
  swept = true;
  try {
    for (let i = sessionStorage.length - 1; i >= 0; i--) {
      const k = sessionStorage.key(i);
      if (k && k.startsWith('bl.av') && !k.startsWith(PREFIX)) sessionStorage.removeItem(k);
    }
  } catch {
    /* storage blocked */
  }
}

function peek(key: string): string | undefined {
  const m = MEM.get(key);
  if (m) {
    remember(key, m);
    return m;
  }
  sweepOld();
  try {
    const s = sessionStorage.getItem(PREFIX + key);
    if (s) {
      remember(key, s);
      return s;
    }
  } catch {
    /* storage blocked */
  }
  return undefined;
}

function store(key: string, url: string) {
  remember(key, url);
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

/** Renders (or returns the cached) image for a look. Usable outside React. Retries once (e.g. after a lost context). */
export function getAvatarImage(cfg: AvatarConfig, view: PortraitView = 'portrait', size = 48, yaw = 0): Promise<string> {
  const px = bucket(view, size);
  const key = cacheKey(cfg, view, px, yaw);
  const hit = peek(key);
  if (hit) return Promise.resolve(hit);
  let p = PENDING.get(key);
  if (!p) {
    const opts = { view, width: px, height: view === 'full' ? px * 2 : px, yaw };
    p = import('./engine/portrait')
      .then((m) => m.renderAvatarImage(cfg, opts).catch(() => m.renderAvatarImage(cfg, opts)))
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

/** True once the element is within ~1.5 screens of the viewport (always true without IntersectionObserver). */
function useNearViewport(ref: React.RefObject<HTMLElement | null>, enabled: boolean) {
  const [near, setNear] = useState(typeof IntersectionObserver === 'undefined');
  useEffect(() => {
    const el = ref.current;
    if (!enabled || near || !el) return;
    const io = new IntersectionObserver((e) => {
      if (e.some((x) => x.isIntersecting)) {
        setNear(true);
        io.disconnect();
      }
    }, { rootMargin: '400px 200px' });
    io.observe(el);
    return () => io.disconnect();
  }, [ref, enabled, near]);
  return near;
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

export function AvatarPortrait({ config: raw, size = 48, view = 'portrait', yaw = 0, className, style, alt = '' }: AvatarPortraitProps) {
  // Accept whatever a caller has (v1 rows, `{}`, junk): always draw a valid v2 look.
  const config = useMemo(() => migrateAvatar(raw), [raw]);
  const px = bucket(view, size);
  const key = cacheKey(config, view, px, yaw);
  const [state, setState] = useState<{ key: string; url?: string; failed?: boolean; tries?: number }>(() => ({ key, url: peek(key) }));
  const current = state.key === key ? state : { key, url: peek(key) };
  const ph = useRef<HTMLSpanElement>(null);
  const near = useNearViewport(ph, !current.url);

  useEffect(() => {
    if (current.url || !near) return;
    let live = true;
    const tries = current.tries ?? 0;
    let timer: ReturnType<typeof setTimeout> | undefined;
    const run = () =>
      getAvatarImage(config, view, size, yaw).then(
        (url) => live && setState({ key, url }),
        // WebGL can be briefly unavailable (context lost, tab restored): try again a little later, twice.
        () => live && setState({ key, failed: true, tries: tries + 1 }),
      );
    if (tries === 0) void run();
    else if (tries < 3) timer = setTimeout(run, 4000 * tries);
    return () => {
      live = false;
      if (timer) clearTimeout(timer);
    };
    // config identity is covered by key
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key, near, current.tries]);

  const w = size;
  const h = view === 'full' ? size * 2 : size;
  const cls = `avatar-img avatar-img--${view}${className ? ' ' + className : ''}`;
  if (current.url) {
    return <img src={current.url} width={w} height={h} alt={alt} className={cls} style={style} draggable={false} decoding="async" />;
  }
  // light placeholder in the Sim's skin tone while the image renders
  const tone = skinTone(config.skin).base;
  return (
    <span ref={ph} className={`${cls} avatar-ph${current.failed ? ' is-failed' : ''}`} style={{ width: w, height: h, ...style, ['--ph-skin' as string]: tone }} role={alt ? 'img' : undefined} aria-label={alt || undefined} />
  );
}
