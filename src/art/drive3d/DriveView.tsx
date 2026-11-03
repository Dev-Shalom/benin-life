// The drive scene: a short 3D drive along the real roads while a trip runs (docs/DRIVE.md).
// This file is the UI layer and the road-event flow; the 3D itself is the lazy chunk engine/DriveScene.tsx.
// Layout rule: nothing covers the road. Top-left: the route chip. Top-right: camera, horn, map. Bottom: only the event
// card (when something happens), the outcome line, the arrival card, and two small links (Turn back, Skip).
import { lazy, Suspense, useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { driveEventChoose, driveEventRoll, driveTurnBack, type DriveEvent, type DriveOutcome } from '../../api/drive';
import { errorMessage } from '../../lib/api';
import { serverNow } from '../../lib/clock';
import { useConfig } from '../../lib/config';
import { naira } from '../../lib/format';
import { Button, ErrorBoundary, Icon, Spinner, toast } from '../../ui';
import { useDrive } from '../../state/drive';
import { useGame } from '../../state/game';
import { useTier } from '../feel/quality';
import { honk } from './horn';
import { CAMS, CAM_LABEL, clock, roadAt, roadKey, vehicleFor, type CamMode } from './model';
import { MiniMap } from './MiniMap';
import type { Track } from './track';
import type { DriveApi, DriveLive } from './engine/DriveScene';
import { useDriveOthers } from './useOthers';
import './drive3d.css';

const DriveScene = lazy(() => import('./engine/DriveScene'));

export interface DriveTrip {
  key: string;
  fromName: string;
  toName: string;
  toScene: string;
  toId: string;
  toX: number;
  toY: number;
  mode: string;
  startedAt: number;
  arrivesAt: number;
  vehicleId: string | null;
  /** The real route: roads, turns, roundabout, timing (./track.ts). */
  track: Track;
}

export interface DriveViewProps {
  trip: DriveTrip;
  arrived: boolean;
  hour: number;
  me: { id: string; name: string };
  onGoIn: () => void;
  onSkip: () => void;
  onTurnBack: () => void;
  onMap: () => void;
  onLost?: () => void;
  /** Dev lab / screenshots: no RPCs; show this event after a moment and answer it locally. */
  demo?: { event?: DriveEvent; startS?: number; stopped?: boolean; cam?: CamMode; others?: boolean };
}

const KIND_ICON: Record<string, string> = { ambush: 'warning', police: 'shield', goslow: 'road', beggar: 'people' };
const KIND_TAG: Record<string, string> = { ambush: 'Road trouble', police: 'Checkpoint', goslow: 'Traffic', beggar: 'Roadside' };

function loadCam(): CamMode {
  try {
    const v = localStorage.getItem('bl.drive.cam');
    if (v === 'chase' || v === 'side' || v === 'inside') return v;
  } catch {
    /* storage blocked */
  }
  return 'chase';
}

export function DriveView({ trip, arrived, hour, me, onGoIn, onSkip, onTurnBack, onMap, onLost, demo }: DriveViewProps) {
  const { cfg } = useConfig();
  const tier = useTier();
  const [cam, setCam] = useState<CamMode>(demo?.cam ?? loadCam());
  const [ready, setReady] = useState(false);
  const [left, setLeft] = useState(() => Math.max(0, (trip.arrivesAt - serverNow()) / 1000));
  const [progress, setProgress] = useState(0);
  const [carS, setCarS] = useState(0);
  const [carV, setCarV] = useState(0);
  const [stopName, setStopName] = useState<string | null>(null);
  const [miniOpen, setMiniOpen] = useState(false);
  const live = useRef<DriveLive>({ progress: 0, left: 0, arrived });
  const tripRef = useRef(trip);
  tripRef.current = trip;
  const arrivedRef = useRef(arrived);
  arrivedRef.current = arrived;

  // event flow
  const [event, setEvent] = useState<{ id: number; kind: DriveEvent['kind']; ev: DriveEvent } | null>(null);
  const [card, setCard] = useState<DriveEvent | null>(null);
  const [resolved, setResolved] = useState<{ id: number; ok: boolean } | null>(null);
  const [outcome, setOutcome] = useState<DriveOutcome | null>(null);
  const [busy, setBusy] = useState(false);
  const [entering, setEntering] = useState(false);
  const [confirmBack, setConfirmBack] = useState(false);
  const seq = useRef(0);
  const setHold = useDrive((s) => s.setHold);
  const refresh = useGame((s) => s.refresh);

  const vehicle = useMemo(() => vehicleFor(trip.mode, trip.vehicleId, me.id), [trip.mode, trip.vehicleId, me.id]);
  const road = roadKey(trip.track.roads);
  const presenceOn = Boolean(cfg('drive.presence_on', true)) && !demo;
  const others = useDriveOthers(road, me, vehicle, presenceOn);
  const demoOthers = useMemo(
    () =>
      demo?.others
        ? [
            { id: 'd1', name: 'Osas_K', look: vehicleFor('car', 'camry_new', 'd1') },
            { id: 'd2', name: 'Tonye', look: vehicleFor('car', 'lexus_rx350', 'd2') },
            { id: 'd3', name: 'Efe_B', look: vehicleFor('car', 'hilux_new', 'd3') },
          ]
        : [],
    [demo?.others],
  );
  const shownOthers = demo ? demoOthers : others;

  // clock: progress and time left from the server clock; the scene reads the ref
  useEffect(() => {
    const tick = () => {
      const t = tripRef.current;
      const now = serverNow();
      const total = Math.max(1, t.arrivesAt - t.startedAt);
      const p = Math.min(1, Math.max(0, (now - t.startedAt) / total));
      const l = Math.max(0, (t.arrivesAt - now) / 1000);
      live.current = { ...live.current, progress: arrivedRef.current ? 1 : p, left: arrivedRef.current ? 0 : l, arrived: arrivedRef.current };
      setProgress(p);
      setLeft(l);
      const lv = live.current;
      setCarS(lv.s ?? 0);
      setCarV(lv.v ?? 0);
      setStopName(lv.stop ?? null);
    };
    tick();
    const id = window.setInterval(tick, 250);
    return () => window.clearInterval(id);
  }, []);
  useEffect(() => {
    live.current = { ...live.current, arrived };
    if (arrived) {
      setHold(false);
      setConfirmBack(false);
    }
  }, [arrived, setHold]);
  useEffect(() => () => setHold(false), [setHold]);

  // ask the server for a road event about every 8 s (it applies its own limits). Refs keep the timers stable
  // while this component re-renders every 250 ms.
  const rolling = useRef(false);
  const busyRef = useRef({ event, card, outcome });
  busyRef.current = { event, card, outcome };
  const eventsOn = Boolean(cfg('drive.events_enabled', true));
  const demoEvent = demo?.event ?? null;
  const isDemo = Boolean(demo);
  useEffect(() => {
    if (isDemo) {
      if (!demoEvent) return;
      const id = window.setTimeout(() => {
        const n = ++seq.current;
        setEvent({ id: n, kind: demoEvent.kind, ev: demoEvent });
      }, 900);
      return () => window.clearTimeout(id);
    }
    if (arrived || !eventsOn) return;
    let alive = true;
    const roll = async () => {
      const b = busyRef.current;
      if (!alive || rolling.current || b.event || b.card || b.outcome || arrivedRef.current || document.hidden) return;
      const l = live.current;
      if (l.progress < 0.1 || l.progress > 0.88 || l.left < 3) return;
      rolling.current = true;
      try {
        const r = await driveEventRoll();
        if (!alive || !r.event || arrivedRef.current) return;
        setHold(true);
        const n = ++seq.current;
        setEvent({ id: n, kind: r.event.kind, ev: r.event });
      } catch {
        /* old server, offline, or limits: just keep driving */
      } finally {
        rolling.current = false;
      }
    };
    const first = window.setTimeout(roll, 3500);
    const id = window.setInterval(roll, 8000);
    return () => {
      alive = false;
      window.clearTimeout(first);
      window.clearInterval(id);
    };
  }, [arrived, eventsOn, isDemo, demoEvent, setHold]);

  const onStopped = useCallback(
    (id: number) => {
      setEvent((e) => {
        if (e && e.id === id) setCard(e.ev);
        return e;
      });
    },
    [],
  );

  const choose = async (choiceId: string) => {
    if (!event || busy) return;
    setBusy(true);
    try {
      let o: DriveOutcome;
      if (demo) {
        o = { message: 'You hand over the money. The boys step aside and you drive on.', tone: 'warn', kind: event.kind, choice: choiceId, cash_delta: -9000, delay_s: 0, arrives_at: '' };
      } else {
        o = await driveEventChoose(choiceId);
      }
      setOutcome(o);
      setResolved({ id: event.id, ok: o.tone !== 'bad' });
      setCard(null);
      setHold(false);
      if (!demo) void refresh();
      window.setTimeout(() => {
        setOutcome(null);
        setEvent(null);
        setResolved(null);
      }, 4200);
    } catch (e) {
      toast(errorMessage(e), 'bad');
      setCard(null);
      setResolved({ id: event.id, ok: true });
      setHold(false);
      window.setTimeout(() => {
        setEvent(null);
        setResolved(null);
      }, 1500);
    } finally {
      setBusy(false);
    }
  };

  const turnBack = async () => {
    if (!confirmBack) {
      setConfirmBack(true);
      window.setTimeout(() => setConfirmBack(false), 3000);
      return;
    }
    try {
      const r = await driveTurnBack();
      toast(r.message, 'good');
      setHold(false);
      await refresh();
      onTurnBack();
    } catch (e) {
      toast(errorMessage(e), 'bad');
      setConfirmBack(false);
    }
  };

  const cycleCam = () => {
    const next = CAMS[(CAMS.indexOf(cam) + 1) % CAMS.length];
    setCam(next);
    try {
      localStorage.setItem('bl.drive.cam', next);
    } catch {
      /* storage blocked */
    }
  };

  const goIn = () => {
    setEntering(true);
    window.setTimeout(onGoIn, 1100);
  };

  const seg = roadAt(trip.track.roads, Math.min(1, carS / Math.max(1, trip.track.L)));
  const camLabel = cam === 'inside' && vehicle.kind === 'bus' ? 'Seat' : CAM_LABEL[cam];
  const showBottomLinks = !card && !outcome && !arrived && !event;
  const camIcon = cam === 'inside' ? 'eye' : 'camera';

  return (
    <div className="drive" role="dialog" aria-label="Driving">
      <ErrorBoundary fallback={<div className="drive__fail">The drive scene could not start.</div>}>
        <Suspense fallback={null}>
          <DriveScene
            hour={hour}
            tier={tier}
            vehicle={vehicle}
            cam={cam}
            track={trip.track}
            dest={{ id: trip.toId, name: trip.toName, scene: trip.toScene, x: trip.toX, y: trip.toY }}
            live={live}
            event={event ? { id: event.id, kind: event.kind } : null}
            resolved={resolved}
            entering={entering}
            others={tier === 'low' ? shownOthers.slice(0, 4) : shownOthers}
            startAt={demo ? { s: demo.startS, stopped: demo.stopped } : undefined}
            onStopped={onStopped}
            onReady={(api: DriveApi) => {
              setReady(true);
              if (import.meta.env.DEV) (window as unknown as { __drive?: DriveApi }).__drive = api;
            }}
            onLost={onLost}
          />
        </Suspense>
      </ErrorBoundary>
      {!ready && (
        <div className="drive__loading">
          <Spinner size={22} />
          <span>Starting the engine…</span>
        </div>
      )}

      <div className="drive-speed" style={{ ['--sp' as string]: String(Math.max(0, Math.min(0.5, (carV - 10) / 14))) }} aria-hidden="true" />
      <div className="drive__top">
        <div className="drive__left">
        <div className="drive-chip" aria-live="off">
          <div className="drive-chip__route">
            <span>{trip.fromName}</span>
            <Icon name="chevronRight" size={12} />
            <span>{trip.toName}</span>
          </div>
          <div className="drive-chip__sub">
            <span className="drive-chip__road">{arrived ? 'Arrived' : stopName ? `Bus stop · ${stopName.replace(/ Stop$/, '')}` : seg.name}</span>
            {!arrived && <span className="drive-chip__time">{clock(left)}</span>}
          </div>
          <div className="drive-chip__bar" aria-hidden="true">
            <i style={{ width: `${Math.round((arrived ? 1 : progress) * 100)}%` }} />
          </div>
        </div>
        <MiniMap track={trip.track} s={arrived ? trip.track.L : carS} open={miniOpen} onToggle={() => setMiniOpen((o) => !o)} fromName={trip.fromName} toName={trip.toName} />
        </div>
        <div className="drive__ctrls">
          <button type="button" className="drive-btn drive-btn--cam" onClick={cycleCam} aria-label={`Camera: ${camLabel}. Tap to change`}>
            <Icon name={camIcon} size={18} />
            <span>{camLabel}</span>
          </button>
          <button type="button" className="drive-btn drive-btn--round" onClick={honk} aria-label="Horn">
            <Icon name="horn" size={20} />
          </button>
          <button type="button" className="drive-btn drive-btn--round" onClick={onMap} aria-label="Open the map">
            <Icon name="map" size={20} />
          </button>
        </div>
      </div>

      {showBottomLinks && (
        <div className="drive__links">
          {cfg('drive.turn_back_on', true) && !demo ? (
            <button type="button" className={`drive-link${confirmBack ? ' is-warn' : ''}`} onClick={turnBack}>
              {confirmBack ? 'Tap again to turn back' : 'Turn back'}
            </button>
          ) : (
            <span />
          )}
          <button type="button" className="drive-link" onClick={onSkip}>
            Skip
          </button>
        </div>
      )}

      {card && (
        <div className={`drive-card drive-card--${card.kind}`} role="alertdialog" aria-label={card.title}>
          <div className="drive-card__head">
            <span className="drive-card__icon">
              <Icon name={KIND_ICON[card.kind] ?? 'warning'} size={18} />
            </span>
            <div>
              <div className="drive-card__tag">{KIND_TAG[card.kind]}</div>
              <div className="drive-card__title">{card.title}</div>
            </div>
          </div>
          <p className="drive-card__body">{card.body}</p>
          <div className="drive-card__choices">
            {card.choices.map((c, i) => (
              <button key={c.id} type="button" className={`drive-choice${i === 0 ? ' is-first' : ''}`} disabled={busy} onClick={() => choose(c.id)}>
                <span className="drive-choice__label">{c.label}</span>
                {c.hint && <span className="drive-choice__hint">{c.hint}</span>}
              </button>
            ))}
          </div>
        </div>
      )}

      {outcome && (
        <div className={`drive-outcome drive-outcome--${outcome.tone}`} role="status">
          <span>{outcome.message}</span>
          {outcome.cash_delta !== 0 && <b>{outcome.cash_delta < 0 ? '−' : '+'}{naira(Math.abs(outcome.cash_delta))}</b>}
          {outcome.delay_s !== 0 && <b>{outcome.delay_s > 0 ? `+${outcome.delay_s}s` : `${outcome.delay_s}s`}</b>}
        </div>
      )}

      {arrived && !entering && (
        <div className="drive-card drive-card--arrive" role="alertdialog" aria-label="Arrived">
          <div className="drive-card__tag">You have arrived</div>
          <div className="drive-card__title">{trip.toName}</div>
          <Button block size="lg" onClick={goIn}>
            Go in
          </Button>
        </div>
      )}
    </div>
  );
}

export default DriveView;
