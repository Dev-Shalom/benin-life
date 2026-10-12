// C1 crime state (docs/CRIME.md): my open jail case (the "Police don catch you!" popup + jail banner buttons) and a
// running pickpocket. The server is the source of truth (crime_status / steal_finish); this store only asks it:
//   * once when the game starts (the popup comes back after a reload / on login while a case is open and undecided),
//   * when a crime-related event arrives (steal_caught, police_release …) or my cell timer changes,
//   * when my pickpocket timer runs out (steal_finish rolls the outcome).
import { create } from 'zustand';
import { crimeStatus, stealFinish, type JailCase, type StealResult } from '../api/crime';
import { errorMessage } from '../lib/api';
import { serverNow } from '../lib/clock';
import { naira } from '../lib/format';
import { playCue } from '../lib/sound';
import { toast } from '../ui';
import { useGame } from './game';

interface CrimeStore {
  case: JailCase | null;
  attempt: { id: number; resolve_at: string; target: string } | null;
  cooldownUntil: string | null;
  load: () => Promise<void>;
  setCase: (c: JailCase | null) => void;
  /** steal_attempt just started: wait for the timer, then roll. */
  started: (a: { id: number; resolve_at: string; target: string }) => void;
}

let finishTimer: number | null = null;
let loading: Promise<void> | null = null;

/** Show a pickpocket outcome (toast; a caught one opens the popup through `case`). */
export function showStealResult(r: StealResult | null | undefined) {
  if (!r || r.already) return;
  if (r.status === 'success') {
    playCue('money');
    toast(`🫳 You slipped ${naira(r.amount)} from @${r.victim ?? 'them'}'s pocket.`, 'good');
  } else if (r.status === 'caught') {
    playCue('error');
    if (r.case) useCrime.getState().setCase(r.case);
  } else if (r.message) {
    toast(r.message, 'info');
  }
}

function scheduleFinish(resolveAt: string) {
  if (finishTimer != null) window.clearTimeout(finishTimer);
  const wait = Math.max(0, Date.parse(resolveAt) - serverNow()) + 350;
  let tries = 0;
  const run = async () => {
    finishTimer = null;
    try {
      const r = await stealFinish();
      useCrime.setState({ attempt: null });
      showStealResult(r);
    } catch (e) {
      const hint = (e as { hint?: string }).hint;
      if (hint === 'not_yet' && tries++ < 4) { finishTimer = window.setTimeout(run, 800); return; }
      useCrime.setState({ attempt: null });
      if (hint !== 'no_attempt') toast(errorMessage(e), 'bad');
    }
    void useGame.getState().refresh();
    void useCrime.getState().load();
  };
  finishTimer = window.setTimeout(run, wait);
}

export const useCrime = create<CrimeStore>((set) => ({
  case: null,
  attempt: null,
  cooldownUntil: null,
  load: () => {
    if (loading) return loading;
    loading = (async () => {
      try {
        const s = await crimeStatus();
        set({ case: s.case, attempt: s.attempt, cooldownUntil: s.cooldown_until });
        if (s.resolved) {
          showStealResult(s.resolved);
          void useGame.getState().refresh();
        }
        if (s.attempt) scheduleFinish(s.attempt.resolve_at);
      } catch { /* offline: the next trigger tries again */ }
    })().finally(() => { loading = null; });
    return loading;
  },
  setCase: (c) => set({ case: c && c.status === 'open' ? c : null }),
  started: (a) => {
    set({ attempt: a });
    scheduleFinish(a.resolve_at);
  },
}));

const CRIME_EVENTS = new Set(['steal_caught', 'steal_success', 'police_release']);
let started = false;

/** Follow my crime state for the signed-in game. Returns a stop function. */
export function startCrime(): () => void {
  if (started) return () => undefined;
  started = true;
  void useCrime.getState().load();
  let lastEvent = useGame.getState().events[0]?.id ?? 0;
  let lastJail = useGame.getState().state?.profile.jailed_until ?? null;
  const unsub = useGame.subscribe((s) => {
    const top = s.events[0];
    if (top && top.id > lastEvent) {
      const fresh = s.events.filter((e) => e.id > lastEvent);
      lastEvent = top.id;
      if (fresh.some((e) => CRIME_EVENTS.has(e.kind))) void useCrime.getState().load();
    }
    const jail = s.state?.profile.jailed_until ?? null;
    if (jail !== lastJail) {
      lastJail = jail;
      void useCrime.getState().load();
    }
  });
  return () => {
    started = false;
    unsub();
    if (finishTimer != null) window.clearTimeout(finishTimer);
    finishTimer = null;
    useCrime.setState({ case: null, attempt: null, cooldownUntil: null });
  };
}
