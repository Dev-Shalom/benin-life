// SP2 Pick the money (docs/SPRAY.md). Live drops at the club you're in, the taps you've made, the "+₦70,000"
// counter, and the "@name is picking money!" notices. Drops come from the club channel (Realtime INSERT on
// money_drops), the F1 poll fallback (money_drops_live) or the sprayer's own spray result; state/hype.ts feeds them in.
// Taps are batched: one money_pick call per drop every ~300 ms at most, one in flight at a time. The server is the
// truth (my_total, notes_left); the counter shows confirmed + not-yet-confirmed taps.
import { create } from 'zustand';
import { moneyPick, type MoneyDrop } from '../api/moneyPick';
import { GameError, errorMessage } from '../lib/api';
import { serverNow } from '../lib/clock';
import { naira } from '../lib/format';
import { useGame } from './game';
import { toast } from '../ui/Toast';
import { pushHype, type Announcement } from './hype';

const FLUSH_MS = 300;
/** The server accepts a late batch for club.pick_grace_s (1.5 s); we settle a little after that. */
const SETTLE_AFTER_MS = 1900;
/** The counter stays this long after the last drop ends. */
const LINGER_MS = 2600;

export interface LiveDrop {
  id: number;
  vip: boolean;
  note: number;
  username: string;
  /** The sprayer's own drop (club.pick_self off): notes fall but can't be tapped. */
  mine: boolean;
  /** Local estimate of notes still on the floor. */
  notes: number;
  /** Local ms (Date.now) when the notes vanish. */
  endsAt: number;
  durMs: number;
  ended: boolean;
  /** The server said no more (pool empty / expired / refused). */
  dead: boolean;
  myTotal: number;
  pending: number;
  inflight: number;
}

export interface PickNotice {
  id: number;
  kind: 'pick' | 'pick_top';
  username: string;
  amount: number;
  text: string;
  vip: boolean;
}

interface PickStore {
  drops: LiveDrop[];
  notices: PickNotice[];
  /** Counter visible until (Date.now ms); 0 = hidden. */
  counterUntil: number;
}

export const usePick = create<PickStore>(() => ({ drops: [], notices: [], counterUntil: 0 }));

const timers = new Map<number, number[]>();
let gen = 0; // bumps on clear: late responses for an old club are ignored
let cashSeq = 0;
let cashApplied = 0;

function patch(id: number, f: (d: LiveDrop) => Partial<LiveDrop>) {
  usePick.setState((s) => ({ drops: s.drops.map((d) => (d.id === id ? { ...d, ...f(d) } : d)) }));
}
const get = (id: number) => usePick.getState().drops.find((d) => d.id === id);
function later(id: number, fn: () => void, ms: number) {
  const t = window.setTimeout(fn, ms);
  timers.set(id, [...(timers.get(id) ?? []), t]);
}

/** What the counter shows: confirmed + taps not yet confirmed. */
export function pickedTotal(drops: LiveDrop[]): number {
  return drops.reduce((sum, d) => sum + d.myTotal + (d.pending + d.inflight) * d.note, 0);
}

/** A drop from Realtime / the poll / the spray result. */
export function addDrop(row: MoneyDrop) {
  if (!row || row.settled || usePick.getState().drops.some((d) => d.id === row.id)) return;
  const dur = Math.max(1000, Date.parse(row.expires_at) - Date.parse(row.created_at)) || 5000;
  const left = row.ms_left != null ? Number(row.ms_left) : Date.parse(row.expires_at) - serverNow();
  const msLeft = Math.max(0, Math.min(dur, Number.isFinite(left) ? left : dur));
  if (msLeft < 500) return;
  const note = Math.max(1, Number(row.note) || 10_000);
  const notes = row.notes != null ? Number(row.notes) : Math.floor(Number(row.remaining) / note);
  if (notes <= 0) return;
  const uid = useGame.getState().state?.profile.id ?? null;
  const d: LiveDrop = {
    id: row.id, vip: !!row.vip, note, username: row.username ?? '', mine: !!uid && row.sprayer === uid && !row.self_ok,
    notes, endsAt: Date.now() + msLeft, durMs: dur, ended: false, dead: false,
    myTotal: Number(row.my_total) || 0, pending: 0, inflight: 0,
  };
  usePick.setState((s) => ({ drops: [...s.drops, d] }));
  later(d.id, () => finish(d.id), msLeft);
}

