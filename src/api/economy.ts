// E4 money sinks: typed wrappers for the fee preview, tax, bills and prestige RPCs (server: 20261019000400_money_sinks.sql).
import { rpc } from '../lib/api';

export interface FeeQuote {
  fee: number; tier_fee: number; stamp_duty: number; doubled: boolean; tiered: boolean; rate_pct?: number;
  amount: number; total: number; kind: 'transfer' | 'tip'; sent_today: number; soft_cap: number; left_before_soft_cap: number | null;
}
export const bankTransferQuote = (amount: number, kind: 'transfer' | 'tip' = 'transfer') =>
  rpc<FeeQuote>('bank_transfer_quote', { p_amount: amount, p_kind: kind });

export interface TaxBand { from: number; to: number | null; pct: number; eff_pct: number }
export interface TaxRecord { week: string; earned: number; tax: number; paid: number; rate_pct: number; holiday: boolean; exempt: boolean }
export interface TaxInfo {
  enabled: boolean;
  bands: TaxBand[];
  holiday: { name: string; cut_pct: number } | null;
  week: { start: string; ends_at: string; earned: number; est_tax: number };
  owed: number;
  exempt_until: string;
  exempt_now: boolean;
  last: TaxRecord[];
}
export const taxInfo = () => rpc<TaxInfo>('tax_info');

export type BillKind = 'house' | 'car' | 'business' | 'land';
export interface Bill {
  id: number; kind: BillKind; title: string; detail: string; amount: number; late_fee: number; total: number;
  due_at: string; status: 'open' | 'paid'; paid_at: string | null; late: boolean; overdue: boolean; blocked: boolean; blocks_at: string;
}
export interface BankSinks {
  enabled: boolean; owed: number; grace_until: string; block_days: number; late_fee_pct: number; autopay: boolean; open_total: number;
  bills: Bill[]; tax: TaxInfo;
}
export const bankSinks = () => rpc<BankSinks>('bank_sinks');
export const billsPay = (id: number) => rpc<{ message: string; paid: number }>('bills_pay', { p_id: id });
export const billsPayAll = () => rpc<{ message: string; paid: number; count: number; left: number }>('bills_pay_all');
export const taxPay = (amount?: number) => rpc<{ message: string; paid: number; owed: number }>('tax_pay', { p_amount: amount ?? null });

export interface DonorRow { rank: number; username: string; total: number | null; band?: string | null; badge: string | null; title: string | null; me: boolean }
export interface DonorsTop {
  tiers: { name: string; amount: number }[]; min: number; rows: DonorRow[];
  me: { total: number; donations: number; badge: string | null } | null;
}
export const donateCity = (amount: number) => rpc<{ message: string; total: number; badge: string | null; xp: number }>('donate_city', { p_amount: amount });
export const donorsTop = (limit = 20) => rpc<DonorsTop>('donors_top', { p_limit: limit });

export interface PartyStatus {
  enabled: boolean; cost: number; fun_boost: number; minutes: number; cooldown_left_seconds: number;
  here: { id: string; name: string; ok: boolean; reason: string | null };
  active: { id: number; location: string; name: string; host: string; ends_at: string; guests: number }[];
}
export const cityPartyStatus = () => rpc<PartyStatus>('city_party_status');
export const cityPartyThrow = () => rpc<{ message: string; guests: number }>('city_party_throw');

export interface ChiefTitles {
  enabled: boolean;
  mine: { tier: number; name: string; ward: string; of: string | null; paid: number } | null;
  tiers: { tier: number; name: string; price: number; cost_now: number; owned: boolean }[];
  wards: { id: string; name: string }[];
}
export const chiefTitles = () => rpc<ChiefTitles>('chief_titles');
export const chiefTitleBuy = (tier: number, ward: string) => rpc<{ message: string }>('chief_title_buy', { p_tier: tier, p_ward: ward });

// ---- admin
export interface EconomyOverview {
  days: number; from: string;
  supply: { total: number; cash: number; bank: number; yahoo: number; gangs: number; business: number; players: number };
  window: { created: number; destroyed: number; net: number; destroyed_pct_of_created: number | null };
  inflation: { growth_pct: number | null; growth_7d_pct: number | null; supply_start: number; state: 'hot' | 'ok' | 'cooling' | 'unknown' };
  series: { day: string; created: number; destroyed: number; net: number; categories: { category: string; created: number; destroyed: number }[] }[];
  categories: { category: string; created: number; destroyed: number }[];
  reasons: { reason: string; category: string; created: number; destroyed: number }[];
  holders: { rank: number; id: string; username: string; cash: number; bank: number; yahoo: number; business: number; total: number }[];
  tax: Record<string, number>;
  switches: Record<string, boolean>;
}
