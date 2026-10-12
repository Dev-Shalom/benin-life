// B2 Babalawo shrine (docs/BABALAWO.md). The server rolls every outcome and keeps every charm; the client only shows them.
import { rpc } from '../lib/api';

export interface ShrineOffering { item: string; name: string; icon: string | null; price?: number; need: number; have: number }

export interface Charm {
  id: number;
  kind: string;
  service_id: string | null;
  status: string;
  /** null = no time limit (uses only, e.g. the vanishing charm). */
  expires_at: string | null;
  uses_left: number | null;
  created_at: string;
  value: number | null;
  name: string;
  icon: string;
  /** madness / bad luck / curse */
  debuff: boolean;
  effect: string | null;
  /** Money charm only: Baba's weekly call and the payouts. */
  demand?: {
    due_at: string | null; open: boolean; deadline: string | null; ignored: boolean; cash: number; goats: number;
    next_payout_at: string | null; payouts: number;
  } | null;
}

export interface ShrineService {
  id: string;
  name: string;
  icon: string;
  blurb: string;
  note: string;
  price: number;
  kind: string;
  value: number;
  uses: number | null;
  seconds: number;
  fail_pct: number;
  effect: string;
  duration: string;
  offerings: ShrineOffering[];
  /** My charm of this kind that still works (refused to buy twice). */
  active: Charm | null;
}

export interface ShrineInfo {
  enabled: boolean;
  fail_pct: number;
  cash: number;
  here: boolean;
  services: ShrineService[];
  charms: Charm[];
  visit: { id: number; service_id: string; resolve_at: string; name: string } | null;
}

export interface ShrineResult {
  status: 'done' | 'failed' | 'none';
  service_id?: string;
  name?: string;
  icon?: string;
  line?: string;
  reading?: string | null;
  paid?: number;
  charm?: Charm | null;
  already?: boolean;
}

export interface ShrineNotice { id: number; kind: 'blessing' | 'backfire'; title: string; body: string; amount: number; created_at: string }

export interface ShrineDemand { charm_id: number; deadline: string; ignored: boolean; cash: number; goats: number; have_goats: number; have_cash: number }

export interface ShrineStatus {
  resolved: ShrineResult | null;
  visit: { id: number; service_id: string; resolve_at: string } | null;
  charms: Charm[];
  notices: ShrineNotice[];
  demand: ShrineDemand | null;
}

export const SHRINE_LABEL_PREFIX = 'With Baba:';

export const shrineInfo = () => rpc<ShrineInfo>('shrine_info');
export const shrineStart = (service: string) =>
  rpc<{ visit_id: number; busy_until: string; seconds: number; service_id: string; name: string; paid: number; message: string }>('shrine_start', { p_service: service });
export const shrineFinish = () => rpc<ShrineResult>('shrine_finish');
export const shrineStatus = () => rpc<ShrineStatus>('shrine_status');
export const shrineNoticeSeen = (ids: number[]) => rpc<{ seen: number }>('shrine_notice_seen', { p_ids: ids });
export const shrineDemandPay = () => rpc<{ message: string; paid: number; goats: number; next_due_at: string }>('shrine_demand_pay');
export const shrineDemandIgnore = () => rpc<{ message: string; deadline: string }>('shrine_demand_ignore');

/** "2d 4h", "5h 10m", "12m" until an ISO time (null = no time limit). */
export function timeLeft(iso: string | null | undefined, nowMs: number): string {
  if (!iso || iso === 'infinity') return '';
  const s = Math.max(0, Math.floor((Date.parse(iso) - nowMs) / 1000));
  const d = Math.floor(s / 86400);
  const h = Math.floor((s % 86400) / 3600);
  const m = Math.floor((s % 3600) / 60);
  if (d > 0) return `${d}d ${h}h`;
  if (h > 0) return `${h}h ${m}m`;
  return `${Math.max(1, m)}m`;
}

/** One line for a charm chip: "2d 4h left" / "2 escapes left". */
export function charmLeft(c: Pick<Charm, 'expires_at' | 'uses_left'>, nowMs: number): string {
  if (c.uses_left != null && !c.expires_at) return `${c.uses_left} escape${c.uses_left === 1 ? '' : 's'} left`;
  const t = timeLeft(c.expires_at, nowMs);
  return t ? `${t} left` : '';
}
