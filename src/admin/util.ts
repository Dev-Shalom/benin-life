// Non-component helpers for the admin sections.
import { useCallback, useEffect, useRef, useState } from 'react';
import { errorMessage } from '../lib/api';
import { naira } from '../lib/format';

/** Load data once (and on demand). Keeps the old data while reloading. */
export function useLoad<T>(fn: () => Promise<T>, deps: unknown[] = []) {
  const [data, setData] = useState<T | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const fnRef = useRef(fn);
  fnRef.current = fn;
  const reload = useCallback(async () => {
    setLoading(true);
    try {
      setData(await fnRef.current());
      setError(null);
    } catch (e) {
      setError(errorMessage(e));
    } finally {
      setLoading(false);
    }
  }, []);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  useEffect(() => { void reload(); }, deps);
  return { data, setData, error, loading, reload };
}

// ---------- value helpers ----------
export function decimalsOf(n: number): number {
  const s = String(n);
  const i = s.indexOf('.');
  return i < 0 ? 0 : s.length - i - 1;
}

export function sliderStep(kind: string, min: number, max: number, value: number): number {
  const range = max - min;
  if (kind === 'naira') return range > 20000 ? 500 : range > 2000 ? 50 : 10;
  if (range <= 2) return 0.05;
  if (range <= 20) return decimalsOf(value) > 0 || kind === 'percent' ? 0.1 : 1;
  if (range <= 200) return decimalsOf(value) > 0 ? 0.05 : 1;
  return Math.max(1, Math.round(range / 200));
}

export function showSlider(kind: string, min: number | null, max: number | null): boolean {
  if (min === null || max === null || !(max > min)) return false;
  if (kind === 'naira') return max - min <= 200000;
  return max - min <= 10000;
}

export function fmtNumber(kind: string, v: unknown): string {
  const n = Number(v);
  if (!Number.isFinite(n)) return String(v);
  if (kind === 'naira') return naira(n);
  if (kind === 'percent') return `${n}%`;
  if (kind === 'minutes') return `${n} min`;
  return String(n);
}

export function fmtValue(kind: string, v: unknown): string {
  if (v === null || v === undefined) return '—';
  if (kind === 'bool') return v ? 'On' : 'Off';
  if (typeof v === 'number') return fmtNumber(kind, v);
  if (typeof v === 'string') return v === '' ? '(empty)' : v;
  return JSON.stringify(v);
}

export function timeShort(iso: string | null | undefined): string {
  if (!iso) return '—';
  const d = new Date(iso);
  const now = Date.now();
  const s = Math.round((now - d.getTime()) / 1000);
  if (s < 60) return 'just now';
  if (s < 3600) return `${Math.floor(s / 60)}m ago`;
  if (s < 86400) return `${Math.floor(s / 3600)}h ago`;
  if (s < 86400 * 7) return `${Math.floor(s / 86400)}d ago`;
  return d.toLocaleDateString(undefined, { day: 'numeric', month: 'short' });
}

