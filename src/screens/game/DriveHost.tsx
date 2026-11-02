// Mounts the 3D drive over the game while a trip runs (docs/DRIVE.md). The server owns the trip (travel_start /
// travel_arrive); this only decides whether to show the scene and keeps it on screen for the gate shot after arrival.
// Off when: the player turned it off (Settings), the admin turned it off (drive.enabled), walking, no WebGL, the
// player skipped this trip, or the scene lost its GPU context. Then travel is the old plain flow.
import { lazy, Suspense, useEffect, useMemo, useRef, useState } from 'react';
import { routeRoads } from '../../art/drive3d/model';
import { webglAvailable } from '../../art/city3d/model';
import { useConfig } from '../../lib/config';
import { usePrefs } from '../../lib/prefs';
import type { GameState } from '../../lib/types';
import { useGame } from '../../state/game';
import { usePrimaryCar } from '../../state/primaryCar';
import { useUi } from '../../state/ui';
import { toast } from '../../ui';

const DriveView = lazy(() => import('../../art/drive3d/DriveView'));

interface Session {
  key: string;
  from: string;
  to: string;
  mode: string;
  startedAt: number;
  arrivesAt: number;
}

let glOk: boolean | null = null;

export function DriveHost({ state, hour }: { state: GameState; hour: number }) {
  const { cfg } = useConfig();
  const wanted = usePrefs((s) => s.driveScene);
  const byId = useGame((s) => s.locationsById);
  const setMapOpen = useUi((s) => s.setMapOpen);
  const driving = usePrimaryCar((s) => s.driving);
  const loadCar = usePrimaryCar((s) => s.load);
  const [session, setSession] = useState<Session | null>(null);
  const [arrived, setArrived] = useState(false);
  const skipped = useRef<string | null>(null);
  const [broken, setBroken] = useState(false);
  const travel = state.travel;
  const enabled = wanted && Boolean(cfg('drive.enabled', true)) && !broken && (glOk ??= webglAvailable());
  const origin = state.profile.location_id;

  useEffect(() => {
    if (travel) {
      const key = `${travel.to}@${travel.started_at}`;
      if (!enabled || travel.mode === 'walk' || skipped.current === key) {
        setSession(null);
        return;
      }
      setArrived(false);
      setSession((prev) => ({
        key,
        from: prev?.key === key ? prev.from : origin,
        to: travel.to,
        mode: travel.mode,
        startedAt: Date.parse(travel.started_at),
        arrivesAt: Date.parse(travel.arrives_at),
      }));
    } else if (session && !arrived) {
      setArrived(true); // the server moved us: the gate shot
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [travel?.to, travel?.started_at, travel?.arrives_at, travel?.mode, enabled, origin]);

  useEffect(() => {
    if (session?.mode === 'car') void loadCar();
  }, [session?.mode, loadCar]);

  const from = session ? byId[session.from] : undefined;
  const to = session ? byId[session.to] : undefined;
  const roads = useMemo(() => (from && to ? routeRoads(from, to) : null), [from, to]);
  if (!session || !from || !to || !roads) return null;

  const close = () => {
    setSession(null);
    setArrived(false);
  };
  return (
    <Suspense fallback={null}>
      <DriveView
        trip={{
          key: session.key,
          fromName: from.id.startsWith('home_') ? 'Home' : from.name,
          toName: to.name,
          toScene: to.scene,
          mode: session.mode,
          startedAt: session.startedAt,
          arrivesAt: session.arrivesAt,
          vehicleId: session.mode === 'car' ? driving : null,
          roads,
        }}
        arrived={arrived}
        hour={hour}
        me={{ id: state.profile.id, name: state.profile.username }}
        onGoIn={() => {
          setMapOpen(false);
          close();
        }}
        onSkip={() => {
          skipped.current = session.key;
          close();
          toast('Skipped. You will still arrive on time.', 'good');
        }}
        onTurnBack={() => {
          skipped.current = session.key;
          close();
        }}
        onMap={() => {
          skipped.current = session.key;
          close();
          setMapOpen(true);
        }}
        onLost={() => {
          setBroken(true);
          close();
          toast('The drive view could not start on this phone. Travel goes on as before.', 'info');
        }}
      />
    </Suspense>
  );
}
