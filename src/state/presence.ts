// Live counts (S1, rebuilt for the launch crowd).
//
// Before: ONE global Realtime Presence channel ("online") that every player joined. Presence sends
// every join/leave to every member, so with N players the traffic grows with N² and a few thousand
// players would blow the Realtime message quota and lag every tab.
//
// Now:
//   * a per-PLACE presence channel `place:<id>`, joined only while the Sim is at that place and left
//     on travel / logout. It gives the exact live list of players connected at MY place (people-here
//     list, live count). Traffic is (players at that place)² instead of (everyone)².
//   * the "players online" pill and the per-place crowd numbers on the map come from ONE cheap RPC,
//     world_counts() (profiles.last_seen, indexed), polled every ~60 s only while the tab is visible.
import { create } from 'zustand';
import type { RealtimeChannel } from '@supabase/supabase-js';
import { supabase } from '../lib/supabase';
import { rpc } from '../lib/api';
import { isPollMode, startPoller, trackSubscribe, useRealtime, type Poller } from '../lib/realtime';

interface PresenceStore {
  /** Players online (last_seen within the presence window); null until the first count. */
  online: number | null;
  /** Place id -> OTHER players seen there recently (server count, me excluded). */
  counts: Record<string, number>;
  /** The place whose live presence channel is joined and synced (null while joining / on the road). */
  here: string | null;
  /** Ids connected at `here` right now (me included). */
  ids: Set<string>;
  /** Compat: { [here]: sorted ids } — only the current place has a live list. */
  at: Record<string, string[]>;
}

export const usePresenceStore = create<PresenceStore>(() => ({ online: null, counts: {}, here: null, ids: new Set(), at: {} }));

let channel: RealtimeChannel | null = null;
let me: string | null = null;
let myLoc: string | null = null;
let pollTimer: number | null = null;
let lastPoll = 0;
let onVis: (() => void) | null = null;

const POLL_MS = 60_000;
/** Presence traffic grows with (players at the place)². Above this many other players at a place we skip the
 *  live channel and the people-here list falls back to a slow players_here poll (last_seen). */
const PRESENCE_MAX = 40;
let joinedLoc: string | null = null;
/** F1 poll mode: players_here_ids every ~25 s replaces the place presence channel. */
const HERE_POLL_MS = 25_000;
/** A player counts as "here" when their last_seen is this fresh (poll-mode tabs bump it every ~18 s, live ones every 60 s). */
const FRESH_MS = 100_000;
let herePoll: Poller | null = null;
/** F1 mixed mode: players at my place that are polling (not on the presence channel), found via players_here. */
let bridgeIds = new Set<string>();
let unsubMode: (() => void) | null = null;

interface HereRow { id: string; last_seen?: string }
function freshIds(rows: HereRow[] | null | undefined): Set<string> {
  const now = Date.now();
  const out = new Set<string>();
  for (const r of rows ?? []) {
    const t = Date.parse(String(r.last_seen ?? ''));
    if (!Number.isFinite(t) || now - t < FRESH_MS) out.add(r.id);
  }
  return out;
}

function setHere(loc: string, ids: Set<string>) {
  if (me) ids.add(me);
  const sorted = [...ids].sort();
  const prev = usePresenceStore.getState();
  if (prev.here === loc && prev.at[loc]?.join() === sorted.join()) return; // keep identity
  usePresenceStore.setState({ here: loc, ids, at: { [loc]: sorted } });
}

function sync(ch: RealtimeChannel, loc: string) {
  if (channel !== ch) return;
  setHere(loc, new Set([...Object.keys(ch.presenceState()), ...bridgeIds]));
}

/** F1 poll mode: the people-here list from players_here_ids (fresh last_seen) instead of Presence. */
async function pollHere(loc: string) {
  const rows = await rpc<HereRow[]>('players_here_ids', { p_location: loc }); // ids only: tiny payload
  if (myLoc !== loc || !isPollMode()) return;
  setHere(loc, freshIds(rows));
}

function joinPlace(loc: string | null) {
  if (channel) void supabase.removeChannel(channel); // phx_leave: the server drops our key at once
  channel = null;
  joinedLoc = null;
  herePoll?.stop();
  herePoll = null;
  bridgeIds = new Set();
  usePresenceStore.setState({ here: null, ids: new Set(), at: {} });
  if (!loc || !me) return;
  if (isPollMode()) {
    herePoll = startPoller(() => pollHere(loc), () => HERE_POLL_MS, { immediate: true });
    return;
  }
  if ((usePresenceStore.getState().counts[loc] ?? 0) >= PRESENCE_MAX) return; // crowded: poll instead
  joinedLoc = loc;
  const ch = supabase.channel(`place:${loc}`, { config: { presence: { key: me } } });
  channel = ch;
  trackSubscribe(ch.on('presence', { event: 'sync' }, () => sync(ch, loc)), 'presence', (status) => {
    if (channel !== ch) return; // an old channel closing after travel / logout
    if (status === 'SUBSCRIBED') {
      void ch.track({ t: 1 }); // tiny payload; tracked once per place
      sync(ch, loc);
    } else if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT' || status === 'CLOSED') {
      usePresenceStore.setState({ here: null, ids: new Set(), at: {} });
    }
  });
}

