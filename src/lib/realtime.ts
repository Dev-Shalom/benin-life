// F1 Realtime fallback: one place that decides whether this tab uses Supabase Realtime ("live") or
// falls back to polling ("poll"), so the game keeps working when the plan's Realtime limits are hit
// (Free: 200 connections / 100 msg/s, Pro with spend cap: 500 / 500).
//
// How a tab ends up in poll mode:
//   * a channel join is refused with a quota / rate-limit reason (too_many_connections, TooManyChannels,
//     ConnectionRateLimitReached, ChannelRateLimitReached, ClientJoinRateLimitReached, "tenant events per
//     second" …): at once;
//   * FAIL_MAX separate failure incidents (CHANNEL_ERROR / TIMED_OUT / socket heartbeat errors, a burst within
//     3 s = one incident) within 90 s, with no successful join in between;
//   * channels exist but none has joined for 25 s (socket refused or unreachable);
//   * the owner set game_config realtime.mode = 'poll_only' (Admin → Settings): everyone, at once.
// In poll mode every feature drops its channels (the socket disconnects when none are left, so it stops
// retrying), and runs its polling fallback instead (only while the tab is visible, jittered).
// A probe re-tries one tiny channel every 2–5 min (longer after a relapse); when it joins, the tab
// goes back to live and features resubscribe (each one catches up and dedupes by id).
import { useEffect } from 'react';
import { create } from 'zustand';
import type { RealtimeChannel } from '@supabase/supabase-js';
import { supabase } from './supabase';

export type RtMode = 'live' | 'poll';

interface RtStore {
  mode: RtMode;
  /** The owner forced polling for everyone (config realtime.mode = poll_only). */
  forced: boolean;
  /** Why we are polling (debug / admin). */
  reason: string | null;
  since: number;
}

export const useRealtime = create<RtStore>(() => ({ mode: 'live', forced: false, reason: null, since: 0 }));

/** FAIL_MAX separate failure incidents within FAIL_WINDOW_MS. One socket drop errors every channel at once:
 *  failures closer than INCIDENT_GAP_MS count as one incident, so a single network blip never flips the mode. */
const FAIL_MAX = 3;
const FAIL_WINDOW_MS = 90_000;
const INCIDENT_GAP_MS = 3_000;
/** Channels exist but none has joined for this long (socket refused / unreachable: realtime-js reports a
 *  socket error to each channel only once, then waits silently): poll. */
const STUCK_MS = 25_000;
const PROBE_MIN_MS = 120_000;
const PROBE_SPREAD_MS = 180_000;
const PROBE_MAX_MS = 600_000;
/** Join refusals that mean "the project is over its Realtime quota": no point retrying soon. */
const QUOTA_RE = /too[_ ]many|TooManyChannels|TooManyConnections|RateLimitReached|rate.?limit|tenant events|events per second|quota|over.?limit|max.?(concurrent|connections|channels)/i;

let fails: number[] = [];
let probeTimer = 0;
let probeCh: RealtimeChannel | null = null;
let relapse = 0;
let lastRecover = 0;
let autoPoll = false; // auto-detected (not forced)

function apply() {
  const { forced } = useRealtime.getState();
  const mode: RtMode = forced || autoPoll ? 'poll' : 'live';
  if (useRealtime.getState().mode === mode) return;
  useRealtime.setState({ mode, since: Date.now(), reason: mode === 'live' ? null : useRealtime.getState().reason });
  if (import.meta.env.DEV) console.info(`[realtime] ${mode}${mode === 'poll' ? ` (${useRealtime.getState().reason})` : ''}`);
}

function enterPoll(reason: string) {
  fails = [];
  useRealtime.setState({ reason });
  if (!autoPoll) {
    // flapping (slot freed, then lost again quickly): wait longer before the next probe
    relapse = lastRecover && Date.now() - lastRecover < 180_000 ? Math.min(relapse + 1, 3) : 0;
    autoPoll = true;
  }
  apply();
  scheduleProbe();
}

