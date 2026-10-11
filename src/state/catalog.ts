// Read-only game data cached for the session (R4): activities (for the home furniture sheets and
// the busy pose) and the creator catalog (trait/dream/home names for the Sim sheet).
import { create } from 'zustand';
import { supabase } from '../lib/supabase';
import { getCreatorCatalog } from '../api/creator';
import type { CreatorCatalog } from '../lib/types';
import type { OwnedPiece } from '../art/home3d/model';

export interface ActivityRow {
  id: string;
  name: string;
  scenes: string[];
  home_only: boolean;
  cost: number;
  game_minutes: number;
  max_seconds?: number | null; // L1 short actions
  min_seconds?: number | null;
  scale_by_need?: boolean | null;
  effects: Record<string, number> | null;
  night_only: boolean;
  sort: number;
  /** Offered at home only with a piece of furniture that lists it (starter furniture). */
  needs_furniture?: boolean | null;
  /** L2: emoji for cards and the task pill. */
  icon?: string | null;
}

/** Can the player do this home activity with the furniture they own? (null furniture = not loaded: allow) */
export function hasFurnitureFor(a: Pick<ActivityRow, 'id' | 'needs_furniture'>, furniture: OwnedPiece[] | null): boolean {
  if (!a.needs_furniture || !furniture) return true;
  return furniture.some((f) => f.activities.includes(a.id));
}

/** B1: one row of the buy catalogue (furniture table). */
export interface ShopFurniture {
  id: string;
  name: string;
  emoji: string;
  kind: string;
  category: 'living' | 'bedroom' | 'kitchen' | 'bathroom' | 'utility' | 'decor';
  tier: 'lapo' | 'mid' | 'nepo';
  price: number;
  description: string;
  activities: string[];
  bonus: Record<string, Record<string, number>>;
  rest_pct: number;
  color: string | null;
  max_qty: number;
  placement: string;
  sort: number;
}

let shopLoading: Promise<void> | null = null;

interface CatalogStore {
  /** B1 buy catalogue (null = not loaded). */
  shop: ShopFurniture[] | null;
  loadShop: (force?: boolean) => Promise<void>;
  activities: ActivityRow[] | null;
  catalog: CreatorCatalog | null;
  /** The player's own furniture (player_furniture + furniture), for the 3D home and the home actions. */
  furniture: OwnedPiece[] | null;
  furnitureOf: string | null;
  loadActivities: () => Promise<void>;
  loadCatalog: () => Promise<void>;
  loadFurniture: (userId: string, force?: boolean) => Promise<void>;
}

let actLoading: Promise<void> | null = null;
let catLoading: Promise<void> | null = null;
let furnLoading: Promise<void> | null = null;

interface FurnitureJoin {
  furniture_id: string;
  slot: string | null;
  qty?: number | null;
  furniture: { kind: string; slot: string; activities: string[] | null; color: string | null; active: boolean; sort: number; name?: string } | null;
}

export const useCatalog = create<CatalogStore>((set, get) => ({
  activities: null,
  catalog: null,
  furniture: null,
  furnitureOf: null,
  shop: null,
  loadShop: (force = false) => {
    if (!force && get().shop) return Promise.resolve();
    shopLoading ??= (async () => {
      const { data, error } = await supabase
        .from('furniture')
        .select('id, name, emoji, kind, category, tier, price, description, activities, bonus, rest_pct, color, max_qty, placement, sort')
        .eq('active', true).eq('buyable', true).order('sort');
      if (!error) set({ shop: ((data ?? []) as ShopFurniture[]).map((r) => ({ ...r, price: Number(r.price) })) });
    })().finally(() => {
      shopLoading = null;
    });
    return shopLoading;
  },
  loadFurniture: (userId, force = false) => {
    if (!force && get().furnitureOf === userId) return Promise.resolve();
    furnLoading ??= (async () => {
      const { data, error } = await supabase
        .from('player_furniture')
        .select('furniture_id, slot, qty, furniture(kind, slot, activities, color, active, sort, name)')
        .eq('user_id', userId);
      if (error) {
        set({ furnitureOf: userId, furniture: null }); // tried: the home keeps its default furnishing
        return;
      }
      const rows = ((data ?? []) as unknown as FurnitureJoin[])
        .filter((r) => r.furniture?.active)
        .sort((a, b) => (a.furniture?.sort ?? 0) - (b.furniture?.sort ?? 0));
      set({
        furnitureOf: userId,
        furniture: rows.map((r) => ({
          id: r.furniture_id,
          kind: r.furniture!.kind,
          slot: r.slot ?? r.furniture!.slot,
          activities: r.furniture!.activities ?? [],
          color: r.furniture!.color,
          qty: r.qty ?? 1,
          name: r.furniture!.name,
        })),
      });
    })().finally(() => {
      furnLoading = null;
    });
    return furnLoading;
  },
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
