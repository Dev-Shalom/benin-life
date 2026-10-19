// Y1 Yahoo state (docs/YAHOO.md). The server is the source of truth (yahoo_status / yahoo_finish):
//   * yahoo_status once when the game starts (finishes a job whose time ran out while away), when the Yahoo app opens,
//     after a job, and after Yahoo / EFCC events;
//   * when a job timer runs out, yahoo_finish rolls the outcome: paid → toast, caught → the C1 jail popup (EFCC copy).
//   * R6 group missions: yahoo_group_status (it also moves a group on: start timer, finish) is polled while I am in a group or
//     have an invite, and reloaded on the group events; when the crew's timer runs out yahoo_group_finish settles it for everyone.
import { create } from 'zustand';
import { yahooFinish, yahooGroupFinish, yahooGroupStatus, yahooStatus, type GroupResult, type GroupStatus, type YahooResult, type YahooRun, type YahooStatus } from '../api/yahoo';
import { errorMessage } from '../lib/api';
import { serverNow } from '../lib/clock';
import { naira } from '../lib/format';
import { playCue } from '../lib/sound';
import { toast } from '../ui';
import { useCrime } from './crime';
import { useGame } from './game';
import { canPoll } from '../lib/activity';

interface YahooStore {
  status: YahooStatus | null;
  run: YahooRun | null;
  /** The last finished job, shown in the app until the next one. */
  last: YahooResult | null;
  /** R6: friends, missions, my open group and invites. */
  groups: GroupStatus | null;
  load: () => Promise<void>;
  loadGroups: () => Promise<void>;
  started: (r: YahooRun) => void;
  setGroups: (g: GroupStatus | null) => void;
}

let finishTimer: number | null = null;
let loading: Promise<void> | null = null;

export function showYahooResult(r: YahooResult | null | undefined) {
  if (!r || r.already || r.status === 'none') return;
  useYahoo.setState({ last: r });
  if (r.status === 'paid') {
    playCue('money');
    toast(`💻 Client paid: +${naira(r.amount)} (yahoo balance)`, 'good');
    if (r.rank_up) toast(`${r.rank_up.icon} You don rise: ${r.rank_up.name}!`, 'good');
  } else if (r.status === 'cashed') {
    playCue('money');
    const fee = r.fee ?? 0;
    toast(`💸 Cash out don land: +${naira(r.amount - fee)} cash${fee > 0 ? ` (${naira(fee)} fee to the Mallam)` : ''}`, 'good');
  } else if (r.status === 'caught') {
    playCue('error');
    if (r.case) useCrime.getState().setCase(r.case);
    else void useCrime.getState().load();
  }
}

function scheduleFinish(resolveAt: string) {
  if (finishTimer != null) window.clearTimeout(finishTimer);
  const wait = Math.max(0, Date.parse(resolveAt) - serverNow()) + 350;
  let tries = 0;
  const run = async () => {
    finishTimer = null;
    try {
      const r = await yahooFinish();
      useYahoo.setState({ run: null });
      showYahooResult(r);
    } catch (e) {
      const hint = (e as { hint?: string }).hint;
      if (hint === 'not_yet' && tries++ < 4) { finishTimer = window.setTimeout(run, 800); return; }
      useYahoo.setState({ run: null });
      if (hint !== 'no_run') toast(errorMessage(e), 'bad');
    }
    void useGame.getState().refresh();
    void useYahoo.getState().load();
  };
  finishTimer = window.setTimeout(run, wait);
}

let groupTimer: number | null = null;
let groupLoading: Promise<void> | null = null;
let lastGroupShown: number | null | undefined;

/** R6: a finished group mission (toast; a caught one opens the EFCC popup through the crime store). */
export function showGroupResult(r: GroupResult | null | undefined) {
  if (!r) return;
  lastGroupShown = r.group.id;
  if (r.status === 'paid') {
    playCue('money');
    toast(`👥 ${r.group.name} paid: +${naira(r.amount)} each (yahoo balance)`, 'good');
  } else if (r.status === 'caught') {
    playCue('error');
    if (r.case) useCrime.getState().setCase(r.case);
    else void useCrime.getState().load();
  }
}

