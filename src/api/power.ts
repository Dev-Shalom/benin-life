// Power cuts, filling stations and the black market (docs/POWER.md). Server: 20261113000100_power.sql, 20261113000200_fuel_market.sql.
import { rpc } from '../lib/api';

export type PowerSource = 'mains' | 'generator' | 'battery' | 'solar' | 'none';
export type BackupKind = 'none' | 'generator' | 'inverter' | 'solar';

export interface PowerGenerator {
  id: string;
  name: string;
  on: boolean;
  running: boolean;
  fuel_l: number;
  tank_l: number;
  fuel: 'petrol' | 'diesel';
  burn_lph: number;
  hours_left: number | null;
  soundproof: boolean;
  noisy: boolean;
  fault_until: string | null;
  faulty: boolean;
  empty: boolean;
}

export interface PowerInverter {
  kva: number;
  kwh: number;
  cap_kwh: number;
  pct: number;
  hours_left: number | null;
  solar_kw: number;
  solar_now_kw: number;
  solar_covers: boolean;
  empty: boolean;
  health: number;
}

/** What the server wants shown once (a card or a toast). `key` identifies the cut so power_ack makes it go away. */
export type NoticeKind =
  | 'outage_none' | 'outage_gen' | 'outage_gen_on' | 'outage_nofuel' | 'outage_inverter' | 'outage_inverter_empty'
  | 'back' | 'back_gen_on' | 'fuel_empty' | 'battery_empty' | 'bm_unlocked';
export interface PowerNotice { kind: NoticeKind; key: string }

export interface PowerBagItem { item: string; name: string; qty: number; litres: number; fuel: 'petrol' | 'diesel'; grey: boolean; icon: string | null }

export interface PowerStatus {
  enabled: boolean;
  visiting?: boolean;
  area?: { id: string; name: string; outage_pct: number };
  mains: 'on' | 'off';
  until?: string | null;
  city?: boolean;
  cut_key?: string | null;
  source: PowerSource;
  lit: boolean;
  hours_left?: number | null;
  load_kw?: number;
  backup: { kind: BackupKind; kinds: string[]; generator?: PowerGenerator | null; inverter?: PowerInverter | null };
  fuel_l?: number;
  battery_pct?: number;
  blackout?: { ends: string } | null;
  notices?: PowerNotice[];
  bag?: PowerBagItem[];
  poll_seconds: number;
  effects?: boolean;
  server_time?: string;
  message?: string;
}

export const powerStatus = () => rpc<PowerStatus>('power_status');
export const powerGenToggle = (on: boolean) => rpc<PowerStatus>('power_gen_toggle', { p_on: on });
export const powerRefuel = (item: string, qty = 1) => rpc<PowerStatus & { poured: number; bad_batch: boolean }>('power_refuel', { p_item: item, p_qty: qty });
export const powerGenRepair = () => rpc<PowerStatus & { spent: number }>('power_gen_repair');
export const powerAck = (kind: 'outage' | 'back' | 'fuel' | 'batt' | 'bm', key: string) => rpc<{ ok: boolean }>('power_ack', { p_kind: kind, p_key: key });

export interface PowerAreaRow { id: string; name: string; outage_pct: number; mains: 'on' | 'off'; city: boolean; until: string | null }
export const powerAreaStatus = (area?: string) => rpc<{ enabled: boolean; areas: PowerAreaRow[] }>('power_area_status', { p_area: area ?? null });

// ---- filling stations ----
export interface FuelStationInfo {
  station: boolean;
  id?: string;
  name?: string;
  dry?: boolean;
  scarce?: boolean;
  state?: 'normal' | 'up' | 'down' | 'scarce' | 'dry';
  petrol?: number;
  diesel?: number;
  yesterday?: number;
  queue_seconds?: number;
  owner?: string | null;
  line?: string;
}
export const fuelStationInfo = (loc?: string) => rpc<FuelStationInfo>('fuel_station_info', { p_loc: loc ?? null });

// ---- black market ----
export interface BmRisk {
  raid_pct: number; scam_pct: number; robbery_pct: number; stolen_pct: number; faulty_pct: number; success_pct: number; unit_price: number; shop_price: number;
}
export interface BmOffer {
  id: string; name: string; emoji: string; blurb: string; kind: 'grey_fuel' | 'gear'; price: number; risk: BmRisk; risk_level: 'low' | 'medium' | 'high';
}
export interface BmStatus {
  unlocked: boolean;
  open?: boolean;
  hot?: boolean;
  here?: boolean;
  open_hour?: number;
  close_hour?: number;
  scarce?: boolean;
  cash?: number;
  crew?: boolean;
  line?: string;
  offers?: BmOffer[];
}
export interface BmDeal {
  outcome: 'ok' | 'faulty' | 'scam' | 'raid' | 'robbery' | 'stolen';
  message: string;
  spent: number;
  cred?: number;
  lost_cash?: number;
  faulty?: boolean;
  case?: number;
}
export const bmStatus = () => rpc<BmStatus>('bm_status');
export const bmBuy = (offer: string, qty = 1) => rpc<BmDeal>('bm_buy', { p_offer: offer, p_qty: qty });

// ---- admin ----
export interface AdminPowerArea { id: string; name: string; outage_pct: number; mains: 'on' | 'off'; until: string | null }
export interface AdminPowerEvent { id: number; kind: 'blackout' | 'scarcity'; started_at: string; ends_at: string; note: string }
export interface AdminPowerOverview {
  areas: AdminPowerArea[];
  blackout: AdminPowerEvent | null;
  scarcity: AdminPowerEvent | null;
  random_blackout_now: boolean;
  random_scarcity_now: boolean;
  recent: AdminPowerEvent[];
  generators_on: number;
  with_backup: number;
  petrol_today: number | null;
  diesel_today: number | null;
}
export const adminPowerOverview = () => rpc<AdminPowerOverview>('admin_power_overview');
export const adminPowerEventStart = (kind: 'blackout' | 'scarcity', hours: number, note: string) =>
  rpc<{ id: number; message: string }>('admin_power_event_start', { p_kind: kind, p_hours: hours, p_note: note });
export const adminPowerEventEnd = (kind: 'blackout' | 'scarcity') => rpc<{ ended: number; message: string }>('admin_power_event_end', { p_kind: kind });