function scheduleProbe() {
  window.clearTimeout(probeTimer);
  if (!autoPoll || useRealtime.getState().forced) return;
  const delay = Math.min(PROBE_MAX_MS, (PROBE_MIN_MS + Math.random() * PROBE_SPREAD_MS) * 2 ** relapse);
  probeTimer = window.setTimeout(probe, delay);
}

function probe() {
  if (!autoPoll || useRealtime.getState().forced) return;
  if (typeof document !== 'undefined' && document.visibilityState !== 'visible') {
    probeTimer = window.setTimeout(probe, 30_000); // a hidden tab doesn't need a slot
    return;
  }
  const ch = supabase.channel(`rt-probe-${Math.random().toString(36).slice(2, 8)}`);
  probeCh = ch;
  let done = false;
  const finish = (ok: boolean, why?: string) => {
    if (done) return;
    done = true;
    window.clearTimeout(guard);
    if (probeCh === ch) probeCh = null;
    if (ok && autoPoll) {
      autoPoll = false;
      lastRecover = Date.now();
      fails = [];
      apply(); // features resubscribe synchronously here, before the probe channel goes away
    } else if (!ok) {
      if (why) useRealtime.setState({ reason: why });
      scheduleProbe();
    }
    void supabase.removeChannel(ch);
  };
  const guard = window.setTimeout(() => finish(false, 'probe timed out'), 15_000);
  ch.subscribe((status, err) => {
    if (status === 'SUBSCRIBED') finish(true);
    else if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') finish(false, err?.message ?? status);
  });
}

/** Feed one Realtime failure (channel status / socket error / system message). */
export function reportRealtimeFailure(what: string, message?: string | null) {
  if (useRealtime.getState().mode === 'poll') return;
  const text = `${what}${message ? `: ${message}` : ''}`;
  if (message && QUOTA_RE.test(message)) return enterPoll(text);
  const now = Date.now();
  fails = fails.filter((t) => now - t < FAIL_WINDOW_MS);
  if (fails.length && now - fails[fails.length - 1] < INCIDENT_GAP_MS) return; // same incident
  fails.push(now);
  if (fails.length >= FAIL_MAX) enterPoll(text);
}

/** A channel joined: the connection works (clears the failure streak). */
export function reportRealtimeOk() {
  if (fails.length) fails = [];
}

let watchdog = 0;
let stuckSince = 0;
function startWatchdog() {
  if (watchdog || typeof window === 'undefined') return;
  watchdog = window.setInterval(() => {
    const chans = supabase.getChannels().filter((c) => c !== probeCh);
    if (useRealtime.getState().mode === 'poll' || !chans.length || document.visibilityState !== 'visible') {
      stuckSince = 0;
      return;
    }
    if (chans.some((c) => c.state === 'joined')) {
      stuckSince = 0;
      return;
    }
    if (!stuckSince) stuckSince = Date.now();
    else if (Date.now() - stuckSince >= STUCK_MS) {
      stuckSince = 0;
      enterPoll(`no channel joined for ${STUCK_MS / 1000} s`);
    }
  }, 5_000);
}

/**
 * Subscribe a channel and report its health. Use instead of `channel.subscribe(cb)` everywhere.
 * Also listens for server `system` errors (quota messages arrive there on a live channel).
 */
export function trackSubscribe(
  ch: RealtimeChannel,
  name: string,
  cb?: (status: 'SUBSCRIBED' | 'TIMED_OUT' | 'CLOSED' | 'CHANNEL_ERROR', err?: Error) => void,
): RealtimeChannel {
  startWatchdog();
  ch.on('system', {}, (payload: { status?: string; message?: string; extension?: string }) => {
    if (payload?.status === 'error' || (payload?.message && QUOTA_RE.test(payload.message))) {
      reportRealtimeFailure(`${name} system`, payload?.message ?? 'error');
    }
  });
  return ch.subscribe((status, err) => {
    if (status === 'SUBSCRIBED') reportRealtimeOk();
    else if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') reportRealtimeFailure(`${name} ${status}`, err?.message);
    cb?.(status, err);
  });
}

