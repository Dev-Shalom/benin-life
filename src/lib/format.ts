// Formatting helpers — P1-SHELL. Money uses the real-world short scale (K, M, B, T, Q).

/** Anything money-like the API might hand us: number, bigint, or a digit string (kept exact). */
export type MoneyInput = number | bigint | string | null | undefined;

/** Exact integer digits + sign for a money value. Strings/bigints keep full precision. */
function toDigits(n: MoneyInput): { neg: boolean; digits: string } {
  let s: string;
  if (typeof n === 'bigint') s = n.toString();
  else if (typeof n === 'string' && /^\s*-?\d+\s*$/.test(n)) s = n.trim();
  else {
    const v = Math.round(Number(n ?? 0) || 0);
    s = Number.isFinite(v) ? BigInt(v).toString() : '0';
  }
  const neg = s.startsWith('-');
  const digits = (neg ? s.slice(1) : s).replace(/^0+(?=\d)/, '');
  return { neg: neg && digits !== '0', digits };
}

function group(digits: string): string {
  return digits.replace(/\B(?=(\d{3})+(?!\d))/g, ',');
}

/** naira(12500) → "₦12,500"; naira(-500) → "-₦500"; naira(1.25e12) → "₦1,250,000,000,000". */
export function naira(n: MoneyInput): string {
  const { neg, digits } = toDigits(n);
  return `${neg ? '-' : ''}₦${group(digits)}`;
}

const SCALE: [number, string][] = [[15, 'Q'], [12, 'T'], [9, 'B'], [6, 'M'], [3, 'K']];

/**
 * Compact naira for tight spots: ₦950, ₦9,999, ₦12.5K, ₦125K, ₦1.2M, ₦3.4B, ₦1.1T, ₦2Q, ₦2,500Q.
 * Under ₦10,000 stays in full. Truncates (never rounds up), so ₦999,999 shows ₦999K, not ₦1M.
 */
export function nairaShort(n: MoneyInput): string {
  const { neg, digits } = toDigits(n);
  const sign = neg ? '-' : '';
  if (digits.length <= 4) return `${sign}₦${group(digits)}`;
  for (const [exp, suffix] of SCALE) {
    if (digits.length <= exp) continue;
    const whole = digits.slice(0, digits.length - exp);
    const frac = digits.charAt(digits.length - exp);
    const body = whole.length >= 3 ? group(whole) : frac === '0' ? whole : `${whole}.${frac}`;
    return `${sign}₦${body}${suffix}`;
  }
  return `${sign}₦${group(digits)}`;
}

/** True when nairaShort would hide digits (so a title/tap should reveal the full amount). */
export function isShortened(n: MoneyInput): boolean {
  return nairaShort(n) !== naira(n);
}

const SUFFIX_EXP: Record<string, number> = { k: 3, m: 6, b: 9, t: 12, q: 15 };

/**
 * Parse typed money: "2.5M" → 2500000, "₦1,250,000" → 1250000, "500k" → 500000, "1 t" → 1e12.
 * Returns null for anything invalid, fractional naira, zero (unless allowZero), negative (unless
 * allowNegative) or beyond JS's exact range (~₦9Q).
 */
export function parseNaira(input: string, opts: { allowNegative?: boolean; allowZero?: boolean } = {}): number | null {
  const s = String(input ?? '').replace(/[\s,₦_]/g, '').toLowerCase().replace(/^n(?=[\d.-])/, '');
  const m = /^(-?)(\d*)(?:\.(\d*))?([kmbtq]?)$/.exec(s);
  if (!m) return null;
  const [, minus, int, frac = '', suf] = m;
  if (!int && !frac) return null;
  const exp = suf ? SUFFIX_EXP[suf] : 0;
  if (frac.length > exp && /[1-9]/.test(frac.slice(exp))) return null; // fractional kobo / naira
  const digits = ((int || '0') + frac.padEnd(exp, '0').slice(0, exp)).replace(/^0+(?=\d)/, '');
  const v = Number(digits);
  if (!Number.isSafeInteger(v)) return null;
  if (v === 0 && !opts.allowZero) return null;
  if (minus && v !== 0 && !opts.allowNegative) return null;
  return minus ? -v : v;
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
