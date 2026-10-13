// SP2 Pick the money (docs/SPRAY.md). Every spray drops club.pick_pct of the money as notes for the other players
// in the club; each tap is club.pick_note to cash. The server checks everything (in the club, not expired, rate and
// per-player caps, the pool) with the drop row locked; the client only batches taps.
import { rpc } from '../lib/api';
import type { Announcement } from '../state/hype';

export interface MoneyDrop {
  id: number;
  location_id: string;
  sprayer: string | null;
  username: string | null;
  total: number;
  remaining: number;
  note: number;
  vip: boolean;
  self_ok: boolean;
  settled: boolean;
  created_at: string;
  expires_at: string;
  /** From the RPCs only (not on a Realtime row). */
  notes?: number;
  ms_left?: number;
  my_total?: number;
}

export interface PickResult {
  drop: number;
  picked: number;
  taps: number;
  capped?: boolean;
  expired: boolean;
  empty?: boolean;
  remaining: number;
  notes_left: number;
  my_taps: number;
  my_total: number;
  cash_after: number;
  first?: boolean;
  hype?: Announcement | null;
}

export interface LiveDrops {
  enabled: boolean;
  poll_s: number;
  drops: MoneyDrop[];
}

export const moneyPick = (drop: number, taps: number) => rpc<PickResult>('money_pick', { p_drop: drop, p_taps: taps });

export const moneyDropsLive = (location: string) => rpc<LiveDrops>('money_drops_live', { p_location: location });
