// UI store — P1-SHELL. Which sheet/panel is open on the game screen.
import { create } from 'zustand';
import type { PanelId } from '../lib/types';

export interface OpenPanel {
  id: PanelId;
  params?: Record<string, unknown>;
  /** Location passed to the panel; defaults to the player's current location. */
  locationId?: string;
}

export type Overlay = 'alerts' | 'settings' | null;

interface UiStore {
  selectedId: string | null;
  panel: OpenPanel | null;
  overlay: Overlay;
  needsOpen: boolean;
  select: (id: string | null) => void;
  openPanel: (id: PanelId, params?: Record<string, unknown>, locationId?: string) => void;
  closePanel: () => void;
  setOverlay: (o: Overlay) => void;
  toggleNeeds: () => void;
}

export const useUi = create<UiStore>((set) => ({
  selectedId: null,
  panel: null,
  overlay: null,
  needsOpen: false,
  select: (id) => set({ selectedId: id }),
  openPanel: (id, params, locationId) => set({ panel: { id, params, locationId } }),
  closePanel: () => set({ panel: null }),
  setOverlay: (overlay) => set({ overlay }),
  toggleNeeds: () => set((s) => ({ needsOpen: !s.needsOpen })),
}));

/** Open a global panel from anywhere (e.g. another panel): openPanel('profile', { targetId }). */
export function openPanel(id: PanelId, params?: Record<string, unknown>, locationId?: string) {
  useUi.getState().openPanel(id, params, locationId);
}
