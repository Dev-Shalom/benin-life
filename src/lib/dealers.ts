// H2 car dealer price tiers (docs/GARAGE.md "Dealer tiers"). The server is the authority (bl_dealer_price in
// 20261012000400_sell_receipts.sql); this mirrors its rounding so the Cars app can compare dealers.
import { useEffect, useState } from 'react';
import { supabase } from './supabase';
import type { DealerInfo } from './types';

export interface DealerRow extends DealerInfo {
  location_id: string;
  sort: number;
  active: boolean;
}

export const TIER_LABEL: Record<DealerInfo['tier'], string> = { budget: 'Budget', mid: 'Standard', premium: 'Premium' };

/** base x multiplier, rounded like the server (₦10,000 from ₦1M, else ₦1,000). */
export function dealerPrice(base: number, multiplier: number): number {
  const v = base * multiplier;
  return v >= 1_000_000 ? Math.round(v / 10_000) * 10_000 : Math.round(v / 1_000) * 1_000;
}

let cache: Promise<DealerRow[]> | null = null;

export function loadDealers(): Promise<DealerRow[]> {
  if (!cache) {
    cache = Promise.resolve(
      supabase.from('car_dealers').select('location_id, tier, multiplier, label, blurb, sort, active').order('sort'),
    ).then(({ data, error }) => {
      if (error) { cache = null; return []; }
      return (data ?? []).map((d) => ({ ...d, multiplier: Number(d.multiplier) })) as DealerRow[];
    });
  }
  return cache;
}

export function useDealers(): DealerRow[] {
  const [rows, setRows] = useState<DealerRow[]>([]);
  useEffect(() => {
    let alive = true;
    void loadDealers().then((r) => { if (alive) setRows(r.filter((d) => d.active)); });
    return () => { alive = false; };
  }, []);
  return rows;
}