/** A tap on a note. False when this note can't be picked (yours, gone, ended). */
export function tapNote(id: number): boolean {
  const d = get(id);
  if (!d || d.mine || d.ended || d.dead || d.notes <= 0 || Date.now() >= d.endsAt) return false;
  patch(id, (x) => ({ pending: x.pending + 1, notes: x.notes - 1 }));
  usePick.setState({ counterUntil: Number.MAX_SAFE_INTEGER });
  if (d.pending === 0 && d.inflight === 0) later(id, () => void flush(id), FLUSH_MS);
  return true;
}

async function flush(id: number) {
  const d = get(id);
  if (!d || d.inflight > 0 || d.pending <= 0) return;
  const n = d.pending;
  const g = gen;
  const seq = ++cashSeq;
  patch(id, () => ({ pending: 0, inflight: n }));
  try {
    const r = await moneyPick(id, n);
    if (g !== gen) return;
    const cur = get(id);
    if (!cur) return;
    const dead = r.expired || !!r.empty || r.notes_left <= 0;
    patch(id, (x) => ({
      inflight: 0, myTotal: Number(r.my_total) || 0, dead,
      pending: dead ? 0 : x.pending,
      notes: dead ? 0 : Math.max(0, Math.min(x.notes, Number(r.notes_left) - x.pending)),
    }));
    if (seq > cashApplied) {
      cashApplied = seq;
      const cash = Number(r.cash_after);
      useGame.setState((s) => (s.state && Number.isFinite(cash) ? { state: { ...s.state, profile: { ...s.state.profile, cash } } } : s));
    }
    if (r.hype) pushHype(r.hype);
    if (!dead && (get(id)?.pending ?? 0) > 0) later(id, () => void flush(id), FLUSH_MS);
  } catch (e) {
    if (g !== gen) return;
    patch(id, () => ({ inflight: 0, pending: 0, dead: true, notes: 0 }));
    const hint = e instanceof GameError ? e.hint : null;
    if (hint !== 'no_drop') toast(errorMessage(e), hint === 'own_drop' ? 'info' : 'bad');
  }
}

function finish(id: number) {
  const d = get(id);
  if (!d) return;
  patch(id, () => ({ ended: true }));
  void flush(id); // the last taps (the server allows a short grace)
  later(id, () => {
    const x = get(id);
    // settle the drop (top picker shout-out) once it is surely over; only pickers ask, it's cheap
    if (x && (x.myTotal > 0 || x.inflight > 0) && !x.mine) void moneyPick(id, 0).catch(() => {});
    later(id, () => removeDrop(id), Math.max(0, LINGER_MS - SETTLE_AFTER_MS));
  }, SETTLE_AFTER_MS);
}

function removeDrop(id: number) {
  (timers.get(id) ?? []).forEach((t) => window.clearTimeout(t));
  timers.delete(id);
  usePick.setState((s) => {
    const drops = s.drops.filter((d) => d.id !== id);
    return { drops, counterUntil: drops.length ? s.counterUntil : 0 };
  });
  if (!usePick.getState().drops.length) void useGame.getState().refresh();
}

/** Left the club (or signed out): stop picking, drop everything. */
export function clearDrops() {
  gen++;
  timers.forEach((ts) => ts.forEach((t) => window.clearTimeout(t)));
  timers.clear();
  usePick.setState({ drops: [], notices: [], counterUntil: 0 });
}

const NOTICE_MS = 3800;
/** DEV only: window.__blHypeHold stretches the notices for screenshots (as the takeover holds). */
export function noticeMs(): number {
  const k = import.meta.env.DEV ? Number((window as { __blHypeHold?: number }).__blHypeHold) || 1 : 1;
  return NOTICE_MS * k;
}
/** A pick / top picker announcement (from the club feed): the small notice card. */
export function pushPickNotice(a: Announcement) {
  if (a.kind !== 'pick' && a.kind !== 'pick_top') return;
  if (usePick.getState().notices.some((n) => n.id === a.id)) return;
  const n: PickNotice = { id: a.id, kind: a.kind, username: a.username, amount: Number(a.amount) || 0, text: a.text, vip: !!a.vip };
  usePick.setState((s) => ({ notices: [...s.notices, n].slice(-3) }));
  window.setTimeout(() => usePick.setState((s) => ({ notices: s.notices.filter((x) => x.id !== n.id) })), noticeMs());
}

export function noticeHeadline(n: PickNotice): string {
  return n.kind === 'pick' ? `@${n.username} is picking money! 💸` : `@${n.username} picked ${naira(n.amount)}! 🏆`;
}
