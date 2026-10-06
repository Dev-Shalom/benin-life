// S1 live counts: one global Supabase Realtime Presence channel ("online"), joined while a player is
// logged in with a Sim (startLive/stopLive in state/game.ts). Presence key = user id; payload = { l } =
// the place the Sim is at (null on the road). From the presence state we derive:
//   online      players connected right now (HUD pill, admin Overview)
//   at[loc]     the ids connected at each place (people-here list refresh + live count)
// No polling. Leaving: removeChannel on logout; the socket closing on unload drops the key on the server.
import { create } from 'zustand';
import type { RealtimeChannel } from '@supabase/supabase-js';
import { supabase } from '../lib/supabase';

interface PresenceStore {
  /** Players connected now; null until the first sync (or when Realtime is unavailable). */
  online: number | null;
  /** Place id -> sorted ids of players connected there. */
  at: Record<string, string[]>;
  /** All connected ids. */
  ids: Set<string>;
}

export const usePresenceStore = create<PresenceStore>(() => ({ online: null, at: {}, ids: new Set() }));

let channel: RealtimeChannel | null = null;
let me: string | null = null;
let myLoc: string | null = null;
let joined = false;

function sync() {
  if (!channel) return;
  const state = channel.presenceState<{ l?: string | null }>();
  const at: Record<string, string[]> = {};
  const ids = new Set<string>();
  for (const [id, metas] of Object.entries(state)) {
    ids.add(id);
    // a player with two tabs has two metas: count them once, at the newest place
    const l = metas[metas.length - 1]?.l;
    if (l) (at[l] ??= []).push(id);
  }
  for (const k of Object.keys(at)) at[k].sort();
  const prev = usePresenceStore.getState().at;
  // keep array identity for unchanged places so per-place subscribers don't re-render
  for (const k of Object.keys(at)) if (prev[k] && prev[k].join() === at[k].join()) at[k] = prev[k];
  usePresenceStore.setState({ online: ids.size, at, ids });
}

export function startPresence(uid: string, loc: string | null) {
  if (channel && me === uid) {
    setPresenceLoc(loc);
    return;
  }
  stopPresence();
  me = uid;
  myLoc = loc;
  joined = false;
  const ch = supabase.channel('online', { config: { presence: { key: uid } } });
  channel = ch;
  ch.on('presence', { event: 'sync' }, () => { if (channel === ch) sync(); })
    .subscribe((status) => {
      if (channel !== ch) return; // an old channel closing after logout / user switch
      if (status === 'SUBSCRIBED') {
        joined = true;
        void ch.track({ l: myLoc });
      } else if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT' || status === 'CLOSED') {
        joined = false;
        usePresenceStore.setState({ online: null, at: {}, ids: new Set() });
      }
    });
}

/** Update the place in our presence payload (cheap; only when it changes). */
export function setPresenceLoc(loc: string | null) {
  if (loc === myLoc) return;
  myLoc = loc;
  if (channel && joined) void channel.track({ l: loc });
}

export function stopPresence() {
  // removing the channel leaves it (phx_leave), so the server drops our presence key at once
  if (channel) void supabase.removeChannel(channel);
  channel = null;
  me = null;
  myLoc = null;
  joined = false;
  usePresenceStore.setState({ online: null, at: {}, ids: new Set() });
}

const EMPTY: string[] = [];
/** Ids connected at a place right now (stable array identity while unchanged). */
export function usePresentAt(loc: string | null): string[] {
  return usePresenceStore((s) => (loc ? (s.at[loc] ?? EMPTY) : EMPTY));
}
