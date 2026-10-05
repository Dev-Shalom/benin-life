// R5: the dock's Map view. Shows the lazy 3D city by default and steps aside for the Phase 1 2D map
// only when it must: extremely weak connection or Data Saver (navigator.connection), the player's
// "Lite map for weak network" setting, no WebGL, or the GPU dropping the 3D context.
// `suspended` unmounts the canvas (so another 3D view is the only WebGL canvas on screen) and shows a
// still frame of the city until it comes back.
import { lazy, Suspense, useCallback, useLayoutEffect, useMemo, useRef, useState } from 'react';
import { isSlowNetwork, usePrefs } from '../../lib/prefs';
import { ErrorBoundary } from '../../ui';
import type { BeninMapProps } from '../map/BeninMap';
import type { CityApi, CitySceneProps } from './engine/CityScene';
import { webglAvailable } from './model';

const CityScene = lazy(() => import('./engine/CityScene'));
const BeninMap = lazy(() => import('../map/BeninMap').then((m) => ({ default: m.BeninMap })));

export interface CityViewProps extends Omit<CitySceneProps, 'onReady' | 'onLost'> {
  night: boolean;
  /** Unmount the canvas and show a still frame instead. */
  suspended?: boolean;
}

type LiteReason = 'nowebgl' | 'lost' | 'pref' | 'network';

/** The player tapped "Use 3D" on a weak network: keep 3D for the rest of the session. */
let force3dSession = false;
let webglCache: boolean | null = null;

export function CityView({ suspended, night, ...props }: CityViewProps) {
  const liteMap = usePrefs((s) => s.liteMap);
  const setPrefs = usePrefs((s) => s.set);
  const [force3d, setForce3d] = useState(force3dSession);
  const [lost, setLost] = useState(false);
  const webgl = useMemo(() => (webglCache ??= webglAvailable()), []);
  const slow = useMemo(() => isSlowNetwork(), []);
  const reason: LiteReason | null = !webgl ? 'nowebgl' : lost ? 'lost' : liteMap ? 'pref' : slow && !force3d ? 'network' : null;

  const api = useRef<CityApi | null>(null);
  const [still, setStill] = useState<string | null>(null);
  const [live, setLive] = useState(!suspended);
  useLayoutEffect(() => {
    if (suspended && live) {
      setStill(api.current?.snapshot() ?? null);
      api.current = null;
      setLive(false);
    } else if (!suspended && !live) {
      setLive(true);
    }
  }, [suspended, live]);
  const onReady = useCallback((a: CityApi) => {
    api.current = a;
    window.setTimeout(() => setStill(null), 120);
  }, []);

  const lite = (r: LiteReason) => {
    const mapProps: BeninMapProps = {
      locations: props.locations,
      currentId: props.currentId,
      selectedId: props.selectedId,
      onSelect: props.onSelect,
      night,
      travel: props.travel,
      crowd: props.crowd,
    };
    const use3d = () => {
      if (r === 'lost') setLost(false);
      else if (r === 'pref') setPrefs({ liteMap: false });
      else {
        force3dSession = true;
        setForce3d(true);
      }
    };
    return (
      <div className="city-view city-view--lite">
        <Suspense fallback={<div className="city-view__loading"><span className="home3d__loader" aria-label="Loading the map" /></div>}>
          <BeninMap {...mapProps} />
        </Suspense>
        <div className="lite-badge" role="status">
          <span className="lite-badge__tag"><span aria-hidden>🪶</span> Lite map</span>
          {r === 'nowebgl' ? (
            <span className="lite-badge__note">3D isn't supported on this device</span>
          ) : (
            <button type="button" className="lite-badge__btn" onClick={use3d}>
              {r === 'lost' ? 'Retry 3D' : 'Switch to 3D'}
            </button>
          )}
        </div>
      </div>
    );
  };

  if (reason) return lite(reason);

  return (
    <div className="city-view">
      {live && (
        <ErrorBoundary fallback={lite('lost')}>
          <Suspense fallback={<div className="city-view__loading"><span className="home3d__loader" aria-label="Loading the city" /></div>}>
            <CityScene {...props} className={night ? 'is-night' : undefined} onReady={onReady} onLost={() => setLost(true)} />
          </Suspense>
        </ErrorBoundary>
      )}
      {still && <img className="city-view__still" src={still} alt="" aria-hidden />}
    </div>
  );
}
