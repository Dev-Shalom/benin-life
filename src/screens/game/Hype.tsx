// P2 hype UI: the club banner (the hype man's line, top of the place view) and the slim app-wide ticker.
// Both read src/state/hype.ts. Enter: a short rise + fade (ease-out); exit: faster. Reduced motion: fade only.
import { useEffect, useRef, useState } from 'react';
import { dismissHypeBanner, useHype, type Announcement } from '../../state/hype';

const KIND_ICON: Record<string, string> = { vip: '👑', bottles: '🍾', spray: '💸', shoutout: '🎤', shutdown: '🔥' };

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

export function HypeBanner({ mcName, top }: { mcName: string; top: number }) {
  const banner = useHype((s) => s.banner);
  const { shown, out } = useLeaving<Announcement>(banner, 180);
  if (!shown) return null;
  return (
    <div className="hype-banner-wrap" style={{ top }}>
      <button type="button" key={shown.id} className={`hype-banner is-${shown.kind}${out ? ' is-out' : ''}`} onClick={dismissHypeBanner}
        aria-label={`${mcName}: ${shown.text}. Tap to close`}>
        <span className="hype-banner__icon" aria-hidden>{KIND_ICON[shown.kind] ?? '🎤'}</span>
        <span className="hype-banner__main">
          <span className="hype-banner__who">{mcName} <span className="hype-banner__live">LIVE</span></span>
          <span className="hype-banner__text">{shown.text}</span>
        </span>
      </button>
      <div className="sr-only" role="status" aria-live="polite">{out ? '' : `${mcName}: ${shown.text}`}</div>
    </div>
  );
}

export function HypeTicker({ top }: { top: number }) {
  const ticker = useHype((s) => s.ticker);
  const { shown, out } = useLeaving<Announcement>(ticker, 180);
  if (!shown || !shown.ticker) return null;
  return (
    <div className={`hype-ticker${out ? ' is-out' : ''}`} role="status" aria-live="polite" key={shown.id} style={{ top }}>
      <span className="hype-ticker__dot" aria-hidden />
      <span className="hype-ticker__text">{shown.ticker}</span>
    </div>
  );
}
