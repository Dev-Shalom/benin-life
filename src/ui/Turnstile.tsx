// Cloudflare Turnstile widget. Renders nothing unless VITE_TURNSTILE_SITE_KEY is set. Tokens are single use: bump `resetKey`
// after every attempt (success or failure) to get a fresh one.
import { useEffect, useRef, useState } from 'react';
import { TURNSTILE_SITE_KEY, loadTurnstile, turnstileEnabled } from '../lib/turnstile';

export function Turnstile({ onToken, resetKey = 0 }: { onToken: (token: string | null) => void; resetKey?: number }) {
  const box = useRef<HTMLDivElement>(null);
  const widget = useRef<string | null>(null);
  const cb = useRef(onToken);
  useEffect(() => { cb.current = onToken; });
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    if (!turnstileEnabled) return;
    let dead = false;
    loadTurnstile().then((api) => {
      if (dead || !box.current) return;
      widget.current = api.render(box.current, {
        sitekey: TURNSTILE_SITE_KEY,
        theme: 'auto',
        callback: (t: string) => cb.current(t),
        'expired-callback': () => cb.current(null),
        'error-callback': () => cb.current(null),
      });
    }).catch(() => { if (!dead) setFailed(true); });
    return () => {
      dead = true;
      try { if (widget.current) window.turnstile?.remove(widget.current); } catch { /* ignore */ }
      widget.current = null;
    };
  }, []);

  useEffect(() => {
    if (resetKey === 0 || !widget.current) return;
    cb.current(null);
    try { window.turnstile?.reset(widget.current); } catch { /* ignore */ }
  }, [resetKey]);

  if (!turnstileEnabled) return null;
  return (
    <div className="au-field">
      <div ref={box} data-testid="turnstile" />
      {failed && <p className="au-msg au-msg--error" role="alert">The safety check could not load. Check your connection and refresh the page.</p>}
    </div>
  );
}
