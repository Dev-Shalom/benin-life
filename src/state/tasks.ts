// M2 action queue (client-side only; docs/HUD_HOME.md "M2 movement & task feel").
// The player taps tasks; they line up here and run one after another. The current task walks first
// ('walking': the Sim walks to its furniture), then its action RPC is called ('starting'), then the
// server's busy timer runs ('running'). The runner (src/screens/game/TaskRunner.tsx) drives the phases;
// the server stays authoritative (it refuses anything while busy). Lives in zustand, so it survives
// sheets opening and closing; cleared on logout, leaving home / travelling, jail, hospital, or when the
// server says the player is busy with something else.
import { create } from 'zustand';
import type { HomeGroup } from '../art/home3d/model';

export interface TaskItem {
  uid: string;
  /** Activity id (do_activity). */
  id: string;
  name: string;
  icon: string;
  /** Home furniture group to walk to first, or null (no walk: starts at once). */
  group: HomeGroup | null;
  /** Where it was queued (cleared when the player leaves). */
  locationId: string;
}

export type TaskPhase = 'walking' | 'starting' | 'running';

export interface CurrentTask extends TaskItem {
  phase: TaskPhase;
  /** busy_until the server gave when the action started ('running'). */
  busyUntil?: string;
}

interface TaskStore {
  current: CurrentTask | null;
  queue: TaskItem[];
  /** A floor tap took over a walk: wait for that walk to end before the next task. */
  holdUntil: number;
  /** Add a task. 'now' = it is the next to run (nothing else waiting), 'queued', or 'full'. */
  add: (t: Omit<TaskItem, 'uid'>, max: number) => 'now' | 'queued' | 'full';
  remove: (uid: string) => void;
  /** Move a queued task one place up (cheap reorder). */
  moveUp: (uid: string) => void;
  setCurrent: (c: CurrentTask | null) => void;
  patchCurrent: (p: Partial<CurrentTask>) => void;
  /** Next queued task becomes the current one (phase given by the runner). */
  popNext: (phase: TaskPhase) => CurrentTask | null;
  hold: (ms: number) => void;
  clear: () => void;
}

let seq = 0;

export const useTasks = create<TaskStore>((set, get) => ({
  current: null,
  queue: [],
  holdUntil: 0,
  add: (t, max) => {
    const { current, queue } = get();
    const count = (current ? 1 : 0) + queue.length;
    if (count >= Math.max(1, max)) return 'full';
    const item: TaskItem = { ...t, uid: `t${Date.now().toString(36)}${(seq++).toString(36)}` };
    set({ queue: [...queue, item] });
    return count === 0 ? 'now' : 'queued';
  },
  remove: (uid) => set((s) => ({ queue: s.queue.filter((q) => q.uid !== uid) })),
  moveUp: (uid) =>
    set((s) => {
      const i = s.queue.findIndex((q) => q.uid === uid);
      if (i <= 0) return s;
      const q = s.queue.slice();
      [q[i - 1], q[i]] = [q[i], q[i - 1]];
      return { queue: q };
    }),
  setCurrent: (current) => set({ current }),
  patchCurrent: (p) => set((s) => (s.current ? { current: { ...s.current, ...p } } : s)),
  popNext: (phase) => {
    const [next, ...rest] = get().queue;
    if (!next) return null;
    const current: CurrentTask = { ...next, phase };
    set({ current, queue: rest });
    return current;
  },
  hold: (ms) => set({ holdUntil: Date.now() + ms }),
  clear: () => set({ current: null, queue: [], holdUntil: 0 }),
}));

/** Icon for an activity (home ones by id, others generic). */
const ICONS: Record<string, string> = {
  sleep: '😴',
  nap: '💤',
  cook_home: '🍲',
  bathe: '🚿',
  use_toilet: '🚽',
  watch_tv: '📺',
  listen_radio: '📻',
  cold_drink: '🥤',
  relax_sofa: '🛋️',
  sit_rest: '🪑',
};
export function activityIcon(id: string | null | undefined, fallback = '✨'): string {
  return (id && ICONS[id]) || fallback;
}

/** "Walking to the bed…" */
export const WALK_TO: Record<HomeGroup, string> = {
  bed: 'the bed',
  kitchen: 'the kitchen',
  bath: 'the bath',
  toilet: 'the toilet',
  media: 'the TV',
  seat: 'a seat',
  wardrobe: 'the wardrobe',
};
