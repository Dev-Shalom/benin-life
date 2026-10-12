import { Logo } from './Logo';

export function Spinner({ size = 20, label }: { size?: number; label?: string }) {
  return (
    <span className="bl-spinner" role="status" aria-label={label ?? 'Loading'} style={{ width: size, height: size }}>
      <svg viewBox="0 0 24 24" width={size} height={size} aria-hidden>
        <circle cx="12" cy="12" r="9.5" fill="none" stroke="currentColor" strokeOpacity="0.22" strokeWidth="3" />
        <path d="M12 2.5a9.5 9.5 0 0 1 9.5 9.5" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round" />
      </svg>
    </span>
  );
}

/** Full-area loader (splash): the Benin Life mark inside a pulsing ring of coral beads. */
export function LoadingScreen({ text = 'Loading…' }: { text?: string }) {
  return (
    <div className="bl-loading">
      <div className="bl-loading__beads" aria-hidden>
        <Logo size={68} title="" className="bl-loading__logo" />
        {Array.from({ length: 12 }, (_, i) => (
          <span key={i} style={{ transform: `rotate(${i * 30}deg) translateY(-54px)`, animationDelay: `${i * 0.08}s` }} />
        ))}
      </div>
      <p>{text}</p>
    </div>
  );
}
