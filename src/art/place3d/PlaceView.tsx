// L2: lazy wrapper for the 3D place interior (three.js + r3f load only when the player is inside a place).
// `suspended` unmounts the canvas (another 3D view is on screen) and shows a still frame; no WebGL or a
// lost context falls back to the place's phase-1 SVG scene.
import { lazy, Suspense, useCallback, useLayoutEffect, useRef, useState, type ReactNode } from 'react';
import { Scene } from '../Scene';
import type { SceneType } from '../../lib/types';
import { ErrorBoundary } from '../../ui';
import { homeLight } from '../home3d/engine/light';
import { webglAvailable } from '../city3d/model';
import type { PlaceApi, PlaceSceneProps } from './engine/PlaceScene';

const PlaceScene = lazy(() => import('./engine/PlaceScene'));

export interface PlaceViewProps extends Omit<PlaceSceneProps, 'onReady' | 'onLost'> {
  suspended?: boolean;
  fallbackScene: SceneType;
  fallbackAction?: ReactNode;
}

let glOk: boolean | null = null;

export function PlaceView({ suspended, fallbackScene, fallbackAction, ...props }: PlaceViewProps) {
  const api = useRef<PlaceApi | null>(null);
  const [still, setStill] = useState<string | null>(null);
  const [live, setLive] = useState(!suspended);
  const [lost, setLost] = useState(() => {
    glOk ??= webglAvailable();
    return !glOk;
  });
  const night = props.hour >= 19 || props.hour < 6;
  const bg = homeLight(props.hour).bg;

  useLayoutEffect(() => {
    if (suspended && live) {
      setStill(api.current?.snapshot() ?? null);
      api.current = null;
      setLive(false);
    } else if (!suspended && !live) setLive(true);
  }, [suspended, live]);

  const onReady = useCallback((a: PlaceApi) => {
    api.current = a;
    window.setTimeout(() => setStill(null), 120);
  }, []);

  const fallback = (
    <div className="place3d place3d--fallback">
      <div className="home3d__svg"><Scene type={fallbackScene} night={night} /></div>
      {fallbackAction}
    </div>
  );
  if (lost) return fallback;

  return (
    <div className="home-view place-view" style={{ background: bg }}>
      {live && (
        <ErrorBoundary fallback={fallback}>
          <Suspense fallback={<div className="home3d home3d--loading"><span className="home3d__loader" aria-label="Loading the place" /></div>}>
            <PlaceScene {...props} onReady={onReady} onLost={() => setLost(true)} />
          </Suspense>
        </ErrorBoundary>
      )}
      {still && <img className="home-view__still" src={still} alt="" aria-hidden />}
    </div>
  );
}
