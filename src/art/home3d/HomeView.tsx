// Lazy wrapper for the 3D home: three.js + r3f load only when the player is at home.
// `suspended` unmounts the canvas (so another 3D view, e.g. the Sim sheet turntable, is the only
// WebGL canvas on screen) and shows a still frame of the house in its place until it comes back.
import { lazy, Suspense, useCallback, useLayoutEffect, useRef, useState, type ReactNode } from 'react';
import { Scene } from '../Scene';
import type { SceneType } from '../../lib/types';
import { ErrorBoundary } from '../../ui';
import type { HomeApi, HomeSceneProps } from './engine/HomeScene';
import { homeLight } from './engine/light';

const HomeScene = lazy(() => import('./engine/HomeScene'));

export interface HomeViewProps extends Omit<HomeSceneProps, 'onReady' | 'paused'> {
  /** Unmount the canvas and show a still frame instead. */
  suspended?: boolean;
  /** Pause rendering but keep the canvas (e.g. while a plain sheet covers it). */
  paused?: boolean;
  /** SVG scene to show when WebGL is not available. */
  fallbackScene: SceneType;
  /** Extra UI for the no-WebGL fallback (e.g. a "Things to do" button). */
  fallbackAction?: ReactNode;
}

export function HomeView({ suspended, paused, fallbackScene, fallbackAction, ...props }: HomeViewProps) {
  const api = useRef<HomeApi | null>(null);
  const [still, setStill] = useState<string | null>(null);
  const [live, setLive] = useState(!suspended);
  const [lost, setLost] = useState(false);
  const night = props.hour >= 20 || props.hour < 6;
  const bg = homeLight(props.hour).bg;

  useLayoutEffect(() => {
    if (suspended && live) {
      setStill(api.current?.snapshot() ?? null);
      api.current = null;
      setLive(false);
    } else if (!suspended && !live) {
      setLive(true);
    }
  }, [suspended, live]);

  const onReady = useCallback((a: HomeApi) => {
    api.current = a;
    // drop the still once the live canvas has drawn
    window.setTimeout(() => setStill(null), 120);
  }, []);

  const fallback = (
    <div className="home3d home3d--fallback">
      <div className="home3d__svg"><Scene type={fallbackScene} night={night} /></div>
      {fallbackAction}
    </div>
  );

  if (lost) return fallback;

  return (
    <div className="home-view" style={{ background: bg }}>
      {live && (
        <ErrorBoundary fallback={fallback}>
          <Suspense fallback={<div className="home3d home3d--loading"><span className="home3d__loader" aria-label="Loading your home" /></div>}>
            <HomeScene {...props} paused={paused} onReady={onReady} onLost={() => setLost(true)} />
          </Suspense>
        </ErrorBoundary>
      )}
      {still && <img className="home-view__still" src={still} alt="" aria-hidden />}
    </div>
  );
}
