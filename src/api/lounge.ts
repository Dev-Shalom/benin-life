// R7 Members' Lounge (docs/LOUNGE.md). Tiers live in the admin table lounge_tiers; status, buying and the VIP guest pass are RPCs.
import { rpc } from '../lib/api';

export interface LoungeTier {
  id: string;
  name: string;
  icon: string;
  blurb: string;
  price: number;
  hours: number;
  discount_pct: number;
  vip: boolean;
  gold_tag: boolean;
  vouchers: number;
  guests: number;
  requirement: string | null;
  requirement_ok: boolean;
  /** buy | renew | upgrade | lower (a better tier is active) | max (renew cap) | locked (requirement). */
  action: 'buy' | 'renew' | 'upgrade' | 'lower' | 'max' | 'locked';
}

export interface LoungeMe {
  tier_id: string;
  tier_name: string;
  icon: string;
  vip: boolean;
  gold: boolean;
  discount_pct: number;
  started_at: string;
  expires_at: string;
  seconds_left: number;
  vouchers_left: number;
  source: 'purchase' | 'admin';
  guest_slots: number;
  guests_active: number;
}

export interface LoungeStatus {
  enabled: boolean;
  location_id: string | null;
  location_name: string | null;
  cash: number;
  bank: number;
  bank_first: boolean;
  access: 'member' | 'guest' | null;
  vip: boolean;
  me: LoungeMe | null;
  expired_tier: string | null;
  guest_pass: { host: string; expires_at: string } | null;
  guest_hours: number;
  tiers: LoungeTier[];
}

/** The `lounge` block place_interior adds for a lounge. */
export interface LoungeCard {
  on: boolean;
  access: 'member' | 'guest' | null;
  vip: boolean;
  tier: { id: string; name: string; icon: string; vip: boolean; gold: boolean; discount_pct: number } | null;
  expires_at: string | null;
  expired: boolean;
  seconds_left: number | null;
  vouchers_left: number;
  guest_until: string | null;
}

export const loungeStatus = () => rpc<LoungeStatus>('lounge_status');
export const loungeBuy = (tier: string) =>
  rpc<{ message: string; kind: string; tier: string; expires_at: string; spent: number; status: LoungeStatus }>('lounge_buy', { p_tier: tier });
export const loungeBringGuest = (friend: string) => rpc<{ message: string; expires_at: string }>('lounge_bring_guest', { p_friend: friend });

/** "29d 23h", "5h 12m", "42m" */
export function timeLeftLabel(seconds: number | null | undefined): string {
  const s = Math.max(0, Math.floor(seconds ?? 0));
  const d = Math.floor(s / 86400);
  const h = Math.floor((s % 86400) / 3600);
  const m = Math.floor((s % 3600) / 60);
  if (d > 0) return `${d}d ${h}h`;
  if (h > 0) return `${h}h ${m}m`;
  return `${Math.max(1, m)}m`;
}

/** "24 hours" / "30 days" */
export function durationLabel(hours: number): string {
  return hours % 24 === 0 ? `${hours / 24} day${hours === 24 ? '' : 's'}` : `${hours} hours`;
}
