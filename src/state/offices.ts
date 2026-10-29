// "My Office" state: does the player hold a seat right now? (server: office_mine). The phone app only shows while it says so. Refreshed at start,
// every few minutes, and when an office alert arrives. The server re-checks the seat on every action behind the app.
import { create } from 'zustand';
import { officeMine, type OfficeMine } from '../api/offices';
import { canPoll } from '../lib/activity';
import { useGame } from './game';

interface OfficeStore { mine: OfficeMine | null; load: () => Promise<void> }
let loading: Promise<void> | null = null;

export const useOffices = create<OfficeStore>((set) => ({
  mine: null,
  load: () => {
    if (loading) return loading;
    loading = (async () => {
      try { set({ mine: await officeMine() }); } catch { /* offline: the next trigger tries again */ }
    })().finally(() => { loading = null; });
    return loading;
  },
}));

const OFFICE_EVENTS = /^(ind_|pol_(won|appointed|sacked|removed))/;
let started = false;

/** Follow the seat for the signed-in game. Returns a stop function. */
export function startOffices(): () => void {
  if (started) return () => undefined;
  started = true;
  void useOffices.getState().load();
  const poll = window.setInterval(() => { if (canPoll()) void useOffices.getState().load(); }, 180_000);
  let last = useGame.getState().events[0]?.id ?? 0;
  const unsub = useGame.subscribe((g) => {
    const top = g.events[0];
    if (top && top.id > last) {
      const fresh = g.events.filter((e) => e.id > last);
      last = top.id;
      if (fresh.some((e) => OFFICE_EVENTS.test(e.kind))) void useOffices.getState().load();
    }
  });
  return () => { started = false; unsub(); window.clearInterval(poll); useOffices.setState({ mine: null }); };
}
