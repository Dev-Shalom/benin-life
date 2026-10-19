// E4: VAT is part of the displayed price (docs/ECONOMY_SINKS.md). The server returns the VAT-inclusive price for shop and car
// items (shop_list); furniture and boutique prices come straight from their tables, so the client adds the same VAT and luxury
// levy with the same rounding as the server's bl_gross(): net + round(net x vat %) + round(net x luxury %).
import { getCfg } from './config';

export type TaxKind = 'furniture' | 'wardrobe';

export interface TaxRates { vat: number; lux: number }

export function taxRates(kind: TaxKind, net: number): TaxRates {
  if (net <= 0) return { vat: 0, lux: 0 };
  const vat = getCfg('economy.vat_enabled', true) ? getCfg('economy.vat_pct', 7.5) : 0;
  let lux = 0;
  if (getCfg('economy.luxury_enabled', true)) {
    const min = kind === 'wardrobe' ? getCfg('economy.luxury_wardrobe_min', 1_000_000) : getCfg('economy.luxury_furniture_min', 5_000_000);
    if (net >= min) lux = getCfg('economy.luxury_pct', 5);
  }
  return { vat, lux };
}

/** The price the player pays for a catalogue price, VAT and luxury levy included. */
export function grossPrice(kind: TaxKind, net: number): number {
  const r = taxRates(kind, net);
  return net + Math.round((net * r.vat) / 100) + Math.round((net * r.lux) / 100);
}

/** "incl. VAT" / "incl. VAT + luxury levy" (empty when there is no tax on it). */
export function taxNote(vat: number, lux: number): string {
  if (vat > 0 && lux > 0) return 'incl. VAT + luxury levy';
  if (vat > 0) return 'incl. VAT';
  if (lux > 0) return 'incl. luxury levy';
  return '';
}

export function noteFor(kind: TaxKind, net: number): string {
  const r = taxRates(kind, net);
  return taxNote(r.vat, r.lux);
}
