// Game store — P1-SHELL. Session, GameState (via get_my_state), locations, events + realtime.
import { showLevelUp } from './skills';
import { useChallenges } from './challenges';
import { showGraduation } from './school';
import { create } from 'zustand';
import type { Session } from '@supabase/supabase-js';
import { supabase, supabaseConfigured } from '../lib/supabase';
import { startPresence, stopPresence } from './presence';
import { useTasks } from './tasks';
import { playCue } from '../lib/sound';
import { rpc, errorMessage, GameError, lastWriteAt } from '../lib/api';
import { serverNow, syncServerTime } from '../lib/clock';
import { ensureConfig } from '../lib/config';
import { bindRealtime, isPollMode, startPoller, trackSubscribe } from '../lib/realtime';
import { migrateAvatar } from '../art/avatar3d/catalog';
import type { GameEvent, GameState, Location } from '../lib/types';
import { toast, type ToastKind } from '../ui/Toast';

export type GameStatus = 'idle' | 'loading' | 'ready' | 'noprofile' | 'error';

interface GameStore {
  authReady: boolean;
  session: Session | null;
  status: GameStatus;
  error: string | null;
  state: GameState | null;
  locations: Location[];
  locationsById: Record<string, Location>;
  events: GameEvent[];
  lastReadEventId: number;
  unread: number;
  refresh: () => Promise<void>;
  applyState: (s: GameState) => void;
  loadLocations: () => Promise<void>;
  loadEvents: () => Promise<void>;
  markEventsRead: () => void;
  signOut: () => Promise<void>;
}

const HEARTBEAT_MS = 60_000;

let live: { uid: string; unbind: () => void; heartbeat: number; onVis: () => void } | null = null;
/** F1: newest event id we know of (null until loadEvents ran), the cursor for the poll-mode events fetch. */
let eventsCursor: number | null = null;
/** F1 poll mode: own state every ~15–20 s, new events every ~30 s (visible tab only). */
const POLL_STATE_MS = 17_500;
const POLL_EVENTS_MS = 30_000;
let inflight: Promise<void> | null = null;
let refreshTimer: number | null = null;
/** When the last get_my_state answer arrived (S1: skip the Realtime echo of its own last_seen bump). */
let lastStateAt = 0;

function readKey(uid: string) {
  return `bl.lastReadEvent.${uid}`;
}
function loadLastRead(uid: string): number {
  try {
    return Number(localStorage.getItem(readKey(uid)) ?? 0) || 0;
  } catch {
    return 0;
  }
}

function normalizeState(raw: GameState): GameState {
  const profile = { ...raw.profile, avatar: migrateAvatar(raw.profile?.avatar) };
  profile.cash = Number(profile.cash ?? 0);
  profile.bank = Number(profile.bank ?? 0);
  return { ...raw, profile };
}

/** Guess a toast tone from an event kind. */
export function eventTone(kind: string): ToastKind {
  const k = kind.toLowerCase();
  if (/rob|arrest|jail|raid|injur|hospital|theft|stolen|fine|ban|loss|fail|caught|wanted|debt|default|owed/.test(k)) return 'bad';
  if (/pay|salary|wage|harvest|reward|win|bonus|deposit|credit|topup|top_up|gift|grant|promot|level|sold|release/.test(k)) return 'good';
  return 'info';
}

function looksLikeNoProfile(msg: string): boolean {
  return /profile|create.*(sim|character|account)|no sim|never create|register/i.test(msg);
}

