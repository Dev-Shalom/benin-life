// Game screen (R4): the 3D home when the player is at home, otherwise the city map (2D until R5).
// HUD: top pill, left rail, needs card, dock (Home · Buy · Map · Phone), status banners, toasts.
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { HomeView, activityGroup, homeLayoutFor, itemGroup, type FurnitureItem } from '../art/home3d';
import { BeninMap } from '../art/map/BeninMap';
import { useGameClock } from '../lib/clock';
import { randomGreeting } from '../lib/pidgin';
import { usePrefs } from '../lib/prefs';
import { useCatalog } from '../state/catalog';
import { useGame } from '../state/game';
import { useUi } from '../state/ui';
import { Icon, LoadingScreen, toast } from '../ui';
import { BuySheet, ShortcutsSheet } from './game/Extras';
import { useGameShortcuts } from './game/shortcuts';
import { HomeSheet } from './game/HomeSheet';
import { Dock, KeyboardButton, LeftRail, NeedsCard, TopPill, type DockId } from './game/Hud';
import { LocationSheet } from './game/LocationSheet';
import { AlertsSheet } from './game/Overlays';
import { GlobalPanelSheet } from './game/PanelHost';
import { Phone } from './game/Phone';
import { LookSheet, SimSheet } from './game/SimSheet';
import { StatusBanners } from './game/StatusBanners';
import { deriveStatus } from './game/status';

function useNightTheme(night: boolean) {
  useEffect(() => {
    const root = document.documentElement;
    root.dataset.theme = night ? 'night' : 'day';
    document.querySelector('meta[name="theme-color"]')?.setAttribute('content', night ? '#1d2542' : '#e4f0fa');
  }, [night]);
  useEffect(
    () => () => {
      delete document.documentElement.dataset.theme;
    },
    [],
  );
}

/** Space the HUD covers at the top and bottom (for framing the 3D home between them). */
function useInsets() {
  const [w, setW] = useState(() => window.innerWidth);
  useEffect(() => {
    const on = () => setW(window.innerWidth);
    window.addEventListener('resize', on);
    return () => window.removeEventListener('resize', on);
  }, []);
  return w >= 900 ? { top: 84, bottom: 108 } : { top: 128, bottom: 176 };
}

