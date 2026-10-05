// UI store — P1-SHELL, extended in R4. Which sheet/panel/overlay is open on the game screen.
import { create } from 'zustand';
import type { PanelId } from '../lib/types';
import type { HomeGroup } from '../art/home3d/model';

export interface OpenPanel {
  id: PanelId;
  params?: Record<string, unknown>;
  /** Location passed to the panel; defaults to the player's current location. */
  locationId?: string;
}

/** Full-screen overlays (one at a time). 'settings' is kept as an alias for the Sim sheet's Settings tab. */
export type Overlay = 'alerts' | 'settings' | 'phone' | 'sim' | 'buy' | 'shortcuts' | 'look' | null;

export type SimTab = 'profile' | 'needs' | 'goals' | 'skills' | 'people' | 'career' | 'settings';

interface UiStore {
  selectedId: string | null;
  /** Tab to open first in the location sheet (e.g. 'jobs' from "Go to work"). */
  selectedTab: PanelId | null;
  panel: OpenPanel | null;
  overlay: Overlay;
  simTab: SimTab;
  /** At home: the player picked the map instead of the 3D home. */
  mapOpen: boolean;
  /** Tapped furniture in the 3D home (opens its activity sheet). */
  homePick: { id: string | null; group: HomeGroup } | null;
  /** Phone app to open with the phone (e.g. 'alerts'). */
  phoneApp: string | null;
  select: (id: string | null, tab?: PanelId | null) => void;
  openPanel: (id: PanelId, params?: Record<string, unknown>, locationId?: string) => void;
  closePanel: () => void;
  setOverlay: (o: Overlay) => void;
  openSim: (tab?: SimTab) => void;
  openPhone: (app?: string | null) => void;
  setMapOpen: (v: boolean) => void;
  pickHome: (p: { id: string | null; group: HomeGroup } | null) => void;
  /** Close every sheet/overlay (used before switching views). */
  closeAll: () => void;
}

export const useUi = create<UiStore>((set) => ({
  selectedId: null,
  selectedTab: null,
  panel: null,
  overlay: null,
  simTab: 'profile',
  mapOpen: false,
  homePick: null,
  phoneApp: null,
  select: (id, tab = null) => set({ selectedId: id, selectedTab: tab }),
  openPanel: (id, params, locationId) => set({ panel: { id, params, locationId } }),
  closePanel: () => set({ panel: null }),
  setOverlay: (overlay) => (overlay === 'settings' ? set({ overlay: 'sim', simTab: 'settings' }) : set({ overlay })),
  openSim: (tab) => set((s) => ({ overlay: 'sim', simTab: tab ?? s.simTab })),
  openPhone: (app = null) => set({ overlay: 'phone', phoneApp: app }),
  setMapOpen: (mapOpen) => set({ mapOpen }),
  pickHome: (homePick) => set({ homePick }),
  closeAll: () => set({ selectedId: null, panel: null, overlay: null, homePick: null }),
}));

/** Open a global panel from anywhere (e.g. another panel): openPanel('profile', { targetId }). */
export function openPanel(id: PanelId, params?: Record<string, unknown>, locationId?: string) {
  useUi.getState().openPanel(id, params, locationId);
}
