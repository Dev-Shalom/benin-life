// E2 hustles state (docs/HUSTLES.md). The server is the source of truth (hustle_status / hustle_finish):
//   * hustle_status once when the game starts (finishes a hustle whose time ran out while away), when the Hustles app opens
//     and after every hustle;
//   * when the timer runs out, hustle_finish rolls the outcome and the result shows as a toast and in the app.
import { create } from 'zustand';
import { hustleFinish, hustleStatus, type HustleResult, type HustleRun, type HustleStatus } from '../api/hustles';
import { errorMessage } from '../lib/api';
import { serverNow } from '../lib/clock';
import { naira } from '../lib/format';
import { playCue } from '../lib/sound';
import { toast } from '../ui';
import { useGame } from './game';

interface HustleStore {
  status: HustleStatus | null;
  run: HustleRun | null;
  /** The last finished hustle, shown in the app until the next one. */
  last: HustleResult | null;
  load: () => Promise<void>;
  started: (r: HustleRun) => void;
}

let finishTimer: number | null = null;
let loading: Promise<void> | null = null;

export function showHustleResult(r: HustleResult | null | undefined) {
  if (!r || r.already || r.status === 'none') return;
  useHustles.setState({ last: r });
  const icon = r.icon ?? '💪';
  if (r.outcome === 'loss') {
    playCue('error');
    toast(`${icon} ${r.message ?? 'You lost money.'}`, 'bad');
  } else if (r.fish) {
    playCue('money');
    toast(`🎣 ${r.message ?? `You caught a ${r.fish.name}!`}`, 'good');
  } else if (r.kind === 'fishing') {
    toast(`🎣 ${r.message ?? 'Nothing bit.'}`, 'info');
  } else if (r.amount > 0) {
    playCue('money');
    toast(`${icon} ${r.message ?? `+${naira(r.amount)}`}`, r.outcome === 'risk' ? 'info' : 'good');
  } else {
    toast(`${icon} ${r.message ?? 'No pay this time.'}`, 'info');
  }
}

function scheduleFinish(resolveAt: string) {
  if (finishTimer != null) window.clearTimeout(finishTimer);
  const wait = Math.max(0, Date.parse(resolveAt) - serverNow()) + 350;
  let tries = 0;
  const run = async () => {
    finishTimer = null;
    try {
      const r = await hustleFinish();
      useHustles.setState({ run: null });
      showHustleResult(r);
    } catch (e) {
      const hint = (e as { hint?: string }).hint;
      if (hint === 'not_yet' && tries++ < 4) { finishTimer = window.setTimeout(run, 800); return; }
      useHustles.setState({ run: null });
      if (hint !== 'no_run') toast(errorMessage(e), 'bad');
    }
    void useGame.getState().refresh();
    void useHustles.getState().load();
  };
  finishTimer = window.setTimeout(run, wait);
}

export const useHustles = create<HustleStore>((set) => ({
  status: null,
  run: null,
  last: null,
  load: () => {
    if (loading) return loading;
    loading = (async () => {
      try {
        const s = await hustleStatus();
        set({ status: s, run: s.run });
        if (s.resolved) {
          showHustleResult(s.resolved);
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

let started = false;

/** Follow my hustle state for the signed-in game. Returns a stop function. */
export function startHustles(): () => void {
  if (started) return () => undefined;
  started = true;
  void useHustles.getState().load();
  return () => {
    started = false;
    if (finishTimer != null) window.clearTimeout(finishTimer);
    finishTimer = null;
    useHustles.setState({ status: null, run: null, last: null });
  };
}
