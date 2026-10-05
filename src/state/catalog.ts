// Read-only game data cached for the session (R4): activities (for the home furniture sheets and
// the busy pose) and the creator catalog (trait/dream/home names for the Sim sheet).
import { create } from 'zustand';
import { supabase } from '../lib/supabase';
import { getCreatorCatalog } from '../api/creator';
import type { CreatorCatalog } from '../lib/types';

export interface ActivityRow {
  id: string;
  name: string;
  scenes: string[];
  home_only: boolean;
  cost: number;
  game_minutes: number;
  effects: Record<string, number> | null;
  night_only: boolean;
  sort: number;
}

interface CatalogStore {
  activities: ActivityRow[] | null;
  catalog: CreatorCatalog | null;
  loadActivities: () => Promise<void>;
  loadCatalog: () => Promise<void>;
}

let actLoading: Promise<void> | null = null;
let catLoading: Promise<void> | null = null;

export const useCatalog = create<CatalogStore>((set, get) => ({
  activities: null,
  catalog: null,
  loadActivities: () => {
    if (get().activities) return Promise.resolve();
    actLoading ??= (async () => {
      const { data, error } = await supabase.from('activities').select('*').order('sort');
      if (!error) set({ activities: (data ?? []) as ActivityRow[] });
    })().finally(() => {
      actLoading = null;
    });
    return actLoading;
  },
  loadCatalog: () => {
    if (get().catalog) return Promise.resolve();
    catLoading ??= (async () => {
      try {
        set({ catalog: await getCreatorCatalog() });
      } catch {
        /* the sheet shows ids until it loads */
      }
    })().finally(() => {
      catLoading = null;
    });
    return catLoading;
  },
}));
