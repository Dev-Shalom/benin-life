// R9 Benin Market RPCs (server: 20261018000800_market.sql, docs/MARKET.md).
import { useEffect, useState } from 'react';
import { rpc } from '../lib/api';

export type MarketKind = 'item' | 'furniture' | 'car' | 'land' | 'business';

export interface MarketKindInfo {
  kind: MarketKind;
  label: string;
  enabled: boolean;
  fee_pct: number;
  floor_pct: number;
  ceiling_pct: number;
}

export interface MarketInfo {
  enabled: boolean;
  kinds: MarketKindInfo[];
  tradeable_items: string[];
  tradeable_cars: string[];
  tradeable_furniture: string[];
  daily_cap: number;
  daily_used: number;
  max_active: number;
  active: number;
  expire_days: number;
  min_offer_pct: number;
  min_price: number;
  private_enabled: boolean;
  sell_wait_seconds: number;
  can_sell: boolean;
}

export interface MarketListing {
  id: number;
  kind: MarketKind;
  ref: string;
  title: string;
  icon: string;
  qty: number;
  price: number;
  value: number;
  pct: number | null;
  open_to_offers: boolean;
  private: boolean;
  private_to: string | null;
  seller: string;
  mine: boolean;
  detail: { plate?: string; wear?: number } & Record<string, unknown>;
  cond: string;
  status: 'active' | 'sold' | 'cancelled' | 'expired' | 'removed';
  created_at: string;
  expires_at: string;
  reports: number;
  sold_price: number | null;
  fee: number | null;
  my_offer: { id: number; amount: number; expires_at: string } | null;
  offers: number | null;
}

export interface MarketQuote {
  ok: boolean;
  message?: string;
  hint?: string;
  kind?: MarketKind;
  title?: string;
  icon?: string;
  value?: number;
  qty?: number;
  cond?: string;
  detail?: Record<string, unknown>;
  fee_pct?: number;
  enabled?: boolean;
  min_price?: number;
  max_price?: number;
  floor_pct?: number;
  ceiling_pct?: number;
}

export interface MarketOfferIn { id: number; listing: number; title: string; icon: string; price: number; amount: number; buyer: string; expires_at: string; created_at: string }
export interface MarketOfferOut { id: number; listing: number; title: string; icon: string; price: number; amount: number; status: string; seller: string; expires_at: string; created_at: string }
export interface MarketTradeRow { id: number; title: string; price: number; fee: number; side: 'sold' | 'bought'; other: string; at: string }
export interface MarketMine { listings: MarketListing[]; offers_in: MarketOfferIn[]; offers_out: MarketOfferOut[]; history: MarketTradeRow[] }

export type MarketSort = 'new' | 'price_asc' | 'price_desc' | 'deal';
export interface BrowseArgs { kind?: MarketKind | ''; search?: string; min?: number | null; max?: number | null; sort?: MarketSort; limit?: number; offset?: number }

export const marketInfo = () => rpc<MarketInfo>('market_info');
export const marketQuote = (kind: MarketKind, ref: string, qty = 1, key?: string | null) =>
  rpc<MarketQuote>('market_quote', { p_kind: kind, p_ref: ref, p_qty: qty, p_key: key ?? null });
export const marketList = (a: { kind: MarketKind; ref: string; qty?: number; price: number; offers?: boolean; to?: string; key?: string | null }) =>
  rpc<{ message: string; listing: MarketListing }>('market_list', {
    p_kind: a.kind, p_ref: a.ref, p_qty: a.qty ?? 1, p_price: a.price, p_open_offers: Boolean(a.offers), p_to: a.to?.trim() || null, p_key: a.key ?? null,
  });
export const marketCancel = (id: number) => rpc<{ message: string }>('market_cancel', { p_listing: id });
export const marketBrowse = (a: BrowseArgs = {}) =>
  rpc<{ rows: MarketListing[]; total: number }>('market_browse', {
    p_kind: a.kind || null, p_search: a.search?.trim() || null, p_min: a.min ?? null, p_max: a.max ?? null, p_sort: a.sort ?? 'new',
    p_limit: a.limit ?? 40, p_offset: a.offset ?? 0,
  });
export const marketMine = () => rpc<MarketMine>('market_mine');
export const marketBuy = (id: number, expected?: number) => rpc<{ message: string; price: number; fee: number; net: number }>('market_buy', { p_listing: id, p_expected: expected ?? null });
export const marketOffer = (id: number, amount: number) => rpc<{ message: string; offer: number }>('market_offer', { p_listing: id, p_amount: amount });
export const marketOfferRespond = (id: number, accept: boolean) => rpc<{ message: string; accepted: boolean; failed?: boolean }>('market_offer_respond', { p_offer: id, p_accept: accept });
export const marketOfferCancel = (id: number) => rpc<{ message: string }>('market_offer_cancel', { p_offer: id });
export const marketReport = (id: number, reason: string) => rpc<{ message: string }>('market_report', { p_listing: id, p_reason: reason });

// ---- admin ----
export interface AdminMarketLive {
  id: number; kind: MarketKind; title: string; icon: string; qty: number; price: number; value: number; pct: number | null;
  seller: string; seller_id: string; open_to_offers: boolean; private_to: string | null; cond: string; reports: number; reasons: string[];
  created_at: string; expires_at: string;
}
export interface AdminMarketTrade {
  id: number; title: string; kind: MarketKind; price: number; fee: number; value: number; pct: number | null; via: 'buy' | 'offer';
  flags: string[]; seller: string; buyer: string; created_at: string;
}
export interface AdminMarketOverview {
  stats: { active: number; sold_7d: number; volume_7d: number; fees_7d: number; flagged_7d: number; reported: number };
  live: AdminMarketLive[];
  trades: AdminMarketTrade[];
}
export const adminMarketOverview = (limit = 100) => rpc<AdminMarketOverview>('admin_market_overview', { p_limit: limit });
export const adminMarketRemove = (id: number, reason: string) => rpc<{ message: string }>('admin_market_remove', { p_listing: id, p_reason: reason });

// ---- small cache so the sell sheets and the app share one market_info ----
let cache: { at: number; info: MarketInfo } | null = null;
const freshInfo = (): MarketInfo | null => (cache && Date.now() - cache.at < 20_000 ? cache.info : null);
export function useMarketInfo(): MarketInfo | null {
  const [info, setInfo] = useState<MarketInfo | null>(freshInfo);
  useEffect(() => {
    let alive = true;
    if (freshInfo()) return;
    marketInfo().then((i) => { cache = { at: Date.now(), info: i }; if (alive) setInfo(i); }).catch(() => {});
    return () => { alive = false; };
  }, []);
  return info;
}
export const dropMarketInfoCache = () => { cache = null; };

/** "in 3d 4h", "in 5h", "in 12 min". */
export function leftText(iso: string, nowMs = Date.now()): string {
  const s = Math.max(0, (Date.parse(iso) - nowMs) / 1000);
  if (s >= 86400) return `${Math.floor(s / 86400)}d ${Math.floor((s % 86400) / 3600)}h`;
  if (s >= 3600) return `${Math.floor(s / 3600)}h`;
  return `${Math.max(1, Math.ceil(s / 60))} min`;
}
