// S1 scaling: one tiny connection-health store behind the "Reconnecting…" banner.
// Fed by the RPC wrapper (lib/api.ts), the browser online/offline events and the Realtime heartbeat.
// The game stays usable while the banner shows; it only tells the player why taps may be slow.
import { create } from 'zustand';
import { supabase } from '../lib/supabase';

interface NetStore {
  /** Consecutive RPC failures that look like a connection problem (0 / 429 / 5xx). */
  fails: number;
  browserOffline: boolean;
  realtimeDown: boolean;
  /** Last failure was a 429 (server busy) rather than a dead connection. */
  busy: boolean;
}

export const useNet = create<NetStore>(() => ({
  fails: 0,
  browserOffline: typeof navigator !== 'undefined' && navigator.onLine === false,
  realtimeDown: false,
  busy: false,
}));

export function netFailed(status: number) {
  useNet.setState((s) => ({ fails: s.fails + 1, busy: status === 429 }));
}

export function netOk() {
  if (useNet.getState().fails !== 0) useNet.setState({ fails: 0, busy: false });
}

/** True when the banner should show. Two failures in a row, so one blip doesn't flash it. */
export const selectReconnecting = (s: NetStore) => s.browserOffline || s.fails >= 2 || s.realtimeDown;

let started = false;
export function initNet() {
  if (started || typeof window === 'undefined') return;
  started = true;
  window.addEventListener('online', () => useNet.setState({ browserOffline: false, fails: 0 }));
  window.addEventListener('offline', () => useNet.setState({ browserOffline: true }));
  let downSince = 0;
  try {
    supabase.realtime.onHeartbeat((status) => {
      if (status === 'ok') {
        downSince = 0;
        if (useNet.getState().realtimeDown) useNet.setState({ realtimeDown: false });
      } else if (supabase.getChannels().length === 0) {
        downSince = 0; // no channels joined (landing, admin): an idle socket is not "down"
      } else if (status === 'timeout' || status === 'error' || status === 'disconnected') {
        // only after ~a minute of trouble: Realtime reconnects by itself (with jitter, lib/supabase.ts)
        if (!downSince) downSince = Date.now();
        else if (Date.now() - downSince > 45_000) useNet.setState({ realtimeDown: true });
      }
    });
  } catch {
    /* older realtime-js without onHeartbeat: RPC failures still drive the banner */
  }
}
