// V1-5 hooks/helpers shared by the Bank panel, the PoS panel and the phone Bank app (docs/BANK.md).
import { useEffect, useState } from 'react';
import { bankInfo } from '../../api/bank';
import { errorMessage } from '../../lib/api';
import type { BankInfo } from '../../lib/types';
import { useGame } from '../../state/game';
import { useUi } from '../../state/ui';

/** bank_info(), reloaded with `reload()` (call it after any money move). */
export function useBankInfo() {
  const [info, setInfo] = useState<BankInfo | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [tick, setTick] = useState(0);
  useEffect(() => {
    let alive = true;
    bankInfo()
      .then((i) => alive && (setInfo(i), setErr(null)))
      .catch((e) => alive && setErr(errorMessage(e)));
    return () => {
      alive = false;
    };
  }, [tick]);
  return { info, err, reload: () => setTick((t) => t + 1) };
}

/** Close the panel/phone, open the map and select a place (optionally on a tab). */
export function useGoTo() {
  const select = useUi((s) => s.select);
  const setMapOpen = useUi((s) => s.setMapOpen);
  const setOverlay = useUi((s) => s.setOverlay);
  const closePanel = useUi((s) => s.closePanel);
  const here = useGame((s) => s.state?.profile.location_id);
  return (id: string, tab: 'bank' | 'pos') => {
    setOverlay(null);
    closePanel();
    if (id !== here) setMapOpen(true);
    select(id, tab);
  };
}

/** "Closed · opens 8:00 AM in about 4 min" for the bank hours block. */
export function realWait(seconds: number): string {
  if (seconds < 60) return `${Math.max(1, Math.ceil(seconds))} sec`;
  const m = Math.ceil(seconds / 60);
  return m < 60 ? `${m} min` : `${Math.floor(m / 60)} hr ${m % 60 ? `${m % 60} min` : ''}`.trim();
}
