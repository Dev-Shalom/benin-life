// Mounts free roam over the game (docs/ROAM.md). Free roam is opt-in: nothing here runs until the player taps "Step outside" /
// "Walk the city". The server owns where you are: roam_start records the walk, roam_enter moves you into a place after a believable
// walk or drive, roam_set_mode / roam_drive_report keep the player's own vehicle honest (fuel, damage), roam_hail_keke starts a normal
// keke trip. Coming out of a place into the street puts you at its door; "Leave" returns to the normal map.
import { lazy, Suspense, useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { roamCarInfo, roamDriveReport, roamDryChoose, roamEnter, roamHailKeke, roamLeave, roamSetMode, roamStart, type RoamCarInfo } from '../../api/roam';
import { webglAvailable } from '../../art/city3d/model';
import { placeInRoam, roamCfg } from '../../art/roam3d/access';
import type { RoamCarCtl, RoamKekeCtl } from '../../art/roam3d/RoamView';
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

const CLASS_KEY: Record<string, string> = { car: 'car', suv: 'suv', pickup: 'pickup', motorcycle: 'motorcycle' };

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

  // "Go to King's Square to walk" / "back to the street after a keke ride": once the trip ends at that place, step out
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

  // every place of the city (closed ones too: the airport stands there with a shut gate)
  const places = useMemo(
    () => locations.filter((l) => rc.all || placeInRoam(l, rc)).map((l) => ({ id: l.id, name: l.name, scene: l.scene, x: Number(l.x), y: Number(l.y), active: l.active !== false, keke_ok: l.keke_ok })),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [locations, rc.enabled, rc.all, rc.box.x0, rc.box.y0, rc.box.x1, rc.box.y1],
  );

  /* ---------------- the player's own vehicle ---------------- */
  const [carInfo, setCarInfo] = useState<RoamCarInfo | null>(null);
  const [carDone, setCarDone] = useState(false);
  const roamKey = roam ? `${roam.place}` : '';
  useEffect(() => {
    if (!roam) { setCarDone(false); setCarInfo(null); return; }
    let live = true;
    roamCarInfo()
      .then((i) => { if (live) setCarInfo(i.enabled ? i : { ...i, has_car: false }); })
      .catch(() => undefined)
      .finally(() => { if (live) setCarDone(true); });
    return () => { live = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [roamKey]);
  const carCtl: RoamCarCtl = useMemo(() => {
    const cls = CLASS_KEY[carInfo?.class ?? 'car'] ?? 'car';
    return {
      info: carInfo,
      fuelPerM: (Number(cfg(`drive.fuel.lpk_${cls}`, 0.11)) * Number(cfg('roam.drive.fuel_scale', 8))) / 1000,
      mechanicCost: Number(cfg('drive.dry.mechanic_cost', 3500)),
      setMode: async (mode, pose) => {
        const r = await roamSetMode(mode, pose);
        if (mode === 'car') setCarInfo((i) => (i ? { ...i, fuel_l: r.fuel_l ?? i.fuel_l, cond: r.cond ?? i.cond, mode: 'car', car_x: null, car_y: null } : i));
        return r;
      },
      report: (s) => roamDriveReport(s),
      dry: (c) => roamDryChoose(c),
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [carInfo, cfg]);
  const kekeCtl: RoamKekeCtl = useMemo(
    () => ({
      enabled: Boolean(cfg('roam.keke.enabled', true)),
      hail: async (dest: string) => {
        try {
          await roamHailKeke(dest);
        } catch (e) {
          return errorMessage(e);
        }
        // the keke trip runs through the normal travel system (and its 3D ride); the street opens again at the destination
        useUi.getState().setRoamPending(dest);
        closeRoam();
        closeAll();
        setMapOpen(false);
        await refresh();
      },
    }),
    [cfg, closeRoam, closeAll, setMapOpen, refresh],
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

  if (!roam || !carDone) return null;
  return (
    <Suspense fallback={null}>
      <RoamView
        places={places}
        startId={roam.place}
        avatar={avatar}
        hour={hour}
        onGoIn={onGoIn}
        onLeave={onLeave}
        car={carCtl}
        keke={kekeCtl}
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
