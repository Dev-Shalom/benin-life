// Game screen (R4/R5): the 3D home when the player is at home, otherwise the 3D city map
// (the 2D map only as the lite fallback, see src/art/city3d/CityView.tsx).
// HUD: top pill, left rail, needs card, dock (Home · Buy · Map · Phone), status banners, toasts.
import { lazy, Suspense, useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { HomeView, KINDS, LAYOUTS, activityGroup, findFreeSpot, furnishHome, furnitureIdOfKey, homeLayoutFor, itemGroup, placementIssue, type FurnitureItem, type FurnitureKind, type SavedHomePosition } from '../art/home3d';
import { CityView, type CityBoard } from '../art/city3d';
import { adImageUrl, noteAdView, useBillboards } from '../lib/billboards';
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
import { recoverPendingPayments } from '../lib/payments';
import { naira } from '../lib/format';
import { socialHouseInfo, socialLeaveHouse, type HouseFurniturePlacement, type HouseInfo } from '../api/social';
import { furniturePlace, furnitureStore } from '../api/furniture';
import { useArrange } from '../state/arrange';
import { ArrangeBar } from './game/ArrangeBar';
import { supabase } from '../lib/supabase';
import { useHouseRoom } from '../state/houseRoom';
import { IX_ROLE, loadInteractionTypes, type InteractionType } from '../api/interactions';
import { HouseInteractSheet, InteractPrompts, type Prompt, type Waiting } from './game/HouseInteract';
import { HypeStrip, HypeTakeover } from './game/Hype';
import { useHypeLive } from '../state/hype';
import { useEventsLive } from '../state/events';
import { EventBanner, useEventBadges } from './game/Events';
import JourneyGuide from './game/JourneyGuide';
import { DailySync, usePlaceGem } from './game/Daily';
import { useShownAvatar, useWardrobe } from '../state/wardrobe';
import { GarageSheet } from './game/GarageSheet';
import { MoveHouseSheet } from './game/MoveHouseSheet';
import { ReceiptSheet } from './game/ReceiptSheet';
import { useGarage } from '../state/garage';
import { garageHome, type GarageHome } from '../api/garage';

const Boutique = lazy(() => import('./game/Boutique'));
const BillboardSheet = lazy(() => import('./game/BillboardSheet'));

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

/** A player_house_furniture row as a saved position (B1: stored + layout). */
function rowPosition(row: HouseFurniturePlacement): SavedHomePosition {
  return { x: Number(row.x), z: Number(row.z), rotation: Number(row.rotation), stored: Boolean(row.stored), layout: row.layout ?? null };
}

export default function Game() {
  const state = useGame((s) => s.state);
  const locations = useGame((s) => s.locations);
  const byId = useGame((s) => s.locationsById);
  const unread = useGame((s) => s.unread);
  const gameEvents = useGame((s) => s.events);
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

  // H3 billboards on the map: boards + their live rotation (refreshed every few minutes while the map is open)
  const boardsData = useBillboards((s) => s.data);
  const openBoard = useBillboards((s) => s.open);
  const boardSheet = useBillboards((s) => s.sheet);
  const boardsOn = cfg<boolean>('billboards.enabled', true);
  useEffect(() => {
    if (!mapOpen || !boardsOn) return;
    void useBillboards.getState().load();
    const t = window.setInterval(() => void useBillboards.getState().load(true), 180_000);
    return () => window.clearInterval(t);
  }, [mapOpen, boardsOn]);
  const cityBoards = useMemo<CityBoard[] | undefined>(() => {
    if (!boardsOn || !boardsData?.enabled) return undefined;
    return boardsData.boards.map((b) => ({
      id: b.id, name: b.name, x: Number(b.x), y: Number(b.y), yaw: Number(b.yaw), kind: b.kind,
      ads: b.ads.map((a) => ({ id: a.id, url: adImageUrl(a.image) })),
    }));
  }, [boardsData, boardsOn]);

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
  const homeOwnerId = p ? (p.home_visit_host_id ?? p.id) : null;
  const [houseInfo, setHouseInfo] = useState<HouseInfo | null>(null);
  const [housePositions, setHousePositions] = useState<Record<string, SavedHomePosition>>({});
  const [arrangeBusy, setArrangeBusy] = useState(false);
  const [buyTab, setBuyTab] = useState<'shop' | 'arrange' | 'bag'>('shop');
  const [selectedHousePlayer, setSelectedHousePlayer] = useState<string | null>(null);
  // V2 house interactions: the catalogue, our side of a running one (slot 0 asked, 1 accepted), the
  // request waiting for our answer, and ours waiting for theirs
  const [ixTypes, setIxTypes] = useState<InteractionType[]>([]);
  const [ixSlot, setIxSlot] = useState<{ until: string; slot: number } | null>(null);
  const [ixPrompt, setIxPrompt] = useState<Prompt | null>(null);
  const [ixWaiting, setIxWaiting] = useState<Waiting | null>(null);
  const ixHandled = useRef(new Set<number>());
  const [leavingHouse, setLeavingHouse] = useState(false);
  // G1: the home owner's garage + cars (the host's when visiting), reloaded after a car purchase or a build.
  const garageVersion = useGarage((s) => s.version);
  const vehicleKey = (state?.inventory ?? []).filter((item) => item.category === 'vehicle').map((item) => item.id).join(',');
  const [garage, setGarage] = useState<GarageHome | null>(null);
  // the player's own furniture (starter set by origin + home); reloads when the home changes
  const furnKey = p && homeOwnerId ? `${homeOwnerId}:${p.home_location_id}:${p.housing_id ?? ''}` : null;
  const lastFurnKey = useRef<string | null>(null);
  useEffect(() => {
    if (!furnKey || !homeOwnerId) return;
    const force = lastFurnKey.current !== null && lastFurnKey.current !== furnKey;
    lastFurnKey.current = furnKey;
    void loadFurniture(homeOwnerId, force);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [furnKey, homeOwnerId, loadFurniture]);
  const atHome = Boolean(p && state && !state.travel && p.location_id === state.location.id
    && (p.location_id === p.home_location_id || p.home_visit_host_id));
  const showHome = atHome && !mapOpen;
  // Q1: count arrivals at a house (derived during render, so the scene mounts with the new key and the
  // Sim walks in from the door instead of reappearing where it stood before the trip)
  // H1: moving house (housing changes while at home) is an arrival too: the Sim walks into the new home
  const arrivalSig = atHome ? `home:${p?.housing_id ?? ''}` : null;
  const [homeArrival, setHomeArrival] = useState({ at: arrivalSig, n: 0 });
  if (homeArrival.at !== arrivalSig) setHomeArrival({ at: arrivalSig, n: arrivalSig ? homeArrival.n + 1 : homeArrival.n });
  useEffect(() => {
    if (!atHome || !homeOwnerId) { setGarage(null); return; }
    let alive = true;
    garageHome(homeOwnerId).then((g) => { if (alive) setGarage(g); }).catch(() => { if (alive) setGarage(null); });
    return () => { alive = false; };
  }, [atHome, homeOwnerId, garageVersion, vehicleKey]);
  const parking = useMemo(() => garage && (garage.cars.length || garage.garage)
    ? { cars: garage.cars.map((c) => c.id), garage: garage.garage ? { style: garage.garage.style, capacity: garage.garage.capacity } : null }
    : null, [garage]);
  const houseRoomId = atHome && state ? state.location.id : null;
  // W1: the 3D Sim wears the outfit for the context (sleep / home / work / party / gym / everyday).
  const atOwnHomeNow = Boolean(p && state && !state.travel && !p.home_visit_host_id && p.location_id === p.home_location_id
    && state.location.id === p.home_location_id);
  const { avatar: shownAvatar } = useShownAvatar(state, now, atOwnHomeNow, Boolean(p && state && !state.travel && !atHome));
  const wardrobeUid = p?.id ?? null;
  useEffect(() => { if (wardrobeUid) void useWardrobe.getState().load(wardrobeUid); }, [wardrobeUid]);
  const houseProfile = useMemo(() => (p && shownAvatar && shownAvatar !== p.avatar ? { ...p, avatar: shownAvatar } : p ?? null), [p, shownAvatar]);
  const { members: houseMembers, publish: publishHouseMove, publishPath: publishHousePath } = useHouseRoom(houseRoomId, houseProfile);
  useEffect(() => { if (houseRoomId) void loadInteractionTypes().then(setIxTypes); }, [houseRoomId]);
  // requests arrive as events (postgres_changes on events, already live); replies tell the asker their slot
  useEffect(() => {
    const nowMs = Date.now();
    for (const ev of gameEvents) {
      if (ixHandled.current.has(ev.id)) continue;
      const d = ev.data as { id?: number; kind?: string; from?: string; username?: string; label?: string; icon?: string; expires_at?: string; status?: string; busy_until?: string };
      if (ev.kind === 'house_interact' && d.id && d.expires_at && Date.parse(d.expires_at) > nowMs) {
        ixHandled.current.add(ev.id);
        setIxPrompt({ id: d.id, label: d.label ?? 'Do something together', icon: d.icon ?? '✨', username: d.username ?? 'someone', from: d.from ?? '', expires: Date.parse(d.expires_at) });
      } else if (ev.kind === 'house_interact_reply' && Date.parse(ev.created_at) > nowMs - 120_000) {
        ixHandled.current.add(ev.id);
        setIxWaiting((w) => (w && w.id === d.id ? null : w));
        if (d.status === 'accepted' && d.busy_until) setIxSlot({ until: d.busy_until, slot: 0 });
      } else if (ev.kind === 'house_interact_end') {
        // Q1: the partner left the house or stopped: the server freed us too (the toast comes from state/game)
        ixHandled.current.add(ev.id);
        setIxSlot(null);
      } else ixHandled.current.add(ev.id);
    }
  }, [gameEvents]);
  // Q1: a different house (or none: we left, the visit ended, we travelled) drops any running/pending
  // interaction state; the server already ended it for both players (profiles_end_interactions_on_leave)
  useEffect(() => {
    setIxSlot(null);
    setIxPrompt(null);
    setIxWaiting(null);
    setSelectedHousePlayer(null);
  }, [houseRoomId]);
  useEffect(() => {
    if (!ixPrompt && !ixWaiting) return;
    const next = Math.min(ixPrompt?.expires ?? Infinity, ixWaiting?.expires ?? Infinity);
    const id = window.setTimeout(() => {
      setIxPrompt((p) => (p && p.expires <= Date.now() ? null : p));
      setIxWaiting((w) => (w && w.expires <= Date.now() ? null : w));
    }, Math.max(0, next - Date.now()) + 200);
    return () => window.clearTimeout(id);
  }, [ixPrompt, ixWaiting]);
  if (import.meta.env.DEV) (window as unknown as { __house?: unknown }).__house = { room: houseRoomId, members: houseMembers };
  // Top-ups that stayed pending (verify failed at checkout) are re-checked once per session.
  const payRecovered = useRef(false);
  const payUid = p?.id ?? null;
  useEffect(() => {
    if (!payUid || payRecovered.current) return;
    payRecovered.current = true;
    void recoverPendingPayments().then((n) => {
      if (n > 0) {
        toast(`Your top-up came through: ${naira(n)} is now in your bank.`, 'good');
        void useGame.getState().refresh();
      }
    }).catch(() => {});
  }, [payUid]);

  useEffect(() => {
    let alive = true;
    if (!atHome || !p || !homeOwnerId) {
      setHouseInfo(null);
      setHousePositions({});
      useArrange.getState().close();
      setSelectedHousePlayer(null);
      return;
    }
    setHouseInfo(null);
    setHousePositions({});
    void Promise.all([
      socialHouseInfo(),
      supabase.from('player_house_furniture').select('owner_id,furniture_key,x,z,rotation,stored,layout').eq('owner_id', homeOwnerId),
    ]).then(([info, rows]) => {
      if (!alive) return;
      setHouseInfo(info);
      if (!rows.error) {
        setHousePositions(Object.fromEntries(((rows.data ?? []) as HouseFurniturePlacement[]).map((row) => [row.furniture_key, rowPosition(row)])));
      }
    }).catch(() => { /* retain the local default furnishing if house metadata is temporarily unavailable */ });
    const channel = supabase.channel(`house-furniture:${homeOwnerId}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'player_house_furniture', filter: `owner_id=eq.${homeOwnerId}` }, (payload) => {
        if (payload.eventType === 'DELETE') {
          const old = payload.old as Partial<HouseFurniturePlacement>;
          if (old.furniture_key) setHousePositions((positions) => {
            const next = { ...positions };
            delete next[old.furniture_key!];
            return next;
          });
          return;
        }
        const row = payload.new as HouseFurniturePlacement;
        if (row.furniture_key) setHousePositions((positions) => ({
          ...positions, [row.furniture_key]: rowPosition(row),
        }));
      })
      .on('postgres_changes', { event: '*', schema: 'public', table: 'player_furniture', filter: `user_id=eq.${homeOwnerId}` }, () => {
        void loadFurniture(homeOwnerId, true);
      }).subscribe();
    return () => { alive = false; void supabase.removeChannel(channel); };
  }, [atHome, homeOwnerId, p?.id, p?.housing_id, loadFurniture]);
  // L2: anywhere else (not on the road) you are INSIDE the place: its 3D interior + the place card
  const showPlace = Boolean(p && state && !state.travel && !atHome && !mapOpen);
  // V1-6: stay subscribed to the chat of the place you are at (unread dot while the sheet is closed).
  useChatLive(state && !state.travel ? state.location.id : null, p?.id ?? null);
  const chatUnread = useChat((s) => s.unread);
  // L3: the last location chat lines float over the speaker's head inside a place
  const chatMsgs = useChat((s) => s.messages);
  const speech = useMemo(() => chatMsgs.slice(-8).map((m) => ({ id: m.id, who: m.mine ? 'me' : m.user_id, text: m.body ?? 'Voice message' })), [chatMsgs]);
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
    if (a) return { group: activityGroup(a.id), key: busyUntil, activity: a.id, seconds };
    // V2: a house interaction (busy_label = its label): our role's piece / pose, our side of the sofa
    const ix = ixTypes.find((t) => t.label === busyLabel);
    if (!ix) return null;
    const slot = ixSlot && Math.abs(Date.parse(ixSlot.until) - Date.parse(busyUntil)) < 2000 ? ixSlot.slot : 0;
    const role = IX_ROLE[ix.kind]?.[slot] ?? {};
    return { group: role.activity ? activityGroup(role.activity) : 'seat' as const, key: busyUntil, activity: role.activity, seconds, slot,
      pose: role.pose ?? (role.activity ? null : 'stand' as const) };
  }, [busyUntil, busyLabel, busyActive, activities, ixTypes, ixSlot]);

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
  const suspendHomeNow = (overlay === 'sim' && simTab === 'profile') || overlay === 'look' || overlay === 'boutique';
  const homeLive = showHome && Boolean(p) && furnitureOf === homeOwnerId && !suspendHomeNow;
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
  // Q1: a shared "Dance together" running at home plays the afrobeats loop for both players until it ends
  const danceOn = Boolean(busyActive && busyLabel && ixTypes.some((t) => t.kind === 'dance' && t.label === busyLabel));
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
    : showHome && danceOn ? 'dance'
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
  const dailyHere = p && state && !state.travel ? p.location_id : null;
  const placeGem = usePlaceGem(showPlace ? dailyHere : null);
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
  const furnished = useMemo(() => furnishHome(LAYOUTS[layoutId], furniture, housePositions), [layoutId, furniture, housePositions]);

  // ---- B1 arrange (inside Buy): the selected piece is drawn live as the scene's ghost
  const arrangeOn = useArrange((s) => s.active);
  const arrSel = useArrange((s) => s.sel);
  const arrPending = useArrange((s) => s.pending);
  const canArrange = Boolean(showHome && p && !p.home_visit_host_id);
  const arrActive = arrangeOn && canArrange;
  const selKey = arrActive ? arrSel?.key ?? null : null;
  const pieceItem = useCallback((key: string): FurnitureItem | null => {
    const placed = furnished.furniture.find((f) => f.id === key);
    if (placed) return placed;
    const piece = furniture?.find((f) => f.id === furnitureIdOfKey(key));
    if (!piece || !(piece.kind in KINDS)) return null;
    return { id: key, kind: piece.kind as FurnitureKind, x: 0, z: 0, rot: 0, color: piece.color ?? undefined, activities: piece.activities };
  }, [furnished, furniture]);
  const sceneLayout = useMemo(
    () => (selKey ? { ...furnished, furniture: furnished.furniture.filter((f) => f.id !== selKey) } : furnished),
    [furnished, selKey],
  );
  const ghostItem = useMemo(() => {
    if (!selKey || !arrSel) return null;
    const base = pieceItem(selKey);
    return base ? { ...base, x: arrSel.x, z: arrSel.z, rot: arrSel.rot } : null;
  }, [selKey, arrSel, pieceItem]);
  const arrIssue = ghostItem ? placementIssue(layoutId, ghostItem, sceneLayout.furniture) : null;
  const ghost = useMemo(() => (ghostItem ? { item: ghostItem, invalid: Boolean(arrIssue) } : null), [ghostItem, arrIssue]);
  const selName = selKey ? (furniture?.find((f) => f.id === furnitureIdOfKey(selKey))?.name ?? KINDS[ghostItem?.kind ?? 'stool']?.label ?? 'Furniture') : null;
  // close arrange mode when leaving home / visiting
  useEffect(() => {
    if (arrangeOn && !canArrange && furnitureOf) useArrange.getState().close();
  }, [arrangeOn, canArrange, furnitureOf]);
  // a piece asked for by key (just bought, or picked from My items): select it once it has loaded
  useEffect(() => {
    if (!arrActive || !arrPending || !furniture) return;
    const id = furnitureIdOfKey(arrPending);
    const piece = furniture.find((f) => f.id === id);
    if (!piece) return; // the purchase is still loading
    const copy = Number(/-(\d+)$/.exec(arrPending)?.[1] ?? 1);
    if ((piece.qty ?? 1) < copy) return;
    useArrange.getState().clearPending();
    const placed = furnished.furniture.find((f) => f.id === arrPending);
    if (placed) {
      useArrange.getState().select({ key: placed.id, x: placed.x, z: placed.z, rot: placed.rot ?? 0, fromStore: false });
      return;
    }
    const others = furnished.furniture;
    const spot = findFreeSpot(layoutId, piece.kind, others, { x: LAYOUTS[layoutId].home[0], z: LAYOUTS[layoutId].home[1] })
      ?? { x: LAYOUTS[layoutId].w / 2, z: LAYOUTS[layoutId].d / 2, rot: 0 };
    useArrange.getState().select({ key: arrPending, x: spot.x, z: spot.z, rot: spot.rot, fromStore: true });
    if (!findFreeSpot(layoutId, piece.kind, others)) toast('No free space for this one. Store something first or move things around.', 'bad');
  }, [arrActive, arrPending, furniture, furnished, layoutId]);

  const arrangeDone = useCallback(async () => {
    const sel = useArrange.getState().sel;
    if (!sel || arrangeBusy) return;
    if (arrIssue) {
      toast(`Can't put it there: ${arrIssue}`, 'bad');
      return;
    }
    setArrangeBusy(true);
    try {
      const r = await furniturePlace(sel.key, sel.x, sel.z, sel.rot);
      setHousePositions((rows) => ({ ...rows, [r.furniture_key]: { x: Number(r.x), z: Number(r.z), rotation: Number(r.rotation), stored: false, layout: r.layout } }));
      useArrange.getState().select(null);
    } catch (error) {
      toast(error instanceof Error ? error.message : 'Could not save that furniture position.', 'bad');
    } finally {
      setArrangeBusy(false);
    }
  }, [arrIssue, arrangeBusy]);
  const arrangeStore = useCallback(async () => {
    const sel = useArrange.getState().sel;
    if (!sel || arrangeBusy) return;
    setArrangeBusy(true);
    try {
      const r = await furnitureStore(sel.key);
      setHousePositions((rows) => ({ ...rows, [sel.key]: { ...(rows[sel.key] ?? { x: 0, z: 0, rotation: 0 }), stored: true, layout: r.layout } }));
      useArrange.getState().select(null);
      toast('Stored. Find it under My items.', 'info');
    } catch (error) {
      toast(error instanceof Error ? error.message : 'Could not store that.', 'bad');
    } finally {
      setArrangeBusy(false);
    }
  }, [arrangeBusy]);
  // positions changed elsewhere (a purchase materialises the starter pieces): reload the saved rows
  const reloadPositions = useCallback(async () => {
    if (!homeOwnerId) return;
    const rows = await supabase.from('player_house_furniture').select('owner_id,furniture_key,x,z,rotation,stored,layout').eq('owner_id', homeOwnerId);
    if (!rows.error) setHousePositions(Object.fromEntries(((rows.data ?? []) as HouseFurniturePlacement[]).map((row) => [row.furniture_key, rowPosition(row)])));
  }, [homeOwnerId]);

  const leaveHouse = useCallback(async () => {
    if (!p?.home_visit_host_id || leavingHouse) return;
    setLeavingHouse(true);
    try {
      const result = await socialLeaveHouse();
      closeAll();
      setMapOpen(false);
      await useGame.getState().refresh();
      toast(result.message, 'good');
    } catch (error) {
      toast(error instanceof Error ? error.message : 'Could not leave this home. Try again.', 'bad');
    } finally {
      setLeavingHouse(false);
    }
  }, [p?.home_visit_host_id, leavingHouse, closeAll, setMapOpen]);

  if (!state || !p) return <LoadingScreen />;

  const status = deriveStatus(state, now);
  const here = byId[state.location.id] ?? state.location;
  const travel = state.travel
    ? { from: p.location_id || state.location.id, to: state.travel.to, progress: status.travelProgress, mode: state.travel.mode }
    : null;
  // Another live 3D view is open (Sim sheet turntable / look editor): the home canvas steps aside.
  const suspendHome = (overlay === 'sim' && simTab === 'profile') || overlay === 'look' || overlay === 'boutique';
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
            avatar={shownAvatar ?? p.avatar}
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
            gem={placeGem}
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
        ) : showHome && furnitureOf !== homeOwnerId ? (
          <div className="home3d home3d--loading"><span className="home3d__loader" aria-label="Loading your home" /></div>
        ) : showHome ? (
          <HomeView
            layoutId={layout}
            layout={sceneLayout}
            ghost={ghost}
            playerId={p.id}
            arrivalKey={homeArrival.n}
            origin={(houseInfo?.origin ?? p.origin) === 'nepo' ? 'nepo' : 'lapo'}
            parking={parking}
            walk={walk}
            avatar={shownAvatar ?? p.avatar}
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
            onActorState={publishHouseMove}
            onWalkPath={publishHousePath}
            remotePlayers={houseMembers}
            onPickRemote={(id) => setSelectedHousePlayer(id)}
            editableFurniture={arrActive}
            selectedFurnitureId={selKey}
            onSelectFurniture={(item) => {
              useArrange.getState().select({ key: item.id, x: item.x, z: item.z, rot: item.rot ?? 0, fromStore: false });
            }}
            onMoveFurniture={(_id, x, z) => useArrange.getState().setPos(x, z)}
            insetTop={clean ? 70 : insets.top}
            insetBottom={arrActive && window.innerWidth < 900 ? 320 : clean ? 40 : insets.bottom}
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
            boards={cityBoards}
            rotateSeconds={boardsData?.rotate_seconds ?? 15}
            nowMs={serverNow}
            onBoard={openBoard}
            onAdView={noteAdView}
          />
        )}
      </div>

      {arrActive && (
        <ArrangeBar
          name={selName}
          issue={arrIssue}
          busy={arrangeBusy}
          onDone={() => void arrangeDone()}
          onStore={() => void arrangeStore()}
          onCancel={() => useArrange.getState().select(null)}
          onExit={() => useArrange.getState().close()}
          onOwned={() => { setBuyTab('arrange'); setOverlay('buy'); }}
        />
      )}

      {showHome && (
        <HouseInteractSheet
          person={houseMembers.find((member) => member.id === selectedHousePlayer) ?? null}
          types={ixTypes}
          layout={furnished}
          inventory={state.inventory ?? []}
          busy={busyActive}
          onClose={() => setSelectedHousePlayer(null)}
          onAsked={(w) => { setIxWaiting(w); toast(`Asked @${w.username}. Waiting for an answer.`, 'info'); }}
        />
      )}
      {showHome && (
        <InteractPrompts
          prompt={ixPrompt}
          waiting={ixWaiting}
          avatarOf={(id) => houseMembers.find((m) => m.id === id)?.avatar}
          onAnswered={(prompt, r) => {
            setIxPrompt((cur) => (cur?.id === prompt.id ? null : cur));
            if (r?.status === 'accepted' && r.busy_until) setIxSlot({ until: r.busy_until, slot: 1 });
            void useGame.getState().refresh();
          }}
          onDismissWaiting={() => setIxWaiting(null)}
        />
      )}

      {!clean && <TopPill state={state} clock={clock} />}
      <HypeTakeover mcName={people?.npcs.find((n) => n.motion === 'hype')?.name ?? 'MC Lightning'} />
      <HypeStrip top={insets.narrow ? 14 : 72}
        onOpen={(id) => { if (id !== state.location.id || state.travel) setMapOpen(true); select(id); }} />
      {!clean && (
        <EventBanner hereId={state.travel ? null : state.location.id}
          onOpen={(id) => { if (id !== state.location.id || state.travel) setMapOpen(true); select(id); }} />
      )}
      <DailySync here={dailyHere} />
      <LeftRail state={state} status={status} atHome={atHome} compact={!showHome && (!showPlace || insets.narrow)} />

      <div className={`game__bottom${arrActive ? ' is-arranging' : ''}`} ref={bottomRef}>
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
            <div className="home-chip-row">
              <button type="button" className="home-chip" onClick={() => select(here.id)}>
                <span aria-hidden>🏠</span> <span className="home-chip__name">{here.name.replace(/ \(.*\)$/, '')}</span>
                <span className="home-chip__go">Things to do <Icon name="chevronUp" size={13} /></span>
              </button>
              {houseMembers.length > 0 && (
                <button type="button" className="home-chip-chat" onClick={() => select(here.id, 'chat')}>
                  <Icon name="chat" size={15} /> House chat
                </button>
              )}
              {p.home_visit_host_id && <button type="button" className="home-chip-chat home-chip-leave" onClick={() => void leaveHouse()} disabled={leavingHouse}>
                <Icon name="back" size={15} /> {leavingHouse ? 'Leaving…' : 'Leave house'}
              </button>}
            </div>
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
      <BuySheet
        tab={buyTab}
        onTab={setBuyTab}
        home={canArrange ? { layout: furnished, pieces: furniture ?? [], positions: housePositions, layoutId } : null}
        onBought={(key) => {
          if (homeOwnerId) void useCatalog.getState().loadFurniture(homeOwnerId, true);
          void reloadPositions();
          if (canArrange) { setOverlay(null); useArrange.getState().open(key); }
        }}
        onSold={() => {
          if (homeOwnerId) void useCatalog.getState().loadFurniture(homeOwnerId, true);
          void reloadPositions();
        }}
        onArrange={(key) => { setOverlay(null); useArrange.getState().open(key); }}
      />
      <GarageSheet />
      <MoveHouseSheet />
      <ReceiptSheet />
      <ShortcutsSheet />
      <Phone state={state} clock={clock} />
      {boardSheet && <Suspense fallback={null}><BillboardSheet state={state} /></Suspense>}
      {overlay === 'boutique' && <Suspense fallback={null}><Boutique state={state} /></Suspense>}
      <JourneyGuide state={state} onFinish={(explore) => { if (explore) setMapOpen(true); }} />
    </div>
  );
}
