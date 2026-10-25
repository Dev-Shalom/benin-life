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

/** Full-area loader (splash): plain light page, "Benin Life" and a muted status line, gentle fade-in. */
export function LoadingScreen({ text = 'Loading your game…' }: { text?: string }) {
  return (
    <div className="bl-loading" role="status" aria-live="polite">
      <h1 className="bl-loading__title">Benin Life</h1>
      <p className="bl-loading__text">{text}</p>
    </div>
  );
}
