// The HUD "Today" card (docs/DAILY_RETURN.md part 4): one today_card() call that gathers the daily reasons to open the game.
// The daily reward, gem hunt and story chips keep their own richer stores (src/state/daily.ts, moments.ts); this store adds what
// they do not show: the weekly event of the day, a waiting welcome-back gift and anything that needs the player (child, rent, takings).
import { create } from 'zustand';
import { rpc } from '../lib/api';
import type { WeeklyEvent } from './weekly';

export interface TodayNeed { kind: 'kid' | 'rent' | 'takings'; icon: string; text: string; go: string }
export interface TodayCardData {
  enabled: boolean;
  count: number;
  date?: string;
  reward?: { ready: boolean; day: number; cash: number; item_name: string | null } | null;
  story?: { waiting: number; chapters: number } | null;
  gems?: { found: number; total: number; next_prize: number } | null;
  event?: WeeklyEvent | null;
  gift?: { cash: number; away_days: number; item_name: string | null } | null;
  needs?: TodayNeed[];
}

interface Store {
  card: TodayCardData | null;
  load: () => Promise<void>;
}

export const useToday = create<Store>((set) => ({
  card: null,
  async load() {
    try {
      set({ card: await rpc<TodayCardData>('today_card') });
    } catch {
      /* keep the last copy */
    }
  },
}));

const OPENED = 'bl.today.opened';
/** The card opens by itself once per Benin day per device (the day string comes from the server). */
export function todayAlreadyOpened(day: string | undefined): boolean {
  try { return !day || window.localStorage.getItem(OPENED) === day; } catch { return true; }
}
export function markTodayOpened(day: string | undefined): void {
  try { if (day) window.localStorage.setItem(OPENED, day); } catch { /* shows again next visit */ }
}
