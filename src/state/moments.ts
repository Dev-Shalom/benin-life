// Life moments (docs/MOMENTS.md): the cards the server has for me right now. ONE cheap read, moments_pending(), also rolls the next random
// card on the server when it is time, so the poll is the only trigger: every ~90 s while the tab is visible and the player is active
// (startPoller = canPoll + idleFactor, lib/activity.ts) and once when the game opens. <MomentsHost/> shows them one at a time.
import { create } from 'zustand';
import { momentsOpen, momentsPending, type HandledMoment, type Moment } from '../api/moments';
import { startPoller } from '../lib/realtime';

interface MomentsStore {
  /** Due cards, the one on screen first. */
  queue: Moment[];
  handled: HandledMoment[];
  pollSeconds: number;
  snoozeHours: number;
  load: () => Promise<void>;
  /** Put a card first (the "See the doctor" button) and make it the one on screen. */
  show: (m: Moment) => void;
  /** Take a card off the queue (answered or snoozed). */
  drop: (id: number) => void;
  dropHandled: (id: number) => void;
  reset: () => void;
}

export const useMoments = create<MomentsStore>((set, get) => ({
  queue: [],
  handled: [],
  pollSeconds: 90,
  snoozeHours: 2,
  load: async () => {
    const r = await momentsPending();
    if (!r.enabled) { set({ queue: [], handled: [] }); return; }
    // keep the order the server gave, but never move the card the player is looking at
    const cur = get().queue[0];
    let queue = r.moments;
    if (cur && queue.some((m) => m.id === cur.id)) queue = [queue.find((m) => m.id === cur.id) as Moment, ...queue.filter((m) => m.id !== cur.id)];
    set({ queue, handled: r.handled, pollSeconds: r.poll_seconds || 90, snoozeHours: r.snooze_hours ?? 2 });
  },
  show: (m) => set((s) => ({ queue: [m, ...s.queue.filter((x) => x.id !== m.id)] })),
  drop: (id) => set((s) => ({ queue: s.queue.filter((m) => m.id !== id) })),
  dropHandled: (id) => set((s) => ({ handled: s.handled.filter((h) => h.id !== id) })),
  reset: () => set({ queue: [], handled: [] }),
}));

/** Open a doctor card (or any card) by its instance id, from a button elsewhere in the game. */
export async function openMoment(instance: number): Promise<void> {
  const m = await momentsOpen(instance);
  useMoments.getState().show(m);
}

/** Start checking for cards: once now, then every ~90 s. Returns the stop function. */
export function startMoments(): () => void {
  const p = startPoller(() => useMoments.getState().load(), () => useMoments.getState().pollSeconds * 1000, { immediate: true });
  return () => { p.stop(); useMoments.getState().reset(); };
}