export default function Game() {
  const state = useGame((s) => s.state);
  const locations = useGame((s) => s.locations);
  const byId = useGame((s) => s.locationsById);
  const unread = useGame((s) => s.unread);
  const selectedId = useUi((s) => s.selectedId);
  const select = useUi((s) => s.select);
  const overlay = useUi((s) => s.overlay);
  const setOverlay = useUi((s) => s.setOverlay);
  const simTab = useUi((s) => s.simTab);
  const openSim = useUi((s) => s.openSim);
  const openPhone = useUi((s) => s.openPhone);
  const mapOpen = useUi((s) => s.mapOpen);
  const setMapOpen = useUi((s) => s.setMapOpen);
  const homePick = useUi((s) => s.homePick);
  const pickHome = useUi((s) => s.pickHome);
  const closeAll = useUi((s) => s.closeAll);
  const panel = useUi((s) => s.panel);
  const clean = usePrefs((s) => s.clean);
  const activities = useCatalog((s) => s.activities);
  const loadActivities = useCatalog((s) => s.loadActivities);
  const { clock, now } = useGameClock(1000);
  const greeted = useRef(false);
  const insets = useInsets();

  useNightTheme(clock.is_night);

  useEffect(() => {
    void loadActivities();
  }, [loadActivities]);

  useEffect(() => {
    if (state && !greeted.current) {
      greeted.current = true;
      toast(randomGreeting(state.profile.username), 'info');
    }
  }, [state]);

  const p = state?.profile;
  const atHome = Boolean(p && !state?.travel && p.location_id === p.home_location_id);
  const showHome = atHome && !mapOpen;

  // Coming back home switches to the home view.
  const wasHome = useRef(atHome);
  useEffect(() => {
    if (atHome && !wasHome.current) setMapOpen(false);
    wasHome.current = atHome;
  }, [atHome, setMapOpen]);

  // The home activity running now -> which furniture the Sim goes to.
  const busyUntil = p?.busy_until ?? null;
  const busyLabel = p?.busy_label ?? null;
  const busyActive = Boolean(busyUntil && Date.parse(busyUntil) > now);
  const busyGroup = useMemo(() => {
    if (!busyUntil || !busyLabel || !busyActive) return null;
    const a = activities?.find((x) => x.name === busyLabel && x.home_only);
    return a ? { group: activityGroup(a.id), key: busyUntil } : null;
  }, [busyUntil, busyLabel, busyActive, activities]);

  const goHome = useCallback(() => {
    if (!p) return;
    closeAll();
    if (atHome) setMapOpen(false);
    else {
      setMapOpen(true);
      select(p.home_location_id);
    }
  }, [p, atHome, closeAll, setMapOpen, select]);

  const onDock = useCallback(
    (id: DockId) => {
      if (id === 'home') goHome();
      else if (id === 'map') {
        closeAll();
        setMapOpen(true);
      } else if (id === 'buy') setOverlay(overlay === 'buy' ? null : 'buy');
      else if (overlay === 'phone') setOverlay(null);
      else openPhone();
    },
    [goHome, closeAll, setMapOpen, setOverlay, overlay, openPhone],
  );

  useGameShortcuts({
    map: () => onDock('map'),
    home: () => onDock('home'),
    buy: () => onDock('buy'),
    phone: () => onDock('phone'),
    sheet: () => (overlay === 'sim' ? setOverlay(null) : openSim('needs')),
    things: () => p && select(selectedId ? null : p.location_id),
    people: () => p && select(selectedId ? null : p.location_id),
    help: () => setOverlay(overlay === 'shortcuts' ? null : 'shortcuts'),
  });

  const onPick = useCallback(
    (f: FurnitureItem) => {
      const g = itemGroup(f);
      if (g) pickHome({ id: f.id, group: g });
    },
    [pickHome],
  );

  if (!state || !p) return <LoadingScreen />;

  const status = deriveStatus(state, now);
  const here = byId[state.location.id] ?? state.location;
  const travel = state.travel
    ? { from: p.location_id || state.location.id, to: state.travel.to, progress: status.travelProgress }
    : null;
  // Another live 3D view is open (Sim sheet turntable / look editor): the home canvas steps aside.
  const suspendHome = (overlay === 'sim' && simTab === 'profile') || overlay === 'look';
  const coveredHome = Boolean(selectedId || panel || homePick || (overlay && !suspendHome));
  const layout = homeLayoutFor(p.housing_id, here.scene);
  const dockActive: DockId | null = overlay === 'phone' ? 'phone' : overlay === 'buy' ? 'buy' : showHome ? 'home' : 'map';
  const hourF = clock.hour + clock.minute / 60;

  return (
    <div className={`game${clock.is_night ? ' is-night' : ''}${clean ? ' is-clean' : ''}${showHome ? ' is-home' : ' is-map'}`}>
      <div className="game__map">
        {showHome ? (
          <HomeView
            layoutId={layout}
            avatar={p.avatar}
            busy={busyGroup}
            hour={hourF}
            suspended={suspendHome}
            paused={coveredHome}
            selectedId={homePick?.id ?? null}
            onPick={onPick}
            insetTop={clean ? 70 : insets.top}
            insetBottom={clean ? 40 : insets.bottom}
            fallbackScene={here.scene}
            fallbackAction={
              <button type="button" className="where-chip home3d__fallback-btn" onClick={() => select(here.id)}>
                <span className="grow"><span className="where-chip__name">Things to do at home</span></span>
                <Icon name="chevronUp" size={14} />
              </button>
            }
          />
        ) : (
          <BeninMap
            locations={locations.length ? locations : [state.location]}
            currentId={state.travel ? undefined : state.location.id}
            selectedId={selectedId ?? undefined}
            onSelect={(id) => select(id)}
            night={clock.is_night}
            travel={travel}
          />
        )}
      </div>

      {!clean && <TopPill state={state} clock={clock} />}
      <LeftRail state={state} status={status} atHome={atHome} />

      <div className="game__bottom">
        <div className="game__banners">
          <StatusBanners state={state} status={status} />
          {!clean && !state.travel && !showHome && (
            <button type="button" className="where-chip" onClick={() => select(here.id)}>
              <span className="where-chip__dot" />
              <span className="grow">
                <span className="where-chip__label">You're at</span>
                <span className="where-chip__name">{atHome ? 'Home' : here.name}</span>
              </span>
              <span className="where-chip__go">Open <Icon name="chevronUp" size={14} /></span>
            </button>
          )}
          {!clean && showHome && status.free && (
            <button type="button" className="home-chip" onClick={() => select(here.id)}>
              <span aria-hidden>🏠</span> {here.name.replace(/ \(.*\)$/, '')}
              <span className="home-chip__go">Things to do <Icon name="chevronUp" size={13} /></span>
            </button>
          )}
        </div>
        {!clean && (
          <div className="game__dockrow">
            <NeedsCard state={state} />
            <Dock active={dockActive} unread={unread} onPick={onDock} />
            <KeyboardButton onClick={() => setOverlay('shortcuts')} />
          </div>
        )}
      </div>

      <LocationSheet state={state} status={status} night={clock.is_night} />
      <HomeSheet state={state} status={status} />
      <GlobalPanelSheet />
      <AlertsSheet />
      <SimSheet state={state} />
      <LookSheet state={state} />
      <BuySheet />
      <ShortcutsSheet />
      <Phone state={state} clock={clock} />
    </div>
  );
}
