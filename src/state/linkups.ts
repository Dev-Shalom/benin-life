// D2 Link-ups state (docs/LINKUPS.md). The server is the source of truth (linkup_status / linkup_finish):
//   * linkup_status once when the game starts (finishes an action whose time ran out while away, brings back an unseen
//     morning-after popup), when the app or the pick sheet opens, and after each action;
//   * when an action's timer runs out, linkup_finish rolls it: yes / no toast, dinner toast, or (hotel) the morning-after popup.
import { create } from 'zustand';
import { linkupFinish, linkupStatus, type LinkupMorning, type LinkupResult, type LinkupRun, type LinkupStarted, type LinkupStatus } from '../api/linkups';
import { errorMessage } from '../lib/api';
import { serverNow } from '../lib/clock';
import { playCue } from '../lib/sound';
import { toast } from '../ui';
import { useGame } from './game';

interface LinkupStore {
  status: LinkupStatus | null;
  run: LinkupRun | null;
  last: LinkupResult | null;
  /** The morning-after popup (hotel actions), until seen. */
  morning: LinkupMorning | null;
  /** The pick sheet opened from a place card: which action (null = closed). */
  sheet: string | null;
  load: () => Promise<void>;
  started: (r: LinkupStarted) => void;
  openSheet: (action: string) => void;
  closeSheet: () => void;
  setMorning: (m: LinkupMorning | null) => void;
}

let finishTimer: number | null = null;
let loading: Promise<void> | null = null;

export function showLinkupResult(r: LinkupResult | null | undefined) {
  if (!r || r.already || r.status === 'none') return;
  useLinkups.setState({ last: r });
  const who = r.npc?.name ?? 'They';
  if (r.status === 'yes') {
    playCue('done');
    toast(`💞 ${who} said yes! “${r.line ?? ''}”`, 'good');
  } else if (r.status === 'no') {
    toast(`🙅 ${who}: “${r.line ?? 'No.'}”`, 'info');
  } else if (r.kind === 'date') {
    playCue('done');
    toast(`🍽️ Dinner with ${who} went well. Spark ${r.spark ?? 0}/100`, 'good');
    if (r.new_partner) toast(`💑 You and ${who} are now an item!`, 'good');
  } else if (r.morning) {
    useLinkups.setState({ morning: { ...r.morning, run_id: r.run_id } });
    playCue(r.morning.robbed || r.morning.caught ? 'error' : 'done');
  }
}

function scheduleFinish(resolveAt: string) {
  if (finishTimer != null) window.clearTimeout(finishTimer);
  const wait = Math.max(0, Date.parse(resolveAt) - serverNow()) + 350;
  let tries = 0;
  const run = async () => {
    finishTimer = null;
    try {
      const r = await linkupFinish();
      useLinkups.setState({ run: null });
      showLinkupResult(r);
    } catch (e) {
      const hint = (e as { hint?: string }).hint;
      if (hint === 'not_yet' && tries++ < 4) { finishTimer = window.setTimeout(run, 800); return; }
      useLinkups.setState({ run: null });
      if (hint !== 'no_run') toast(errorMessage(e), 'bad');
    }
    void useGame.getState().refresh();
    void useLinkups.getState().load();
  };
  finishTimer = window.setTimeout(run, wait);
}

export const useLinkups = create<LinkupStore>((set) => ({
  status: null,
  run: null,
  last: null,
  morning: null,
  sheet: null,
  load: () => {
    if (loading) return loading;
    loading = (async () => {
      try {
        const s = await linkupStatus();
        set((st) => ({ status: s, run: s.run, morning: st.morning ?? s.morning }));
        if (s.resolved) {
          showLinkupResult(s.resolved);
          void useGame.getState().refresh();
        }
        if (s.run) scheduleFinish(s.run.resolve_at);
      } catch { /* offline: the next trigger tries again */ }
    })().finally(() => { loading = null; });
    return loading;
  },
  started: (r) => {
    set({
      run: {
        id: r.run_id, action_id: r.action_id, npc_id: r.npc.id, name: r.name, icon: r.icon, kind: r.kind, npc_name: r.npc.name,
        started_at: new Date(serverNow()).toISOString(), resolve_at: r.resolve_at, status: 'running', price: r.price,
        yes_pct: r.yes_pct, line: r.line, place: null,
      },
    });
    scheduleFinish(r.resolve_at);
  },
  openSheet: (action) => {
    set({ sheet: action });
    void useLinkups.getState().load();
  },
  closeSheet: () => set({ sheet: null }),
  setMorning: (m) => set({ morning: m }),
}));

const LINKUP_EVENTS = new Set(['linkup_yes', 'linkup_partner', 'linkup_breakup']);
let started = false;

/** Follow my link-up state for the signed-in game. Returns a stop function. */
export function startLinkups(): () => void {
  if (started) return () => undefined;
  started = true;
  void useLinkups.getState().load();
  let lastEvent = useGame.getState().events[0]?.id ?? 0;
  const unsub = useGame.subscribe((s) => {
    const top = s.events[0];
    if (top && top.id > lastEvent) {
      const fresh = s.events.filter((e) => e.id > lastEvent);
      lastEvent = top.id;
      if (fresh.some((e) => LINKUP_EVENTS.has(e.kind))) void useLinkups.getState().load();
    }
  });
  return () => {
    started = false;
    unsub();
    if (finishTimer != null) window.clearTimeout(finishTimer);
    finishTimer = null;
    useLinkups.setState({ status: null, run: null, last: null, morning: null, sheet: null });
  };
}
