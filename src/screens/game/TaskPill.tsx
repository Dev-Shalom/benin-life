// M2 task pill + queue, in the left column (with the wish chips), so the middle of the screen stays clear.
// Pill: icon, short name, a thin live progress bar, seconds left, a small x. While the Sim walks to a
// task it reads "Walking to the bed…" (the server timer has not started yet). Live progress (bars, shift
// pay) keeps working: the bar is the server's busy window, interpolated ~10×/s.
// P1: the queue is small round circles to the RIGHT of the pill (the next two tasks' icons, "+N" on the
// last one when more wait). Tap a circle: a small popover with the name, Move up and Remove. When the
// running task ends, the first circle grows into the pill and the rest slide left (FLIP, WAAPI, ~260 ms).
import { useEffect, useLayoutEffect, useRef, useState } from 'react';
import { naira } from '../../lib/format';
import { busyFraction, useLiveNow } from '../../lib/live';
import type { GameState } from '../../lib/types';
import { useCatalog } from '../../state/catalog';
import { activityIcon, useTasks, WALK_TO } from '../../state/tasks';
import type { PlayerStatus } from './status';
import { stopRunning } from './TaskRunner';

function shortName(s: string): string {
  return s.length > 22 ? `${s.slice(0, 21).trimEnd()}…` : s;
}

export function TaskPill({ state, status }: { state: GameState; status: PlayerStatus }) {
  const p = state.profile;
  const current = useTasks((s) => s.current);
  const queue = useTasks((s) => s.queue);
  const remove = useTasks((s) => s.remove);
  const moveUp = useTasks((s) => s.moveUp);
  const setCurrent = useTasks((s) => s.setCurrent);
  const activities = useCatalog((s) => s.activities);

  const ticking = status.busyLeft > 0 && status.busyEndMs !== null;
  const now = Math.max(useLiveNow(ticking), status.now);
  // the live clock decides (status.busyLeft only ticks once a second)
  const busy = ticking && status.busyEndMs! > now;
  const shift = Boolean(p.job_shift_ends_at && p.busy_until && p.job_shift_ends_at === p.busy_until);

  let pill: React.ReactNode = null;
  if (busy) {
    const end = status.busyEndMs!;
    const start = status.busyStartMs;
    const frac = busyFraction(p, now) ?? (start && end > start ? Math.min(1, Math.max(0, (now - start) / (end - start))) : 0);
    const left = Math.max(0, Math.ceil((end - now) / 1000));
    const act = activities?.find((a) => a.name === p.busy_label);
    const icon = shift
      ? (state.career?.job?.emoji ?? '💼')
      : current?.phase === 'running' && current.kind !== 'buy'
        ? current.icon
        : act?.icon ?? activityIcon(act?.id ?? null, '⏳');
    const label = p.busy_label ?? 'Busy';
    const pay = shift ? Math.floor((Number(p.job_shift_pay ?? 0) * frac) / 10) * 10 : 0;
    const xp = shift ? Math.floor(Number(p.job_shift_xp ?? 0) * frac) : 0;
    pill = (
      <div className="task-pill" role="status" aria-label={`${label}, ${left} seconds left`}>
        <span className="task-pill__icon" aria-hidden>{icon}</span>
        <span className="task-pill__body">
          <span className="task-pill__row">
            <span className="task-pill__name" title={label}>{shortName(label)}</span>
            <span className="task-pill__time">{left}s</span>
          </span>
          {shift && (
            <span className="task-pill__sub">
              +{naira(pay)}{Number(p.job_shift_xp ?? 0) > 0 && <> · +{xp} XP</>}
            </span>
          )}
          <span className="task-pill__bar"><span style={{ transform: `scaleX(${frac})` }} /></span>
        </span>
        {!shift && (
          <button type="button" className="task-pill__x" onClick={() => void stopRunning()} aria-label={`Stop ${label}`} title="Stop">
            <XIcon />
          </button>
        )}
      </div>
    );
  } else if (current && !(current.phase === 'running' && current.busyUntil && Date.parse(current.busyUntil) <= now)) {
    // 'running' with no busy timer seen yet = the RPC answered, fresh state is on its way
    const walking = current.phase === 'walking';
    const label = walking ? `Walking to ${current.walkTo ?? (current.group ? WALK_TO[current.group] : 'it')}…` : 'Starting…';
    pill = (
      <div className={`task-pill is-${walking ? 'walking' : 'starting'}`} role="status">
        <span className="task-pill__icon" aria-hidden>{current.icon}</span>
        <span className="task-pill__body">
          <span className="task-pill__row">
            <span className="task-pill__name" title={current.name}>{shortName(current.name)}</span>
          </span>
          <span className="task-pill__sub">{walking ? label : 'Starting…'}</span>
          <span className="task-pill__bar is-waiting"><span /></span>
        </span>
        {walking && (
          <button type="button" className="task-pill__x" onClick={() => setCurrent(null)} aria-label={`Cancel ${current.name}`} title="Cancel">
            <XIcon />
          </button>
        )}
      </div>
    );
  }

  const pillKey = pill ? (current?.uid ?? 'busy') : null;
  return <TaskRow pill={pill} pillKey={pillKey} queue={queue} remove={remove} moveUp={moveUp} />;
}

