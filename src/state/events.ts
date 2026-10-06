// L4 events — today's and LIVE events for the whole city (events_on_today(), server-computed in WAT).
// One list for the map badges, the map place sheet's "On today", the top banner and the place card.
// Reloaded every 3 min, when the tab comes back, at the next start / end, and after a ticket is bought.
// `live` is re-derived on the client from starts_at / ends_at with the server-corrected clock, so the
// LIVE badge flips at kick-off without waiting for the next reload.
import { useEffect } from 'react';
import { create } from 'zustand';
import { eventsOnToday, type PlaceEvent } from '../api/events';
import { serverNow } from '../lib/clock';

interface EventsStore {
  list: PlaceEvent[];
  loaded: boolean;
  /** Banner items the player closed this session (id:occurs_on). */
  dismissed: string[];
}

export const useEvents = create<EventsStore>(() => ({ list: [], loaded: false, dismissed: readDismissed() }));

const DISMISS_KEY = 'bl.events.dismissed';
function readDismissed(): string[] {
  try {
    return JSON.parse(sessionStorage.getItem(DISMISS_KEY) ?? '[]') as string[];
  } catch {
    return [];
  }
}

export const occKey = (e: Pick<PlaceEvent, 'id' | 'occurs_on'>) => `${e.id}:${e.occurs_on}`;

export function dismissEvent(e: PlaceEvent) {
  const dismissed = [...useEvents.getState().dismissed.filter((k) => k !== occKey(e)), occKey(e)].slice(-40);
  useEvents.setState({ dismissed });
  try {
    sessionStorage.setItem(DISMISS_KEY, JSON.stringify(dismissed));
  } catch {
    /* private mode */
  }
}

/** Is it on now (client clock, server-corrected)? Ended ones are dropped by `current`. */
export const isLive = (e: PlaceEvent, now = serverNow()) => Date.parse(e.starts_at) <= now && Date.parse(e.ends_at) > now;

/** The list with `live` re-derived and finished events dropped. */
export function current(list: PlaceEvent[], now = serverNow()): PlaceEvent[] {
  return list.filter((e) => Date.parse(e.ends_at) > now).map((e) => (isLive(e, now) === e.live ? e : { ...e, live: isLive(e, now) }));
}

let inflight: Promise<void> | null = null;
export function reloadEvents(): Promise<void> {
  inflight ??= eventsOnToday()
    .then((list) => useEvents.setState({ list: list ?? [], loaded: true }))
    .catch(() => useEvents.setState({ loaded: true }))
    .finally(() => {
      inflight = null;
    });
  return inflight;
}

/** Replace one event in the list (after buying a ticket). */
export function patchEvent(e: PlaceEvent) {
  const { list } = useEvents.getState();
  useEvents.setState({ list: list.some((x) => x.id === e.id) ? list.map((x) => (x.id === e.id ? e : x)) : [...list, e] });
}

/** Mounted once by the game screen while signed in. */
export function useEventsLive(uid: string | null) {
  const list = useEvents((s) => s.list);
  useEffect(() => {
    if (!uid) return;
    void reloadEvents();
    const id = window.setInterval(() => void reloadEvents(), 180_000);
    const vis = () => document.visibilityState === 'visible' && void reloadEvents();
    document.addEventListener('visibilitychange', vis);
    return () => {
      window.clearInterval(id);
      document.removeEventListener('visibilitychange', vis);
    };
  }, [uid]);
  // reload just after the next start / end (a new day's events, the next one coming into the lead window)
  useEffect(() => {
    if (!uid || !list.length) return;
    const now = serverNow();
    const next = Math.min(...list.flatMap((e) => [Date.parse(e.starts_at), Date.parse(e.ends_at)]).filter((t) => t > now));
    if (!Number.isFinite(next)) return;
    const t = window.setTimeout(() => void reloadEvents(), Math.min(next - now + 1500, 2 ** 31 - 1));
    return () => window.clearTimeout(t);
  }, [uid, list]);
}

/** "in 2h 10m", "in 25 min" */
export function startsIn(e: PlaceEvent, now = serverNow()): string {
  const m = Math.max(0, Math.round((Date.parse(e.starts_at) - now) / 60000));
  if (m < 60) return `in ${Math.max(1, m)} min`;
  const h = Math.floor(m / 60);
  const r = m % 60;
  return r && h < 3 ? `in ${h}h ${r}m` : `in ${h}h`;
}
