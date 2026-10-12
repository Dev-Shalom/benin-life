// P3 hype with aura (docs/PLACES.md "P3 hype aura"). Reads src/state/hype.ts.
//  * HypeTakeover: the full-screen moment for everyone in the club (and a calm gold one for a VIP arrival at any
//    place). Layers, back to front: dimmed + blurred backdrop, tier light (spotlight / light sweep / edge glow),
//    the radial aura breathing on the beat, the particle canvas (hypeFx.ts), then the content: MC pill, crown,
//    the @name huge with a glow + shimmer (SVG, clipped band), the type label, the amount rolling up, and
//    MC Lightning's line revealed word by word. Tap / Esc skips; a hairline shows the time left.
//  * HypeStrip: the app-wide strip for big spends elsewhere (~6 s, aura + shimmer); tap opens that place.
// Motion is transforms + opacity only. prefers-reduced-motion: a calm fade, no particles, no beat loop.
import { Fragment, useEffect, useMemo, useRef, useState } from 'react';
import { dismissHypeBanner, dismissHypeTicker, hypeHoldMs, sprayLevel, useHype, type Announcement } from '../../state/hype';
import { nairaWords } from '../../api/spray';
import { useTier } from '../../art/feel/quality';
import { naira } from '../../lib/format';
import { preloadHypeFx, startHypeFx, type HypeTier } from './hypeFx';
import '../../styles/hype.css';

const KIND_ICON: Record<string, string> = { vip: '👑', bottles: '🍾', spray: '💸', shoutout: '🎤', shutdown: '🔥', vip_arrival: '👑' };

const SPRAY_NAME = ['SMALL', 'NICE', 'BIG', 'HUGE', 'OGA', 'BILLIONAIRE', 'TRILLIONAIRE'];
/** SP1: particles by spray tier (x the base pool). */
const SPRAY_FX = [0.6, 0.8, 1, 1.35, 1.7, 2.1, 2.6];

function tierOf(kind: string, vip?: boolean | null): HypeTier {
  if (kind === 'spray' && vip) return 'vip';
  switch (kind) {
    case 'spray': return 'spray';
    case 'shoutout': return 'shout';
    case 'shutdown': return 'shutdown';
    case 'bottles': return 'bottles';
    case 'vip_arrival': return 'calm';
    default: return 'gold';
  }
}

/** ₦50K / ₦1.5M for the label (the counter shows the full amount). */
function nairaK(n: number): string {
  const v = Math.max(0, Math.round(n));
  if (v >= 1e9) return `₦${+(v / 1e9).toFixed(1)}B`;
  if (v >= 1e6) return `₦${+(v / 1e6).toFixed(1)}M`;
  if (v >= 1e3) return `₦${Math.round(v / 1e3)}K`;
  return `₦${v}`;
}

function placeOf(a: Announcement): string {
  return (a.place || '').trim() || 'the club';
}

function labelOf(a: Announcement): string {
  switch (a.kind) {
    case 'vip': return 'VIP TABLE';
    case 'bottles': return `POPPED ${Math.max(1, a.qty)} BOTTLE${a.qty === 1 ? '' : 'S'}`;
    case 'spray': {
      const lv = sprayLevel(a);
      if (lv < 0) return `SPRAYED ${nairaK(a.amount)}`;
      return a.vip ? `VIP SPRAY · ${SPRAY_NAME[lv]}` : `${SPRAY_NAME[lv]} SPRAY`;
    }
    case 'shoutout': return 'HYPE MAN SHOUT-OUT';
    case 'shutdown': return `SHUT DOWN ${placeOf(a).toUpperCase()}`;
    case 'vip_arrival': return 'VIP HAS ARRIVED';
    default: return 'BIG SPENDER';
  }
}

/** The strip's short kicker. */
function kickerOf(a: Announcement): string {
  const k: Record<string, string> = { vip: 'VIP TABLE', bottles: 'BOTTLES', spray: 'NAIRA RAIN', shoutout: 'SHOUT-OUT', shutdown: 'CLUB SHUT DOWN' };
  const lv = sprayLevel(a);
  if (lv >= 0) return `${SPRAY_NAME[lv]} SPRAY · ${nairaWords(a.amount)}`;
  return `${k[a.kind] ?? 'BIG SPEND'}${a.amount > 0 ? ` · ${nairaK(a.amount)}` : ''}`;
}

