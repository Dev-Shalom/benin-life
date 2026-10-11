// H2: 3D thumbnails for shop cards (furniture in Buy, cars at the dealers / Cars app / Bag).
// One shared offscreen renderer (./render.ts, loaded lazily) draws a model only when its card scrolls into
// view; images are cached in memory and in sessionStorage. The emoji stays when WebGL is missing, in Lite
// mode (Settings → lite map) or on a data-saver / 2G connection. No per-card canvases.
import { useEffect, useRef, useState, type ReactNode } from 'react';
import { isSlowNetwork, usePrefs } from '../../lib/prefs';
import type { ThumbSpec } from './render';

export type { ThumbSpec };

const VERSION = 'v1';
const mem = new Map<string, string>();
interface Job { key: string; spec: ThumbSpec; done: (u: string | null) => void; wants: number }
const queue: Job[] = [];
const jobs = new Map<string, Job>();
const waiting = new Map<string, Promise<string | null>>();
let running = false;
let dead = false;
let webglOk: boolean | null = null;

export function thumbKey(spec: ThumbSpec): string {
  return spec.type === 'furniture' ? `f:${spec.kind}:${spec.color ?? ''}` : `c:${spec.id}`;
}

function storageKey(key: string) {
  return `bl.thumb.${VERSION}.${key}`;
}

function cached(key: string): string | null {
  const m = mem.get(key);
  if (m) return m;
  try {
    const s = sessionStorage.getItem(storageKey(key));
    if (s) { mem.set(key, s); return s; }
  } catch { /* storage blocked */ }
  return null;
}

function hasWebGL(): boolean {
  if (webglOk !== null) return webglOk;
  try {
    // no throwaway context here: the shared renderer reports a failed context itself (then `dead`)
    webglOk = typeof window !== 'undefined' && 'WebGLRenderingContext' in window;
  } catch {
    webglOk = false;
  }
  return webglOk;
}

/** Thumbnails on this device right now? */
export function thumbsEnabled(lite: boolean): boolean {
  return !dead && !lite && !isSlowNetwork() && hasWebGL();
}

function pump() {
  if (running || !queue.length) return;
  running = true;
  // a small time budget per tick (not per animation frame: the 3D home may hold frames on slow GPUs),
  // then yield so scrolling and taps stay smooth
  setTimeout(() => {
    import('./render')
      .then((mod) => {
        const t0 = performance.now();
        while (queue.length && performance.now() - t0 < 24) {
          // newest first: the cards on screen now; jobs whose cards scrolled away or unmounted are dropped
          const job = queue.pop()!;
          jobs.delete(job.key);
          if (job.wants <= 0) { job.done(null); continue; }
          const url = mod.renderThumb(job.spec);
          if (mod.thumbsFailed()) dead = true;
          if (url) {
            mem.set(job.key, url);
            try { sessionStorage.setItem(storageKey(job.key), url); } catch { /* full or blocked: memory only */ }
          }
          job.done(url);
          if (dead) break;
        }
      })
      .catch(() => { dead = true; })
      .finally(() => {
        running = false;
        if (dead) { for (const j of queue.splice(0)) j.done(null); jobs.clear(); return; }
        pump();
      });
  }, 16);
}

/** Ask for a thumbnail; the returned cancel() drops the job if no other card still wants it. */
function requestThumb(spec: ThumbSpec): { promise: Promise<string | null>; cancel: () => void } {
  const key = thumbKey(spec);
  const hit = cached(key);
  if (hit) return { promise: Promise.resolve(hit), cancel: () => {} };
  let job = jobs.get(key);
  if (job) {
    job.wants += 1;
    // move it to the end (rendered next)
    const i = queue.indexOf(job);
    if (i >= 0) { queue.splice(i, 1); queue.push(job); }
  } else {
    let done!: (u: string | null) => void;
    const promise = new Promise<string | null>((resolve) => { done = resolve; });
    job = { key, spec, done, wants: 1 };
    waiting.set(key, promise);
    void promise.finally(() => waiting.delete(key));
    jobs.set(key, job);
    queue.push(job);
    pump();
  }
  const j = job;
  let cancelled = false;
  return {
    promise: waiting.get(key) ?? Promise.resolve(cached(key)),
    cancel: () => { if (!cancelled) { cancelled = true; j.wants -= 1; } },
  };
}

/** A card thumbnail: the rendered model once visible, the fallback (emoji) until then or when disabled. */
export function Thumb({ spec, fallback, className }: { spec: ThumbSpec; fallback: ReactNode; className?: string }) {
  const key = thumbKey(spec);
  const lite = usePrefs((s) => s.liteMap);
  const enabled = thumbsEnabled(lite);
  const [url, setUrl] = useState<string | null>(() => (enabled ? cached(key) : null));
  const ref = useRef<HTMLSpanElement>(null);
  const specRef = useRef(spec);
  specRef.current = spec;

  useEffect(() => {
    if (!enabled) { setUrl(null); return; }
    const hit = cached(key);
    if (hit) { setUrl(hit); return; }
    setUrl(null);
    const el = ref.current;
    if (!el) return;
    let alive = true;
    let req: ReturnType<typeof requestThumb> | null = null;
    const start = () => {
      if (req) return;
      req = requestThumb(specRef.current);
      void req.promise.then((u) => { if (alive && u) setUrl(u); });
    };
    const stop = () => { req?.cancel(); req = null; };
    if (typeof IntersectionObserver === 'undefined') { start(); return () => { alive = false; stop(); }; }
    // render while (nearly) visible; a card scrolled away before its turn gives its slot up
    const io = new IntersectionObserver((entries) => {
      const vis = entries[entries.length - 1]?.isIntersecting;
      if (vis) start(); else stop();
    }, { rootMargin: '160px' });
    io.observe(el);
    return () => { alive = false; io.disconnect(); stop(); };
  }, [key, enabled]);

  return (
    <span ref={ref} className={`${className ?? ''}${url ? ' has-thumb' : ''}`} aria-hidden>
      {url ? <img className="thumb-img" src={url} alt="" draggable={false} /> : fallback}
    </span>
  );
}
