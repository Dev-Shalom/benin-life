// Game screen (R4/R5): the 3D home when the player is at home, otherwise the 3D city map
// (the 2D map only as the lite fallback, see src/art/city3d/CityView.tsx).
// HUD: top pill, left rail, needs card, dock (Home · Buy · Map · Phone), status banners, toasts.
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { HomeView, LAYOUTS, activityGroup, furnishLayout, homeLayoutFor, itemGroup, type FurnitureItem } from '../art/home3d';
import { CityView } from '../art/city3d';
import { PlaceView, buildPlaceGrid, planCrowd, roomFor } from '../art/place3d';
import { serverNow, useGameClock } from '../lib/clock';
import { devHourOverride, looksNight } from '../lib/daylight';
import { setPlaceTrack, setSoundPlace, setSoundScene, type PlaceSound } from '../lib/sound';
import { useConfig } from '../lib/config';
import { simPosture } from '../lib/mood';
import { randomGreeting } from '../lib/pidgin';
import { usePrefs } from '../lib/prefs';
import { useCatalog } from '../state/catalog';
import { useChat, useChatLive } from '../state/chat';
import { useTier } from '../art/feel/quality';
import { useGame } from '../state/game';
import { usePresenceStore } from '../state/presence';
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
import { useTaskRunner } from './game/TaskRunner';
import { useTasks } from '../state/tasks';
import { PlaceCard, usePlaceInterior, usePlacePeople, usePlayersAt } from './game/PlaceCard';
import { placeClosedEject } from '../api/places';
import { HypeBanner, HypeTicker } from './game/Hype';
import { useHypeLive } from '../state/hype';
import { useEventsLive } from '../state/events';
import { EventBanner, useEventBadges } from './game/Events';

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
  return w >= 900 ? { top: 84, bottom: 108, narrow: false } : { top: 128, bottom: 176, narrow: true };
}