async function poll(force = false) {
  if (!me) return;
  if (!force && (document.visibilityState !== 'visible' || Date.now() - lastPoll < POLL_MS / 2)) return;
  lastPoll = Date.now();
  try {
    const r = await rpc<{ online?: number; at?: Record<string, number> }>('world_counts');
    if (!me) return;
    usePresenceStore.setState({ online: Number(r?.online ?? 0), counts: r?.at ?? {} });
    // the place got crowded: drop the live channel (or it emptied out: join it)
    const n = myLoc ? (r?.at?.[myLoc] ?? 0) : 0;
    if (isPollMode()) return; // F1: players_here polling covers my place
    if (joinedLoc && n >= PRESENCE_MAX * 1.5) joinPlace(null);
    else if (myLoc && !joinedLoc && n < PRESENCE_MAX) joinPlace(myLoc);
    else if (joinedLoc && channel && myLoc === joinedLoc) void bridge(myLoc, n);
  } catch {
    /* older server / offline: keep the last numbers */
  }
}

/**
 * F1 mixed mode: some players at my place may be polling (Realtime full for them), so they are not on the
 * presence channel. When the server counts more players here than Presence shows, fetch players_here once and
 * add the fresh ones. Costs nothing while the numbers agree (at most one call per world_counts poll).
 */
async function bridge(loc: string, serverOthers: number) {
  const ch = channel;
  if (!ch) return;
  const presenceOthers = Object.keys(ch.presenceState()).filter((id) => id !== me).length;
  if (serverOthers <= presenceOthers) {
    if (bridgeIds.size) { bridgeIds = new Set(); sync(ch, loc); }
    return;
  }
  try {
    const rows = await rpc<HereRow[]>('players_here_ids', { p_location: loc });
    if (channel !== ch) return;
    const live = new Set(Object.keys(ch.presenceState()));
    bridgeIds = new Set([...freshIds(rows)].filter((id) => !live.has(id)));
    sync(ch, loc);
  } catch { /* keep what we have */ }
}

export function startPresence(uid: string, loc: string | null) {
  if (me === uid) {
    setPresenceLoc(loc);
    return;
  }
  stopPresence();
  me = uid;
  myLoc = loc;
  joinPlace(loc);
  void poll(true);
  // jitter the period so a crowd that loaded together doesn't poll in lockstep
  pollTimer = window.setInterval(() => void poll(), POLL_MS + Math.round(Math.random() * 15_000));
  onVis = () => void poll();
  document.addEventListener('visibilitychange', onVis);
  // F1: live <-> poll switch: rejoin the place the new way
  let mode = useRealtime.getState().mode;
  unsubMode = useRealtime.subscribe((s) => {
    if (s.mode === mode) return;
    mode = s.mode;
    if (me) joinPlace(myLoc);
  });
}

/** Move our presence to another place (only when it changes). */
export function setPresenceLoc(loc: string | null) {
  if (loc === myLoc) return;
  myLoc = loc;
  joinPlace(loc);
}

export function stopPresence() {
  if (channel) void supabase.removeChannel(channel);
  channel = null;
  herePoll?.stop();
  herePoll = null;
  bridgeIds = new Set();
  unsubMode?.();
  unsubMode = null;
  me = null;
  myLoc = null;
  lastPoll = 0;
  if (pollTimer) window.clearInterval(pollTimer);
  pollTimer = null;
  if (onVis) document.removeEventListener('visibilitychange', onVis);
  onVis = null;
  usePresenceStore.setState({ online: null, counts: {}, here: null, ids: new Set(), at: {} });
}

const EMPTY: string[] = [];
/** Ids connected at a place right now: only known live for the place the Sim is at (else []). */
export function usePresentAt(loc: string | null): string[] {
  return usePresenceStore((s) => (loc ? (s.at[loc] ?? EMPTY) : EMPTY));
}

/** True when `loc` has a live presence list (it's my place and the channel is synced). */
export function usePresenceLiveAt(loc: string | null): boolean {
  return usePresenceStore((s) => loc !== null && s.here === loc);
}

/** Other players at a place: exact live number at my place, the server's recent count elsewhere. */
export function useOthersAt(loc: string | null, meId: string | null | undefined): number {
  return usePresenceStore((s) => {
    if (!loc) return 0;
    if (s.here === loc) return (s.at[loc] ?? EMPTY).filter((id) => id !== meId).length;
    return s.counts[loc] ?? 0;
  });
}

if (import.meta.env.DEV) (window as unknown as { __presence?: unknown }).__presence = usePresenceStore;
