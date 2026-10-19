// B2 Babalawo shrine state (docs/BABALAWO.md). The server is the source of truth (shrine_status / shrine_finish):
//   * shrine_status once when the game starts (the money charm pays on session start), then every 5 minutes, when the tab
//     comes back, and after shrine events; it returns my charms (Sim sheet chips), unseen popups (Baba's blessing,
//     backfire) and Baba's open weekly call;
//   * when a service timer runs out, shrine_finish rolls the outcome and the result popup shows Baba's line.
import { create } from 'zustand';
import { shrineFinish, shrineStatus, type Charm, type ShrineDemand, type ShrineNotice, type ShrineResult } from '../api/shrine';
import { errorMessage } from '../lib/api';
import { serverNow } from '../lib/clock';
import { playCue } from '../lib/sound';
import { toast } from '../ui';
import { useGame } from './game';
import { canPoll } from '../lib/activity';

interface ShrineStore {
  charms: Charm[];
  notices: ShrineNotice[];
  demand: ShrineDemand | null;
  visit: { id: number; service_id: string; resolve_at: string } | null;
  /** The last finished service, shown as a popup until closed. */
  result: ShrineResult | null;
  /** A zone card asked the Babalawo tab to scroll to this service. */
  focus: string | null;
  /** Bumped after anything changes (the Babalawo tab reloads). */
  version: number;
  load: () => Promise<void>;
  started: (v: { id: number; service_id: string; resolve_at: string }) => void;
  setResult: (r: ShrineResult | null) => void;
  setFocus: (id: string | null) => void;
}

let finishTimer: number | null = null;
let loading: Promise<void> | null = null;

function showResult(r: ShrineResult | null | undefined) {
  if (!r || r.already || r.status === 'none') return;
  playCue(r.status === 'done' ? 'done' : 'error');
  useShrine.setState((s) => ({ result: r, version: s.version + 1 }));
}

function scheduleFinish(resolveAt: string) {
  if (finishTimer != null) window.clearTimeout(finishTimer);
  const wait = Math.max(0, Date.parse(resolveAt) - serverNow()) + 350;
  let tries = 0;
  const run = async () => {
    finishTimer = null;
    try {
      const r = await shrineFinish();
      useShrine.setState({ visit: null });
      showResult(r);
    } catch (e) {
      const hint = (e as { hint?: string }).hint;
      if (hint === 'not_yet' && tries++ < 4) { finishTimer = window.setTimeout(run, 800); return; }
      useShrine.setState({ visit: null });
      if (hint !== 'no_visit') toast(errorMessage(e), 'bad');
    }
    void useGame.getState().refresh();
    void useShrine.getState().load();
  };
  finishTimer = window.setTimeout(run, wait);
}

export const useShrine = create<ShrineStore>((set) => ({
  charms: [],
  notices: [],
  demand: null,
  visit: null,
  result: null,
  focus: null,
  version: 0,
  load: () => {
    if (loading) return loading;
    loading = (async () => {
      try {
        const s = await shrineStatus();
        const before = useShrine.getState();
        set({ charms: s.charms ?? [], notices: s.notices ?? [], demand: s.demand ?? null, visit: s.visit,
              version: before.version + (s.resolved || (s.notices?.length ?? 0) > 0 ? 1 : 0) });
        if (s.resolved) showResult(s.resolved);
        if (s.visit) scheduleFinish(s.visit.resolve_at);
        if (s.resolved || (s.notices?.length ?? 0) > 0) void useGame.getState().refresh();
      } catch { /* offline: the next poll tries again */ }
    })().finally(() => { loading = null; });
    return loading;
  },
  started: (v) => {
    set({ visit: v });
    scheduleFinish(v.resolve_at);
  },
  setResult: (r) => set({ result: r }),
  setFocus: (id) => set({ focus: id }),
}));

const SHRINE_EVENTS = new Set(['baba_calling', 'baba_backfire']);
let started = false;

/** Follow my shrine state for the signed-in game. Returns a stop function. */
export function startShrine(): () => void {
  if (started) return () => undefined;
  started = true;
  void useShrine.getState().load();
  const poll = window.setInterval(() => {
    if (canPoll()) void useShrine.getState().load();
  }, 5 * 60_000);
  const onVis = () => { if (document.visibilityState === 'visible') void useShrine.getState().load(); };
  document.addEventListener('visibilitychange', onVis);
  let lastEvent = useGame.getState().events[0]?.id ?? 0;
  const unsub = useGame.subscribe((s) => {
    const top = s.events[0];
    if (top && top.id > lastEvent) {
      const fresh = s.events.filter((e) => e.id > lastEvent);
      lastEvent = top.id;
      if (fresh.some((e) => SHRINE_EVENTS.has(e.kind))) void useShrine.getState().load();
    }
  });
  return () => {
    started = false;
    unsub();
    window.clearInterval(poll);
    document.removeEventListener('visibilitychange', onVis);
    if (finishTimer != null) window.clearTimeout(finishTimer);
    finishTimer = null;
    useShrine.setState({ charms: [], notices: [], demand: null, visit: null, result: null });
  };
}
