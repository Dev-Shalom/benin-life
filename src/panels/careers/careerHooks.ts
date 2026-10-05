// V1-3 career helpers + hooks (kept apart from CareerUI.tsx so that file only exports components).
import { useCallback, useEffect, useState } from 'react';
import { applyForJob, getJobsCatalog, quitJob, workShift } from '../../api/careers';
import { errorMessage } from '../../lib/api';
import { getCfg } from '../../lib/config';
import { gameDuration, realDuration } from '../../lib/format';
import type { JobsCatalog } from '../../lib/types';
import { useGame } from '../../state/game';
import { supabase } from '../../lib/supabase';
import { toast } from '../../ui';

/** "5 hrs · about 3m 45s" (game length + real length at the current speed). */
export function shiftLength(minutes: number): string {
  return `${gameDuration(minutes)} · about ${realLength(minutes)}`;
}

/** Real time a shift of `minutes` game minutes takes at the current speed ("3m 45s"). */
export function realLength(minutes: number): string {
  return realDuration(minutes * Number(getCfg('time.real_seconds_per_game_minute', 0.75)));
}

export function perfHint(perf: number): string {
  if (perf >= 105) return 'You are in great shape: bonus pay this shift.';
  if (perf >= 85) return 'Good shape. Full pay or close to it.';
  if (perf >= 65) return 'A bit worn out. Eat, rest or bathe first to earn more.';
  return 'You will struggle today. Eat, sleep and freshen up before you work.';
}

/** Jobs catalog with reload; refetches when the job changes. */
export function useJobsCatalog() {
  const jobKey = useGame((s) => `${s.state?.profile.job_id ?? ''}:${s.state?.profile.job_level ?? ''}`);
  const [cat, setCat] = useState<JobsCatalog | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [tick, setTick] = useState(0);
  useEffect(() => {
    let alive = true;
    getJobsCatalog()
      .then((c) => alive && (setCat(c), setErr(null)))
      .catch((e) => alive && setErr(errorMessage(e)));
    return () => {
      alive = false;
    };
  }, [jobKey, tick]);
  return { cat, err, reload: () => setTick((t) => t + 1) };
}

/** Apply / quit / work with toasts + refresh. */
export function useCareerActions(after?: () => void) {
  const refresh = useGame((s) => s.refresh);
  const [busy, setBusy] = useState<string | null>(null);
  const run = useCallback(async (key: string, fn: () => Promise<{ message: string }>, close = false) => {
    setBusy(key);
    try {
      const r = await fn();
      toast(r.message, 'good');
      await refresh();
      if (close) after?.();
    } catch (e) {
      toast(errorMessage(e), 'bad');
    } finally {
      setBusy(null);
    }
  }, [refresh, after]);
  return {
    busy,
    apply: (track: string) => run(`apply:${track}`, () => applyForJob(track)),
    quit: () => run('quit', quitJob),
    work: () => run('work', workShift, true),
  };
}


const sellersCache = new Map<string, Promise<string[]>>();

/** Location ids that sell an item (items.sold_at), cached for the session. V1-4. */
export function useItemSellers(itemId: string | undefined): string[] | null {
  const [ids, setIds] = useState<string[] | null>(null);
  useEffect(() => {
    if (!itemId) return;
    let alive = true;
    let p = sellersCache.get(itemId);
    if (!p) {
      p = Promise.resolve(supabase.from('items').select('sold_at').eq('id', itemId).maybeSingle())
        .then(({ data }) => ((data?.sold_at as string[] | undefined) ?? []))
        .catch(() => []);
      sellersCache.set(itemId, p);
    }
    void p.then((v) => alive && setIds(v));
    return () => {
      alive = false;
    };
  }, [itemId]);
  return ids;
}
