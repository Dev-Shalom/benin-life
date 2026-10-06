import { lazy, Suspense, type ReactNode } from 'react';
import { BrowserRouter, Navigate, Route, Routes, useLocation } from 'react-router-dom';
import { supabaseConfigured } from './lib/supabase';
import { useGame } from './state/game';
import { needsHome } from './api/creator';
import { LoadingScreen, Toaster } from './ui';
import { UpdateNotice } from './ui/UpdateNotice';
import { P } from './lib/pidgin';
import Landing from './screens/Landing';
import Auth from './screens/Auth';
import Setup from './screens/Setup';
import ErrorScreen from './screens/ErrorScreen';

// Heavier screens load on demand to keep the first load small on mobile data.
const CreateSim = lazy(() => import('./screens/CreateSim'));
const Game = lazy(() => import('./screens/Game'));
const AdminRoute = lazy(() => import('./screens/AdminRoute'));
const Terms = lazy(() => import('./screens/Legal').then((m) => ({ default: m.Terms })));
const Privacy = lazy(() => import('./screens/Legal').then((m) => ({ default: m.Privacy })));
// Dev-only gallery of the 3D avatars (not linked anywhere; dev server only).
const AvatarLab = import.meta.env.DEV ? lazy(() => import('./art/avatar3d/dev/AvatarLab')) : null;
const HomeLab = import.meta.env.DEV ? lazy(() => import('./art/home3d/dev/HomeLab')) : null;
// Dev-only 3D city close-ups (tree-shaken out of production builds).
const CityLab = import.meta.env.DEV ? lazy(() => import('./art/city3d/dev/CityLab')) : null;

function RequireSession({ children }: { children: ReactNode }) {
  const authReady = useGame((s) => s.authReady);
  const session = useGame((s) => s.session);
  const loc = useLocation();
  if (!authReady) return <LoadingScreen text={P.loading} />;
  if (!session) return <Navigate to={`/auth?mode=signin&next=${encodeURIComponent(loc.pathname)}`} replace />;
  return <>{children}</>;
}

/** Needs a created Sim with a home. Sends new accounts (and Sims still choosing a home) to /create. */
function RequirePlayer({ children }: { children: ReactNode }) {
  const status = useGame((s) => s.status);
  const error = useGame((s) => s.error);
  const homeless = useGame((s) => needsHome(s.state));
  if (status === 'noprofile' || (status === 'ready' && homeless)) return <Navigate to="/create" replace />;
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
          <Route path="/terms" element={<Terms />} />
          <Route path="/privacy" element={<Privacy />} />
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
          {AvatarLab && <Route path="/dev/avatars" element={<AvatarLab />} /> /* dev server only */}
          {HomeLab && <Route path="/dev/home" element={<HomeLab />} /> /* 3D home without a session */}
          {CityLab && <Route path="/dev/city" element={<CityLab />} /> /* 3D city without a session */}
          {import.meta.env.DEV && <Route path="/dev/create" element={<CreateSim />} /> /* creator without a session, for screenshots */}
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </Suspense>
      <Toaster />
      <UpdateNotice />
    </BrowserRouter>
  );
}
