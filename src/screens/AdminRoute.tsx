// /admin — lazily loads src/admin/AdminApp.tsx (P2-ADMIN) if it exists. Server RPCs enforce admin rights;
// this is just the door.
import { lazy, Suspense, type ComponentType, type LazyExoticComponent } from 'react';
import { Link } from 'react-router-dom';
import { useGame } from '../state/game';
import { EmptyState, ErrorBoundary, LoadingScreen } from '../ui';

const modules = import.meta.glob<{ default: ComponentType }>('../admin/AdminApp.tsx');
const loader = Object.values(modules)[0];
const AdminApp: LazyExoticComponent<ComponentType> | null = loader ? lazy(loader) : null;

export default function AdminRoute() {
  const isAdmin = useGame((s) => s.state?.profile.is_admin ?? false);
  if (!isAdmin) {
    return (
      <div className="center-screen">
        <div className="auth-card">
          <EmptyState icon="lock" title="Oga, this place na for admin only"
            body="You no get admin access. Go back go hustle."
            action={<Link to="/play" className="bl-btn bl-btn--primary bl-btn--md"><span className="bl-btn__label">Back to game</span></Link>} />
        </div>
      </div>
    );
  }
  if (!AdminApp) {
    return (
      <div className="center-screen">
        <div className="auth-card">
          <EmptyState icon="crown" title="Admin panel no dey yet"
            body="The developer tools never land for this build. Check back later."
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
