// P1-MAP — pan / pinch / wheel / double-tap zoom with inertia.
// The transform is written straight to the DOM (no React re-render while gesturing);
// React only hears about the zoom level once a gesture settles (for pin sizing + labels).
import { useCallback, useEffect, useLayoutEffect, useRef, useState, type KeyboardEvent as RKeyboardEvent, type PointerEvent as RPointerEvent } from 'react';
import { MAP_H, MAP_W } from './mapGeo';

interface View {
  s: number;
  tx: number;
  ty: number;
}

interface Options {
  /** map point to centre on first layout */
  focus?: { x: number; y: number } | null;
  onTapPin: (id: string) => void;
}

const TAP_SLOP = 7;
const SETTLE_MS = 140;

export function useMapViewport({ focus, onTapPin }: Options) {
  const surfaceRef = useRef<HTMLDivElement | null>(null);
  const contentRef = useRef<HTMLDivElement | null>(null);
  const view = useRef<View>({ s: 1, tx: 0, ty: 0 });
  const size = useRef({ w: 0, h: 0 });
  const [zoom, setZoom] = useState(1);
  const [ready, setReady] = useState(false);
  const settleTimer = useRef<number | undefined>(undefined);
  const anim = useRef<number | undefined>(undefined);
  const onTapRef = useRef(onTapPin);
  onTapRef.current = onTapPin;
  const focusRef = useRef(focus);
  focusRef.current = focus;

  const limits = useCallback(() => {
    const { w, h } = size.current;
    const contain = Math.min(w / MAP_W, h / MAP_H);
    const cover = Math.max(w / MAP_W, h / MAP_H);
    return { min: contain, cover, max: Math.max(cover * 4.2, 2.6) };
  }, []);

  const clamp = useCallback(
    (v: View): View => {
      const { w, h } = size.current;
      const { min, max } = limits();
      const s = Math.min(max, Math.max(min, v.s));
      const mw = MAP_W * s;
      const mh = MAP_H * s;
      const tx = mw <= w ? (w - mw) / 2 : Math.min(0, Math.max(w - mw, v.tx));
      const ty = mh <= h ? (h - mh) / 2 : Math.min(0, Math.max(h - mh, v.ty));
      return { s, tx, ty };
    },
    [limits],
  );

  const apply = useCallback(() => {
    const el = contentRef.current;
    if (!el) return;
    const { s, tx, ty } = view.current;
    el.style.transform = `translate3d(${tx.toFixed(2)}px, ${ty.toFixed(2)}px, 0) scale(${s.toFixed(5)})`;
  }, []);

  /** Mark the start/continuation of motion; after it settles, drop will-change (crisp re-raster) and commit zoom. */
  const moving = useCallback(() => {
    const el = contentRef.current;
    if (el && el.style.willChange !== 'transform') el.style.willChange = 'transform';
    window.clearTimeout(settleTimer.current);
    settleTimer.current = window.setTimeout(() => {
      if (contentRef.current) contentRef.current.style.willChange = 'auto';
      setZoom(view.current.s);
    }, SETTLE_MS);
  }, []);

  const set = useCallback(
    (v: View) => {
      view.current = clamp(v);
      apply();
      moving();
    },
    [apply, clamp, moving],
  );

  const stopAnim = () => {
    if (anim.current !== undefined) cancelAnimationFrame(anim.current);
    anim.current = undefined;
  };

  const animateTo = useCallback(
    (target: View, ms = 280) => {
      stopAnim();
      const from = { ...view.current };
      const to = clamp(target);
      const t0 = performance.now();
      const step = (now: number) => {
        const k = Math.min(1, (now - t0) / ms);
        const e = 1 - Math.pow(1 - k, 3);
        set({ s: from.s + (to.s - from.s) * e, tx: from.tx + (to.tx - from.tx) * e, ty: from.ty + (to.ty - from.ty) * e });
        if (k < 1) anim.current = requestAnimationFrame(step);
        else anim.current = undefined;
      };
      anim.current = requestAnimationFrame(step);
    },
    [clamp, set],
  );

  const zoomAround = useCallback((px: number, py: number, s: number, v: View = view.current): View => {
    const mx = (px - v.tx) / v.s;
    const my = (py - v.ty) / v.s;
    return { s, tx: px - mx * s, ty: py - my * s };
  }, []);

  const zoomBy = useCallback(
    (factor: number) => {
      const { w, h } = size.current;
      const { min, max } = limits();
      const s = Math.min(max, Math.max(min, view.current.s * factor));
      animateTo(zoomAround(w / 2, h / 2, s));
    },
    [animateTo, limits, zoomAround],
  );

  const centerOn = useCallback(
    (x: number, y: number, s?: number) => {
      const { w, h } = size.current;
      const ns = s ?? Math.max(view.current.s, limits().cover);
      animateTo({ s: ns, tx: w / 2 - x * ns, ty: h / 2 - y * ns });
    },
    [animateTo, limits],
  );

  /* ---------- initial layout + resize ---------- */
  useLayoutEffect(() => {
    const el = surfaceRef.current;
    if (!el) return;
    const measure = () => {
      const r = el.getBoundingClientRect();
      return { w: Math.max(1, r.width), h: Math.max(1, r.height) };
    };
    size.current = measure();
    const { cover } = limits();
    const f = focusRef.current ?? { x: 500, y: 500 };
    view.current = clamp({ s: cover, tx: size.current.w / 2 - f.x * cover, ty: size.current.h / 2 - f.y * cover });
    apply();
    setZoom(view.current.s);
    setReady(true);
    const ro = new ResizeObserver(() => {
      const prev = size.current;
      const next = measure();
      if (Math.abs(prev.w - next.w) < 0.5 && Math.abs(prev.h - next.h) < 0.5) return;
      // keep the map point at the centre of the screen fixed
      const v = view.current;
      const cx = (prev.w / 2 - v.tx) / v.s;
      const cy = (prev.h / 2 - v.ty) / v.s;
      size.current = next;
      const s = Math.max(v.s, limits().min);
      view.current = clamp({ s, tx: next.w / 2 - cx * s, ty: next.h / 2 - cy * s });
      apply();
      setZoom(view.current.s);
    });
    ro.observe(el);
    return () => ro.disconnect();
  }, [apply, clamp, limits]);

  /* ---------- wheel (needs a non-passive listener) ---------- */
  useEffect(() => {
    const el = surfaceRef.current;
    if (!el) return;
    const onWheel = (e: WheelEvent) => {
      e.preventDefault();
      stopAnim();
      const r = el.getBoundingClientRect();
      const unit = e.deltaMode === 1 ? 32 : e.deltaMode === 2 ? 400 : 1;
      const k = e.ctrlKey ? 0.012 : 0.0022;
      const factor = Math.exp(-e.deltaY * unit * k);
      set(zoomAround(e.clientX - r.left, e.clientY - r.top, view.current.s * factor));
    };
    el.addEventListener('wheel', onWheel, { passive: false });
    return () => el.removeEventListener('wheel', onWheel);
  }, [set, zoomAround]);

  useEffect(() => () => {
    stopAnim();
    window.clearTimeout(settleTimer.current);
  }, []);

  /* ---------- pointers: pan, pinch, tap, double-tap, inertia ---------- */
  const ptrs = useRef(new Map<number, { x: number; y: number }>());
  const g = useRef({
    startX: 0,
    startY: 0,
    startT: 0,
    moved: false,
    pinId: null as string | null,
    base: { s: 1, tx: 0, ty: 0 } as View,
    pinchDist: 0,
    pinchMid: { x: 0, y: 0 },
    multi: false,
    vx: 0,
    vy: 0,
    lastX: 0,
    lastY: 0,
    lastT: 0,
  });
  const lastTap = useRef<{ t: number; x: number; y: number } | null>(null);

  const local = (e: { clientX: number; clientY: number }) => {
    const r = surfaceRef.current!.getBoundingClientRect();
    return { x: e.clientX - r.left, y: e.clientY - r.top };
  };

  const startPan = (p: { x: number; y: number }) => {
    const s = g.current;
    s.startX = p.x;
    s.startY = p.y;
    s.lastX = p.x;
    s.lastY = p.y;
    s.lastT = performance.now();
    s.vx = 0;
    s.vy = 0;
    s.base = { ...view.current };
  };

  const startPinch = () => {
    const [a, b] = [...ptrs.current.values()];
    const s = g.current;
    s.pinchDist = Math.max(10, Math.hypot(a.x - b.x, a.y - b.y));
    s.pinchMid = { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 };
    s.base = { ...view.current };
  };

  const onPointerDown = (e: RPointerEvent<HTMLDivElement>) => {
    if (e.pointerType === 'mouse' && e.button !== 0) return;
    stopAnim();
    const p = local(e);
    ptrs.current.set(e.pointerId, p);
    try {
      e.currentTarget.setPointerCapture(e.pointerId);
    } catch {
      /* ignore */
    }
    const s = g.current;
    if (ptrs.current.size === 1) {
      s.moved = false;
      s.multi = false;
      s.startT = performance.now();
      s.pinId = (e.target as Element).closest?.('[data-pin-id]')?.getAttribute('data-pin-id') ?? null;
      startPan(p);
    } else if (ptrs.current.size === 2) {
      s.multi = true;
      s.moved = true;
      startPinch();
    }
  };

  const onPointerMove = (e: RPointerEvent<HTMLDivElement>) => {
    if (!ptrs.current.has(e.pointerId)) return;
    const p = local(e);
    ptrs.current.set(e.pointerId, p);
    const s = g.current;
    if (ptrs.current.size >= 2) {
      const [a, b] = [...ptrs.current.values()];
      const dist = Math.max(10, Math.hypot(a.x - b.x, a.y - b.y));
      const mid = { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 };
      const ns = s.base.s * (dist / s.pinchDist);
      const z = zoomAround(s.pinchMid.x, s.pinchMid.y, ns, s.base);
      set({ s: z.s, tx: z.tx + (mid.x - s.pinchMid.x), ty: z.ty + (mid.y - s.pinchMid.y) });
      return;
    }
    const dx = p.x - s.startX;
    const dy = p.y - s.startY;
    if (!s.moved && Math.hypot(dx, dy) < TAP_SLOP) return;
    s.moved = true;
    const now = performance.now();
    const dt = Math.max(1, now - s.lastT);
    s.vx = s.vx * 0.6 + ((p.x - s.lastX) / dt) * 0.4;
    s.vy = s.vy * 0.6 + ((p.y - s.lastY) / dt) * 0.4;
    s.lastX = p.x;
    s.lastY = p.y;
    s.lastT = now;
    set({ s: s.base.s, tx: s.base.tx + dx, ty: s.base.ty + dy });
  };

  const onPointerEnd = (e: RPointerEvent<HTMLDivElement>) => {
    if (!ptrs.current.has(e.pointerId)) return;
    const p = local(e);
    ptrs.current.delete(e.pointerId);
    const s = g.current;
    if (ptrs.current.size === 1) {
      // pinch → pan with the remaining finger, without a jump
      const [rest] = [...ptrs.current.values()];
      startPan(rest);
      return;
    }
    if (ptrs.current.size > 0) return;
    if (e.type === 'pointercancel') return;
    const quick = performance.now() - s.startT < 600;
    if (!s.moved && !s.multi && quick) {
      if (s.pinId) {
        lastTap.current = null;
        onTapRef.current(s.pinId);
        return;
      }
      const now = performance.now();
      const lt = lastTap.current;
      if (lt && now - lt.t < 320 && Math.hypot(lt.x - p.x, lt.y - p.y) < 30) {
        lastTap.current = null;
        animateTo(zoomAround(p.x, p.y, view.current.s * 2));
      } else lastTap.current = { t: now, x: p.x, y: p.y };
      return;
    }
    // inertia
    if (!s.multi && performance.now() - s.lastT < 80) {
      let vx = s.vx * 16;
      let vy = s.vy * 16;
      if (Math.hypot(vx, vy) > 2) {
        stopAnim();
        const step = () => {
          vx *= 0.9;
          vy *= 0.9;
          const v = view.current;
          set({ s: v.s, tx: v.tx + vx, ty: v.ty + vy });
          if (Math.hypot(vx, vy) > 0.4) anim.current = requestAnimationFrame(step);
          else anim.current = undefined;
        };
        anim.current = requestAnimationFrame(step);
      }
    }
  };

  const onKeyDown = (e: RKeyboardEvent<HTMLDivElement>) => {
    const v = view.current;
    const step = 80;
    if (e.key === '+' || e.key === '=') zoomBy(1.4);
    else if (e.key === '-' || e.key === '_') zoomBy(1 / 1.4);
    else if (e.key === 'ArrowLeft') animateTo({ ...v, tx: v.tx + step }, 160);
    else if (e.key === 'ArrowRight') animateTo({ ...v, tx: v.tx - step }, 160);
    else if (e.key === 'ArrowUp') animateTo({ ...v, ty: v.ty + step }, 160);
    else if (e.key === 'ArrowDown') animateTo({ ...v, ty: v.ty - step }, 160);
    else return;
    e.preventDefault();
  };

  return {
    surfaceRef,
    contentRef,
    zoom,
    ready,
    zoomBy,
    centerOn,
    handlers: {
      onPointerDown,
      onPointerMove,
      onPointerUp: onPointerEnd,
      onPointerCancel: onPointerEnd,
      onKeyDown,
    },
  };
}
