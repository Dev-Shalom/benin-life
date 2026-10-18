// Shared on-screen-keyboard handling (docs/MOBILE_INPUT.md).
//
// iOS Safari and Android Chrome (default `resizes-visual`) keep the layout viewport the same height when the
// keyboard opens; only `window.visualViewport` shrinks. So `100vh`, `100dvh` and `position: fixed; bottom: 0`
// all end up behind the keyboard. This module publishes the visual viewport as CSS variables on <html>:
//
//   --vvh     visible height in px (visual viewport height)
//   --kb      px of the layout viewport the keyboard covers (0 when closed)
//   --vv-top  px the visual viewport is scrolled down inside the layout viewport (iOS pans the page)
//   html.has-kb   set while a text field is focused AND the keyboard covers > 80px
//
// It is started once from main.tsx (`initKeyboardInset`) and never torn down, so unmounting one chat can
// never clear the vars another screen still needs. `useKeyboardInset()` reads the same state in React.
import { useSyncExternalStore } from 'react';

export interface KeyboardInset { kb: number; vvh: number; open: boolean }

const MIN_KB = 80;
let state: KeyboardInset = { kb: 0, vvh: 0, open: false };
const subs = new Set<() => void>();
let started = false;

const isEditable = (el: Element | null) =>
  !!el && (el.tagName === 'TEXTAREA' || el.tagName === 'SELECT' || (el.tagName === 'INPUT' && !/^(checkbox|radio|button|submit|range|file|color)$/.test((el as HTMLInputElement).type)) || (el as HTMLElement).isContentEditable);

// Tallest visible height seen while no field was focused (per width): the "keyboard closed" height. Browsers
// that resize the layout viewport for the keyboard (Android `resizes-content`, some PWAs) shrink innerHeight
// itself, so comparing against this baseline catches both behaviours.
let baseH = 0;
let baseW = 0;

function measure(): KeyboardInset {
  const vv = window.visualViewport;
  const h = vv ? vv.height + vv.offsetTop : window.innerHeight;
  const focused = isEditable(document.activeElement);
  if (window.innerWidth !== baseW || (!focused && (vv?.scale ?? 1) <= 1.02)) { baseW = window.innerWidth; baseH = Math.max(window.innerHeight, Math.round(h)); }
  if (!vv) return { kb: 0, vvh: Math.round(window.innerHeight), open: false };
  const covered = Math.max(0, Math.round(window.innerHeight - vv.height - vv.offsetTop));
  const shrunk = Math.round(baseH - h);
  // pinch-zoom also shrinks the visual viewport: only a focused field counts as "keyboard"
  const open = focused && vv.scale <= 1.02 && Math.max(covered, shrunk) > MIN_KB;
  return { kb: open ? covered : 0, vvh: Math.round(vv.height), open };
}

function apply() {
  const next = measure();
  const root = document.documentElement;
  const vv = window.visualViewport;
  root.style.setProperty('--vvh', `${next.vvh}px`);
  root.style.setProperty('--kb', `${next.kb}px`);
  root.style.setProperty('--vv-top', `${vv ? Math.round(vv.offsetTop) : 0}px`);
  root.classList.toggle('has-kb', next.open);
  if (next.kb === state.kb && next.vvh === state.vvh && next.open === state.open) return;
  const opened = next.open && !state.open;
  state = next;
  subs.forEach((f) => f());
  // iOS pans the whole page to reveal the field; the game never scrolls the document, so put it back.
  if (next.open && (window.scrollY || document.documentElement.scrollTop)) window.scrollTo(0, 0);
  if (opened) {
    window.dispatchEvent(new Event('bl:keyboard-open'));
    // a field inside a scrolling sheet / form: nudge only its own scroller (the document never scrolls)
    window.setTimeout(() => {
      const el = document.activeElement as HTMLElement | null;
      if (el && isEditable(el) && !el.closest('.kb-composer')) el.scrollIntoView({ block: 'nearest', inline: 'nearest' });
    }, 150);
  }
}

export function initKeyboardInset() {
  if (started || typeof window === 'undefined') return;
  started = true;
  let raf = 0;
  const schedule = () => { cancelAnimationFrame(raf); raf = requestAnimationFrame(apply); };
  const vv = window.visualViewport;
  vv?.addEventListener('resize', schedule);
  vv?.addEventListener('scroll', schedule);
  window.addEventListener('resize', schedule);
  // focus moves decide whether a shrink is a keyboard; wait a beat for the keyboard animation to settle
  const later = () => { schedule(); window.setTimeout(schedule, 120); window.setTimeout(schedule, 360); };
  document.addEventListener('focusin', later);
  document.addEventListener('focusout', later);
  apply();
}

/** React view of the keyboard state (also makes sure the CSS variables are being published). */
export function useKeyboardInset(): KeyboardInset {
  initKeyboardInset();
  return useSyncExternalStore(
    (f) => { subs.add(f); return () => { subs.delete(f); }; },
    () => state,
    () => state,
  );
}
