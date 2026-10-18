// R8: the Upgrade tab's data, the builders' timer and the "builders don finish" toast (docs/HOUSE_UPGRADES.md).
// The server settles lazily: a finished build only becomes real on the next read, so the watcher below reads once at
// sign-in and again just after the next build is due. Nothing polls.
import { useEffect } from 'react';
import { create } from 'zustand';
import { houseUpgradeState, type UpgradeState } from '../api/upgrades';
import { toast } from '../ui';
import { useGame } from './game';
import { useGarage } from './garage';

interface UpgradeStore {
  data: UpgradeState | null;
  /** Bumped when something finished or was bought: the 3D home reloads its upgrades. */
  version: number;
  load: () => Promise<UpgradeState | null>;
  /** Replace the data after a purchase (and bump). */
  bump: () => void;
}

export const useUpgrades = create<UpgradeStore>((set, get) => ({
  data: null,
  version: 0,
  load: async () => {
    try {
      const d = await houseUpgradeState();
      set({ data: d });
      if (d.just_finished.length) {
        for (const f of d.just_finished) toast(`${f.emoji} Builders don finish: ${f.name} is ready!`, 'good');
        set((s) => ({ version: s.version + 1 }));
        useGarage.getState().bump();
        void useGame.getState().refresh();
      }
      return d;
    } catch {
      return get().data;
    }
  },
  bump: () => set((s) => ({ version: s.version + 1 })),
}));

/** Mount once in the game screen: loads at sign-in and right after each build's timer runs out. */
export function useUpgradeWatcher(enabled: boolean) {
  const load = useUpgrades((s) => s.load);
  const nextReady = useUpgrades((s) => s.data?.building.reduce<number | null>((m, b) => {
    const t = Date.parse(b.ready_at);
    return Number.isNaN(t) ? m : m === null ? t : Math.min(m, t);
  }, null) ?? null);
  useEffect(() => {
    if (enabled) void load();
  }, [enabled, load]);
  useEffect(() => {
    if (!enabled || nextReady === null) return;
    const ms = Math.max(1500, nextReady - Date.now() + 1500);
    const t = window.setTimeout(() => void load(), Math.min(ms, 2 ** 30));
    return () => window.clearTimeout(t);
  }, [enabled, nextReady, load]);
}
