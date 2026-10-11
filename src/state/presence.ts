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

function sync(ch: RealtimeChannel, loc: string) {
  if (channel !== ch) return;
  const ids = new Set(Object.keys(ch.presenceState()));
  if (me) ids.add(me);
  const sorted = [...ids].sort();
  const prev = usePresenceStore.getState();
  const same = prev.here === loc && prev.at[loc]?.join() === sorted.join();
  if (same) return; // keep identity so subscribers don't re-render
  usePresenceStore.setState({ here: loc, ids, at: { [loc]: sorted } });
}

function joinPlace(loc: string | null) {
  if (channel) void supabase.removeChannel(channel); // phx_leave: the server drops our key at once
  channel = null;
  joinedLoc = null;
  usePresenceStore.setState({ here: null, ids: new Set(), at: {} });
  if (!loc || !me) return;
  if ((usePresenceStore.getState().counts[loc] ?? 0) >= PRESENCE_MAX) return; // crowded: poll instead
  joinedLoc = loc;
  const ch = supabase.channel(`place:${loc}`, { config: { presence: { key: me } } });
  channel = ch;
  ch.on('presence', { event: 'sync' }, () => sync(ch, loc)).subscribe((status) => {
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
    if (joinedLoc && n >= PRESENCE_MAX * 1.5) joinPlace(null);
    else if (myLoc && !joinedLoc && n < PRESENCE_MAX) joinPlace(myLoc);
  } catch {
    /* older server / offline: keep the last numbers */
  }
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
