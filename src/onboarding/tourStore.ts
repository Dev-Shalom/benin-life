// Tour + intro state (zustand) and the "tour done" flag. docs/ONBOARDING.md.
//
// "Done" is remembered twice: server-side in profiles.tour_done_at (migration 20261018000600_tour.sql, via the
// tour_done() RPC, so it follows the account to every device) and in localStorage as a fallback when the call fails.
import { create } from 'zustand';
import { rpc } from '../lib/api';
import { useGame } from '../state/game';
import { NEW_STEP_IDS, TOUR_STEPS, stepsById, toGame, type TourStep } from './tourSteps';

export type TourKind = 'full' | 'new' | 'show';

interface TourStore {
  active: boolean;
  kind: TourKind;
  steps: TourStep[];
  index: number;
  /** A full tour is waiting for the game screen to be ready (set when the intro ends). */
  queued: boolean;
  /** The "Take the tour?" prompt for existing players. */
  prompt: boolean;
  /** Start now. No ids = the full tour. */
  start: (ids?: string[], kind?: TourKind) => void;
  queueFull: () => void;
  go: (i: number) => void;
  next: () => void;
  back: () => void;
  /** End the tour. A full tour (finished or skipped) is saved as done. */
  stop: () => void;
  setPrompt: (v: boolean) => void;
}

const doneKey = (uid: string) => `bl.tour.done.${uid}`;

export function tourDoneLocal(uid: string): boolean {
  try { return window.localStorage.getItem(doneKey(uid)) === '1'; } catch { return false; }
}

/** True when this player has finished or dismissed the tour on this account or this device. */
export function isTourDone(profile: { id: string; tour_done_at?: string | null }): boolean {
  return Boolean(profile.tour_done_at) || tourDoneLocal(profile.id);
}

export function markTourDone(uid: string): void {
  try { window.localStorage.setItem(doneKey(uid), '1'); } catch { /* private browsing */ }
  void rpc('tour_done').then(() => {
    // keep the live profile in step so the prompt never comes back this session
    const s = useGame.getState().state;
    if (s && s.profile.id === uid && !s.profile.tour_done_at) {
      useGame.setState({ state: { ...s, profile: { ...s.profile, tour_done_at: new Date().toISOString() } } });
    }
  }).catch(() => { /* local flag is enough */ });
}

export const useTour = create<TourStore>((set, get) => ({
  active: false,
  kind: 'full',
  steps: TOUR_STEPS,
  index: 0,
  queued: false,
  prompt: false,
  start: (ids, kind) => {
    const steps = ids && ids.length ? stepsById(ids) : TOUR_STEPS;
    if (!steps.length) return;
    set({ active: true, kind: kind ?? (ids && ids.length ? 'show' : 'full'), steps, index: 0, queued: false, prompt: false });
  },
  queueFull: () => set({ queued: true }),
  go: (i) => set((s) => ({ index: Math.max(0, Math.min(s.steps.length - 1, i)) })),
  next: () => {
    const s = get();
    if (s.index >= s.steps.length - 1) s.stop();
    else set({ index: s.index + 1 });
  },
  back: () => set((s) => ({ index: Math.max(0, s.index - 1) })),
  stop: () => {
    const { kind, active } = get();
    if (!active) return;
    set({ active: false, queued: false });
    toGame();
    if (kind === 'full') {
      const uid = useGame.getState().state?.profile.id;
      if (uid) markTourDone(uid);
    }
  },
  setPrompt: (prompt) => set({ prompt }),
}));

// dev only: lets browser tests drive the app's own store instance (a fresh dynamic import can be a different module after HMR)
if (import.meta.env.DEV && typeof window !== 'undefined') (window as unknown as { __blTour?: typeof useTour }).__blTour = useTour;

export const startTour = (ids?: string[]) => useTour.getState().start(ids);
export const startWhatsNew = () => useTour.getState().start(NEW_STEP_IDS, 'new');
