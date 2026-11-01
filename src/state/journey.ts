// New-player journey, "Your first days" (docs/JOURNEY.md). Server-authoritative: journey_status() / journey_claim().
import { create } from 'zustand';
import { rpc } from '../lib/api';

export type JourneyState = 'locked' | 'active' | 'done' | 'claimed';
export interface JourneyStep {
  id: string;
  day: 1 | 2 | 3;
  title: string;
  hint: string;
  icon: string;
  go: string | null;
  state: JourneyState;
  reward: { cash: number; item: string | null; item_name: string | null; qty: number };
  progress: { have: number; need: number; money: boolean } | null;
}
export interface JourneyStatus {
  enabled: boolean;
  eligible?: boolean;
  day?: number;
  days?: number;
  total?: number;
  done?: number;
  claimed?: number;
  claimable?: number;
  pct?: number;
  complete?: boolean;
  badge?: string | null;
  bonus?: { cash: number; item_name: string | null; badge: string };
  steps?: JourneyStep[];
}
export interface JourneyClaim {
  message: string;
  step: string;
  cash: number;
  item_name: string | null;
  finished: boolean;
  bonus: number;
  bonus_item_name: string | null;
  badge: string | null;
}

interface Store {
  status: JourneyStatus | null;
  sheet: boolean;
  /** The step that was just claimed: the card and sheet show a small celebration for it. */
  celebrate: { step: string; cash: number; finished: boolean; at: number } | null;
  setSheet: (v: boolean) => void;
  load: () => Promise<void>;
  claim: (step: string) => Promise<JourneyClaim>;
}

let lastLoad = 0;
let inflight: Promise<void> | null = null;

export const useJourney = create<Store>((set, get) => ({
  status: null,
  sheet: false,
  celebrate: null,
  setSheet: (sheet) => set({ sheet }),
  load() {
    if (inflight) return inflight;
    inflight = (async () => {
      try {
        set({ status: await rpc<JourneyStatus>('journey_status') });
        lastLoad = Date.now();
      } catch {
        /* an older server, or offline: keep the last copy (the card stays hidden without one) */
      } finally {
        inflight = null;
      }
    })();
    return inflight;
  },
  async claim(step) {
    const res = await rpc<JourneyClaim>('journey_claim', { p_step: step });
    set({ celebrate: { step, cash: res.cash, finished: res.finished, at: Date.now() } });
    await get().load();
    return res;
  },
}));

/** Load again only if the last load is older than `minMs` (called after money moves, so the server is not asked every second). */
export function loadJourneySoon(minMs = 12_000): void {
  if (Date.now() - lastLoad < minMs) return;
  void useJourney.getState().load();
}

/** The card, in short: what to show in the Today list. */
export function journeySummary(s: JourneyStatus | null) {
  if (!s || !s.enabled || !s.eligible || s.complete || !s.steps) return null;
  const open = s.steps.filter((x) => x.state === 'done' || x.state === 'active');
  // claimable first, then the day's next steps in order
  const next = [...open.filter((x) => x.state === 'done'), ...open.filter((x) => x.state === 'active')].slice(0, 3);
  const nextLocked = s.steps.find((x) => x.state === 'locked');
  return {
    next,
    claimable: s.claimable ?? 0,
    pct: s.pct ?? 0,
    claimed: s.claimed ?? 0,
    total: s.total ?? 0,
    day: s.day ?? 1,
    lockedDay: next.length === 0 ? nextLocked?.day ?? null : null,
  };
}

/** The dream step: the Sim sheet's Goals tab tells the server the player looked at it (once per session). */
let dreamSent = false;
export function markDreamSeen(): void {
  const s = useJourney.getState().status;
  if (dreamSent || !s?.eligible || s.complete) return;
  dreamSent = true;
  void rpc('journey_mark', { p_key: 'dream_seen' }).then(() => loadJourneySoon(0)).catch(() => { dreamSent = false; });
}
