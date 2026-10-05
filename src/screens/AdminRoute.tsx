// /admin — lazily loads src/admin/AdminApp.tsx (P2-ADMIN) if it exists. Server RPCs enforce admin rights;
// this is just the door.
import { lazy, Suspense, useState, type ComponentType, type LazyExoticComponent } from 'react';
import { Link } from 'react-router-dom';
import { useGame } from '../state/game';
import { rpc, errorMessage } from '../lib/api';
import { Button, EmptyState, ErrorBoundary, LoadingScreen, toast } from '../ui';

const modules = import.meta.glob<{ default: ComponentType }>('../admin/AdminApp.tsx');
const loader = Object.values(modules)[0];
const AdminApp: LazyExoticComponent<ComponentType> | null = loader ? lazy(loader) : null;

/** Owner bootstrap: admin_claim() makes the caller admin if their login email is on admin.bootstrap_emails. */
function ClaimButton() {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const refresh = useGame((s) => s.refresh);
  return (
    <div style={{ marginTop: 20, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 8 }}>
      <Button variant="ghost" icon="crown" loading={busy} onClick={async () => {
        setBusy(true);
        setError(null);
        try {
          const r = await rpc<{ message: string }>('admin_claim');
          toast(r.message, 'good');
          await refresh();
        } catch (e) {
          setError(errorMessage(e));
        } finally {
          setBusy(false);
        }
      }}>I'm the owner: claim admin</Button>
      {error && <p className="hint" role="alert" style={{ margin: 0, textAlign: 'center', color: 'var(--red-600)' }}>{error}</p>}
    </div>
  );
}

export default function AdminRoute() {
  const isAdmin = useGame((s) => s.state?.profile.is_admin ?? false);
  if (!isAdmin) {
    return (
      <div className="center-screen">
        <div className="auth-card">
          <EmptyState icon="lock" title="Admins only"
            body="Your account doesn't have admin access."
            action={<Link to="/play" className="bl-btn bl-btn--primary bl-btn--md"><span className="bl-btn__label">Back to game</span></Link>} />
          <ClaimButton />
        </div>
      </div>
    );
  }
  if (!AdminApp) {
    return (
      <div className="center-screen">
        <div className="auth-card">
          <EmptyState icon="crown" title="Admin panel not available yet"
            body="The admin tools aren't in this build yet. Check back later."
            action={<Link to="/play" className="bl-btn bl-btn--primary bl-btn--md"><span className="bl-btn__label">Back to game</span></Link>} />
        </div>
      </div>
    );
  }
  return (
    <ErrorBoundary>
      <Suspense fallback={<LoadingScreen text="Loading admin…" />}>
        <AdminApp />
      </Suspense>
    </ErrorBoundary>
  );
}
