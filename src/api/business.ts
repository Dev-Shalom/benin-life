// R10 own a business RPCs (server: 20261018000900_business.sql, docs/BUSINESS.md).
import { rpc } from '../lib/api';

export interface BusinessLogRow { id: number; kind: string; title: string; amount: number; at: string }

export interface BusinessCard {
  id: number;
  name: string;
  type: string;
  type_name: string;
  icon: string;
  scene: string;
  plot: string;
  plot_label: string;
  area: string;
  area_label: string;
  /** locations.id of the plot (go there to work a shift) */
  location: string;
  level: number;
  max_level: number;
  next: { level: number; cost: number; mult: number } | null;
  takings: number;
  cap_at: string;
  full: boolean;
  ready_at: string;
  setting_up: boolean;
  gross_day: number;
  cost_day: number;
  net_day: number;
  base_day: number;
  level_mult: number;
  needs_stock: boolean;
  stock_pct: number;
  stock_until: string;
  restock_cost: number;
  restock_hours: number;
  staff: number;
  staff_slots: number;
  staff_wage: number;
  staff_income_pct: number;
  staff_list: { name: string; wage: number }[];
  hire_fee: number;
  boost: boolean;
  boost_until: string | null;
  boost_pct: number;
  insured: boolean;
  insured_until: string | null;
  insure_cost: number;
  insure_days: number;
  shifts_used: number;
  shifts_cap: number;
  invested: number;
  value: number;
  sell_back: number;
  listed: boolean;
  lifetime_income: number;
  lifetime_visit: number;
  bought_at: string;
  log: BusinessLogRow[] | null;
}

export interface BusinessMine {
  enabled: boolean;
  businesses: BusinessCard[];
  max_owned: number;
  cap_hours: number;
  skill_level: number;
  visit_cut_pct: number;
  sell_back_pct: number;
  shift_seconds: number;
  shift_energy: number;
  insurance_cover_pct: number;
}

export interface BusinessSlot { plot: string; label: string; area: string; area_label: string; price: number; taken: boolean; taken_by: string | null; taken_name: string | null }
export interface BusinessTypeInfo {
  id: string;
  name: string;
  icon: string;
  blurb: string;
  scene: string;
  price: number;
  setup_minutes: number;
  income_min: number;
  income_max: number;
  rent_day: number;
  power_day: number;
  staff_slots: number;
  staff_wage: number;
  staff_income_pct: number;
  max_level: number;
  needs_stock: boolean;
  restock_cost: number;
  req_skill_level: number;
  req_cert: string | null;
  req_cert_text: string | null;
  gate: string | null;
  met: boolean;
  slots: BusinessSlot[];
}
export interface BusinessCatalog { enabled: boolean; types: BusinessTypeInfo[]; owned: number; max_owned: number; skill_level: number }

/** What a place card needs to know about a business place (null = not a business). */
export interface BusinessAt {
  id: number; name: string; type: string; type_name: string; icon: string; level: number; max_level: number; owner: string; mine: boolean;
  setting_up: boolean; ready_at: string; listed: boolean; staff: number; cut_pct: number; takings: number | null; boost: boolean;
}

type Msg = { message: string };
export const businessMine = () => rpc<BusinessMine>('business_mine');
export const businessCatalog = () => rpc<BusinessCatalog>('business_catalog');
export const businessAt = (location: string) => rpc<BusinessAt | null>('business_at', { p_location: location });
export const businessBuy = (type: string, plot: string, name: string) =>
  rpc<Msg & { business: BusinessCard; location: string }>('business_buy', { p_type: type, p_plot: plot, p_name: name });
export const businessCollect = (id?: number | null) => rpc<Msg & { amount: number; count: number }>('business_collect', { p_id: id ?? null });
export const businessRestock = (id: number) => rpc<Msg & { business: BusinessCard; cost: number }>('business_restock', { p_id: id });
export const businessUpgrade = (id: number) => rpc<Msg & { business: BusinessCard; cost: number }>('business_upgrade', { p_id: id });
export const businessHire = (id: number) => rpc<Msg & { business: BusinessCard }>('business_hire', { p_id: id });
export const businessFire = (id: number) => rpc<Msg & { business: BusinessCard }>('business_fire', { p_id: id });
export const businessInsure = (id: number) => rpc<Msg & { business: BusinessCard }>('business_insure', { p_id: id });
export const businessWork = (id: number) => rpc<Msg & { business: BusinessCard; busy_until: string }>('business_work', { p_id: id });
export const businessSell = (id: number) => rpc<Msg & { amount: number; takings: number }>('business_sell', { p_id: id });

// ---- admin ----
export interface AdminBusinessRow {
  id: number; name: string; type: string; icon: string; level: number; owner: string; owner_id: string; plot: string; takings: number; staff: number;
  listed: boolean; source: string; bought_at: string; lifetime_income: number; lifetime_visit: number;
}
export interface AdminBusinessOverview {
  stats: { owned: number; plots: number; free: number; listed: number; income_7d: number };
  rows: AdminBusinessRow[];
}
export interface AdminBusinessGet {
  businesses: { id: number; name: string; type: string; icon: string; level: number; plot: string; takings: number; staff: number; listed: boolean; source: string; invested: number; lifetime_income: number }[];
  types: { id: string; name: string; areas: string[] }[];
  plots: { id: string; label: string; area: string }[];
}
export const adminBusinessOverview = (limit = 200) => rpc<AdminBusinessOverview>('admin_business_overview', { p_limit: limit });
export const adminBusinessGet = (user: string) => rpc<AdminBusinessGet>('admin_business_get', { p_user: user });
export const adminBusinessGrant = (user: string, type: string, plot: string, name: string) =>
  rpc<Msg & { business: number }>('admin_business_grant', { p_user: user, p_type: type, p_plot: plot, p_name: name });
export const adminBusinessRemove = (id: number, reason: string) => rpc<Msg & { business: number }>('admin_business_remove', { p_business: id, p_reason: reason });

/** "in 3h", "in 12 min", "now". */
export function inText(iso: string | null, nowMs = Date.now()): string {
  if (!iso) return '';
  const s = (Date.parse(iso) - nowMs) / 1000;
  if (s <= 30) return 'now';
  if (s >= 86400) return `${Math.floor(s / 86400)}d ${Math.floor((s % 86400) / 3600)}h`;
  if (s >= 3600) return `${Math.floor(s / 3600)}h ${Math.floor((s % 3600) / 60)}m`;
  return `${Math.max(1, Math.ceil(s / 60))} min`;
}
