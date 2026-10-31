// "This week in Benin" (docs/DAILY_RETURN.md part 3). Server-authoritative: weekly_calendar() / weekly_event_checkin().
import { create } from 'zustand';
import { rpc } from '../lib/api';

export interface WeeklyWinner { rank: number; username: string; total: number }
export interface WeeklyEvent {
  key: string;
  weekday: number;
  icon: string;
  title: string;
  blurb: string;
  reward: string | null;
  where: string | null;
  place_id: string | null;
  checkin: boolean;
  rule: 'club' | 'place' | 'home' | null;
  checked_in: boolean;
  winners: WeeklyWinner[] | null;
  discount_pct: number | null;
}
export interface WeeklyDay { date: string; weekday: number; today: boolean; past: boolean; event: WeeklyEvent | null }
export interface WeeklyCalendar { enabled: boolean; today?: string; weekday?: number; days: WeeklyDay[]; today_event?: WeeklyEvent | null }
export interface CheckinResult { ok: boolean; event: string; cash: number; message: string }

const DKEY = 'bl.wk.dismissed';
function readDismissed(): string | null {
  try { return window.localStorage.getItem(DKEY); } catch { return null; }
}

interface Store {
  cal: WeeklyCalendar | null;
  open: boolean;
  /** `${date}:${event key}` of the banner the player closed (kept per device). */
  dismissed: string | null;
  setOpen: (v: boolean) => void;
  dismissBanner: () => void;
  load: () => Promise<void>;
  checkin: () => Promise<CheckinResult>;
}

export const useWeekly = create<Store>((set, get) => ({
  cal: null,
  open: false,
  dismissed: readDismissed(),
  setOpen: (open) => set({ open }),
  dismissBanner() {
    const ev = get().cal?.today_event;
    if (!ev || !get().cal?.today) return;
    const v = `${get().cal!.today}:${ev.key}`;
    try { window.localStorage.setItem(DKEY, v); } catch { /* blocked storage: it just shows again next visit */ }
    set({ dismissed: v });
  },
  async load() {
    try {
      set({ cal: await rpc<WeeklyCalendar>('weekly_calendar') });
    } catch {
      /* keep the last copy */
    }
  },
  async checkin() {
    const res = await rpc<CheckinResult>('weekly_event_checkin');
    await get().load();
    return res;
  },
}));

/** The event for the top banner today: on, not yet dismissed on this device. */
export function bannerEvent(cal: WeeklyCalendar | null, dismissed: string | null): WeeklyEvent | null {
  const ev = cal?.enabled ? cal.today_event ?? null : null;
  if (!ev || !cal?.today) return null;
  return dismissed === `${cal.today}:${ev.key}` ? null : ev;
}
