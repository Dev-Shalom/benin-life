// Power cuts (docs/POWER.md): the player's power state. ONE cheap read, power_status(), polled about once a minute (startPoller)
// and right after any power action. It also settles the player's own generator / battery on the server. <PowerHost/> turns its
// `notices` into cards and toasts; the HUD chip and the Power sheet read `data`; Game.tsx passes `lit` to the 3D home as `powered`.
import { create } from 'zustand';
import { powerStatus, type PowerStatus } from '../api/power';
import { startPoller } from '../lib/realtime';

interface PowerStore {
  data: PowerStatus | null;
  sheet: boolean;
  load: () => Promise<PowerStatus | null>;
  apply: (d: PowerStatus) => void;
  openSheet: () => void;
  closeSheet: () => void;
  reset: () => void;
}

export const usePower = create<PowerStore>((set, get) => ({
  data: null,
  sheet: false,
  load: async () => {
    const d = await powerStatus();
    set({ data: d });
    return d;
  },
  // an action (switch the generator, pour fuel) returns the new state: keep the notices the poll already brought
  apply: (d) => set((s) => ({ data: { ...d, notices: d.notices ?? s.data?.notices, bag: d.bag ?? s.data?.bag, poll_seconds: d.poll_seconds ?? s.data?.poll_seconds ?? 60 } })),
  openSheet: () => { set({ sheet: true }); void get().load().catch(() => undefined); },
  closeSheet: () => set({ sheet: false }),
  reset: () => set({ data: null, sheet: false }),
}));

/** Start polling power_status. Returns the stop function. */
export function startPower(): () => void {
  const p = startPoller(() => usePower.getState().load(), () => (usePower.getState().data?.poll_seconds ?? 60) * 1000, { immediate: true });
  return () => { p.stop(); usePower.getState().reset(); };
}

/** Is the room lit right now? True while unknown or when power cuts are off, so a slow read never darkens the home. */
export function useLit(): boolean {
  return usePower((s) => s.data?.lit ?? true);
}

/** "1 h 20 min" / "35 min" for real hours. */
export function hoursLabel(h: number | null | undefined): string {
  if (h == null || !Number.isFinite(h)) return '';
  const mins = Math.max(1, Math.round(h * 60));
  if (mins < 60) return `${mins} min`;
  const hh = Math.floor(mins / 60);
  const mm = mins % 60;
  return mm ? `${hh} h ${mm} min` : `${hh} h`;
}

/** A Benin clock time (24 h) for an ISO instant. */
export function beninTime(iso: string | null | undefined): string {
  if (!iso) return '';
  const t = Date.parse(iso);
  if (Number.isNaN(t)) return '';
  return new Date(t).toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit', timeZone: 'Africa/Lagos' });
}
