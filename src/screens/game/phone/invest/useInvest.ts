// I1: loads the Invest overview for the Bank app (polls while a Save / Invest tab is open) and runs actions.
import { useCallback, useEffect, useRef, useState } from 'react';
import { investOverview, type InvestMsg, type InvestOverview } from '../../../../api/invest';
import { errorMessage } from '../../../../lib/api';
import { useGame } from '../../../../state/game';
import { toast } from '../../../../ui';

export function useInvest(active: boolean) {
  const refresh = useGame((s) => s.refresh);
  const [data, setData] = useState<InvestOverview | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const alive = useRef(true);
  useEffect(() => { alive.current = true; return () => { alive.current = false; }; }, []);

  const reload = useCallback(async () => {
    try {
      const d = await investOverview();
      if (alive.current) { setData(d); setErr(null); }
    } catch (e) {
      if (alive.current) setErr(errorMessage(e));
    }
  }, []);

  useEffect(() => {
    if (!active) return;
    void reload();
    const t = window.setInterval(() => { if (!document.hidden) void reload(); }, 20000);
    return () => window.clearInterval(t);
  }, [active, reload]);

  /** Run an action; toast its message; refresh the wallet + the overview. Returns the result or null on error. */
  const run = useCallback(async <T extends { message?: string }>(fn: () => Promise<T>, quiet = false): Promise<T | null> => {
    setBusy(true);
    try {
      const r = await fn();
      if (!quiet && r.message) toast(r.message, (r as InvestMsg).profit != null && (r as InvestMsg).profit! < 0 ? 'info' : 'good');
      await Promise.all([refresh(), reload()]);
      return r;
    } catch (e) {
      toast(errorMessage(e), 'bad');
      await reload();
      return null;
    } finally {
      if (alive.current) setBusy(false);
    }
  }, [refresh, reload]);

  return { data, err, busy, reload, run };
}
