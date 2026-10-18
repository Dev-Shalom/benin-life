// R3 skills store: the Skills tab data, plus the level-up moment. A level-up is a `skill_up` row in `events`
// (written by the server when XP crosses a level); the game store hands it to showLevelUp().
import { create } from 'zustand';
import { skillsStatus, type SkillsStatus } from '../api/skills';
import { playCue } from '../lib/sound';

export interface LevelUp { id: number; skill: string; name: string; icon: string; level: number; unlocks: string[] }

interface SkillsStore {
  status: SkillsStatus | null;
  loading: boolean;
  queue: LevelUp[];
  load: () => Promise<void>;
  dismiss: () => void;
}

export const useSkills = create<SkillsStore>((set, get) => ({
  status: null,
  loading: false,
  queue: [],
  load: async () => {
    if (get().loading) return;
    set({ loading: true });
    try { set({ status: await skillsStatus() }); } catch { /* offline: next open retries */ } finally { set({ loading: false }); }
  },
  dismiss: () => set((s) => ({ queue: s.queue.slice(1) })),
}));

let seq = 0;
/** Called for each new `skill_up` event. */
export function showLevelUp(data: Record<string, unknown> | null | undefined, title: string) {
  const d = (data ?? {}) as { skill?: string; name?: string; icon?: string; level?: number; unlocks?: string[] };
  const lu: LevelUp = { id: ++seq, skill: d.skill ?? '', name: d.name ?? title, icon: d.icon ?? '⭐', level: d.level ?? 0, unlocks: d.unlocks ?? [] };
  useSkills.setState((s) => ({ queue: [...s.queue, lu].slice(-4) }));
  playCue('done');
  void useSkills.getState().load();
}