function useReducedMotion(): boolean {
  const q = '(prefers-reduced-motion: reduce)';
  const [r, setR] = useState(() => typeof window !== 'undefined' && !!window.matchMedia?.(q).matches);
  useEffect(() => {
    const m = window.matchMedia?.(q);
    if (!m) return;
    const on = () => setR(m.matches);
    m.addEventListener?.('change', on);
    return () => m.removeEventListener?.('change', on);
  }, []);
  return r;
}

/** Keeps the last item on screen for the exit animation. */
function useLeaving<T extends { id: number }>(cur: T | null, exitMs: number) {
  const [shown, setShown] = useState<T | null>(cur);
  const [out, setOut] = useState(false);
  const t = useRef(0);
  useEffect(() => {
    window.clearTimeout(t.current);
    if (cur && (!shown || cur.id === shown.id)) {
      setShown(cur);
      setOut(false);
    } else if (shown) {
      setOut(true);
      t.current = window.setTimeout(() => {
        setShown(cur);
        setOut(false);
      }, exitMs);
    }
    return () => window.clearTimeout(t.current);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [cur]);
  return { shown, out };
}

/** The amount rolls up (ease-out), written straight into the node: no re-render per frame. */
function RollUp({ to, delay, ms, still }: { to: number; delay: number; ms: number; still: boolean }) {
  const ref = useRef<HTMLSpanElement>(null);
  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    if (still) { el.textContent = naira(to); return; }
    el.textContent = naira(0);
    let raf = 0;
    const t0 = performance.now() + delay;
    const step = (now: number) => {
      const p = Math.min(1, Math.max(0, (now - t0) / ms));
      const e = 1 - Math.pow(1 - p, 3);
      el.textContent = naira(Math.round(to * e));
      if (p < 1) raf = requestAnimationFrame(step);
    };
    raf = requestAnimationFrame(step);
    return () => cancelAnimationFrame(raf);
  }, [to, delay, ms, still]);
  return <span ref={ref} className="hx-amount__n">{naira(still ? to : 0)}</span>;
}

function Crown() {
  return (
    <svg className="hx-crown" viewBox="0 0 120 72" aria-hidden>
      <defs>
        <linearGradient id="hx-crown-g" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#fff3c4" />
          <stop offset="0.45" stopColor="#f3c65a" />
          <stop offset="1" stopColor="#b07a22" />
        </linearGradient>
      </defs>
      <path d="M10 60 L4 18 L34 40 L60 6 L86 40 L116 18 L110 60 Z" fill="url(#hx-crown-g)" stroke="#7a4f12" strokeWidth="2.5" strokeLinejoin="round" />
      <rect x="10" y="58" width="100" height="10" rx="3" fill="url(#hx-crown-g)" stroke="#7a4f12" strokeWidth="2.5" />
      <circle cx="60" cy="40" r="6" fill="#e2384f" stroke="#7a1f2a" strokeWidth="1.5" />
      <circle cx="34" cy="48" r="4" fill="#37b36c" stroke="#145a33" strokeWidth="1.2" />
      <circle cx="86" cy="48" r="4" fill="#3a8be0" stroke="#173f78" strokeWidth="1.2" />
      {[4, 60, 116].map((cx, i) => <circle key={cx} cx={cx} cy={i === 1 ? 6 : 18} r="5" fill="#fff3c4" stroke="#7a4f12" strokeWidth="2" />)}
    </svg>
  );
}

/** The @name: SVG so it always fits (viewBox sized to the name), gold gradient, a soft glow copy behind and a
 *  light band sweeping across inside a text clip (a transform on the band, nothing else moves). */
