import { useGame } from '../state/game';
import { Ph } from './mk/Ph';
import { MkNav, MkRoot } from './mk/Shell';

export default function ErrorScreen({ message }: { message: string }) {
  const refresh = useGame((s) => s.refresh);
  const signOut = useGame((s) => s.signOut);
  return (
    <MkRoot className="er">
      <MkNav />
      <main id="main" className="mk-wrap er-main">
        <div className="er-card" role="alert">
          <span className="er-icon"><Ph name="warning" /></span>
          <h1 className="mk-display">Something went wrong</h1>
          <p>{message}</p>
          <div className="er-actions">
            <button type="button" className="mk-btn mk-btn--primary" onClick={() => void refresh()}>Try again</button>
            <button type="button" className="mk-btn mk-btn--ghost" onClick={() => void signOut()}>Log out</button>
          </div>
        </div>
      </main>
    </MkRoot>
  );
}
