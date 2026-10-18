// R4 school state (docs/SCHOOL.md). The server is the source of truth (course_status / course_finish_class):
//   * course_status once when the game starts (finishes a class whose time ran out while away), when the School app opens and after every class;
//   * when the class timer runs out, course_finish_class rolls the exam and the result shows as a toast and in the app;
//   * a graduation is a `graduated` row in `events` (the server writes it when the last class passes, or an admin grants a certificate):
//     the game store hands it to showGraduation() and <SchoolHost/> shows the toast with confetti.
import { create } from 'zustand';
import { courseFinishClass, courseStatus, type CourseResult, type CourseRun, type CourseStatus } from '../api/school';
import { errorMessage } from '../lib/api';
import { serverNow } from '../lib/clock';
import { playCue } from '../lib/sound';
import { toast } from '../ui';
import { useGame } from './game';

export interface Graduation { id: number; cert: string; name: string; icon: string; title: string; unlocks: string[] }

interface SchoolStore {
  status: CourseStatus | null;
  run: CourseRun | null;
  /** The last finished class, shown in the app until the next one. */
  last: CourseResult | null;
  queue: Graduation[];
  load: () => Promise<void>;
  started: (r: CourseRun) => void;
  dismiss: () => void;
}

let finishTimer: number | null = null;
let loading: Promise<void> | null = null;

export function showClassResult(r: CourseResult | null | undefined) {
  if (!r || r.already || r.status === 'none') return;
  useSchool.setState({ last: r });
  const icon = r.icon ?? '🎓';
  if (r.outcome === 'fail') {
    playCue('error');
    toast(`${icon} ${r.message ?? 'You missed the pass mark. Retake the final class.'}`, 'bad');
  } else if (r.graduated) {
    // the graduation toast + confetti comes from the `graduated` event
    playCue('money');
  } else {
    playCue('done');
    toast(`${icon} ${r.message ?? 'Class done.'}`, 'good');
  }
}

function scheduleFinish(resolveAt: string) {
  if (finishTimer != null) window.clearTimeout(finishTimer);
  const wait = Math.max(0, Date.parse(resolveAt) - serverNow()) + 350;
  let tries = 0;
  const run = async () => {
    finishTimer = null;
    try {
      const r = await courseFinishClass();
      useSchool.setState({ run: null });
      showClassResult(r);
    } catch (e) {
      const hint = (e as { hint?: string }).hint;
      if (hint === 'not_yet' && tries++ < 4) { finishTimer = window.setTimeout(run, 800); return; }
      useSchool.setState({ run: null });
      if (hint !== 'no_run') toast(errorMessage(e), 'bad');
    }
    void useGame.getState().refresh();
    void useSchool.getState().load();
  };
  finishTimer = window.setTimeout(run, wait);
}

export const useSchool = create<SchoolStore>((set) => ({
  status: null,
  run: null,
  last: null,
  queue: [],
  load: () => {
    if (loading) return loading;
    loading = (async () => {
      try {
        const s = await courseStatus();
        set({ status: s, run: s.run });
        if (s.resolved) {
          showClassResult(s.resolved);
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
  dismiss: () => set((s) => ({ queue: s.queue.slice(1) })),
}));

let seq = 0;
/** Called for each new `graduated` event. */
export function showGraduation(data: Record<string, unknown> | null | undefined, title: string) {
  const d = (data ?? {}) as { cert?: string; name?: string; icon?: string; unlocks?: string[] };
  const g: Graduation = { id: ++seq, cert: d.cert ?? '', name: d.name ?? title, icon: d.icon ?? '🎓', title, unlocks: d.unlocks ?? [] };
  useSchool.setState((s) => ({ queue: [...s.queue, g].slice(-3) }));
  playCue('done');
  void useSchool.getState().load();
}

let started = false;

/** Follow my school state for the signed-in game. Returns a stop function. */
export function startSchool(): () => void {
  if (started) return () => undefined;
  started = true;
  void useSchool.getState().load();
  return () => {
    started = false;
    if (finishTimer != null) window.clearTimeout(finishTimer);
    finishTimer = null;
    useSchool.setState({ status: null, run: null, last: null, queue: [] });
  };
}
