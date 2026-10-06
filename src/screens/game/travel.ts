// Shared trip logic (S1): the location sheet's TravelPicker and the phone's Ride app both use it.
import { useEffect, useState } from 'react';
import { rpc, errorMessage } from '../../lib/api';
import { naira } from '../../lib/format';
import { MODE_META } from '../../lib/pidgin';
import type { Location, TravelOption, TravelQuote } from '../../lib/types';
import { useGame } from '../../state/game';
import { toast } from '../../ui';

export function riskTone(pct: number): 'good' | 'warn' | 'bad' {
  if (pct < 3) return 'good';
  if (pct < 10) return 'warn';
  return 'bad';
}

/** Quote + book a trip (shared by the location sheet's picker and the phone's Ride app). */
export function useTravel(dest: Location, cash: number, onStarted: () => void) {
  const refresh = useGame((s) => s.refresh);
  const [quote, setQuote] = useState<TravelQuote | null>(null);
  const [loading, setLoading] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [mode, setMode] = useState<string | null>(null);
  const [going, setGoing] = useState(false);

  // New destination → reset.
  const [forDest, setForDest] = useState(dest.id);
  if (forDest !== dest.id) {
    setForDest(dest.id);
    setQuote(null);
    setMode(null);
    setErr(null);
  }

  const load = async () => {
    setLoading(true);
    setErr(null);
    try {
      const q = await rpc<TravelQuote>('travel_quote', { p_dest: dest.id });
      setQuote(q);
      const best = q.options.find((o) => o.allowed && o.cost <= cash && o.mode === 'bus') ?? q.options.find((o) => o.allowed && o.cost <= cash);
      setMode(best?.mode ?? null);
    } catch (e) {
      setErr(errorMessage(e));
    } finally {
      setLoading(false);
    }
  };

  // Re-quote if the sheet stays open a while (traffic changes with the clock).
  useEffect(() => {
    if (!quote) return;
    const id = window.setInterval(() => void load(), 45_000);
    return () => window.clearInterval(id);
  }, [quote?.dest]);

  const go = async () => {
    if (!mode) return;
    setGoing(true);
    try {
      const res = await rpc<{ message?: string }>('travel_start', { p_dest: dest.id, p_mode: mode });
      toast(res?.message ?? `You're on your way to ${dest.name}.`, 'good');
      await refresh();
      onStarted();
    } catch (e) {
      toast(errorMessage(e), 'bad');
    } finally {
      setGoing(false);
    }
  };

  const selected = quote?.options.find((o) => o.mode === mode);
  return { quote, loading, err, mode, setMode, going, load, go, selected };
}

/** The book button label for the chosen option. */
export function bookLabel(o: TravelOption | undefined, verb = 'Go by'): string {
  if (!o) return 'Pick a way to travel';
  const name = o.mode === 'walk' ? 'Walk there' : `${verb} ${MODE_META[o.mode]?.label ?? o.label}`;
  return `${name} · ${o.cost ? naira(o.cost) : 'Free'}`;
}

