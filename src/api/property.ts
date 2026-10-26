// Own your home (server: 20261103000100_property.sql, docs/PROPERTY.md): buy, build, rent out, and the landlord's dashboard.
import { rpc } from '../lib/api';
import type { Receipt } from '../state/receipts';

export interface PropLand { plots: number; locked: number; free: number; plot_price: number | null; avg_cost: number }
export interface PropArea { id: string; name: string; blurb: string; can_build: boolean; land: PropLand }
export interface PropType { id: string; name: string; emoji: string; bedrooms: number; blurb: string; kind: string; m2: number }
export interface PropOffer { id: string; area: string; type_id: string; price: number; agent: number; legal: number; total: number; rent_market: number }
export interface PropStage { name: string; pct: number; starts_at?: string; ends_at?: string }
export interface PropDesign {
  id: string; name: string; emoji: string; description: string; type_id: string; units: number; plots: number;
  hours: number; stages: PropStage[]; costs: Record<string, number>;
}
export interface PropBuild {
  id: string; area: string; area_name: string; design_id: string; name: string; emoji: string; units: number; plots: number;
  cost: number; status: string; started_at: string; ready_at: string; progress: number; seconds_left: number;
  stage: string; stages: Required<PropStage>[]; refund: number;
}
export interface PropOccupant {
  user_id: string; username: string; role: 'owner' | 'tenant'; since: string; rent: number; caution: number; owed: number;
  notice_at: string | null; ends_at: string | null; ended_by: string | null;
}
export interface PropCard {
  id: string; name: string; area: string; area_name: string; type_id: string; type_name: string; emoji: string; bedrooms: number;
  kind: string; m2: number; source: 'bought' | 'built'; unit_no: number | null; build_id: string | null; basis: number; value: number;
  market_rent: number; rent_min: number; rent_max: number; listed: boolean; listed_rent: number | null; caution: number;
  sale: { gross: number; agent: number; upgrades: number; net: number }; upgrades: number; garage: boolean;
  occupant: PropOccupant | null; lives_here: boolean; bill_rent: number; pending_income: number; earned: number; acquired_at: string;
}
export interface PropResidence {
  role: 'owner' | 'tenant'; property: PropCard; since: string; rent: number; caution: number; landlord: string | null;
  notice_at: string | null; ends_at: string | null; ended_by: string | null;
}
export interface PropSettings {
  agent_fee_pct: number; legal_fee_pct: number; resale_pct: number; sell_agent_pct: number; rent_cut_pct: number; notice_days: number;
  caution_max_weeks: number; return_days: number; evict_owed_weeks: number; advance_weeks: number; tenant_agent_weeks: number;
  max_owned: number; permit_pct: number; cancel_refund_pct: number;
}
export interface PropOverview {
  enabled: boolean; buy_enabled: boolean; build_enabled: boolean; rent_out_enabled: boolean;
  money: { bank: number; cash: number }; settings: PropSettings;
  areas: PropArea[]; types: PropType[]; offers: PropOffer[]; designs: PropDesign[]; builds: PropBuild[]; properties: PropCard[];
  residence: PropResidence | null; pending_income: number; owned_count: number;
}
export interface PropListing {
  id: string; name: string; area: string; area_name: string; type_id: string; type_name: string; emoji: string; bedrooms: number;
  kind: string; m2: number; rent: number; caution: number; market_rent: number; landlord: string; unit_no: number | null;
  upgrades: number; garage: boolean; advance: number; agent: number; total: number; listed_at: string;
}
export interface PropRentQuote extends PropListing { can_rent: boolean; reason: string | null; have: number; notice_days: number }
export interface PropBuyQuote extends PropOffer { can_buy: boolean; reason: string | null; have: number }
export interface PropBuildQuote {
  design: string; area: string; cost: number; permit: number; total: number; hours: number; units: number; plots: number;
  land: PropLand; have: number; can_build: boolean; reason: string | null; stages: PropStage[];
}
export interface PropResult { message: string; receipt?: Receipt; [k: string]: unknown }

export const propertyOverview = () => rpc<PropOverview>('property_overview');
export const propertyQuoteBuy = (offer: string) => rpc<PropBuyQuote>('property_quote_buy', { p_offer: offer });
export const propertyBuy = (offer: string) => rpc<PropResult>('property_buy', { p_offer: offer });
export const propertySell = (id: string) => rpc<PropResult>('property_sell', { p_property: id });
export const propertyLiveIn = (id: string) => rpc<PropResult>('property_live_in', { p_property: id });
export const propertyQuoteBuild = (design: string, area: string) => rpc<PropBuildQuote>('property_quote_build', { p_design: design, p_area: area });
export const propertyBuildStart = (design: string, area: string) => rpc<PropResult>('property_build_start', { p_design: design, p_area: area });
export const propertyBuildCancel = (id: string) => rpc<PropResult>('property_build_cancel', { p_build: id });
export const propertyList = (id: string, rent: number, caution: number) => rpc<PropResult>('property_list', { p_property: id, p_rent: rent, p_caution: caution });
export const propertyUnlist = (id: string) => rpc<PropResult>('property_unlist', { p_property: id });
export const propertyListings = (area: string | null, maxRent: number | null, kind: string | null) =>
  rpc<{ listings: PropListing[] }>('property_listings', { p_area: area, p_max_rent: maxRent, p_kind: kind });
export const propertyRentQuote = (id: string) => rpc<PropRentQuote>('property_rent_quote', { p_property: id });
export const propertyRent = (id: string) => rpc<PropResult>('property_rent', { p_property: id });
export const propertyGiveNotice = (id: string) => rpc<PropResult>('property_give_notice', { p_property: id });
export const propertyCancelNotice = (id: string) => rpc<PropResult>('property_cancel_notice', { p_property: id });
export const housePastRelease = (home: string) => rpc<{ message: string; refund: number }>('house_past_release', { p_home: home });

// admin
export interface AdminPropertyOverview {
  stats: Record<'properties' | 'bought' | 'built' | 'listed_vacant' | 'tenancies' | 'owner_living' | 'builds' | 'rent_per_week' | 'rent_paid_7d' | 'value', number>;
  listings: { id: string; name: string; area: string; owner: string; rent: number; caution: number; market_rent: number; listed_at: string }[];
  tenancies: { property: string; name: string; area: string; owner: string; tenant: string; rent: number; caution: number; owed: number; since: string;
    notice_at: string | null; ends_at: string | null; ended_by: string | null }[];
  builds: { id: string; owner: string; name: string; area: string; cost: number; started_at: string; ready_at: string }[];
  events: { at: string; kind: string; user: string | null; detail: Record<string, unknown> }[];
}
export const adminPropertyOverview = (limit = 100) => rpc<AdminPropertyOverview>('admin_property_overview', { p_limit: limit });
export const adminPropertyEndTenancy = (id: string, reason: string) => rpc<{ message: string }>('admin_property_end_tenancy', { p_property: id, p_reason: reason });
