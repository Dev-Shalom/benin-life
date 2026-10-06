// S1 update notice: production builds poll /version.json (written by the Vite plugin in vite.config.ts)
// every 3 minutes and when the tab comes back; if its id differs from the running build, a small
// phone-style dialog offers a Refresh. Game state lives on the server and prefs in localStorage, so a
// reload keeps everything. Never runs in dev; a failed fetch is ignored.
import { useEffect, useState } from 'react';
import { createPortal } from 'react-dom';
import { usePresence } from './presence';

const RUNNING: string = import.meta.env.VITE_BUILD_ID ?? '';
const EVERY_MS = 3 * 60_000;

async function latestId(): Promise<string | null> {
  try {
    const r = await fetch(`/version.json?t=${Date.now()}`, { cache: 'no-store' });
    if (!r.ok) return null;
    const j = (await r.json()) as { id?: unknown };
    return typeof j.id === 'string' && j.id ? j.id : null;
  } catch {
    return null;
  }
}

function useNewBuild(): [string | null, () => void] {
  const [found, setFound] = useState<string | null>(null);
  const [dismissed, setDismissed] = useState<string | null>(null);
  useEffect(() => {
    if (!import.meta.env.PROD || !RUNNING) return;
    let alive = true;
    let last = 0;
    const check = async () => {
      if (document.visibilityState !== 'visible' || Date.now() - last < 20_000) return;
      last = Date.now();
      const id = await latestId();
      if (alive && id && id !== RUNNING) setFound(id);
    };
    const id = window.setInterval(check, EVERY_MS);
    const onShow = () => void check();
    window.addEventListener('focus', onShow);
    document.addEventListener('visibilitychange', onShow);
    return () => {
      alive = false;
      window.clearInterval(id);
      window.removeEventListener('focus', onShow);
      document.removeEventListener('visibilitychange', onShow);
    };
  }, []);
  const show = found && found !== dismissed ? found : null;
  return [show, () => setDismissed(found)];
}

export function UpdateNotice() {
  const [next, later] = useNewBuild();
  const open = Boolean(next);
  const { mounted, closing } = usePresence(open, 180);
  if (!mounted) return null;
  return createPortal(
    <div className={`update-note${closing ? ' is-closing' : ''}`} role="alertdialog" aria-modal="false"
      aria-labelledby="update-note-title" aria-describedby="update-note-body">
      <div className="update-note__card">
        <span className="update-note__icon" aria-hidden>✨</span>
        <h2 id="update-note-title" className="update-note__title">There's a new update</h2>
        <p id="update-note-body" className="update-note__body">Refresh to get the latest. Your Sim, money and settings are saved.</p>
        <div className="update-note__actions">
          <button type="button" className="update-note__btn" onClick={later}>Later</button>
          <button type="button" className="update-note__btn update-note__btn--main" onClick={() => window.location.reload()}>Refresh</button>
        </div>
      </div>
    </div>,
    document.body,
  );
}
