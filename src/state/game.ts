// Game store — P1-SHELL. Session, GameState (via get_my_state), locations, events + realtime.
import { create } from 'zustand';
import type { RealtimeChannel, Session } from '@supabase/supabase-js';
import { supabase, supabaseConfigured } from '../lib/supabase';
import { rpc, errorMessage } from '../lib/api';
import { syncServerTime } from '../lib/clock';
import { ensureConfig } from '../lib/config';
import { normalizeAvatar } from '../art/avatar/catalog';
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

let live: { uid: string; channel: RealtimeChannel; heartbeat: number; onVis: () => void } | null = null;
let inflight: Promise<void> | null = null;
let refreshTimer: number | null = null;

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
  const profile = { ...raw.profile, avatar: normalizeAvatar(raw.profile?.avatar) };
  profile.cash = Number(profile.cash ?? 0);
  profile.bank = Number(profile.bank ?? 0);
  return { ...raw, profile };
}

/** Guess a toast tone from an event kind. */
export function eventTone(kind: string): ToastKind {
  const k = kind.toLowerCase();
  if (/rob|arrest|jail|raid|injur|hospital|theft|stolen|fine|ban|loss|fail|caught|wanted|debt|default/.test(k)) return 'bad';
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
        if (!data || !data.profile) {
          set({ status: 'noprofile', state: null });
          return;
        }
        if (data.server_time) syncServerTime(data.server_time, t0, t1);
        get().applyState(data);
      } catch (e) {
        const msg = errorMessage(e);
        // Distinguish "no profile yet" from real errors.
        let noProfile = looksLikeNoProfile(msg);
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
    if (s.server_time) syncServerTime(s.server_time);
    set({ state: s, status: 'ready', error: null });
    const uid = s.profile.id;
    if (!live || live.uid !== uid) startLive(uid);
    if (!get().locations.length) void get().loadLocations();
  },

  loadLocations: async () => {
    const { data, error } = await supabase.from('locations').select('*').order('sort');
    if (error) {
      console.warn('[locations]', error.message);
      return;
    }
    const locations = ((data ?? []) as Location[]).map((l) => ({ ...l, actions: l.actions ?? [] }));
    set({ locations, locationsById: Object.fromEntries(locations.map((l) => [l.id, l])) });
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

function startLive(uid: string) {
  stopLive();
  const channel = supabase
    .channel(`me-${uid}`)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'profiles', filter: `id=eq.${uid}` }, () =>
      scheduleRefresh(),
    )
    .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'events', filter: `user_id=eq.${uid}` }, (payload) => {
      const ev = payload.new as GameEvent;
      useGame.setState((s) => ({
        events: [ev, ...s.events.filter((e) => e.id !== ev.id)].slice(0, 80),
        unread: s.unread + 1,
      }));
      // Street robbery already has its own modal (StatusBanners); the event stays in Alerts.
      if (ev.kind !== 'robbed') toast(ev.body ? `${ev.title}${/[.!?…]$/.test(ev.title) ? '' : ':'} ${ev.body}` : ev.title, eventTone(ev.kind));
      scheduleRefresh(600);
    })
    .subscribe();
  const heartbeat = window.setInterval(() => {
    if (document.visibilityState === 'visible') void useGame.getState().refresh();
  }, HEARTBEAT_MS);
  const onVis = () => {
    if (document.visibilityState === 'visible') scheduleRefresh(50);
  };
  document.addEventListener('visibilitychange', onVis);
  live = { uid, channel, heartbeat, onVis };
  void useGame.getState().loadEvents();
}

function stopLive() {
  if (!live) return;
  void supabase.removeChannel(live.channel);
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
