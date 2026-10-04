import { useEffect, useRef } from 'react';
import { BeninMap } from '../art/map/BeninMap';
import { useGameClock } from '../lib/clock';
import { randomGreeting } from '../lib/pidgin';
import { useGame } from '../state/game';
import { useUi } from '../state/ui';
import { Icon, LoadingScreen, toast } from '../ui';
import { Hud } from './game/Hud';
import { LocationSheet } from './game/LocationSheet';
import { AlertsSheet, SettingsSheet } from './game/Overlays';
import { GlobalPanelSheet } from './game/PanelHost';
import { StatusBanners } from './game/StatusBanners';
import { deriveStatus } from './game/status';

function useNightTheme(night: boolean) {
  useEffect(() => {
    const root = document.documentElement;
    root.dataset.theme = night ? 'night' : 'day';
    document.querySelector('meta[name="theme-color"]')?.setAttribute('content', night ? '#0e1028' : '#7c3216');
  }, [night]);
  useEffect(
    () => () => {
      delete document.documentElement.dataset.theme;
    },
    [],
  );
}

export default function Game() {
  const state = useGame((s) => s.state);
  const locations = useGame((s) => s.locations);
  const byId = useGame((s) => s.locationsById);
  const selectedId = useUi((s) => s.selectedId);
  const select = useUi((s) => s.select);
  const { clock, now } = useGameClock(1000);
  const greeted = useRef(false);

  useNightTheme(clock.is_night);

  useEffect(() => {
    if (state && !greeted.current) {
      greeted.current = true;
      toast(randomGreeting(state.profile.username), 'info');
    }
  }, [state]);

  if (!state) return <LoadingScreen />;

  const status = deriveStatus(state, now);
  const here = byId[state.location.id] ?? state.location;
  const travel = state.travel
    ? { from: state.profile.location_id || state.location.id, to: state.travel.to, progress: status.travelProgress }
    : null;

  return (
    <div className={`game${clock.is_night ? ' is-night' : ''}`}>
      <div className="game__map">
        <BeninMap
          locations={locations.length ? locations : [state.location]}
          currentId={state.travel ? undefined : state.location.id}
          selectedId={selectedId ?? undefined}
          onSelect={(id) => select(id)}
          night={clock.is_night}
          travel={travel}
        />
      </div>

      <Hud state={state} clock={clock} status={status} />

      <div className="game__bottom">
        <StatusBanners state={state} status={status} />
        {!state.travel && (
          <button type="button" className="where-chip" onClick={() => select(here.id)}>
            <span className="where-chip__dot" />
            <span className="grow">
              <span className="where-chip__label">You dey</span>
              <span className="where-chip__name">{here.name}</span>
            </span>
            <span className="where-chip__go">Open <Icon name="chevronUp" size={14} /></span>
          </button>
        )}
      </div>

      <LocationSheet state={state} status={status} night={clock.is_night} />
      <GlobalPanelSheet />
      <AlertsSheet />
      <SettingsSheet />
    </div>
  );
}
