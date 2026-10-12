// SP1: which spray sheet is open (the dance floor / DJ booth / VIP "Spray money" cards open it).
import { create } from 'zustand';

interface SprayStore {
  open: { locationId: string; vip: boolean } | null;
  show: (locationId: string, vip: boolean) => void;
  close: () => void;
}

export const useSpray = create<SprayStore>((set) => ({
  open: null,
  show: (locationId, vip) => set({ open: { locationId, vip } }),
  close: () => set({ open: null }),
}));