function scheduleGroupFinish(resolveAt: string) {
  if (groupTimer != null) window.clearTimeout(groupTimer);
  const wait = Math.max(0, Date.parse(resolveAt) - serverNow()) + 400;
  let tries = 0;
  const run = async () => {
    groupTimer = null;
    try {
      showGroupResult(await yahooGroupFinish());
    } catch (e) {
      const hint = (e as { hint?: string }).hint;
      if (hint === 'not_yet' && tries++ < 4) { groupTimer = window.setTimeout(run, 800); return; }
      if (hint !== 'no_group') toast(errorMessage(e), 'bad');
    }
    void useGame.getState().refresh();
    void useYahoo.getState().load();
    void useYahoo.getState().loadGroups();
  };
  groupTimer = window.setTimeout(run, wait);
}

export const useYahoo = create<YahooStore>((set) => ({
  status: null,
  run: null,
  last: null,
  groups: null,
  setGroups: (g) => set({ groups: g }),
  loadGroups: () => {
    if (groupLoading) return groupLoading;
    groupLoading = (async () => {
      try {
        const g = await yahooGroupStatus();
        // the first load only remembers the last result, so an old mission is not announced again
        if (lastGroupShown === undefined) lastGroupShown = g.last?.id ?? null;
        else if (g.last && g.last.id !== lastGroupShown && !g.group) {
          lastGroupShown = g.last.id;
          if (g.last.status === 'paid') {
            const mine = g.last.members.find((m) => m.me);
            playCue('money');
            toast(`👥 ${g.last.name} paid: +${naira(mine?.payout ?? g.last.per_member)} each (yahoo balance)`, 'good');
            void useGame.getState().refresh();
          } else if (g.last.status === 'caught') {
            void useCrime.getState().load();
            void useGame.getState().refresh();
          }
        }
        set({ groups: g });
        if (g.group?.status === 'running' && g.group.resolve_at) scheduleGroupFinish(g.group.resolve_at);
      } catch { /* offline: the next trigger tries again */ }
    })().finally(() => { groupLoading = null; });
    return groupLoading;
  },
  load: () => {
    if (loading) return loading;
    loading = (async () => {
      try {
        const s = await yahooStatus();
        set({ status: s, run: s.run });
        if (s.resolved) {
          showYahooResult(s.resolved);
          void useGame.getState().refresh();
        }
        if (s.run) scheduleFinish(s.run.resolve_at);
      } catch { /* offline: the next trigger tries again */ }
    })().finally(() => { loading = null; });
    return loading;
  },
  started: (r) => {
    set({ run: r });
    scheduleFinish(r.resolve_at);
  },
}));

const YAHOO_EVENTS = new Set(['efcc_caught', 'yahoo_rank_up', 'police_release']);
/** R6 group mission alerts: an invite, a reply, the start, the result, a cancel or a drop. */
const GROUP_EVENTS = new Set(['yahoo_group_invite', 'yahoo_group_reply', 'yahoo_group_start', 'yahoo_group_paid', 'yahoo_group_cancel', 'yahoo_group_drop', 'efcc_caught']);
let started = false;

/** Follow my Yahoo state for the signed-in game. Returns a stop function. */
export function startYahoo(): () => void {
  if (started) return () => undefined;
  started = true;
  void useYahoo.getState().load();
  void useYahoo.getState().loadGroups();
  // while I am in a group or have an invite, ask the server every few seconds (it also starts / settles overdue groups)
  const poll = window.setInterval(() => {
    const g = useYahoo.getState().groups;
    if (!canPoll() || !g || !(g.group || g.invites.length > 0)) return;
    void useYahoo.getState().loadGroups();
  }, 8000); // IO: 5 s -> 8 s, and silent while hidden or AFK
  let lastEvent = useGame.getState().events[0]?.id ?? 0;
  const unsub = useGame.subscribe((s) => {
    const top = s.events[0];
    if (top && top.id > lastEvent) {
      const fresh = s.events.filter((e) => e.id > lastEvent);
      lastEvent = top.id;
      if (fresh.some((e) => YAHOO_EVENTS.has(e.kind))) void useYahoo.getState().load();
      if (fresh.some((e) => GROUP_EVENTS.has(e.kind))) void useYahoo.getState().loadGroups();
    }
  });
  return () => {
    started = false;
    unsub();
    window.clearInterval(poll);
    if (finishTimer != null) window.clearTimeout(finishTimer);
    finishTimer = null;
    if (groupTimer != null) window.clearTimeout(groupTimer);
    groupTimer = null;
    lastGroupShown = undefined;
    useYahoo.setState({ status: null, run: null, last: null, groups: null });
  };
}
