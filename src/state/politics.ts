// R12 politics state (docs/POLITICS.md): the Benin Votes status. The server owns the clock (pol_status moves a cycle on, settles it and pays
// salaries lazily), so this store only asks it: at start, every few minutes (the election-day banner), faster while the app is open, and
// when a politics alert arrives.
import { create } from 'zustand';
import { polStatus, type PolStatus } from '../api/politics';
import { serverNow } from '../lib/clock';
import { useGame } from './game';

interface PoliticsStore {
  status: PolStatus | null;
  load: () => Promise<void>;
}

let loading: Promise<void> | null = null;
let timer: number | null = null;

/** Look again right after the next phase boundary, so the banner and the app flip on time. */
function schedule(s: PolStatus | null) {
  if (timer != null) window.clearTimeout(timer);
  timer = null;
  const at = s?.cycle?.next_at ?? null;
  if (!at) return;
  const wait = Date.parse(at) - serverNow() + 1500;
  if (wait > 0 && wait < 2_000_000_000) timer = window.setTimeout(() => { void usePolitics.getState().load(); }, wait);
}

export const usePolitics = create<PoliticsStore>((set) => ({
  status: null,
  load: () => {
    if (loading) return loading;
    loading = (async () => {
      try {
        const s = await polStatus();
        set({ status: s });
        schedule(s);
      } catch { /* offline: the next trigger tries again */ }
    })().finally(() => { loading = null; });
    return loading;
  },
}));

const POL_EVENTS = new Set(['pol_won', 'pol_lost', 'pol_appointed', 'pol_sacked', 'pol_removed', 'pol_disqualified', 'pol_cancelled', 'pol_rally', 'pol_ward_notice']);
let started = false;

/** Follow Benin Votes for the signed-in game. Returns a stop function. */
export function startPolitics(): () => void {
  if (started) return () => undefined;
  started = true;
  void usePolitics.getState().load();
  const poll = window.setInterval(() => { if (!document.hidden) void usePolitics.getState().load(); }, 120_000);
  let lastEvent = useGame.getState().events[0]?.id ?? 0;
  const unsub = useGame.subscribe((g) => {
    const top = g.events[0];
    if (top && top.id > lastEvent) {
      const fresh = g.events.filter((e) => e.id > lastEvent);
      lastEvent = top.id;
      if (fresh.some((e) => POL_EVENTS.has(e.kind))) void usePolitics.getState().load();
    }
  });
  return () => {
    started = false;
    unsub();
    window.clearInterval(poll);
    if (timer != null) window.clearTimeout(timer);
    timer = null;
    usePolitics.setState({ status: null });
  };
}
