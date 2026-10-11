// B1 arrange mode (inside Buy): which of the player's pieces is being moved and its unsaved spot.
// The 3D home draws the selected piece live at `sel` (HomeScene `ghost`); Done saves it with
// furniture_place, Store puts it back in the inventory (furniture_store). See src/screens/Game.tsx.
import { create } from 'zustand';
import { GRID_STEP } from '../art/home3d/arrange';

export interface ArrangeSel {
  key: string;
  x: number;
  z: number;
  rot: number;
  /** It came out of the inventory (Cancel leaves it there). */
  fromStore: boolean;
}

interface ArrangeStore {
  active: boolean;
  sel: ArrangeSel | null;
  /** Select this key as soon as its furniture is loaded (after buying, or from the owned list). */
  pending: string | null;
  open: (pending?: string | null) => void;
  close: () => void;
  select: (sel: ArrangeSel | null) => void;
  nudge: (dx: number, dz: number) => void;
  rotate: () => void;
  setPos: (x: number, z: number) => void;
  clearPending: () => void;
}

const r3 = (n: number) => Math.round(n * 1000) / 1000;

export const useArrange = create<ArrangeStore>((set) => ({
  active: false,
  sel: null,
  pending: null,
  open: (pending = null) => set({ active: true, pending, sel: null }),
  close: () => set({ active: false, sel: null, pending: null }),
  select: (sel) => set({ sel }),
  nudge: (dx, dz) => set((s) => (s.sel ? { sel: { ...s.sel, x: r3(s.sel.x + dx * GRID_STEP), z: r3(s.sel.z + dz * GRID_STEP) } } : s)),
  rotate: () => set((s) => (s.sel ? { sel: { ...s.sel, rot: (s.sel.rot + 1) % 4 } } : s)),
  setPos: (x, z) => set((s) => (s.sel ? { sel: { ...s.sel, x: r3(Math.round(x / 0.05) * 0.05), z: r3(Math.round(z / 0.05) * 0.05) } } : s)),
  clearPending: () => set({ pending: null }),
}));
