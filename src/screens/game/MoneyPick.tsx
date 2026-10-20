// SP2 Pick the money (docs/SPRAY.md). Reads src/state/moneyPick.ts.
//  * The notes layer sits ABOVE the spray takeover (z 86 > 80). The layer itself lets taps through
//    (pointer-events: none); only the notes catch them, on pointerdown, so "Tap to skip" never swallows a pick and a
//    note tap never skips the takeover.
//  * Notes fall for the drop's life (5 s), topped up to a handful on screen while the floor still has notes, then
//    vanish. A tap pops the note (scale + fade, a "+₦10K" floats up) with a coin ting. VIP drops fall in gold.
//  * The sprayer's own drop (club.pick_self off) falls too, but can't be tapped.
//  * The "+₦70,000" counter (confirmed + in-flight taps) and the "@name is picking money!" notices, top centre.
// Motion is transforms + opacity only; GFX low = fewer notes, no shadows.
import { memo, useEffect, useRef, useState, type CSSProperties } from 'react';
import { useTier } from '../../art/feel/quality';
import { naira } from '../../lib/format';
import { playCoin } from '../../lib/sound';
import { noticeHeadline, noticeMs, pickedTotal, tapNote, usePick, type LiveDrop } from '../../state/moneyPick';
import '../../styles/moneyPick.css';

interface Note {
  k: number;
  x: number;
  dur: number;
  delay: number;
  rot: number;
  sway: number;
  scale: number;
  /** 0 = falling, 1 = picked (+₦ shows), 2 = gone (no pick) */
  state: 0 | 1 | 2;
}

/** ₦10K / ₦1.5M for a note's face. */
function faceOf(n: number): string {
  const v = Math.max(0, Math.round(n));
  if (v >= 1e6) return `₦${+(v / 1e6).toFixed(1)}M`;
  if (v >= 1e3) return `₦${+(v / 1e3).toFixed(1)}K`;
  return `₦${v}`;
}

const rnd = (a: number, b: number) => a + Math.random() * (b - a);
let noteKey = 0;

function makeNote(first: boolean): Note {
  return {
    k: ++noteKey, x: rnd(3, 80), dur: rnd(2.5, 3.6), delay: first ? -rnd(0.2, 1.4) : 0,
    rot: rnd(-35, 35), sway: rnd(14, 34) * (Math.random() < 0.5 ? -1 : 1), scale: rnd(0.9, 1.12), state: 0,
  };
}

const DropRain = memo(function DropRain({ drop, low }: { drop: LiveDrop; low: boolean }) {
  const ref = useRef(drop);
  ref.current = drop;
  const [notes, setNotes] = useState<Note[]>([]);
  const max = drop.mine ? (low ? 5 : 8) : low ? 9 : 15;

  useEffect(() => {
    const top = (first: boolean) => {
      const d = ref.current;
      if (d.ended || d.dead || d.endsAt - Date.now() < 700) return;
      setNotes((cur) => {
        const live = cur.filter((n) => n.state === 0).length;
        const want = Math.min(max, d.notes) - live;
        if (want <= 0) return cur;
        const add = Array.from({ length: first ? want : Math.min(2, want) }, () => makeNote(first));
        return [...cur, ...add];
      });
    };
    top(true);
    const t = window.setInterval(() => top(false), 140);
    return () => window.clearInterval(t);
  }, [drop.id, max]);

  const done = drop.ended || drop.dead;
  // ended: the notes vanish (CSS), then leave the DOM so nothing invisible can be tapped
  useEffect(() => {
    if (!done) return;
    const t = window.setTimeout(() => setNotes((cur) => cur.filter((n) => n.state === 1)), 280);
    return () => window.clearTimeout(t);
  }, [done]);
  const remove = (k: number) => setNotes((cur) => cur.filter((n) => n.k !== k));
  const face = faceOf(drop.note);

  return (
    <div className={`mp-rain${drop.vip ? ' is-gold' : ''}${drop.mine ? ' is-mine' : ''}${done ? ' is-done' : ''}${low ? ' is-low' : ''}`}>
      {notes.map((n) => (
        <span key={n.k} className={`mp-fall${n.state === 1 ? ' is-picked' : n.state === 2 ? ' is-gone' : ''}`}
          style={{ '--x': `${n.x}%`, '--dur': `${n.dur}s`, '--delay': `${n.delay}s`, '--rot': `${n.rot}deg`,
                   '--sway': `${n.sway}px`, '--s': n.scale } as CSSProperties}
          onAnimationEnd={(e) => { if (e.animationName === 'mp-fall' && n.state === 0) remove(n.k); }}>
          <span className="mp-sway">
            <span className="mp-note" role="presentation"
              onPointerDown={(e) => {
                e.preventDefault();
                e.stopPropagation();
                if (n.state !== 0 || done) return;
                const ok = tapNote(drop.id);
                if (ok) {
                  playCoin();
                  try { navigator.vibrate?.(8); } catch { /* not on this device */ }
                }
                setNotes((cur) => cur.map((x) => (x.k === n.k ? { ...x, state: ok ? 1 : 2 } : x)));
                window.setTimeout(() => remove(n.k), ok ? 620 : 260);
              }}
              onClick={(e) => e.stopPropagation()}>
              <i className="mp-note__ring" aria-hidden>₦</i>
              <b className="mp-note__face">{face}</b>
            </span>
          </span>
          {n.state === 1 && <span className="mp-plus" aria-hidden>+{face}</span>}
        </span>
      ))}
    </div>
  );
});

/** The live "+₦70,000": bumps on every change. */
function Counter({ total, gold }: { total: number; gold: boolean }) {
  return (
    <div className={`mp-counter${gold ? ' is-gold' : ''}`} role="status" aria-live="polite">
      <span className="mp-counter__label">You picked</span>
      <span className="mp-counter__n" key={total}>+{naira(total)}</span>
    </div>
  );
}

export function MoneyPickLayer() {
  const drops = usePick((s) => s.drops);
  const notices = usePick((s) => s.notices);
  const gfx = useTier();
  const total = pickedTotal(drops);
  const live = drops.some((d) => !d.ended && !d.dead && !d.mine);
  if (!drops.length && !notices.length) return null;
  return (
    <div className="mp" aria-label={live ? 'Money on the floor: tap the notes to pick them' : undefined}>
      {drops.map((d) => <DropRain key={d.id} drop={d} low={gfx === 'low'} />)}
      <div className="mp-top">
        {total > 0 && <Counter total={total} gold={drops.some((d) => d.vip)} />}
        {live && total === 0 && <div className="mp-hint">Tap the notes! 💸</div>}
        {/* mobile: one small pill at a time so the notes stay tappable (the hype man says the MC line) */}
        {notices.slice(-1).map((n) => (
          <div key={n.id} className={`mp-notice${n.vip ? ' is-gold' : ''}${n.kind === 'pick_top' ? ' is-top' : ''}`}
            style={{ animationDelay: `0ms, ${noticeMs() - 300}ms` }}>
            {noticeHeadline(n)}
          </div>
        ))}
      </div>
    </div>
  );
}