const MAX_DOTS = 2;

/** Layout box relative to the row (offsets ignore running transforms, so a FLIP never measures one in flight). */
interface Box { left: number; top: number; width: number; height: number }
function boxOf(el: HTMLElement): Box {
  let left = el.offsetLeft;
  let top = el.offsetTop;
  // dots sit in the <ol>; bring them into the row's frame
  const par = el.offsetParent as HTMLElement | null;
  if (par && !par.classList.contains('task-row') && par.offsetParent) { left += par.offsetLeft; top += par.offsetTop; }
  return { left, top, width: el.offsetWidth, height: el.offsetHeight };
}
const EASE = 'cubic-bezier(0.23, 1, 0.32, 1)';

/** The pill + up to two queue circles, with the shift animation and the circle popover. */
function TaskRow({ pill, pillKey, queue, remove, moveUp }: {
  pill: React.ReactNode;
  pillKey: string | null;
  queue: { uid: string; name: string; icon: string }[];
  remove: (uid: string) => void;
  moveUp: (uid: string) => void;
}) {
  const [open, setOpen] = useState<string | null>(null);
  const colRef = useRef<HTMLDivElement>(null);
  const pillRef = useRef<HTMLDivElement>(null);
  const dotRefs = useRef(new Map<string, HTMLLIElement>());
  const prev = useRef<{ dots: Map<string, Box>; pill: string | null }>({ dots: new Map(), pill: null });
  const popRef = useRef<HTMLDivElement>(null);
  // the last pill width: a hidden placeholder keeps the circles in place between two tasks
  const pillW = useRef(0);
  const dots = queue.slice(0, MAX_DOTS);
  const extra = queue.length - dots.length;
  const openIdx = open ? queue.findIndex((q) => q.uid === open) : -1;
  const openItem = openIdx >= 0 ? queue[openIdx] : null;

  // FLIP: the first circle grows into the new pill; the other circles slide left into their new place
  useLayoutEffect(() => {
    const reduced = typeof window !== 'undefined' && !!window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;
    const was = prev.current;
    const el = pillRef.current;
    if (el && pillKey && pillKey !== was.pill && typeof el.animate === 'function') {
      const from = was.dots.get(pillKey);
      if (from && !reduced) {
        const to = boxOf(el);
        const dx = from.left - to.left;
        const dy = from.top - to.top;
        el.animate(
          [
            { transformOrigin: '0 0', transform: `translate(${dx}px, ${dy}px) scale(${from.width / to.width}, ${from.height / to.height})`, opacity: 0.6, borderRadius: '50%' },
            { transformOrigin: '0 0', transform: 'none', opacity: 1, borderRadius: '18px' },
          ],
          { duration: 280, easing: EASE },
        );
        const body = el.querySelector('.task-pill__body, .task-pill__x');
        body?.animate([{ opacity: 0 }, { opacity: 0, offset: 0.35 }, { opacity: 1 }], { duration: 280, easing: 'ease-out' });
      }
    }
    if (el) pillW.current = el.offsetWidth;
    const now = new Map<string, Box>();
    for (const [uid, li] of dotRefs.current) {
      const r = boxOf(li);
      now.set(uid, r);
      const before = was.dots.get(uid);
      if (reduced || typeof li.animate !== 'function') continue;
      if (before) {
        const dx = before.left - r.left;
        if (Math.abs(dx) > 1) li.animate([{ transform: `translateX(${dx}px)` }, { transform: 'none' }], { duration: 260, easing: EASE });
      } else {
        li.animate([{ transform: 'scale(0.6)', opacity: 0 }, { transform: 'none', opacity: 1 }], { duration: 200, easing: EASE });
      }
    }
    prev.current = { dots: now, pill: pillKey };
  });

  // keep the popover on screen (phones): shift it left, the scale origin stays on its circle
  useLayoutEffect(() => {
    const el = popRef.current;
    if (!el) return;
    const r = el.getBoundingClientRect();
    const over = r.right - (window.innerWidth - 10);
    if (over > 0) {
      const left = Math.max(0, parseFloat(el.style.left || '0') - over);
      const anchorX = parseFloat(el.dataset.ax || '0');
      el.style.left = `${left}px`;
      el.style.setProperty('--tx', `${Math.max(12, anchorX - left)}px`);
    }
  });

  // the popover closes on an outside tap, Escape, or when its task leaves the queue
  useEffect(() => {
    if (!open) return;
    if (!openItem) { setOpen(null); return; }
    const onDown = (e: PointerEvent) => {
      if (!colRef.current?.contains(e.target as Node)) setOpen(null);
    };
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') setOpen(null); };
    window.addEventListener('pointerdown', onDown, true);
    window.addEventListener('keydown', onKey);
    return () => { window.removeEventListener('pointerdown', onDown, true); window.removeEventListener('keydown', onKey); };
  }, [open, openItem]);

  if (!pill && queue.length === 0) return null;
  const dotIdx = openItem ? Math.min(openIdx, MAX_DOTS - 1) : 0;
  const anchor = openItem ? dotRefs.current.get(dots[dotIdx]?.uid ?? '') : null;
  const anchorX = anchor && colRef.current ? anchor.offsetLeft + anchor.offsetWidth / 2 : 0;
  return (
    <div className="task-col" ref={colRef}>
      <div className="task-row">
        {pill && <div className="task-pill-wrap" key={pillKey ?? 'p'} ref={pillRef}>{pill}</div>}
        {!pill && dots.length > 0 && <div className="task-pill-wrap is-ghost" aria-hidden style={pillW.current ? { flex: `0 0 ${pillW.current}px` } : undefined}><i /></div>}
        {dots.length > 0 && (
          <ol className="task-dots" aria-label={`Up next (${queue.length})`}>
            {dots.map((q, i) => (
              <li key={q.uid} ref={(el) => { if (el) dotRefs.current.set(q.uid, el); else dotRefs.current.delete(q.uid); }}>
                <button type="button" className={`task-dot${open === q.uid || (i === dots.length - 1 && extra > 0 && openIdx >= MAX_DOTS) ? ' is-open' : ''}`}
                  onClick={() => setOpen((o) => (o === q.uid ? null : q.uid))} aria-haspopup="dialog" aria-expanded={open === q.uid}
                  aria-label={`Up next ${i + 1}: ${q.name}${i === dots.length - 1 && extra > 0 ? ` (and ${extra} more)` : ''}`} title={q.name}>
                  <span aria-hidden>{q.icon}</span>
                  {i === dots.length - 1 && extra > 0 && <span className="task-dot__more" aria-hidden>+{extra}</span>}
                </button>
              </li>
            ))}
          </ol>
        )}
      </div>
      {openItem && (
        <div className="task-pop" ref={popRef} data-ax={anchorX} role="dialog" aria-label={`Queued: ${openItem.name}`} style={{ left: Math.max(0, anchorX - 26), ['--tx' as string]: '26px' }}>
          {(dotIdx === MAX_DOTS - 1 && extra > 0 ? queue.slice(MAX_DOTS - 1) : [openItem]).map((q) => {
            const qi = queue.findIndex((x) => x.uid === q.uid);
            return (
              <div key={q.uid} className="task-pop__row">
                <span className="task-pop__icon" aria-hidden>{q.icon}</span>
                <span className="task-pop__name" title={q.name}>{shortName(q.name)}</span>
                {qi > 0 && (
                  <button type="button" className="task-pop__btn" onClick={() => moveUp(q.uid)} aria-label={`Move ${q.name} up`} title="Move up">
                    <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round" aria-hidden><path d="M6 15l6-6 6 6" /></svg>
                  </button>
                )}
                <button type="button" className="task-pop__btn is-remove" onClick={() => remove(q.uid)} aria-label={`Remove ${q.name} from the queue`} title="Remove">
                  <XIcon size={11} />
                </button>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}

function XIcon({ size = 13 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round" aria-hidden>
      <path d="M6 6l12 12M18 6L6 18" />
    </svg>
  );
}
