// Own your home: the Houses app's data (docs/PROPERTY.md). One server call (property_overview) fills every tab; the server settles
// builds, rent income and tenancies lazily on that same call, so there is no polling.
import { create } from 'zustand';
import { propertyOverview, type PropOverview } from '../api/property';
import { useGame } from './game';
import { useGarage } from './garage';
import { useUpgrades } from './upgrades';

interface PropertyStore {
  data: PropOverview | null;
  error: string | null;
  loading: boolean;
  load: () => Promise<PropOverview | null>;
  /** After a move, a purchase or a sale: reload this, the player's state, the garage and the 3D home's upgrades. */
  afterAction: () => Promise<void>;
}

export const useProperty = create<PropertyStore>((set, get) => ({
  data: null,
  error: null,
  loading: false,
  load: async () => {
    set({ loading: true });
    try {
      const d = await propertyOverview();
      set({ data: d, error: null, loading: false });
      return d;
    } catch (e) {
      set({ error: e instanceof Error ? e.message : 'Could not load your homes.', loading: false });
      return get().data;
    }
  },
  afterAction: async () => {
    await Promise.all([get().load(), useGame.getState().refresh()]);
    useGarage.getState().bump();
    useUpgrades.getState().bump();
  },
}));
