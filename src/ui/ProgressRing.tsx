// Slow-filling circular progress ring — P1-TIME. Used by the busy banner (sleep, eat, chat…).
//
// Cheap on low-end phones: no requestAnimationFrame loop. The parent re-renders once per tick
// (`useNow`, 1 s); each render aims the ring at where it must be ONE TICK FROM NOW and lets a
// linear CSS transition of that same length carry it there. So the fill moves continuously and
// lands on 100% exactly at `endMs`. With prefers-reduced-motion the ring jumps to the current
// value each tick instead (still shows progress, no easing).
import { useEffect, useState, type ReactNode } from 'react';

const REDUCED = '(prefers-reduced-motion: reduce)';

function usePrefersReducedMotion(): boolean {
  const [reduced, setReduced] = useState(() =>
    typeof window !== 'undefined' && typeof window.matchMedia === 'function' ? window.matchMedia(REDUCED).matches : false,
  );
  useEffect(() => {
    if (typeof window.matchMedia !== 'function') return;
    const mq = window.matchMedia(REDUCED);
    const on = () => setReduced(mq.matches);
    mq.addEventListener('change', on);
    return () => mq.removeEventListener('change', on);
  }, []);
  return reduced;
}

export interface ProgressRingProps {
  startMs: number;
  endMs: number;
  /** Server-corrected now (ms) — the value the parent ticks with. */
  nowMs: number;
  /** How often the parent re-renders (ms). Must match the parent's tick. */
  tickMs?: number;
  size?: number;
  stroke?: number;
  label?: string;
  className?: string;
  children?: ReactNode;
}

export function ProgressRing({
  startMs,
  endMs,
  nowMs,
  tickMs = 1000,
  size = 44,
  stroke = 4,
  label,
  className,
  children,
}: ProgressRingProps) {
  const reduced = usePrefersReducedMotion();
  const total = Math.max(1, endMs - startMs);
  const at = (t: number) => Math.min(1, Math.max(0, (t - startMs) / total));
  const current = at(nowMs);
  const target = reduced ? current : at(nowMs + tickMs);

  const r = (size - stroke) / 2;
  const c = 2 * Math.PI * r;
  return (
    <span
      className={`ring${className ? ` ${className}` : ''}`}
      style={{ width: size, height: size }}
      role="progressbar"
      aria-label={label}
      aria-valuemin={0}
      aria-valuemax={100}
      aria-valuenow={Math.round(current * 100)}
    >
      <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} aria-hidden>
        <circle className="ring__track" cx={size / 2} cy={size / 2} r={r} strokeWidth={stroke} />
        <circle
          className="ring__fill"
          cx={size / 2}
          cy={size / 2}
          r={r}
          strokeWidth={stroke}
          strokeDasharray={c}
          strokeDashoffset={c * (1 - target)}
          style={{ transitionDuration: reduced ? '0ms' : `${tickMs}ms` }}
        />
      </svg>
      {children && <span className="ring__inner">{children}</span>}
    </span>
  );
}
