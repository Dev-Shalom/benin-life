// Kids (docs/LOVE.md): the one cheap kids_status() read, shared by the Family icon's dot and the Family tab. It is loaded only while the phone is
// open (Phone.tsx runs the poller through lib/realtime startPoller: visible tab, not AFK, slower when idle) and after every care action.
import { create } from 'zustand';
import { kidsStatus, type KidsStatus } from '../api/kids';
import { serverNow } from '../lib/clock';

interface KidsStore {
  status: KidsStatus | null;
  /** serverNow() when the status was read (cooldown seconds count down from here). */
  at: number;
  error: string | null;
  load: () => Promise<void>;
  reset: () => void;
}

export const useKids = create<KidsStore>((set) => ({
  status: null,
  at: 0,
  error: null,
  load: async () => {
    try {
      const status = await kidsStatus();
      set({ status, at: serverNow(), error: null });
    } catch (e) {
      set({ error: e instanceof Error ? e.message : 'Could not load' });
    }
  },
  reset: () => set({ status: null, at: 0, error: null }),
}));
