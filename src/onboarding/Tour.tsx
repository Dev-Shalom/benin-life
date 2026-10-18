// Guided tour overlay (spotlight coach marks). Data: tourSteps.ts. Notes: docs/ONBOARDING.md.
//
// One fixed "spot" element sits over the target. Its huge box-shadow dims the rest of the screen, so the target is cut
// out bright with a soft glow ring. It moves with transform + size transitions only (no blur over the WebGL canvas).
// A transparent blocker underneath swallows taps so the game cannot be used while the tour is up.
// The card is placed on the side of the target with room (never over the target) and slides between steps.
import { useCallback, useEffect, useLayoutEffect, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import { useTour } from './tourStore';
import type { TourPlacement, TourStep } from './tourSteps';
import './tour.css';

interface Box { x: number; y: number; w: number; h: number }
interface Viewport { w: number; h: number; x: number; y: number }

const MARGIN = 12;
const GAP = 16;
const PAD = 7; // spotlight padding around the target
const MIN_CARD_H = 150; // a squeezed card never gets shorter than this

const reducedMotion = () => typeof window !== 'undefined' && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
const sleep = (ms: number) => new Promise<void>((r) => window.setTimeout(r, ms));

function visibleRect(el: Element): DOMRect | null {
  const r = el.getBoundingClientRect();
  if (r.width < 2 || r.height < 2) return null;
  const cs = window.getComputedStyle(el);
  if (cs.visibility === 'hidden' || cs.display === 'none') return null;
  return r;
}

/** First visible element for a selector list ("a, b, c" tries a, then b, then c). */
export function resolveTarget(selector: string): HTMLElement | null {
  for (const part of selector.split(',').map((s) => s.trim()).filter(Boolean)) {
    for (const el of Array.from(document.querySelectorAll<HTMLElement>(part))) {
      if (visibleRect(el)) return el;
    }
  }
  return null;
}

function viewport(): Viewport {
  const v = window.visualViewport;
  return v
    ? { w: v.width, h: v.height, x: v.offsetLeft, y: v.offsetTop }
    : { w: window.innerWidth, h: window.innerHeight, x: 0, y: 0 };
}

/** Where the card goes. Returns its top-left in viewport coordinates and whether it had to overlap the target. */
export function placeCard(spot: Box | null, card: { w: number; h: number }, vp: Viewport, pref: TourPlacement = 'auto'): { x: number; y: number; overlap: boolean; maxH?: number } {
  const minX = vp.x + MARGIN;
  const maxX = vp.x + vp.w - card.w - MARGIN;
  const minY = vp.y + MARGIN + safeTop();
  const maxY = vp.y + vp.h - card.h - MARGIN - safeBottom();
  const clampX = (x: number) => Math.min(Math.max(x, minX), Math.max(minX, maxX));
  const clampY = (y: number) => Math.min(Math.max(y, minY), Math.max(minY, maxY));
  if (!spot || pref === 'center') {
    return { x: clampX(vp.x + (vp.w - card.w) / 2), y: clampY(vp.y + (vp.h - card.h) / 2), overlap: false };
  }
  const cx = spot.x + spot.w / 2;
  const cy = spot.y + spot.h / 2;
  const tries: Record<'top' | 'bottom' | 'left' | 'right', { x: number; y: number; ok: boolean }> = {
    bottom: { x: clampX(cx - card.w / 2), y: spot.y + spot.h + GAP, ok: false },
    top: { x: clampX(cx - card.w / 2), y: spot.y - GAP - card.h, ok: false },
    right: { x: spot.x + spot.w + GAP, y: clampY(cy - card.h / 2), ok: false },
    left: { x: spot.x - GAP - card.w, y: clampY(cy - card.h / 2), ok: false },
  };
  tries.bottom.ok = tries.bottom.y <= maxY;
  tries.top.ok = tries.top.y >= minY;
  tries.right.ok = tries.right.x <= maxX;
  tries.left.ok = tries.left.x >= minX;
  const order: Array<'top' | 'bottom' | 'left' | 'right'> =
    pref === 'auto' ? ['bottom', 'top', 'right', 'left'] : [pref, ...(['bottom', 'top', 'right', 'left'] as const).filter((s) => s !== pref)];
  for (const side of order) if (tries[side].ok) return { x: tries[side].x, y: tries[side].y, overlap: false };
  // No clean side: squeeze the card (it scrolls inside) into the vertical side with more room, so it still never covers
  // the target. Only when even that is too small does it overlap (the spotlight stays on top of it).
  const aboveRoom = spot.y - GAP - minY;
  const belowRoom = vp.y + vp.h - MARGIN - (spot.y + spot.h + GAP);
  const room = Math.max(aboveRoom, belowRoom);
  if (room >= MIN_CARD_H) {
    const h = Math.min(card.h, room);
    const y = belowRoom >= aboveRoom ? spot.y + spot.h + GAP : spot.y - GAP - h;
    return { x: clampX(cx - card.w / 2), y, overlap: false, maxH: h };
  }
  return { x: clampX(cx - card.w / 2), y: aboveRoom > belowRoom ? minY : maxY, overlap: true };
}

function safeTop() { return 0; }
function safeBottom() { return 0; }

const dotsLabel = (i: number, n: number) => `Step ${i + 1} of ${n}`;

export default function Tour() {
  const active = useTour((s) => s.active);
  const steps = useTour((s) => s.steps);
  const index = useTour((s) => s.index);
  const kind = useTour((s) => s.kind);
  const next = useTour((s) => s.next);
  const back = useTour((s) => s.back);
  const stop = useTour((s) => s.stop);
  const step = steps[index];

  // The card and spotlight keep showing the previous step until the next one is ready (its before() ran and its
  // target was found, or not), so there is never a half-switched flash.
  const [target, setTarget] = useState<HTMLElement | null>(null);
  const [view, setView] = useState<{ step: TourStep; index: number } | null>(null);
  const resolved = view !== null;
  const [spot, setSpot] = useState<Box | null>(null);
  const [vp, setVp] = useState<Viewport>(viewport);
  const [cardSize, setCardSize] = useState({ w: 320, h: 200 });
  const [shown, setShown] = useState(false);
  const cardRef = useRef<HTMLDivElement>(null);
  const nextRef = useRef<HTMLButtonElement>(null);
  const reduced = reducedMotion();

  // ---- find (and prepare) the target of the current step ----
  useEffect(() => {
    if (!active || !step) return;
    let cancelled = false;
    (async () => {
      try { await step.before?.(); } catch { /* a failed before() just means no spotlight */ }
      if (cancelled) return;
      let el: HTMLElement | null = null;
      if (step.target) {
        const t0 = performance.now();
        await sleep(50);
        while (!cancelled && performance.now() - t0 < 1800) {
          el = resolveTarget(step.target);
          if (el) break;
          await sleep(80);
        }
      }
      if (cancelled) return;
      if (el) {
        // bring it into view if a scroller hides part of it
        const r = el.getBoundingClientRect();
        const v = viewport();
        if (r.top < v.y || r.bottom > v.y + v.h) {
          el.scrollIntoView({ block: 'center', inline: 'nearest' });
          await sleep(60);
        } else {
          let p: HTMLElement | null = el.parentElement;
          while (p && p !== document.body) {
            const cs = getComputedStyle(p);
            if (/(auto|scroll)/.test(cs.overflowY) && p.scrollHeight > p.clientHeight) {
              const pr = p.getBoundingClientRect();
              if (r.top < pr.top || r.bottom > pr.bottom) { el.scrollIntoView({ block: 'nearest' }); await sleep(60); }
              break;
            }
            p = p.parentElement;
          }
        }
      }
      if (cancelled) return;
      setTarget(el);
      setView({ step, index });
    })();
    return () => { cancelled = true; };
  }, [active, step, index]);

  // ---- keep the spotlight on the target (layout moves, animations, resize, keyboard) ----
  const measure = useCallback(() => {
    const v = viewport();
    setVp((cur) => (cur.w === v.w && cur.h === v.h && cur.x === v.x && cur.y === v.y ? cur : v));
    let el = target;
    const sel = view?.step.target;
    if (el && !el.isConnected && sel) el = resolveTarget(sel);
    const r = el ? visibleRect(el) : null;
    if (!r) { setSpot((cur) => (cur ? null : cur)); return; }
    const b = { x: Math.round(r.left - PAD), y: Math.round(r.top - PAD), w: Math.round(r.width + PAD * 2), h: Math.round(r.height + PAD * 2) };
    setSpot((cur) => (cur && cur.x === b.x && cur.y === b.y && cur.w === b.w && cur.h === b.h ? cur : b));
  }, [target, view]);

  useLayoutEffect(() => {
    if (!active || !resolved) return;
    measure();
    const id = window.setInterval(measure, 120);
    window.addEventListener('resize', measure);
    window.addEventListener('scroll', measure, true);
    window.visualViewport?.addEventListener('resize', measure);
    window.visualViewport?.addEventListener('scroll', measure);
    const ro = target && 'ResizeObserver' in window ? new ResizeObserver(measure) : null;
    if (ro && target) ro.observe(target);
    return () => {
      window.clearInterval(id);
      window.removeEventListener('resize', measure);
      window.removeEventListener('scroll', measure, true);
      window.visualViewport?.removeEventListener('resize', measure);
      window.visualViewport?.removeEventListener('scroll', measure);
      ro?.disconnect();
    };
  }, [active, resolved, measure, target]);

  // ---- card size (its text changes per step) ----
  useLayoutEffect(() => {
    const el = cardRef.current;
    if (!el) return;
    // scrollHeight = the card's natural height even when it is squeezed and scrolling
    const read = () => setCardSize((c) => (c.w === el.offsetWidth && c.h === el.scrollHeight + 2 ? c : { w: el.offsetWidth, h: el.scrollHeight + 2 }));
    read();
    const ro = new ResizeObserver(read);
    ro.observe(el);
    return () => ro.disconnect();
  }, [active, view]);

  // ---- fade the layer in/out with the tour ----
  useEffect(() => {
    if (!active) { setShown(false); setTarget(null); setSpot(null); setView(null); return; }
    const id = window.requestAnimationFrame(() => setShown(true));
    return () => window.cancelAnimationFrame(id);
  }, [active]);

  // ---- keyboard: arrows move, Escape skips (and does not close the sheet or phone underneath) ----
  useEffect(() => {
    if (!active) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') { e.preventDefault(); e.stopImmediatePropagation(); stop(); }
      else if (e.key === 'ArrowRight') { e.preventDefault(); e.stopImmediatePropagation(); next(); }
      else if (e.key === 'ArrowLeft') { e.preventDefault(); e.stopImmediatePropagation(); back(); }
    };
    window.addEventListener('keydown', onKey, true);
    return () => window.removeEventListener('keydown', onKey, true);
  }, [active, next, back, stop]);

  // focus the primary button on each step (keyboard and screen reader users stay in the card)
  useEffect(() => {
    if (active && resolved) nextRef.current?.focus({ preventScroll: true });
  }, [active, resolved, index]);

  if (!active || !step) return null;

  const cur = view?.step ?? step;
  const curIndex = view?.index ?? index;
  const pref = cur.placement ?? 'auto';
  const useSpot = resolved && spot && pref !== 'center' ? spot : null;
  const pos = placeCard(useSpot, cardSize, vp, pref);
  // collapsed hole: shrinks to the middle of the screen so the dim stays smooth
  const hole = useSpot ?? { x: vp.x + vp.w / 2, y: vp.y + vp.h / 2, w: 0, h: 0 };
  const last = curIndex === steps.length - 1;
  const first = curIndex === 0;
  const nextLabel = last ? (kind === 'full' ? 'Done' : 'Got it') : first && kind === 'full' ? 'Let’s go' : 'Next';

  return createPortal(
    <div className={`tour${shown ? ' is-on' : ''}${reduced ? ' is-reduced' : ''}`} data-tour-root data-step={cur.id} data-overlap={pos.overlap ? '1' : '0'}>
      <div className="tour__blocker" aria-hidden />
      <div
        className={`tour__spot${useSpot ? ' has-target' : ''}`}
        aria-hidden
        data-tour-spot
        style={{ width: hole.w, height: hole.h, transform: `translate3d(${hole.x}px, ${hole.y}px, 0)` }}
      />
      <div
        ref={cardRef}
        className="tour__card"
        role="dialog"
        aria-modal="true"
        aria-labelledby="tour-title"
        aria-describedby="tour-body"
        data-tour-card
        style={{ transform: `translate3d(${Math.round(pos.x)}px, ${Math.round(pos.y)}px, 0)`, visibility: resolved ? 'visible' : 'hidden', maxHeight: pos.maxH ? Math.floor(pos.maxH) : undefined }}
      >
        <div className="tour__inner" key={cur.id}>
          <div className="tour__eyebrow">{kind === 'new' ? 'What’s new' : kind === 'show' ? 'Show me' : 'Quick tour'}</div>
          <h2 id="tour-title" className="tour__title">{cur.title}</h2>
          <p id="tour-body" className="tour__body">{cur.body}</p>
          {cur.points && cur.points.length > 0 && (
            <ul className="tour__points">
              {cur.points.map((p) => <li key={p}>{p}</li>)}
            </ul>
          )}
        </div>
        <div className="tour__foot">
          <div className="tour__dots" role="img" aria-label={dotsLabel(curIndex, steps.length)}>
            {steps.map((s, i) => <span key={s.id} className={`tour__dot${i === curIndex ? ' is-on' : i < curIndex ? ' is-done' : ''}`} />)}
            <span className="tour__count" aria-hidden>{curIndex + 1}/{steps.length}</span>
          </div>
          <div className="tour__btns">
            {!last && <button type="button" className="tour__skip" onClick={stop}>Skip tour</button>}
            <span className="grow" />
            {!first && <button type="button" className="tour__btn tour__btn--ghost" onClick={back}>Back</button>}
            <button ref={nextRef} type="button" className="tour__btn tour__btn--go" onClick={next}>{nextLabel}</button>
          </div>
        </div>
      </div>
    </div>,
    document.body,
  );
}
