// R7 lounge store: the membership sheet (open from the place sheet, the lounge card, the Friends tab) and its cached status.
import { create } from 'zustand';
import { loungeStatus, type LoungeStatus } from '../api/lounge';

interface LoungeStore {
  open: boolean;
  status: LoungeStatus | null;
  loading: boolean;
  show: () => void;
  hide: () => void;
  load: () => Promise<void>;
  set: (s: LoungeStatus) => void;
}

export const useLounge = create<LoungeStore>((set, get) => ({
  open: false,
  status: null,
  loading: false,
  show: () => { set({ open: true }); void get().load(); },
  hide: () => set({ open: false }),
  set: (status) => set({ status }),
  load: async () => {
    if (get().loading) return;
    set({ loading: true });
    try {
      set({ status: await loungeStatus() });
    } catch {
      /* an older server without R7: the sheet shows its empty state */
    } finally {
      set({ loading: false });
    }
  },
}));
