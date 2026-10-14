// I1 Invest & Save (docs/INVEST.md; server: 20261014000200_invest_save.sql). All money moves bank <-> holdings.
import { rpc } from '../lib/api';

export type Risk = 'safe' | 'medium' | 'high';

export interface InvestProduct {
  id: string; kind: 'savings' | 'safelock' | 'mmf' | 'fd' | 'tbill' | 'bond' | 'farm' | 'transport' | 'pos' | 'flat';
  name: string; icon: string; blurb: string; risk: Risk; rate_pct: number; term_days: number; exit_fee_pct: number;
  forfeits_interest: boolean; unit_price: number; market_id: string | null; min_amount: number; max_amount: number;
  cycle_days: number; gain_min_pct: number; gain_max_pct: number; income_day: number; resale_pct: number; depr_pct_year: number;
  events: Record<string, { label: string; chance_pct: number; loss_of: string; loss_pct?: number; span_days?: number }>; sort: number;
}

export interface InvestMarket {
  id: string; kind: 'stock' | 'crypto' | 'land' | 'bond' | 'index'; name: string; icon: string; blurb: string; risk: Risk; ticker: string;
  price: number; change_24h: number; change_7d: number; fee_pct: number; community_pct: number; levy_chance_pct: number;
  levy_min_pct: number; levy_max_pct: number; dividend_yield_pct: number; drift_pct_year: number; min_qty: number; max_qty: number;
  spark: [number, number][]; sort: number;
}

export interface InvestPosition {
  id: number; ref_id: string; kind: string; name: string; icon: string; risk: Risk; qty: number; cost: number; value: number;
  profit: number; exit_value: number; exit_fee: number; forfeit: number; day_change: number; collectable: number; ready: boolean;
  matured: boolean; note: string; chart: 'line' | 'market'; market_id: string | null; price: number | null; rate_pct: number;
  accrued: number; opened_at: string; matures_at: string | null; locked: boolean; vacant_until: string | null; gain_pct: number | null;
  last_at: string;
}

export interface InvestSummary { invested: number; value: number; unrealized: number; realized: number; profit: number; today: number; count: number }

export interface InvestLogRow { id: number; at: string; kind: string; label: string; amount: number; profit: number | null }

export interface InvestOverview {
  cash: number; bank: number; year_days: number; day_seconds: number; now: string; enabled: boolean;
  summary: InvestSummary; products: InvestProduct[]; markets: InvestMarket[]; positions: InvestPosition[]; log: InvestLogRow[];
  pending_deal: { id: number; area: string; plots: number; levy: number; expires_at: string } | null;
}

export interface LandQuote {
  area: string; name: string; plots: number; plot_price: number; subtotal: number; agent_fee_pct: number; agent_fee: number;
  community_pct: number; community: number; total: number; levy_chance_pct: number; levy_min: number; levy_max: number; bank: number;
}

export interface LandResult extends Partial<LandQuote> {
  status: 'done' | 'levy' | 'walked'; message: string; deal_id?: number; levy?: number; levy_pct?: number; total_with_levy?: number; bank?: number;
}

export interface InvestMsg { message: string; bank?: number; payout?: number; profit?: number; events?: { id: string; label: string; loss_pct: number }[] }

export const investOverview = () => rpc<InvestOverview>('invest_overview');
export const investSeries = (market: string, points = 120, hours = 168) =>
  rpc<{ market: string; price: number; points: [number, number][] }>('invest_market_series', { p_market: market, p_points: points, p_hours: hours });
export const investBuy = (product: string, amount: number) => rpc<InvestMsg>('invest_buy', { p_product: product, p_amount: amount });
export const investWithdraw = (position: number, amount: number | null = null) => rpc<InvestMsg>('invest_withdraw', { p_position: position, p_amount: amount });
export const investCollect = (position: number, reinvest = false) => rpc<InvestMsg>('invest_collect', { p_position: position, p_reinvest: reinvest });
export const investMarketBuy = (market: string, qty: number) => rpc<InvestMsg>('invest_market_buy', { p_market: market, p_qty: qty });
export const investMarketSell = (market: string, qty: number | null) => rpc<InvestMsg>('invest_market_sell', { p_market: market, p_qty: qty });
export const landQuote = (area: string, plots: number) => rpc<LandQuote>('invest_land_quote', { p_area: area, p_plots: plots });
export const landBuy = (area: string, plots: number) => rpc<LandResult>('invest_land_buy', { p_area: area, p_plots: plots });
export const landLevy = (deal: number, pay: boolean) => rpc<LandResult>('invest_land_levy', { p_deal: deal, p_pay: pay });
export const landSell = (area: string, plots: number) => rpc<InvestMsg>('invest_land_sell', { p_area: area, p_plots: plots });

/** Seconds -> '3 d 4 h' / '5 h 10 m' / '12 m' of REAL time. */
export function realLeft(sec: number): string {
  const s = Math.max(0, Math.round(sec));
  const d = Math.floor(s / 86400), h = Math.floor((s % 86400) / 3600), m = Math.floor((s % 3600) / 60);
  if (d > 0) return `${d} d ${h} h`;
  if (h > 0) return `${h} h ${m} m`;
  return `${Math.max(1, m)} m`;
}
