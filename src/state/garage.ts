// G1: the garage sheet (after buying a car, or "Build a garage" at home) and a version bump so the
// 3D home reloads its parked cars after a purchase or a build. docs/GARAGE.md
import { create } from 'zustand';

interface GarageStore {
  /** Open sheet: 'car' = right after a car purchase, 'home' = from the home sheet. */
  sheet: 'car' | 'home' | null;
  /** Name of the car just bought (sheet copy). */
  carName: string | null;
  /** Bumped after a car purchase or a garage build. */
  version: number;
  open: (reason: 'car' | 'home', carName?: string | null) => void;
  close: () => void;
  bump: () => void;
}

export const useGarage = create<GarageStore>((set) => ({
  sheet: null,
  carName: null,
  version: 0,
  open: (reason, carName = null) => set((s) => ({ sheet: reason, carName, version: s.version + 1 })),
  close: () => set({ sheet: null }),
  bump: () => set((s) => ({ version: s.version + 1 })),
}));

/** Call after any successful shop_buy: a car purchase opens the garage offer. */
export function afterPurchase(res: { car?: boolean; item?: string } | null | undefined, carName?: string | null) {
  if (!res?.car) return;
  if (res.item === 'bicycle' || res.item === 'bajaj_boxer') { useGarage.getState().bump(); return; }
  useGarage.getState().open('car', carName ?? null);
}
