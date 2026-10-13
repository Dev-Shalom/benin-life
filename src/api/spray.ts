// SP1 custom spray (docs/SPRAY.md). The server checks everything (open club, cash in hand, min / max, cooldown, VIP
// booking) and writes the hype man's shout-out; the client only picks the amount.
import { rpc } from '../lib/api';
import type { Announcement } from '../state/hype';
import type { MoneyDrop } from './moneyPick';

export type SprayTier = 'small' | 'nice' | 'big' | 'huge' | 'oga' | 'billionaire' | 'trillionaire';

export interface SprayStatus {
  enabled: boolean;
  location: string | null;
  place: string;
  in_club: boolean;
  open: boolean;
  cash: number;
  bank: number;
  min: number;
  max: number;
  vip_min: number;
  vip_pct: number;
  vip_ok: boolean;
  cooldown_s: number;
  cooldown_left: number;
  chips: number[];
  vip_chips: number[];
  tiers: { id: SprayTier; label: string; min: number }[];
  points: number;
  sprays: number;
  total_sprayed: number;
  best: number;
}

export interface SprayResult {
  message: string;
  amount: number;
  cash_after: number;
  tier: SprayTier;
  vip: boolean;
  hype_amount: number;
  points: number;
  total_points: number;
  cooldown_s: number;
  hype: Announcement | null;
  /** SP2: the notes this spray dropped for the club (null when the share is under one note). */
  drop?: MoneyDrop | null;
}

export const sprayStatus = (location: string | null) => rpc<SprayStatus>('get_spray_status', { p_location: location });

export const sprayCustom = (location: string, amount: number, vip: boolean) =>
  rpc<SprayResult>('spray_custom', { p_location: location, p_amount: amount, p_vip: vip });

export const SPRAY_TIERS: SprayTier[] = ['small', 'nice', 'big', 'huge', 'oga', 'billionaire', 'trillionaire'];

export const SPRAY_TIER_LABEL: Record<SprayTier, string> = {
  small: 'Small', nice: 'Nice', big: 'Big', huge: 'Huge', oga: 'Oga', billionaire: 'Billionaire', trillionaire: 'Trillionaire',
};

/** 0 (small) … 6 (trillionaire); -1 for an older spray row without a tier. */
export function sprayRank(tier: string | null | undefined): number {
  return tier ? SPRAY_TIERS.indexOf(tier as SprayTier) : -1;
}

/** ₦2 TRILLION / ₦1.5 BILLION / ₦250 MILLION / ₦50 THOUSAND / ₦900 (truncated, same as the server's bl_spray_short). */
export function nairaWords(n: number): string {
  const v = Math.max(0, Math.round(Number(n) || 0));
  const steps: [number, string][] = [[1e12, 'TRILLION'], [1e9, 'BILLION'], [1e6, 'MILLION'], [1e3, 'THOUSAND']];
  for (const [s, w] of steps) {
    if (v >= s) {
      const x = v / s;
      const t = x >= 100 ? Math.floor(x) : Math.floor(x * 10) / 10;
      return `₦${t.toLocaleString('en-US', { maximumFractionDigits: 1 })} ${w}`;
    }
  }
  return `₦${v}`;
}
