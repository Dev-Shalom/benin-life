// D1: daily reward + daily gem hunt (docs/DAILY.md). Server-authoritative; this store only caches
// daily_reward_status() / gem_hunt_status() and runs the claim / find RPCs.
import { create } from 'zustand';
import { rpc } from '../lib/api';

export interface RewardStep {
  day: number;
  cash: number;
  item_id: string | null;
  item_name: string | null;
  item_icon: string | null;
  label: string;
  state: 'claimed' | 'today' | 'upcoming';
}
export interface RewardStatus {
  enabled: boolean;
  date: string;
  ready: boolean;
  claimed: boolean;
  day: number;
  next: RewardStep | null;
  steps: RewardStep[];
  total_claims: number;
}
export interface GemHint {
  idx: number;
  district: string;
  found: boolean;
  location_id: string | null;
  place_name: string | null;
  here: boolean;
}
export interface GemStatus {
  enabled: boolean;
  date: string;
  total: number;
  found: number;
  found_all_players: number;
  prize: number;
  all_bonus: number;
  next_prize: number;
  here: string | null;
  gems: GemHint[];
}
export interface ClaimResult { message: string; day: number; cash: number; item_name: string | null }
export interface FindResult { message: string; prize: number; bonus: number; found: number; total: number }

interface DailyStore {
  reward: RewardStatus | null;
  gems: GemStatus | null;
  sheet: 'reward' | 'gems' | null;
  setSheet: (s: 'reward' | 'gems' | null) => void;
  load: () => Promise<void>;
  loadGems: () => Promise<void>;
  claim: () => Promise<ClaimResult>;
  find: (locationId: string) => Promise<FindResult>;
}

export const useDaily = create<DailyStore>((set, get) => ({
  reward: null,
  gems: null,
  sheet: null,
  setSheet: (sheet) => set({ sheet }),
  load: async () => {
    // an older server without D1: keep both null (chips hidden)
    const [r, g] = await Promise.allSettled([rpc<RewardStatus>('daily_reward_status'), rpc<GemStatus>('gem_hunt_status')]);
    set({ reward: r.status === 'fulfilled' ? r.value : get().reward, gems: g.status === 'fulfilled' ? g.value : get().gems });
  },
  loadGems: async () => {
    try {
      set({ gems: await rpc<GemStatus>('gem_hunt_status') });
    } catch {
      /* keep the last status */
    }
  },
  claim: async () => {
    const r = await rpc<ClaimResult>('daily_reward_claim');
    await get().load();
    return r;
  },
  find: async (locationId) => {
    const r = await rpc<FindResult>('gem_find', { p_location: locationId });
    await get().loadGems();
    return r;
  },
}));
