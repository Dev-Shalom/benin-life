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

/** Full-area loader with a coral-bead ring and Pidgin caption. */
export function LoadingScreen({ text = 'Hold on small…' }: { text?: string }) {
  return (
    <div className="bl-loading">
      <div className="bl-loading__beads" aria-hidden>
        {Array.from({ length: 8 }, (_, i) => (
          <span key={i} style={{ transform: `rotate(${i * 45}deg) translateY(-22px)`, animationDelay: `${i * 0.12}s` }} />
        ))}
      </div>
      <p>{text}</p>
    </div>
  );
}
