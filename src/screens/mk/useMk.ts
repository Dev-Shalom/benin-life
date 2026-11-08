// Behaviour shared by the marketing screens: the graphite page colours, the frosted nav and the reveal-on-enter.
// All with IntersectionObserver (no scroll listeners). The static pages do the same in public/mk/mk.js.
import { useEffect, useLayoutEffect, type RefObject } from 'react';
import { applyTheme } from '../../lib/theme';
import { hasStoredTheme, usePrefs } from '../../lib/prefs';

let mounted = 0;

/** Marks <html> as a marketing page while a marketing screen is on screen, and hands the theme back to the game after. */
export function useMarketingPage() {
  useLayoutEffect(() => {
    const root = document.documentElement;
    mounted++;
    root.classList.add('mk-page', 'mk-js');
    // Nothing saved yet: follow the phone on these pages (the game itself defaults to light).
    applyTheme(hasStoredTheme() ? usePrefs.getState().theme : 'system', false);
    return () => {
      mounted--;
      // Landing -> Auth swaps screens in one commit: only leave marketing mode if nothing took over.
      queueMicrotask(() => {
        if (mounted > 0) return;
        root.classList.remove('mk-page');
        applyTheme(usePrefs.getState().theme, false);
      });
    };
  }, []);
}

const reduced = () => {
  try {
    return window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  } catch {
    return false;
  }
};

function countUp(el: HTMLElement) {
  const to = Number(el.dataset.count);
  const suf = el.dataset.suffix || '';
  if (reduced()) {
    el.textContent = to.toLocaleString('en-NG') + suf;
    return;
  }
  const t0 = performance.now();
  const tick = (t: number) => {
    const k = Math.min(1, (t - t0) / 1400);
    el.textContent = Math.round(to * (1 - Math.pow(1 - k, 4))).toLocaleString('en-NG') + suf;
    if (k < 1) requestAnimationFrame(tick);
  };
  requestAnimationFrame(tick);
}

/** Blur-in rise for .mk-rise and the clip-path image reveal for .mk-reveal-media, once, when they enter the viewport. */
export function useReveal(root: RefObject<HTMLElement | null>) {
  useEffect(() => {
    const host = root.current;
    if (!host) return;
    const els = Array.from(host.querySelectorAll<HTMLElement>('.mk-rise, .mk-reveal-media'));
    if (typeof IntersectionObserver === 'undefined') {
      els.forEach((e) => e.classList.add('in'));
      return;
    }
    const io = new IntersectionObserver(
      (entries) => {
        for (const en of entries) {
          if (!en.isIntersecting) continue;
          const t = en.target as HTMLElement;
          t.classList.add('in');
          io.unobserve(t);
          const c = t.querySelector<HTMLElement>('[data-count]');
          if (c) countUp(c);
        }
      },
      { rootMargin: '0px 0px -8% 0px', threshold: 0.12 },
    );
    els.forEach((e) => io.observe(e));
    // The first screen is visible at load: reveal it on the next frame so the transition plays.
    const raf = requestAnimationFrame(() => {
      host.querySelectorAll('[data-hero] .mk-rise, [data-hero] .mk-reveal-media, [data-hero].mk-rise').forEach((e) => e.classList.add('in'));
    });
    return () => {
      io.disconnect();
      cancelAnimationFrame(raf);
    };
  }, [root]);
}

/** Frosted nav once the page has moved past the top: a 1px sentinel at the top of the page leaves the viewport. */
export function useStuckNav(host: RefObject<HTMLElement | null>, sentinel: RefObject<HTMLElement | null>) {
  useEffect(() => {
    const s = sentinel.current;
    const nav = host.current?.querySelector('.mk-nav');
    if (!s || !nav || typeof IntersectionObserver === 'undefined') return;
    const io = new IntersectionObserver((e) => nav.classList.toggle('is-stuck', !e[0].isIntersecting));
    io.observe(s);
    return () => io.disconnect();
  }, [host, sentinel]);
}