/** Owner switch (game_config realtime.mode). Called by lib/config whenever config values change. */
export function setForcedPoll(forced: boolean) {
  if (useRealtime.getState().forced === forced) return;
  useRealtime.setState({ forced, reason: forced ? 'admin: poll_only' : useRealtime.getState().reason });
  if (forced) window.clearTimeout(probeTimer);
  else if (autoPoll) scheduleProbe();
  apply();
}

export const rtMode = (): RtMode => useRealtime.getState().mode;
export const isPollMode = () => useRealtime.getState().mode === 'poll';

/** React: true while this tab polls instead of using Realtime. */
export function usePollMode(): boolean {
  return useRealtime((s) => s.mode === 'poll');
}

/**
 * Run `start(mode)` now and again whenever the mode flips (after running the previous cleanup).
 * `start` sets up the Realtime channel (live) or the poller (poll) and returns its cleanup.
 */
export function bindRealtime(start: (mode: RtMode) => (() => void) | void): () => void {
  let mode = rtMode();
  let cleanup = start(mode) || null;
  const unsub = useRealtime.subscribe((s) => {
    if (s.mode === mode) return;
    mode = s.mode;
    cleanup?.();
    cleanup = start(mode) || null;
  });
  return () => {
    unsub();
    cleanup?.();
    cleanup = null;
  };
}

export interface Poller {
  stop: () => void;
  /** Run soon (e.g. the chat panel just opened), then continue on the normal period. */
  kick: (delayMs?: number) => void;
}

/**
 * Jittered polling loop: runs `fn` every `periodMs()` (±20 %), only while the tab is visible; when the tab
 * comes back after a full period it runs at once. Errors are swallowed (the next tick retries).
 */
export function startPoller(fn: () => unknown, periodMs: () => number, opts: { immediate?: boolean } = {}): Poller {
  let timer = 0;
  let stopped = false;
  let last = 0;
  let running = false;
  const tick = async () => {
    if (stopped) return;
    if (document.visibilityState === 'visible' && !running) {
      running = true;
      last = Date.now();
      try {
        await fn();
      } catch {
        /* next tick retries */
      } finally {
        running = false;
      }
    }
    schedule();
  };
  const schedule = (ms?: number) => {
    window.clearTimeout(timer);
    if (stopped) return;
    const p = ms ?? periodMs() * (0.8 + Math.random() * 0.4);
    timer = window.setTimeout(() => void tick(), p);
  };
  const onVis = () => {
    if (document.visibilityState === 'visible' && Date.now() - last > periodMs()) schedule(300 + Math.random() * 1200);
  };
  document.addEventListener('visibilitychange', onVis);
  schedule(opts.immediate ? 0 : undefined);
  return {
    stop: () => {
      stopped = true;
      window.clearTimeout(timer);
      document.removeEventListener('visibilitychange', onVis);
    },
    kick: (delayMs = 0) => schedule(delayMs),
  };
}

/** React: a poller that only runs while `enabled`. */
export function usePoller(enabled: boolean, fn: () => unknown, periodMs: number, deps: unknown[] = []) {
  useEffect(() => {
    if (!enabled) return;
    const p = startPoller(fn, () => periodMs);
    return p.stop;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [enabled, periodMs, ...deps]);
}

/** Socket-level health, fed by state/net.ts's heartbeat callback (realtime-js keeps only one). */
export function realtimeHeartbeat(status: string) {
  if (status === 'ok') reportRealtimeOk();
  else if ((status === 'timeout' || status === 'error') && supabase.getChannels().length > (probeCh ? 1 : 0)) {
    reportRealtimeFailure(`socket ${status}`);
  }
}

if (import.meta.env.DEV && typeof window !== 'undefined') {
  (window as unknown as { __rt?: unknown }).__rt = {
    store: useRealtime,
    fail: (msg = 'too_many_connections') => reportRealtimeFailure('dev', msg),
    force: setForcedPoll,
    probe: () => { window.clearTimeout(probeTimer); probe(); },
  };
}