export default function Game() {
  const state = useGame((s) => s.state);
  const locations = useGame((s) => s.locations);
  const byId = useGame((s) => s.locationsById);
  const unread = useGame((s) => s.unread);
  // S3: live player counts per place on the map (Realtime Presence, other players only)
  const presentAt = usePresenceStore((s) => s.at);
  const presenceLive = usePresenceStore((s) => s.online !== null);
  const meId = state?.profile.id;
  const crowd = useMemo(() => {
    if (!presenceLive) return undefined;
    const o: Record<string, number> = {};
    for (const [loc, ids] of Object.entries(presentAt)) {
      const n = ids.filter((id) => id !== meId).length;
      if (n > 0) o[loc] = n;
    }
    return o;
  }, [presentAt, presenceLive, meId]);
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
  const furniture = useCatalog((s) => s.furniture);
  const furnitureOf = useCatalog((s) => s.furnitureOf);
  const loadFurniture = useCatalog((s) => s.loadFurniture);
  const { cfg } = useConfig();
  const { clock, now } = useGameClock(1000);
  const greeted = useRef(false);
  const insets = useInsets();

  // S1: lighting follows real Benin time continuously; the UI theme flips mid-dusk / mid-dawn.
  const hourF = devHourOverride() ?? clock.hour + clock.minute / 60;
  const skyNight = looksNight(hourF);
  useNightTheme(skyNight);
  useEffect(() => {
    setSoundScene(true, skyNight);
  }, [skyNight]);
  useEffect(() => () => { setSoundScene(false, false); setSoundPlace(null); }, []);

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
  const ownedVehicleId = useMemo(
    () => state?.inventory?.filter((item) => item.category === 'vehicle').sort((a, b) => b.price - a.price)[0]?.id ?? null,
    [state?.inventory],
  );
  // the player's own furniture (starter set by origin + home); reloads when the home changes
  const furnKey = p ? `${p.id}:${p.home_location_id}:${p.housing_id ?? ''}` : null;
  const lastFurnKey = useRef<string | null>(null);
  useEffect(() => {
    if (!furnKey || !p) return;
    const force = lastFurnKey.current !== null && lastFurnKey.current !== furnKey;
    lastFurnKey.current = furnKey;
    void loadFurniture(p.id, force);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [furnKey, loadFurniture]);
  const atHome = Boolean(p && !state?.travel && p.location_id === p.home_location_id);
  const showHome = atHome && !mapOpen;
  // L2: anywhere else (not on the road) you are INSIDE the place: its 3D interior + the place card
  const showPlace = Boolean(p && state && !state.travel && !atHome && !mapOpen);
  // V1-6: stay subscribed to the chat of the place you are at (unread dot while the sheet is closed).
  useChatLive(state && !state.travel ? state.location.id : null, p?.id ?? null);
  const chatUnread = useChat((s) => s.unread);
  // L3: the last location chat lines float over the speaker's head inside a place
  const chatMsgs = useChat((s) => s.messages);
  const speech = useMemo(() => chatMsgs.slice(-8).map((m) => ({ id: m.id, who: m.mine ? 'me' : m.user_id, text: m.body })), [chatMsgs]);
  const gfxTier = useTier();

  // A fresh game screen (e.g. after logging out and in again) starts clean: no sheet or map left
  // open from the previous session. The UI store outlives the screen.
  useEffect(() => {
    closeAll();
    setMapOpen(false);
  }, [closeAll, setMapOpen]);

  // Coming back home switches to the home view; arriving at any other place takes you inside it (L2).
  const wasHome = useRef(atHome);
  useEffect(() => {
    if (atHome && !wasHome.current) setMapOpen(false);
    wasHome.current = atHome;
  }, [atHome, setMapOpen]);
  const arrivedAt = state && !state.travel ? state.location.id : null;
  const lastArrived = useRef(arrivedAt);
  useEffect(() => {
    if (arrivedAt && lastArrived.current !== arrivedAt) {
      setMapOpen(false);
      setPlaceZone(null);
    }
    lastArrived.current = arrivedAt;
  }, [arrivedAt, setMapOpen]);

  // The home activity running now -> which furniture the Sim goes to.
  const busyUntil = p?.busy_until ?? null;
  const busyLabel = p?.busy_label ?? null;
  const busyActive = Boolean(busyUntil && Date.parse(busyUntil) > now);
  const busyGroup = useMemo(() => {
    if (!busyUntil || !busyLabel || !busyActive) return null;
    const a = activities?.find((x) => x.name === busyLabel && x.home_only);
    const seconds = Math.max(0, (Date.parse(busyUntil) - serverNow()) / 1000);
    return a ? { group: activityGroup(a.id), key: busyUntil, activity: a.id, seconds } : null;
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
      if (g) pickHome({ id: f.id, group: g, activities: f.activities });
    },
    [pickHome],
  );

  // M2: the action queue. Tasks walk first (3D home on screen), then start; see game/TaskRunner.ts.
  const suspendHomeNow = (overlay === 'sim' && simTab === 'profile') || overlay === 'look';
  const homeLive = showHome && Boolean(p) && furnitureOf === p?.id && !suspendHomeNow;
  const placeLive = showPlace && !suspendHomeNow && state ? state.location.id : null;
  const runner = useTaskRunner(state, homeLive, placeLive);
  const taskPhase = useTasks((s) => s.current?.phase ?? null);
  const taskCurrent = useTasks((s) => s.current);

  // ---- L2 place interior: zones + cards (server), real players + background people (capped)
  const [placeZone, setPlaceZone] = useState<string | null>(null);
  const [placeBump, setPlaceBump] = useState(0);
  const interior = usePlaceInterior(showPlace && state ? state.location.id : null, hourF, placeBump);
  // F1 + P2: per-place soundtrack (club amapiano, buka radio, market, stadium, cinema, hotel lounge, motor park,
  // bank hum, a neighbour's generator at night)
  const placeScene: string = state?.location.scene ?? '';
  const placeOpen = interior.data ? interior.data.open : true;
  // Closed places: a Sim inside a place that has closed (and isn't busy or travelling) is sent home by the server.
  const ejectTried = useRef<string | null>(null);
  const atLoc = state?.location.id ?? null;
  const atOwnHome = Boolean(state && state.location.id === state.profile.home_location_id);
  useEffect(() => {
    if (!showPlace || !interior.data || interior.data.open || atOwnHome || !atLoc || state?.travel || busyActive) return;
    const key = `${atLoc}:${Math.floor(Date.now() / 60_000)}`;
    if (ejectTried.current === key) return;
    ejectTried.current = key;
    placeClosedEject().then((r) => {
      if (!r.ejected) return;
      toast(`${r.place} is closed. The bouncers cleared the place, so you headed home. It opens again at ${r.opens}.`, 'info');
      void useGame.getState().refresh();
    }).catch(() => { /* try again next minute */ });
  }, [showPlace, interior.data, atOwnHome, atLoc, state?.travel, busyActive]);
  const placeSound: PlaceSound = showPlace
    ? !placeOpen ? null
      : placeScene === 'club' ? 'club'
      : placeScene === 'buka' || placeScene === 'restaurant' ? 'buka'
      : placeScene === 'bank' || placeScene === 'hospital' ? 'bank'
      : placeScene === 'market' || placeScene === 'street' ? 'market'
      : placeScene === 'motorpark' ? 'motorpark'
      : placeScene === 'stadium' ? 'stadium'
      : placeScene === 'cinema' ? 'cinema'
      : placeScene === 'hotel' ? 'lounge' : null
    : showHome && skyNight && (placeScene === 'home_face_me' || placeScene === 'hostel') ? 'generator' : null;
  useEffect(() => { setSoundPlace(placeSound); }, [placeSound]);
  // P2: a licensed club track (admin) replaces the synthesized amapiano groove
  const clubTrackUrl = String(cfg('music.club_track_url', '') ?? '');
  useEffect(() => { setPlaceTrack(clubTrackUrl); }, [clubTrackUrl]);
  // P2: club hype (server announcements over Realtime): the club channel while inside a club, the ticker always
  const inClub = showPlace && placeScene === 'club';
  // PAY: the place channel runs at every place (not on the road) so VIP arrivals reach everyone there
  useHypeLive(state && !state.travel ? state.location.id : null, p?.id ?? null, inClub);
  // L4: today's / LIVE events (map badges, place sheet "On today", top banner)
  useEventsLive(p?.id ?? null);
  const eventBadges = useEventBadges();
  // L4: a shared place link (/play?place=<id>) opens that place's sheet on the map, once
  const deepLinked = useRef(false);
  useEffect(() => {
    if (deepLinked.current || !p || !locations.length) return;
    deepLinked.current = true;
    const want = new URLSearchParams(window.location.search).get('place');
    if (!want) return;
    const url = new URL(window.location.href);
    url.searchParams.delete('place');
    window.history.replaceState(window.history.state, '', url.pathname + url.search + url.hash);
    if (!locations.some((l) => l.id === want)) {
      toast('That place is closed for now. Check back soon.', 'info');
      return;
    }
    setMapOpen(true);
    select(want);
  }, [p, locations, select, setMapOpen]);
  const playersHere = usePlayersAt(showPlace && state ? state.location.id : null, p?.id ?? '');
  const placeRoom = useMemo(() => (interior.data ? roomFor(interior.data.location.scene, interior.data.zones) : null), [interior.data]);
  const placeGrid = useMemo(() => (interior.data && placeRoom ? buildPlaceGrid(placeRoom, interior.data.zones) : null), [interior.data, placeRoom]);
  const crowdCap = Math.max(0, Math.min(30, Number(cfg('crowd.max_visible', 10)) || 0));
  const npcPerZone = Math.max(0, Math.min(6, Number(cfg('places.npc_per_zone', 2)) || 0));
  const hourInt = Math.floor(hourF);
  const hourOverride = devHourOverride();
  const people = usePlacePeople(showPlace && state ? state.location.id : null, hourInt, hourOverride == null ? null : Math.floor(hourOverride));
  const crowdPlan = useMemo(() => {
    if (!interior.data || !placeRoom || !placeGrid) return { shown: [], total: 0 };
    return planCrowd({
      placeId: interior.data.location.id, scene: interior.data.location.scene, hour: hourInt, room: placeRoom, zones: interior.data.zones,
      grid: placeGrid, players: playersHere, perZone: npcPerZone, cap: crowdCap, closed: !interior.data.open,
      npcs: people === null ? null : people?.npcs, npcTotal: people?.total ?? 0,
    });
  }, [interior.data, placeRoom, placeGrid, playersHere, npcPerZone, crowdCap, hourInt, people]);
  // the first zone is picked on the way in, so its action cards show at once
  useEffect(() => {
    if (interior.data && !placeZone && interior.data.zones.length) setPlaceZone(interior.data.zones[0].key);
  }, [interior.data, placeZone]);
  // re-read the cards when money / the Bag change (owned counts, "In your Bag")
  const cashKey = p ? `${p.cash}:${p.bank}:${p.job_id ?? ''}:${p.job_level}` : '';
  const lastCashKey = useRef(cashKey);
  useEffect(() => {
    if (!showPlace) return;
    if (lastCashKey.current !== cashKey) {
      lastCashKey.current = cashKey;
      const t = window.setTimeout(() => setPlaceBump((n) => n + 1), 600);
      return () => window.clearTimeout(t);
    }
  }, [cashKey, showPlace]);
  // the zone whose action runs now (the task we walked to, else the zone that offers the busy activity)
  const placeBusyZone = useMemo(() => {
    if (!showPlace || !p || !busyActive) return null;
    if (taskCurrent?.phase === 'running' && taskCurrent.zone && taskCurrent.locationId === p.location_id) return taskCurrent.zone;
    const z = interior.data?.zones.find((zz) => zz.actions.some((a) => a.kind === 'activity' && a.name === p.busy_label));
    return z?.key ?? null;
  }, [showPlace, p, busyActive, taskCurrent, interior.data]);
  // what the HUD covers at the bottom (place card + dock), so the room is framed above it
  const bottomRef = useRef<HTMLDivElement>(null);
  const [bottomH, setBottomH] = useState(0);
  useEffect(() => {
    const el = bottomRef.current;
    if (!el || typeof ResizeObserver === 'undefined') return;
    const ro = new ResizeObserver(() => setBottomH(Math.round(el.getBoundingClientRect().height)));
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  const layoutId = p ? homeLayoutFor(p.housing_id, (state && byId[state.location.id]?.scene) ?? state?.location.scene) : 'face_me';
  const furnished = useMemo(() => furnishLayout(LAYOUTS[layoutId], furniture), [layoutId, furniture]);

  if (!state || !p) return <LoadingScreen />;

  const status = deriveStatus(state, now);
  const here = byId[state.location.id] ?? state.location;
  const travel = state.travel
    ? { from: p.location_id || state.location.id, to: state.travel.to, progress: status.travelProgress, mode: state.travel.mode }
    : null;
  // Another live 3D view is open (Sim sheet turntable / look editor): the home canvas steps aside.
  const suspendHome = (overlay === 'sim' && simTab === 'profile') || overlay === 'look';
  const coveredHome = Boolean(selectedId || panel || homePick || (overlay && !suspendHome));
  // The city stays live under the location sheet (it sits over the lower half) but pauses under
  // full-screen panels and overlays.
  const coveredMap = Boolean(panel || (overlay && !suspendHome));
  const layout = layoutId;
  const walk = {
    speed: Math.min(4, Math.max(0.5, Number(cfg('sim.walk_speed', 1.9)) || 1.9)),
    robeMult: Math.min(1.5, Math.max(0.3, Number(cfg('sim.robe_speed_mult', 0.7)) || 0.7)),
    tiredSlow: Math.min(0.8, Math.max(0, Number(cfg('sim.tired_slowdown', 0.18)))),
  };
  const dockActive: DockId | null = overlay === 'phone' ? 'phone' : overlay === 'buy' ? 'buy' : showHome ? 'home' : showPlace ? null : 'map';
  // phones: the room sits above the card; desktop: the card may cover the front strip (the room reads bigger)
  const placeInsetBottom = clean ? 40 : Math.max(insets.bottom, Math.min(Math.round((bottomH + 12) * (insets.narrow ? 1 : 0.62)), Math.round(window.innerHeight * 0.62)));
  return (
    <div className={`game${skyNight ? ' is-night' : ''}${clean ? ' is-clean' : ''}${showHome ? ' is-home' : showPlace ? ' is-place' : ' is-map'}`}>
      <div className="game__map">
        {showPlace && !interior.data ? (
          <div className="home3d home3d--loading"><span className="home3d__loader" aria-label="Loading the place" /><span className="place-loading">Walking in…</span></div>
        ) : showPlace && interior.data ? (
          <PlaceView
            key={interior.data.location.id}
            placeId={interior.data.location.id}
            placeName={interior.data.location.name}
            scene={interior.data.location.scene}
            zones={interior.data.zones}
            avatar={p.avatar}
            hour={hourF}
            closed={!interior.data.open}
            crowd={crowdPlan.shown}
            rigCount={import.meta.env.DEV && typeof (window as { __blRigs?: number }).__blRigs === 'number' ? (window as { __blRigs?: number }).__blRigs : Math.max(0, Math.min(8, Number(cfg(gfxTier === 'low' ? 'crowd.rigs_low' : 'crowd.rigs_high', gfxTier === 'low' ? 2 : 6)) || 0))}
            chatterSeconds={Math.max(0, Number(cfg('crowd.chatter_seconds', 22)) || 0)}
            speech={speech}
            moreCount={Math.max(0, crowdPlan.total - crowdPlan.shown.length)}
            selectedZone={placeZone}
            onPickZone={setPlaceZone}
            task={runner.placeTask}
            onTaskArrive={runner.onTaskArrive}
            onTaskCancel={runner.onTaskCancel}
            onWalkDone={runner.onWalkDone}
            busyZone={placeBusyZone}
            walkLock={busyActive ? `${busyLabel ?? 'Busy'} first, then you can walk` : taskPhase === 'starting' ? 'Starting, one moment' : null}
            walk={walk}
            mood={simPosture(p)}
            suspended={suspendHome}
            paused={Boolean(panel || selectedId || (overlay && !suspendHome))}
            insetTop={clean ? 70 : insets.top}
            insetBottom={placeInsetBottom}
            fallbackScene={here.scene}
            fallbackAction={
              <button type="button" className="where-chip home3d__fallback-btn" onClick={() => select(here.id)}>
                <span className="grow"><span className="where-chip__name">Things to do here</span></span>
                <Icon name="chevronUp" size={14} />
              </button>
            }
          />
        ) : showHome && furnitureOf !== p.id ? (
          <div className="home3d home3d--loading"><span className="home3d__loader" aria-label="Loading your home" /></div>
        ) : showHome ? (
          <HomeView
            layoutId={layout}
            layout={furnished}
            origin={p.origin === 'nepo' ? 'nepo' : 'lapo'}
            vehicleId={ownedVehicleId}
            walk={walk}
            avatar={p.avatar}
            busy={busyGroup}
            task={runner.homeTask}
            onTaskArrive={runner.onTaskArrive}
            onTaskCancel={runner.onTaskCancel}
            onWalkDone={runner.onWalkDone}
            walkLock={busyActive ? `${busyLabel ?? 'Busy'} first, then you can walk` : taskPhase === 'starting' ? 'Starting, one moment' : null}
            mood={simPosture(p)}
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
          <CityView
            locations={locations.length ? locations : [state.location]}
            currentId={state.travel ? undefined : state.location.id}
            selectedId={selectedId ?? undefined}
            onSelect={(id) => select(id)}
            night={skyNight}
            hour={hourF}
            travel={travel}
            crowd={crowd}
            events={eventBadges}
            suspended={suspendHome}
            paused={coveredMap}
            insetTop={clean ? 70 : insets.top}
            insetBottom={clean ? 40 : insets.bottom}
          />
        )}
      </div>

      {!clean && <TopPill state={state} clock={clock} />}
      <HypeBanner mcName={inClub ? people?.npcs.find((n) => n.motion === 'hype')?.name ?? 'The hype man' : 'VIP alert'} top={inClub ? (clean ? 70 : insets.top) + 6 : clean ? 70 : insets.narrow ? 200 : insets.top + 6} />
      <HypeTicker top={insets.narrow ? 14 : 72} />
      {!clean && (
        <EventBanner top={showHome || showPlace ? (insets.narrow ? 160 : 72) : (insets.narrow ? 156 : 122)} hereId={state.travel ? null : state.location.id}
          onOpen={(id) => { if (id !== state.location.id || state.travel) setMapOpen(true); select(id); }} />
      )}
      <LeftRail state={state} status={status} atHome={atHome} compact={!showHome && (!showPlace || insets.narrow)} />

      <div className="game__bottom" ref={bottomRef}>
        <div className="game__banners">
          <StatusBanners state={state} status={status} />
          {!clean && !state.travel && chatUnread > 0 && (
            <button type="button" className="chat-chip" onClick={() => select(here.id, 'chat')}
              aria-label={`${chatUnread} new chat message${chatUnread === 1 ? '' : 's'} here. Open chat`}>
              <span className="chat-chip__dot" aria-hidden /> <Icon name="chat" size={15} /> {chatUnread > 9 ? '9+' : chatUnread} new in chat
            </button>
          )}
          {!clean && showPlace && (
            <PlaceCard state={state} data={interior.data} error={interior.error} zone={placeZone} onZone={setPlaceZone}
              peopleCount={crowdPlan.total + 1} moodSeconds={Number(cfg('places.mood_seconds', 7)) || 7}
              onMap={() => onDock('map')} onHome={goHome} atHome={atHome}
              players={playersHere} npcs={people?.npcs ?? []} me={{ username: p.username, avatar: p.avatar }} />
          )}
          {!clean && !state.travel && !showHome && !showPlace && (
            <div className="where-row">
              <button type="button" className="where-chip" onClick={() => select(here.id)}>
                <span className="where-chip__dot" />
                <span className="grow">
                  <span className="where-chip__label">You're at</span>
                  <span className="where-chip__name">{atHome ? 'Home' : here.name}</span>
                </span>
                <span className="where-chip__go">Open <Icon name="chevronUp" size={14} /></span>
              </button>
              {!atHome && (
                <button type="button" className="where-enter" onClick={() => { closeAll(); setMapOpen(false); }}>
                  Go inside <Icon name="chevronRight" size={14} />
                </button>
              )}
            </div>
          )}
          {!clean && showHome && (
            <button type="button" className="home-chip" onClick={() => select(here.id)}>
              <span aria-hidden>🏠</span> <span className="home-chip__name">{here.name.replace(/ \(.*\)$/, '')}</span>
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

      <LocationSheet state={state} status={status} night={skyNight} />
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