function NameMark({ name, id, tier }: { name: string; id: number; tier: HypeTier }) {
  const label = `@${name}`;
  const fs = 110;
  const w = Math.max(520, Math.round(label.length * fs * 0.6 + 80));
  const h = 150;
  const k = `hx${id}`;
  const fill = tier === 'vip' ? ['#fffbe8', '#f7d774', '#b0793a'] : tier === 'spray' ? ['#f4ffd8', '#b8f07e', '#f3c65a'] : tier === 'shout' ? ['#fff3ff', '#e2c4ff', '#f3c65a'] : ['#fffbe8', '#ffd97a', '#d79a2c'];
  const text = (props: Record<string, unknown>) => (
    <text x={w / 2} y={112} textAnchor="middle" fontSize={fs} fontWeight={800} fontFamily="Outfit, 'Segoe UI', system-ui, sans-serif" letterSpacing="-1" {...props}>{label}</text>
  );
  return (
    <svg className="hx-name" viewBox={`0 0 ${w} ${h}`} preserveAspectRatio="xMidYMid meet" role="img" aria-label={label}>
      <defs>
        <linearGradient id={`${k}-fill`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor={fill[0]} />
          <stop offset="0.5" stopColor={fill[1]} />
          <stop offset="1" stopColor={fill[2]} />
        </linearGradient>
        <linearGradient id={`${k}-band`} x1="0" y1="0" x2="1" y2="0">
          <stop offset="0" stopColor="#fff" stopOpacity="0" />
          <stop offset="0.5" stopColor="#fff" stopOpacity="0.95" />
          <stop offset="1" stopColor="#fff" stopOpacity="0" />
        </linearGradient>
        <filter id={`${k}-glow`} x="-20%" y="-40%" width="140%" height="180%"><feGaussianBlur stdDeviation="9" /></filter>
        <clipPath id={`${k}-clip`}>{text({})}</clipPath>
      </defs>
      <g className="hx-name__glow" filter={`url(#${k}-glow)`}>{text({ fill: fill[1], stroke: fill[1], strokeWidth: 6 })}</g>
      {text({ fill: `url(#${k}-fill)`, stroke: 'rgba(60,32,4,0.55)', strokeWidth: 2, paintOrder: 'stroke' })}
      <g clipPath={`url(#${k}-clip)`}>
        <g transform="skewX(-18)">
          <rect className="hx-name__band" x={-w * 0.3} y="0" width={w * 0.22} height={h} fill={`url(#${k}-band)`} />
        </g>
      </g>
    </svg>
  );
}

/** MC Lightning's line, word by word. The player's name and money glow. */
function Caption({ text, name, stepMs, still }: { text: string; name: string; stepMs: number; still: boolean }) {
  const words = useMemo(() => text.split(/\s+/).filter(Boolean), [text]);
  const nm = name.toLowerCase();
  return (
    <p className="hx-caption" aria-hidden>
      {words.map((w, i) => {
        const bare = w.replace(/^@/, '').replace(/[!?.,…"']+$/, '').toLowerCase();
        const cls = bare === nm ? ' is-name' : /₦/.test(w) ? ' is-money' : '';
        return (
          <Fragment key={i}>
            <span className={`hx-word${cls}`} style={still ? undefined : { animationDelay: `${520 + i * stepMs}ms` }}>{w}</span>
            {i < words.length - 1 ? ' ' : null}
          </Fragment>
        );
      })}
    </p>
  );
}

export function HypeTakeover({ mcName }: { mcName: string }) {
  const banner = useHype((s) => s.banner);
  const queued = useHype((s) => s.queue.length);
  const { shown, out } = useLeaving<Announcement>(banner, 280);
  const reduced = useReducedMotion();
  const gfx = useTier();
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const auraRef = useRef<HTMLDivElement>(null);

  useEffect(() => { preloadHypeFx(); }, []);

  const hold = shown ? hypeHoldMs(shown) : 0;
  const tier = shown ? tierOf(shown.kind, shown.vip) : 'gold';
  const lv = shown ? sprayLevel(shown) : -1;

  useEffect(() => {
    if (!shown || reduced || !canvasRef.current) return;
    const base = gfx === 'low' ? 40 : 120;
    let count = tier === 'calm' ? Math.round(base * 0.35) : base;
    if (lv >= 0) count = Math.min(gfx === 'low' ? 110 : 320, Math.round(base * SPRAY_FX[lv] * (shown.vip ? 1.2 : 1)));
    return startHypeFx(canvasRef.current, auraRef.current, {
      tier, count, emitMs: Math.max(1200, hold - 1100),
      goldNotes: !!shown.vip || lv >= 5, fireworks: lv >= 6 ? true : undefined,
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [shown?.id, reduced, gfx]);

  useEffect(() => {
    if (!shown) return;
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') dismissHypeBanner(); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [shown]);

  if (!shown) return null;
  const words = shown.text.split(/\s+/).length;
  const stepMs = Math.max(55, Math.min(120, (hold * 0.42) / Math.max(1, words)));
  const calm = shown.kind === 'vip_arrival';
  const who = calm ? (shown.qty > 0 ? `VIP #${shown.qty}` : 'VIP alert') : mcName;
  // SP1: crown only for the top spray tiers (oga+) and VIP; the other kinds keep it
  const crown = lv < 0 || lv >= 4 || !!shown.vip;
  const amt = Math.max(0, Number(shown.amount) || 0);
  const digits = String(Math.round(amt)).length;
  return (
    <div className={`hx tier-${tier}${lv >= 0 ? ` sp-${lv}` : ''}${out ? ' is-out' : ''}${reduced ? ' is-reduced' : ''}`} key={shown.id}
      style={{ ['--hold' as string]: `${hold}ms`, ['--amt-len' as string]: Math.max(6, digits + Math.floor((digits - 1) / 3) + 1) }}>
      <div className="hx-backdrop" aria-hidden />
      {tier === 'shout' && <div className="hx-spot" aria-hidden><i /><i /></div>}
      {(tier === 'shutdown' || lv >= 5 || tier === 'vip') && <><div className="hx-edge" aria-hidden /><div className="hx-sweep" aria-hidden /></>}
      <div className="hx-aura" ref={auraRef} aria-hidden />
      {!reduced && <canvas className="hx-canvas" ref={canvasRef} aria-hidden />}
      <button type="button" className="hx-hit" onClick={dismissHypeBanner} aria-label={`${who}: ${shown.text}. Tap to skip`}>
        <span className="hx-stack">
          <span className="hx-mc"><span className="hx-mc__dot" aria-hidden />{who}{!calm && <span className="hx-mc__live">LIVE</span>}</span>
          {shown.vip && <span className="hx-vipband" aria-hidden><i>👑</i>VIP<i>👑</i></span>}
          {crown && <Crown />}
          <NameMark name={shown.username} id={shown.id} tier={tier} />
          <span className="hx-label"><span aria-hidden>{KIND_ICON[shown.kind] ?? '🎤'}</span>{labelOf(shown)}</span>
          {shown.amount > 0 && (
            <span className={`hx-amount${lv >= 0 ? ' is-spray' : ''}`}><RollUp to={shown.amount} delay={reduced ? 0 : 380} ms={tier === 'shutdown' || lv >= 4 ? 1800 : 1100} still={reduced} /></span>
          )}
          {lv >= 0 && amt >= 1000 && <span className="hx-words">{nairaWords(amt)}</span>}
          <Caption text={shown.text} name={shown.username} stepMs={stepMs} still={reduced} />
        </span>
        <span className="hx-foot" aria-hidden>
          {queued > 0 ? `+${queued} more · ` : ''}Tap to skip
          <span className="hx-progress"><i /></span>
        </span>
      </button>
      <div className="sr-only" role="status" aria-live="polite">{out ? '' : `${who}: ${shown.text}`}</div>
    </div>
  );
}

/** The app-wide strip for a big spend somewhere else: aura + shimmer, ~6 s, tap opens that place. */
export function HypeStrip({ top, onOpen }: { top: number; onOpen: (locationId: string) => void }) {
  const ticker = useHype((s) => s.ticker);
  const { shown, out } = useLeaving<Announcement>(ticker, 220);
  if (!shown || !shown.ticker) return null;
  const tier = tierOf(shown.kind, shown.vip);
  return (
    <div className={`hx-strip-wrap${out ? ' is-out' : ''}`} style={{ top }} key={shown.id}>
      <button type="button" className={`hx-strip tier-${tier}`}
        onClick={() => { dismissHypeTicker(); onOpen(shown.location_id); }}
        aria-label={`${shown.ticker}. Open ${placeOf(shown)}`}>
        <span className="hx-strip__aura" aria-hidden />
        <span className="hx-strip__shine" aria-hidden />
        <span className="hx-strip__icon" aria-hidden>{KIND_ICON[shown.kind] ?? '🔥'}</span>
        <span className="hx-strip__main">
          <span className="hx-strip__kicker">{shown.vip && <span className="hx-strip__vip">VIP</span>}{kickerOf(shown)}</span>
          <span className="hx-strip__text">{shown.ticker}</span>
        </span>
        <span className="hx-strip__go">Go<span aria-hidden> ›</span></span>
        <span className="hx-strip__time" aria-hidden><i /></span>
      </button>
      <div className="sr-only" role="status" aria-live="polite">{out ? '' : shown.ticker}</div>
    </div>
  );
}
