import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import './styles/global.css';
import './styles/ui.css';
import './styles/screens.css';
import './styles/game.css';
import App from './App.tsx';
import { initAuth } from './state/game';
import { initSound } from './lib/sound';
import { Button, EmptyState, ErrorBoundary } from './ui';

initAuth();
initSound();

// After a new deploy, an open tab may ask for old chunk files that no longer exist.
// Reload once to pick up the new build instead of showing a broken screen.
window.addEventListener('vite:preloadError', (e) => {
  try {
    const last = Number(sessionStorage.getItem('bl-chunk-reload') || 0);
    if (Date.now() - last < 30_000) return;
    sessionStorage.setItem('bl-chunk-reload', String(Date.now()));
  } catch {
    /* storage blocked: still reload once */
  }
  e.preventDefault();
  window.location.reload();
});

const crashScreen = (
  <div className="center-screen">
    <div className="auth-card">
      <EmptyState
        icon="warning"
        title="Something went wrong"
        body="Benin Life hit a snag. Reload the page to carry on. Your Sim and money are saved."
        action={<Button icon="refresh" onClick={() => window.location.reload()}>Reload</Button>}
      />
    </div>
  </div>
);

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <ErrorBoundary fallback={crashScreen}>
      <App />
    </ErrorBoundary>
  </StrictMode>,
);