export const useGame = create<GameStore>((set, get) => ({
  authReady: !supabaseConfigured,
  session: null,
  status: 'idle',
  error: null,
  state: null,
  locations: [],
  locationsById: {},
  events: [],
  lastReadEventId: 0,
  unread: 0,

  refresh: () => {
    if (inflight) return inflight;
    const run = async () => {
      const uid = get().session?.user.id;
      if (!uid) return;
      if (!get().state) set({ status: 'loading', error: null });
      const t0 = Date.now();
      try {
        const data = await rpc<GameState | null>('get_my_state');
        const t1 = Date.now();
        lastStateAt = t1;
        if (!data || !data.profile) {
          set({ status: 'noprofile', state: null });
          return;
        }
        if (data.server_time) syncServerTime(data.server_time, t0, t1);
        get().applyState(data);
      } catch (e) {
        const msg = errorMessage(e);
        // Distinguish "no profile yet" from real errors.
        let noProfile = (e instanceof GameError && e.hint === 'no_profile') || looksLikeNoProfile(msg);
        if (!noProfile) {
          const { data: row, error } = await supabase.from('profiles').select('id').eq('id', uid).maybeSingle();
          noProfile = !error && !row;
        }
        if (noProfile) set({ status: 'noprofile', state: null, error: null });
        else if (get().state) toast(msg, 'bad'); // keep playing with stale state
        else set({ status: 'error', error: msg });
      }
    };
    inflight = run().finally(() => {
      inflight = null;
    });
    return inflight;
  },

  applyState: (raw) => {
    const s = normalizeState(raw);
    const prev = get().state?.profile;
    if (prev && prev.id === s.profile.id && s.profile.cash + s.profile.bank > prev.cash + prev.bank) playCue('money');
    if (s.server_time) syncServerTime(s.server_time);
    set({ state: s, status: 'ready', error: null });
    const uid = s.profile.id;
    if (!live || live.uid !== uid) startLive(uid);
    startPresence(uid, s.travel ? null : s.profile.location_id);
    if (!get().locations.length) void get().loadLocations();
  },

  loadLocations: async () => {
    const { data, error } = await supabase.from('locations').select('*').order('sort');
    if (error) {
      console.warn('[locations]', error.message);
      return;
    }
    const all = ((data ?? []) as Location[]).map((l) => ({ ...l, actions: l.actions ?? [] }));
    // F1 soft launch: hidden places get no pin and are not in Ride/search; byId keeps them for names.
    // R2 club switch: a switched-off club keeps its pin, shown as "Closed for now".
    const home = get().state?.profile.home_location_id;
    const locations = all.filter((l) => l.active !== false || l.id === home || l.scene === 'club');
    set({ locations, locationsById: Object.fromEntries(all.map((l) => [l.id, l])) });
  },

  loadEvents: async () => {
    const uid = get().session?.user.id;
    if (!uid) return;
    const { data, error } = await supabase
      .from('events')
      .select('*')
      .eq('user_id', uid)
      .order('id', { ascending: false })
      .limit(60);
    if (error) {
      console.warn('[events]', error.message);
      return;
    }
    const events = (data ?? []) as GameEvent[];
    eventsCursor = Math.max(eventsCursor ?? 0, events[0]?.id ?? 0);
    const lastRead = loadLastRead(uid);
    set({ events, lastReadEventId: lastRead, unread: events.filter((e) => e.id > lastRead && !e.read).length });
  },

  markEventsRead: () => {
    const uid = get().session?.user.id;
    const top = get().events[0]?.id ?? 0;
    if (uid) {
      try {
        localStorage.setItem(readKey(uid), String(top));
      } catch {
        /* private mode */
      }
    }
    set({ lastReadEventId: top, unread: 0 });
  },

  signOut: async () => {
    stopLive();
    useTasks.getState().clear(); // M2: the action queue never outlives the session
    await supabase.auth.signOut();
    set({ state: null, status: 'idle', events: [], unread: 0, error: null });
  },
}));

function scheduleRefresh(ms = 300) {
  if (refreshTimer) window.clearTimeout(refreshTimer);
  refreshTimer = window.setTimeout(() => {
    refreshTimer = null;
    void useGame.getState().refresh();
  }, ms);
}

/** A new row in `events` for me (Realtime INSERT or the poll-mode fetch). Dedupes by id. */
function onEventRow(ev: GameEvent) {
  if (useGame.getState().events.some((e) => e.id === ev.id)) return;
  eventsCursor = Math.max(eventsCursor ?? 0, ev.id);
  playCue('alert');
  useGame.setState((s) => ({
    events: [ev, ...s.events.filter((e) => e.id !== ev.id)].slice(0, 80),
    unread: s.unread + 1,
  }));
  // Street robbery already has its own modal (StatusBanners); hire/promotion already toast from the
  // RPC result (job_apply / work_finish), and so do pay_rent (data.settle) and bank_transfer (transfer_out). The events stay in Alerts.
  if (ev.kind === 'skill_up') {
    showLevelUp(ev.data as Record<string, unknown>, ev.title);
    scheduleRefresh(600);
    return;
  }
  if (ev.kind === 'challenge_done') {
    // R5: a small toast, then refresh the challenge list (the HUD chip and sheet)
    toast(ev.title, 'good');
    void useChallenges.getState().load();
    scheduleRefresh(600);
    return;
  }
  if (ev.kind === 'graduated') {
    showGraduation(ev.data as Record<string, unknown>, ev.title);
    scheduleRefresh(600);
    return;
  }
  if (!['robbed', 'hired', 'promoted', 'transfer_out', 'house_interact', 'steal_success', 'steal_caught'].includes(ev.kind) && !(ev.data as { settle?: boolean } | null)?.settle && !(ev.data as { quiet?: boolean } | null)?.quiet) toast(ev.body ? `${ev.title}${/[.!?…]$/.test(ev.title) ? '' : ':'} ${ev.body}` : ev.title, eventTone(ev.kind));
  scheduleRefresh(600);
}

