// Fix it 10: the vehicle the player drives (docs/FIXIT.md). The server decides (primary pick, else the most expensive one);
// this store only remembers the answer for the Cars app, the garage sheet and the 3D home.
import { create } from 'zustand';
import { carPrimaryGet, carSetPrimary } from '../api/garage';
import { useGarage } from './garage';

interface PrimaryCarStore {
  driving: string | null;
  load: () => Promise<void>;
  set: (item: string) => Promise<string>;
}

export const usePrimaryCar = create<PrimaryCarStore>((set) => ({
  driving: null,
  load: async () => {
    try { set({ driving: (await carPrimaryGet()).driving }); } catch { /* offline: keep the last answer */ }
  },
  set: async (item) => {
    const r = await carSetPrimary(item);
    set({ driving: r.driving });
    useGarage.getState().bump(); // the 3D home draws the picked car first
    return r.message;
  },
}));
