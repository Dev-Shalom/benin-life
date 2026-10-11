// H1: the "Move into your new home?" confirm sheet, opened from the phone's Houses app.
import { create } from 'zustand';
import type { HouseOption } from '../api/houses';

interface MoveStore {
  /** The home to confirm, with the garage that would stay behind. */
  pick: { home: HouseOption; garage: string | null; weeks: number } | null;
  open: (home: HouseOption, garage: string | null, weeks: number) => void;
  close: () => void;
}

export const useMove = create<MoveStore>((set) => ({
  pick: null,
  open: (home, garage, weeks) => set({ pick: { home, garage, weeks } }),
  close: () => set({ pick: null }),
}));
