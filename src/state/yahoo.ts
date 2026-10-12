// Y1 Yahoo state (docs/YAHOO.md). The server is the source of truth (yahoo_status / yahoo_finish):
//   * yahoo_status once when the game starts (finishes a job whose time ran out while away), when the Yahoo app opens,
//     after a job, and after Yahoo / EFCC events;
//   * when a job timer runs out, yahoo_finish rolls the outcome: paid → toast, caught → the C1 jail popup (EFCC copy).
import { create } from 'zustand';
import { yahooFinish, yahooStatus, type YahooResult, type YahooRun, type YahooStatus } from '../api/yahoo';
import { errorMessage } from '../lib/api';
import { serverNow } from '../lib/clock';
import { naira } from '../lib/format';
import { playCue } from '../lib/sound';
import { toast } from '../ui';
import { useCrime } from './crime';
import { useGame } from './game';

interface YahooStore {
  status: YahooStatus | null;
  run: YahooRun | null;
  /** The last finished job, shown in the app until the next one. */
  last: YahooResult | null;
  load: () => Promise<void>;
  started: (r: YahooRun) => void;
}

let finishTimer: number | null = null;
let loading: Promise<void> | null = null;

export function showYahooResult(r: YahooResult | null | undefined) {
  if (!r || r.already || r.status === 'none') return;
  useYahoo.setState({ last: r });
  if (r.status === 'paid') {
    playCue('money');
    toast(`💻 Client paid: +${naira(r.amount)} (yahoo balance)`, 'good');
    if (r.rank_up) toast(`${r.rank_up.icon} You don rise: ${r.rank_up.name}!`, 'good');
  } else if (r.status === 'cashed') {
    playCue('money');
    toast(`💸 Cash out don land: +${naira(r.amount)} cash`, 'good');
  } else if (r.status === 'caught') {
    playCue('error');
    if (r.case) useCrime.getState().setCase(r.case);
    else void useCrime.getState().load();
  }
}

function scheduleFinish(resolveAt: string) {
  if (finishTimer != null) window.clearTimeout(finishTimer);
  const wait = Math.max(0, Date.parse(resolveAt) - serverNow()) + 350;
  let tries = 0;
  const run = async () => {
    finishTimer = null;
    try {
      const r = await yahooFinish();
      useYahoo.setState({ run: null });
      showYahooResult(r);
    } catch (e) {
      const hint = (e as { hint?: string }).hint;
      if (hint === 'not_yet' && tries++ < 4) { finishTimer = window.setTimeout(run, 800); return; }
      useYahoo.setState({ run: null });
      if (hint !== 'no_run') toast(errorMessage(e), 'bad');
    }
    void useGame.getState().refresh();
    void useYahoo.getState().load();
  };
  finishTimer = window.setTimeout(run, wait);
}

export const useYahoo = create<YahooStore>((set) => ({
  status: null,
  run: null,
  last: null,
  load: () => {
    if (loading) return loading;
    loading = (async () => {
      try {
        const s = await yahooStatus();
        set({ status: s, run: s.run });
        if (s.resolved) {
          showYahooResult(s.resolved);
          void useGame.getState().refresh();
        }
        if (s.run) scheduleFinish(s.run.resolve_at);
      } catch { /* offline: the next trigger tries again */ }
    })().finally(() => { loading = null; });
    return loading;
  },
  started: (r) => {
    set({ run: r });
    scheduleFinish(r.resolve_at);
  },
}));

const YAHOO_EVENTS = new Set(['efcc_caught', 'yahoo_rank_up', 'police_release']);
let started = false;

/** Follow my Yahoo state for the signed-in game. Returns a stop function. */
export function startYahoo(): () => void {
  if (started) return () => undefined;
  started = true;
  void useYahoo.getState().load();
  let lastEvent = useGame.getState().events[0]?.id ?? 0;
  const unsub = useGame.subscribe((s) => {
    const top = s.events[0];
    if (top && top.id > lastEvent) {
      const fresh = s.events.filter((e) => e.id > lastEvent);
      lastEvent = top.id;
      if (fresh.some((e) => YAHOO_EVENTS.has(e.kind))) void useYahoo.getState().load();
    }
  });
  return () => {
    started = false;
    unsub();
    if (finishTimer != null) window.clearTimeout(finishTimer);
    finishTimer = null;
    useYahoo.setState({ status: null, run: null, last: null });
  };
}
