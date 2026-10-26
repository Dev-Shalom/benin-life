// Small shared bits for the property tabs (docs/PROPERTY.md).
import type { ReactNode } from 'react';
import { naira } from '../../../../lib/format';

/** 90 -> "1m", 5400 -> "1h 30m", 200000 -> "2d 7h". */
export function longDuration(seconds: number): string {
  const s = Math.max(0, Math.round(seconds));
  const d = Math.floor(s / 86400);
  const h = Math.floor((s % 86400) / 3600);
  const m = Math.floor((s % 3600) / 60);
  if (d > 0) return h ? `${d}d ${h}h` : `${d}d`;
  if (h > 0) return m ? `${h}h ${m}m` : `${h}h`;
  if (m > 0) return `${m}m`;
  return `${s}s`;
}

/** "in 12 days" for a future ISO time, "today" when under a day. */
export function daysLeft(iso: string | null | undefined, nowMs: number): string {
  const ms = iso ? Date.parse(iso) : NaN;
  if (Number.isNaN(ms)) return '';
  const d = (ms - nowMs) / 86400000;
  if (d <= 0) return 'ending now';
  if (d < 1) return `${Math.max(1, Math.round(d * 24))}h left`;
  return `${Math.ceil(d)} day${Math.ceil(d) === 1 ? '' : 's'} left`;
}

export function dateShort(iso: string | null | undefined): string {
  const ms = iso ? Date.parse(iso) : NaN;
  if (Number.isNaN(ms)) return '';
  return new Date(ms).toLocaleString('en-GB', { timeZone: 'Africa/Lagos', day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' });
}

export const KIND_LABEL: Record<string, string> = {
  face_me: 'Room', self_contain: 'Self-contain', mini_flat: 'Flat or bungalow', duplex: 'Duplex', hostel: 'Hostel',
};

/** A label / value row of a quote. */
export function QuoteRow({ label, value, strong, hint }: { label: ReactNode; value: ReactNode; strong?: boolean; hint?: string }) {
  return (
    <div className={`pp-q__row${strong ? ' is-strong' : ''}`}>
      <span>{label}{hint && <small>{hint}</small>}</span>
      <b>{value}</b>
    </div>
  );
}

export const money = (n: number) => naira(n);
