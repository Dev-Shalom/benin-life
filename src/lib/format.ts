// Formatting helpers — P1-SHELL.

function group(n: number): string {
  return Math.trunc(Math.abs(n))
    .toString()
    .replace(/\B(?=(\d{3})+(?!\d))/g, ',');
}

/** naira(12500) → "₦12,500"; naira(-500) → "-₦500". */
export function naira(n: number | string | null | undefined): string {
  const v = Math.round(Number(n ?? 0) || 0);
  return `${v < 0 ? '-' : ''}₦${group(v)}`;
}

/** Compact naira for tight spots: ₦950, ₦12.5k, ₦1.2m, ₦3.4b. */
export function nairaShort(n: number | string | null | undefined): string {
  const v = Math.round(Number(n ?? 0) || 0);
  const a = Math.abs(v);
  const sign = v < 0 ? '-' : '';
  const fmt = (x: number) => (x >= 100 ? Math.round(x).toString() : x.toFixed(1).replace(/\.0$/, ''));
  if (a >= 1e9) return `${sign}₦${fmt(a / 1e9)}b`;
  if (a >= 1e6) return `${sign}₦${fmt(a / 1e6)}m`;
  if (a >= 1e4) return `${sign}₦${fmt(a / 1e3)}k`;
  return `${sign}₦${group(a)}`;
}

/** Real-time countdown: 42 → "0:42", 3723 → "1:02:03". Input seconds. */
export function countdown(seconds: number): string {
  const s = Math.max(0, Math.ceil(seconds));
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const sec = s % 60;
  const pad = (x: number) => x.toString().padStart(2, '0');
  return h > 0 ? `${h}:${pad(m)}:${pad(sec)}` : `${m}:${pad(sec)}`;
}

/** Seconds until an ISO timestamp relative to `nowMs` (server-corrected). */
export function secondsUntil(iso: string | null | undefined, nowMs: number): number {
  if (!iso) return 0;
  const t = Date.parse(iso);
  if (Number.isNaN(t)) return 0;
  return Math.max(0, (t - nowMs) / 1000);
}

/** Game clock time: (14, 5) → "2:05 PM". */
export function clockTime(hour: number, minute: number): string {
  const h12 = hour % 12 === 0 ? 12 : hour % 12;
  return `${h12}:${minute.toString().padStart(2, '0')} ${hour < 12 ? 'AM' : 'PM'}`;
}

/** Game-minute duration: 45 → "45 mins", 90 → "1 hr 30 mins". */
export function gameDuration(minutes: number): string {
  const m = Math.max(0, Math.round(minutes));
  if (m < 60) return `${m} min${m === 1 ? '' : 's'}`;
  const h = Math.floor(m / 60);
  const rest = m % 60;
  const hs = `${h} hr${h === 1 ? '' : 's'}`;
  return rest ? `${hs} ${rest} min${rest === 1 ? '' : 's'}` : hs;
}

/** Real duration in seconds: 8 → "8s", 95 → "1m 35s", 4000 → "1h 6m". */
export function realDuration(seconds: number): string {
  const s = Math.max(0, Math.round(seconds));
  if (s < 60) return `${s}s`;
  const m = Math.floor(s / 60);
  if (m < 60) return s % 60 ? `${m}m ${s % 60}s` : `${m}m`;
  const h = Math.floor(m / 60);
  return m % 60 ? `${h}h ${m % 60}m` : `${h}h`;
}

/** "just now", "5 mins ago", "3 hrs ago", "2 days ago". */
export function timeAgo(iso: string | null | undefined, nowMs = Date.now()): string {
  if (!iso) return '';
  const diff = Math.max(0, (nowMs - Date.parse(iso)) / 1000);
  if (diff < 45) return 'just now';
  const m = Math.round(diff / 60);
  if (m < 60) return `${m} min${m === 1 ? '' : 's'} ago`;
  const h = Math.round(m / 60);
  if (h < 24) return `${h} hr${h === 1 ? '' : 's'} ago`;
  const d = Math.round(h / 24);
  return `${d} day${d === 1 ? '' : 's'} ago`;
}

/** 0.234 → "23%"; values already 0–100 pass `isPct`. */
export function pct(n: number, isPct = false): string {
  const v = isPct ? n : n * 100;
  return `${v < 10 && v > 0 ? v.toFixed(1).replace(/\.0$/, '') : Math.round(v)}%`;
}

/** "upper_sakponba" → "Upper Sakponba". */
const DISTRICT_NAMES: Record<string, string> = { gra: 'GRA', sapele_rd: 'Sapele Road', airport_rd: 'Airport Road' };

/** District id -> display name ("gra" -> "GRA", "sapele_rd" -> "Sapele Road"). */
export function districtName(id: string): string {
  return DISTRICT_NAMES[id] ?? titleCase(id);
}

export function titleCase(id: string): string {
  return id
    .split(/[_\s-]+/)
    .filter(Boolean)
    .map((w) => w[0].toUpperCase() + w.slice(1))
    .join(' ');
}
