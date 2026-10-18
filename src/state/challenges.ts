// R5 challenges store: caches challenge_status() for the HUD chip and the Challenges sheet.
import { create } from 'zustand';
import { challengeStatus, type ChallengeStatus } from '../api/challenges';

interface ChallengeStore {
  status: ChallengeStatus | null;
  loading: boolean;
  /** The Challenges sheet is open (and which tab). */
  sheet: 'daily' | 'weekly' | null;
  setSheet: (s: 'daily' | 'weekly' | null) => void;
  load: () => Promise<void>;
}

export const useChallenges = create<ChallengeStore>((set, get) => ({
  status: null,
  loading: false,
  sheet: null,
  setSheet: (sheet) => set({ sheet }),
  load: async () => {
    if (get().loading) return;
    set({ loading: true });
    try {
      set({ status: await challengeStatus() });
    } catch {
      /* an older server without R5, or offline: keep the last status (chip stays hidden when there is none) */
    } finally {
      set({ loading: false });
    }
  },
}));

/** What the HUD chip needs: how many are done / claimable, and whether any chest is ready. */
export function challengeSummary(s: ChallengeStatus | null) {
  if (!s?.enabled || !s.daily) return null;
  const all = [...(s.daily.items ?? []), ...(s.weekly?.items ?? [])];
  const dDone = s.daily.items.filter((c) => c.done).length;
  const claimable = all.filter((c) => c.done && !c.claimed).length;
  const chest = Boolean(s.daily.chest.ready || s.weekly?.chest.ready);
  const open = s.daily.items.some((c) => !c.done) || (s.weekly?.items ?? []).some((c) => !c.done);
  return { dDone, dTotal: s.daily.items.length, claimable, chest, ready: claimable > 0 || chest, open };
}
