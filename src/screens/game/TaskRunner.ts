// M2 task runner: drives the client-side action queue (src/state/tasks.ts).
//   queued -> 'walking' (the Sim walks to the furniture with M1 pathing; only at home with the live 3D view)
//          -> 'starting' (on arrival: do_activity, so the server's busy timer and the live bars start now)
//          -> 'running' (until busy_until has passed AND fresh state came back) -> next task.
// Tasks with no furniture (or away from the 3D home) skip the walk and start at once. The server stays
// authoritative: nothing is sent while it is busy, and a refusal is shown as a toast (the queue goes on,
// except when the server is busy with something else / jail / hospital / travel: then it is cleared).
import { useCallback, useEffect, useRef, useState } from 'react';
import { activityGroup, type HomeGroup } from '../../art/home3d/model';
import { errorMessage, GameError, rpc } from '../../lib/api';
import { serverNow } from '../../lib/clock';
import { getCfg } from '../../lib/config';
import type { GameState } from '../../lib/types';
import { useGame } from '../../state/game';
import { activityIcon, useTasks, type TaskKind } from '../../state/tasks';
import { toast } from '../../ui';

/** Walks to a task longer than this (real ms) give up and start anyway (e.g. the canvas went away). */
const WALK_TIMEOUT_MS = 20_000;
const CLEAR_HINTS = ['busy', 'jailed', 'hospitalized', 'traveling', 'no_profile', 'banned'];

export function queueMax(): number {
  return Math.max(1, Math.round(Number(getCfg('action.queue_max', 5)) || 5));
}

/** L2: extra details for tasks queued inside a place interior. */
export interface PlaceTaskOpts {
  kind?: TaskKind;
  /** Zone key to walk to first. */
  zone?: string | null;
  /** "the bar" */
  walkTo?: string;
  icon?: string;
  qty?: number;
}

/** Add an activity (or, inside a place, a shift / purchase) to the queue (a toast when it is full). */
export function queueTask(a: { id: string; name: string; home_only?: boolean }, locationId: string, opts: PlaceTaskOpts = {}): 'now' | 'queued' | 'full' {
  const max = queueMax();
  const r = useTasks.getState().add(
    {
      id: a.id,
      name: a.name,
      icon: opts.icon ?? activityIcon(a.id),
      group: a.home_only && !opts.zone ? activityGroup(a.id) : null,
      locationId,
      kind: opts.kind,
      zone: opts.zone ?? null,
      walkTo: opts.walkTo,
      qty: opts.qty,
    },
    max,
  );
  // 'queued' needs no toast: the chip appearing in the left column is the feedback
  if (r === 'full') toast(`Your queue is full (${max} tasks). Remove one first.`, 'bad');
  return r;
}

/** Stop what is running now (the x on the task pill). */
export async function stopRunning(): Promise<void> {
  const t = useTasks.getState();
  try {
    const r = await rpc<{ stopped?: boolean; message?: string }>('activity_stop');
    if (r?.stopped && r.message) toast(r.message, 'info');
    if (t.current?.phase === 'running') useTasks.getState().setCurrent(null);
  } catch (e) {
    toast(errorMessage(e), 'bad');
  } finally {
    await useGame.getState().refresh();
  }
}

export interface PlaceTask {
  key: string;
  zone: string;
}

export interface HomeTask {
  key: string;
  activity: string;
  group: HomeGroup;
}

/**
 * Runs the queue. `homeLive`: the 3D home is on screen and can walk the Sim (else tasks start at once).
 * Returns what the HomeScene needs.
 */
