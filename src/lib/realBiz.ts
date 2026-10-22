// Real-business pins on the map (docs/COMPANIES.md). One read-only RPC, cached for 5 minutes; no polling.
import { create } from 'zustand';
import { realBizMap, type RealPin } from '../api/company';

interface RealBizStore {
  pins: RealPin[];
  loadedAt: number;
  /** The showcase sheet (tap a pin on the map, or Discover). */
  sheet: string | null;
  load(force?: boolean): void;
  open(id: string): void;
  close(): void;
}
let inflight = false;
export const useRealBiz = create<RealBizStore>((set, get) => ({
  pins: [],
  loadedAt: 0,
  sheet: null,
  load(force = false) {
    if (inflight || (!force && get().loadedAt && Date.now() - get().loadedAt < 300_000)) return;
    inflight = true;
    realBizMap().then((r) => set({ pins: r.pins, loadedAt: Date.now() })).catch(() => {}).finally(() => { inflight = false; });
  },
  open: (id) => set({ sheet: id }),
  close: () => set({ sheet: null }),
}));
