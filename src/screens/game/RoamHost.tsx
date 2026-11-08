// Mounts free roam over the game (docs/ROAM.md). Free roam is opt-in: nothing here runs until the player taps "Step outside" /
// "Walk the city". The server owns where you are: roam_start records the walk, roam_enter moves you into a place after a believable
// walk. Coming out of a place into the street puts you at its door; "Leave" returns to the normal map.
import { lazy, Suspense, useCallback, useEffect, useMemo, useRef } from 'react';
import { roamEnter, roamLeave, roamStart } from '../../api/roam';
import { webglAvailable } from '../../art/city3d/model';
import { placeInRoam, roamCfg } from '../../art/roam3d/access';
import { errorMessage, GameError } from '../../lib/api';
import { useConfig } from '../../lib/config';
import type { AvatarConfig, GameState } from '../../lib/types';
import { useGame } from '../../state/game';
import { useUi } from '../../state/ui';
import { toast } from '../../ui';

const RoamView = lazy(() => import('../../art/roam3d/RoamView'));

/** Start the street walk at the place you are at (calls the server, then opens the view). Returns false when refused. */
export async function startRoam(placeId: string): Promise<boolean> {
  if (!webglAvailable()) {
    toast('Walking the city needs 3D, which this phone does not support.', 'info');
    return false;
  }
  try {
    await roamStart(placeId);
    useUi.getState().openRoam(placeId);
    return true;
  } catch (e) {
    toast(errorMessage(e), 'bad');
    return false;
  }
}

export function RoamHost({ state, hour, avatar }: { state: GameState; hour: number; avatar: AvatarConfig | null }) {
  const roam = useUi((s) => s.roam);
  const pending = useUi((s) => s.roamPending);
  const closeRoam = useUi((s) => s.closeRoam);
  const setMapOpen = useUi((s) => s.setMapOpen);
  const closeAll = useUi((s) => s.closeAll);
  const locations = useGame((s) => s.locations);
  const refresh = useGame((s) => s.refresh);
  const { cfg } = useConfig();
  const rc = roamCfg(cfg);
  const here = state.travel ? null : state.profile.location_id;

  // "Go to King's Square to walk": once the trip ends at that place, step out
  const started = useRef<string | null>(null);
  useEffect(() => {
    if (!pending || roam) return;
    if (Date.now() - pending.at > 20 * 60_000) { useUi.getState().setRoamPending(null); return; }
    if (state.travel) {
      if (state.travel.to !== pending.place) useUi.getState().setRoamPending(null);
      return;
    }
    if (here === pending.place && started.current !== `${pending.place}@${pending.at}`) {
      started.current = `${pending.place}@${pending.at}`;
      void startRoam(pending.place).then((ok) => { if (!ok) useUi.getState().setRoamPending(null); });
    }
  }, [pending, roam, state.travel, here]);

  // the game moved us under the street (a trip, a hospital stay, another device): close the walk
  useEffect(() => {
    if (roam && (state.travel || (here && here !== roam.place && !startedByUs.current.has(here)))) {
      closeRoam();
      void roamLeave().catch(() => undefined);
    }
  }, [roam, state.travel, here, closeRoam]);

  const places = useMemo(
    () => locations.filter((l) => placeInRoam(l, rc)).map((l) => ({ id: l.id, name: l.name, scene: l.scene, x: Number(l.x), y: Number(l.y) })),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [locations, rc.enabled, rc.box.x0, rc.box.y0, rc.box.x1, rc.box.y1],
  );

  const onGoIn = useCallback(
    async (placeId: string): Promise<string | void> => {
      try {
        let r = await roamEnter(placeId).catch(async (e) => {
          // the walk timed out or was reset on the server: start it again quietly and retry once
          if (e instanceof GameError && e.hint === 'no_session') {
            await roamStart(useGame.getState().state?.profile.location_id ?? roam?.place ?? placeId);
            return roamEnter(placeId);
          }
          throw e;
        });
        // "here" = the place you stepped out of: nothing to move, just go back in
        if (!r.ok && r.hint === 'here') r = { ...r, ok: true };
        if (!r.ok) return r.message;
        startedByUs.current.add(placeId);
        await refresh();
        closeRoam();
        closeAll();
        setMapOpen(false);
        window.setTimeout(() => startedByUs.current.delete(placeId), 4000);
      } catch (e) {
        if (e instanceof GameError && e.hint === 'no_session') {
          closeRoam();
          setMapOpen(true);
          toast('Your walk timed out. Step out again when you are ready.', 'info');
          return;
        }
        return errorMessage(e);
      }
    },
    [refresh, closeRoam, closeAll, setMapOpen, roam?.place],
  );
  const onLeave = useCallback(() => {
    closeRoam();
    setMapOpen(true);
    void roamLeave().catch(() => undefined);
  }, [closeRoam, setMapOpen]);

  if (!roam) return null;
  return (
    <Suspense fallback={null}>
      <RoamView
        places={places}
        startId={roam.place}
        avatar={avatar}
        hour={hour}
        onGoIn={onGoIn}
        onLeave={onLeave}
        onLost={() => {
          closeRoam();
          void roamLeave().catch(() => undefined);
          toast('The street view could not start on this phone.', 'info');
        }}
      />
    </Suspense>
  );
}

// places we moved into ourselves a moment ago (so the "location changed under us" check does not close our own walk-in)
const startedByUs = { current: new Set<string>() };