export function useTaskRunner(state: GameState | null, homeLive: boolean, placeLive: string | null = null) {
  const current = useTasks((s) => s.current);
  const queue = useTasks((s) => s.queue);
  const holdUntil = useTasks((s) => s.holdUntil);
  const refresh = useGame((s) => s.refresh);
  const [tick, setTick] = useState(0);
  const p = state?.profile ?? null;

  // when fresh state last arrived (server clock): "busy_until passed AND state refreshed"
  const stateAt = useRef(0);
  useEffect(() => {
    stateAt.current = serverNow();
  }, [state]);

  const start = useCallback(
    async (uid: string) => {
      const c = useTasks.getState().current;
      if (!c || c.uid !== uid) return;
      useTasks.getState().patchCurrent({ phase: 'starting' });
      try {
        type Res = { message?: string; busy_until?: string; used?: string[]; rent_penalty?: boolean; robbed?: { amount?: number } | null };
        const kind = c.kind ?? 'activity';
        const res =
          kind === 'shift'
            ? await rpc<Res>('work_shift')
            : kind === 'buy'
              ? await rpc<Res>('shop_buy', { p_item: c.id, p_qty: Math.max(1, c.qty ?? 1) })
              : await rpc<Res>('do_activity', { p_activity: c.id });
        if (useTasks.getState().current?.uid === uid) useTasks.getState().patchCurrent({ phase: 'running', busyUntil: res?.busy_until });
        // the pill already says it started; toast only when the server has more to say (items used,
        // the landlord knocking, a purchase, a pickpocket), so toasts don't cover the left column for every task
        if (kind === 'buy') toast(res?.message ?? 'Bought!', 'good');
        else if (res?.robbed) toast(res?.message ?? 'Omo! Somebody dipped hand for your pocket.', 'bad');
        else if ((res?.used?.length ?? 0) > 0 || res?.rent_penalty) toast(res?.message ?? 'Done!', 'good');
      } catch (e) {
        toast(errorMessage(e), 'bad');
        const hint = e instanceof GameError ? e.hint : undefined;
        if (hint && CLEAR_HINTS.includes(hint)) useTasks.getState().clear();
        else if (useTasks.getState().current?.uid === uid) useTasks.getState().setCurrent(null);
      } finally {
        await refresh();
      }
    },
    [refresh],
  );

  // ---- clear on leaving the place / setting off / jail / hospital
  const where = state ? (state.travel ? 'road' : (p?.location_id ?? '')) : null;
  const lastWhere = useRef(where);
  useEffect(() => {
    if (lastWhere.current !== null && where !== lastWhere.current) useTasks.getState().clear();
    lastWhere.current = where;
  }, [where]);

  // ---- the step machine
  const finishing = useRef<string | null>(null);
  const walkT0 = useRef<{ uid: string; at: number } | null>(null);
  useEffect(() => {
    if (!p || !state) return;
    let timer = 0;
    const later = (ms: number) => {
      timer = window.setTimeout(() => setTick((n) => n + 1), Math.max(30, Math.min(ms, 60_000)));
    };
    const now = serverNow();
    const until = (iso: string | null | undefined) => (iso ? Date.parse(iso) : 0);
    if (state.travel || until(p.jailed_until) > now || until(p.hospitalized_until) > now) {
      if (current || queue.length) useTasks.getState().clear();
      return;
    }
    const busyEnd = until(p.busy_until);

    if (current?.phase === 'running') {
      const end = Math.min(until(current.busyUntil) || busyEnd, busyEnd || Infinity);
      if (now < end) {
        later(end - now + 60);
      } else if (finishing.current !== current.uid) {
        // the timer ran out: fresh state first, then the slot frees up
        finishing.current = current.uid;
        const uid = current.uid;
        void refresh().finally(() => {
          if (useTasks.getState().current?.uid === uid) useTasks.getState().setCurrent(null);
        });
      }
      return () => window.clearTimeout(timer);
    }
    if (current?.phase === 'walking') {
      // no 3D home to walk in (map opened, canvas suspended) or the walk takes too long: start now
      if (walkT0.current?.uid !== current.uid) walkT0.current = { uid: current.uid, at: Date.now() };
      const waited = Date.now() - walkT0.current.at;
      const live = current.zone ? placeLive === current.locationId : homeLive;
      if (!live || waited > WALK_TIMEOUT_MS) void start(current.uid);
      else later(WALK_TIMEOUT_MS - waited + 50);
      return () => window.clearTimeout(timer);
    }
    if (current || !queue.length) return;
    if (Date.now() < holdUntil) {
      later(holdUntil - Date.now() + 30);
      return () => window.clearTimeout(timer);
    }
    // the server is busy (a shift, an action started elsewhere): wait for it, never send early
    if (busyEnd > now) {
      later(busyEnd - now + 60);
      return () => window.clearTimeout(timer);
    }
    if (busyEnd && stateAt.current < busyEnd) {
      void refresh();
      later(1500);
      return () => window.clearTimeout(timer);
    }
    const next = queue[0];
    const walk = next.zone
      ? placeLive === next.locationId && p.location_id === next.locationId
      : Boolean(next.group) && homeLive && next.locationId === p.home_location_id && p.location_id === p.home_location_id;
    const c = useTasks.getState().popNext(walk ? 'walking' : 'starting');
    if (c && !walk) void start(c.uid);
    return () => window.clearTimeout(timer);
  }, [p, state, current, queue, holdUntil, homeLive, placeLive, tick, refresh, start]);

  const onTaskArrive = useCallback(
    (key: string) => {
      const c = useTasks.getState().current;
      if (c && c.uid === key && c.phase === 'walking') void start(key);
    },
    [start],
  );
  const onTaskCancel = useCallback((key: string) => {
    const t = useTasks.getState();
    if (t.current?.uid === key && t.current.phase === 'walking') {
      t.setCurrent(null);
      t.hold(10_000); // the player took over: the next task waits until their walk ends
    }
  }, []);
  const onWalkDone = useCallback(() => {
    if (useTasks.getState().holdUntil > Date.now()) useTasks.getState().hold(0);
  }, []);

  const homeTask: HomeTask | null =
    current?.phase === 'walking' && current.group ? { key: current.uid, activity: current.id, group: current.group } : null;
  // L2: a queued task inside a place walks to its zone first
  const placeTask: PlaceTask | null =
    current?.phase === 'walking' && current.zone ? { key: current.uid, zone: current.zone } : null;
  return { homeTask, placeTask, onTaskArrive, onTaskCancel, onWalkDone };
}