/** F1: events newer than the cursor (poll mode, and once when Realtime comes back). Small: usually []. */
async function fetchNewEvents(uid: string) {
  if (eventsCursor == null) return; // loadEvents hasn't run yet: it sets the cursor (no toast flood)
  const { data, error } = await supabase.from('events').select('*').eq('user_id', uid).gt('id', eventsCursor)
    .order('id', { ascending: true }).limit(20);
  if (error || !live || live.uid !== uid) return;
  for (const ev of (data ?? []) as GameEvent[]) onEventRow(ev);
}

function startLive(uid: string) {
  stopLive();
  let polled = false;
  const unbind = bindRealtime((mode) => {
    if (mode === 'poll') {
      polled = true;
      const st = startPoller(() => useGame.getState().refresh(), () => POLL_STATE_MS);
      const ev = startPoller(() => fetchNewEvents(uid), () => POLL_EVENTS_MS);
      return () => { st.stop(); ev.stop(); };
    }
    const channel = trackSubscribe(supabase
      .channel(`me-${uid}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'profiles', filter: `id=eq.${uid}` }, (payload) => {
        // S1 scaling: get_my_state bumps last_seen, and that UPDATE comes straight back here. Without this check every
        // heartbeat cost two get_my_state calls. A real change in that window is picked up by the next heartbeat, and
        // anything another player does to you also inserts an event (handled below).
        const seen = Date.parse(String((payload.new as { last_seen?: string } | null)?.last_seen ?? ''));
        if (Date.now() - lastStateAt < 3000 && lastWriteAt() < lastStateAt - 1000 && Number.isFinite(seen) && Math.abs(seen - serverNow()) < 5000) return;
        scheduleRefresh();
      })
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'events', filter: `user_id=eq.${uid}` }, (payload) => onEventRow(payload.new as GameEvent)),
    'me', (status) => {
      // back from poll mode: catch up once (events dedupe by id)
      if (status === 'SUBSCRIBED' && polled) {
        polled = false;
        void fetchNewEvents(uid);
        scheduleRefresh(200);
      }
    });
    return () => void supabase.removeChannel(channel);
  });
  const heartbeat = window.setInterval(() => {
    // F1: in poll mode the faster state poller replaces the heartbeat
    if (document.visibilityState === 'visible' && !isPollMode()) void useGame.getState().refresh();
  }, HEARTBEAT_MS);
  const onVis = () => {
    if (document.visibilityState === 'visible') scheduleRefresh(50);
  };
  document.addEventListener('visibilitychange', onVis);
  live = { uid, unbind, heartbeat, onVis };
  void useGame.getState().loadEvents();
}

function stopLive() {
  stopPresence();
  eventsCursor = null;
  if (!live) return;
  live.unbind();
  window.clearInterval(live.heartbeat);
  document.removeEventListener('visibilitychange', live.onVis);
  live = null;
}

let authStarted = false;

/** Wire supabase auth → store. Call once at startup. */
export function initAuth(): void {
  if (authStarted || !supabaseConfigured) return;
  authStarted = true;
  ensureConfig();
  const onSession = (session: Session | null) => {
    const prevUid = useGame.getState().session?.user.id;
    const uid = session?.user.id;
    useGame.setState({ session, authReady: true });
    if (uid !== prevUid) {
      stopLive();
      useTasks.getState().clear();
      useGame.setState({ state: null, status: uid ? 'loading' : 'idle', events: [], unread: 0, error: null });
      if (uid) void useGame.getState().refresh();
    }
  };
  supabase.auth
    .getSession()
    .then(({ data }) => onSession(data.session))
    .catch(() => useGame.setState({ authReady: true }));
  supabase.auth.onAuthStateChange((event, session) => {
    // A password-reset link signs the player in. Send them to "choose a new password" wherever the
    // link landed (Supabase falls back to the site root when the redirect URL isn't allow-listed).
    if (event === 'PASSWORD_RECOVERY' && !/[?&]mode=reset\b/.test(window.location.search)) {
      window.location.replace('/auth?mode=reset');
      return;
    }
    // Defer: supabase warns against awaiting other calls inside this callback.
    window.setTimeout(() => onSession(session), 0);
  });
}
