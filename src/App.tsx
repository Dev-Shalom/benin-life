import { lazy, Suspense, type ReactNode } from 'react';
import { BrowserRouter, Navigate, Route, Routes, useLocation } from 'react-router-dom';
import { supabaseConfigured } from './lib/supabase';
import { useGame } from './state/game';
import { LoadingScreen, Toaster } from './ui';
import { P } from './lib/pidgin';
import Landing from './screens/Landing';
import Auth from './screens/Auth';
import Setup from './screens/Setup';
import ErrorScreen from './screens/ErrorScreen';

// Heavier screens load on demand to keep the first load small on mobile data.
const CreateSim = lazy(() => import('./screens/CreateSim'));
const Game = lazy(() => import('./screens/Game'));
const AdminRoute = lazy(() => import('./screens/AdminRoute'));
// Dev-only gallery of the 3D avatars (not linked anywhere).
const AvatarLab = lazy(() => import('./art/avatar3d/dev/AvatarLab'));

function RequireSession({ children }: { children: ReactNode }) {
  const authReady = useGame((s) => s.authReady);
  const session = useGame((s) => s.session);
  const loc = useLocation();
  if (!authReady) return <LoadingScreen text={P.loading} />;
  if (!session) return <Navigate to={`/auth?mode=signin&next=${encodeURIComponent(loc.pathname)}`} replace />;
  return <>{children}</>;
}

/** Needs a created Sim. Sends new accounts to /create. */
function RequirePlayer({ children }: { children: ReactNode }) {
  const status = useGame((s) => s.status);
  const error = useGame((s) => s.error);
  if (status === 'noprofile') return <Navigate to="/create" replace />;
  if (status === 'error') return <ErrorScreen message={error ?? P.somethingWrong} />;
  if (status !== 'ready') return <LoadingScreen text={P.loadingGame} />;
  return <>{children}</>;
}

function HomeRoute() {
  const session = useGame((s) => s.session);
  if (session) return <Navigate to="/play" replace />;
  return <Landing />;
}

export default function App() {
  if (!supabaseConfigured) {
    return (
      <>
        <Setup />
        <Toaster />
      </>
    );
  }
  return (
    <BrowserRouter>
      <Suspense fallback={<LoadingScreen text={P.loading} />}>
        <Routes>
          <Route path="/" element={<HomeRoute />} />
          <Route path="/auth" element={<Auth />} />
          <Route
            path="/create"
            element={
              <RequireSession>
                <CreateSim />
              </RequireSession>
            }
          />
          <Route
            path="/play"
            element={
              <RequireSession>
                <RequirePlayer>
                  <Game />
                </RequirePlayer>
              </RequireSession>
            }
          />
          <Route
            path="/admin/*"
            element={
              <RequireSession>
                <RequirePlayer>
                  <AdminRoute />
                </RequirePlayer>
              </RequireSession>
            }
          />
          <Route path="/dev/avatars" element={<AvatarLab />} />
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </Suspense>
      <Toaster />
    </BrowserRouter>
  );
}
