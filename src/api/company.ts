// Companies + real businesses RPCs (server: 20261020000100_companies.sql, docs/COMPANIES.md).
import { rpc } from '../lib/api';

export interface CompanyLogRow { id: number; kind: string; title: string; amount: number; at: string }
export interface CompanyBranch {
  id: number; area: string; area_name: string; tier: number; rev_mult: number; format: string; format_name: string; emoji: string; staff_slots: number;
  is_hq: boolean; upkeep_week: number; next_format: string | null; next_name: string | null; next_cost: number | null;
}
export interface MarketingOption { id: string; name: string; emoji: string; boost_pct: number; nights: number; cost: number }
export interface NightRow { night: string; customers: number; sales: number; cogs: number; before_bills: number; bills: number; net: number; stars: number; events: string[]; boosted: boolean; capped: boolean }
export interface CompanyCard {
  id: number; name: string; logo: string; color: string; industry: string; industry_name: string; icon: string; hq_area: string; branches: CompanyBranch[];
  stars: number; rating: number; pricing: 'cheap' | 'fair' | 'premium';
  staff: number; staff_slots: number; wage: number; hire_fee: number; manager: boolean; manager_wage: number; manager_fee: number; manager_bonus_pct: number; manager_extra_nights: number;
  generator: boolean; generator_cost: number; generator_cut_pct: number;
  boost_pct: number; boost_nights: number; marketing: MarketingOption[];
  till: number; till_nights: number; cap_nights: number; full: boolean; next_settle_at: string; night: string; due: boolean;
  last: NightRow | null; nights: { night: string; sales: number; net: number; customers: number }[];
  tonight: { customers: number; sales: number; before_bills: number; after_bills: number; bills: number };
  week_bills: number; value: number; sell_value: number; invested: number; lifetime_sales: number; lifetime_net: number; lifetime_cashed: number;
  listed: boolean; created_at: string; share: string; max_branches: number; branch_cost: number; log: CompanyLogRow[] | null;
}
export interface IndustryInfo {
  id: string; name: string; icon: string; blurb: string; price: number; base_revenue: number; ticket: number; cogs_pct: number; upkeep_week: number; wage_week: number;
  req_skill_level: number; req_cert: string | null; req_cert_text: string | null; gate: string | null; met: boolean;
}
export interface AreaInfo { id: string; name: string; tier: number; setup_mult: number; rev_mult: number; district: string }
export interface FormatInfo { id: string; name: string; emoji: string; demand_mult: number; staff_slots: number; upgrade_pct: number; upkeep_mult: number }
export interface CompanyStatus {
  enabled: boolean; companies: CompanyCard[]; industries: IndustryInfo[]; areas: AreaInfo[]; formats: FormatInfo[]; reg_fee: number; max_owned: number; owned: number;
  skill_level: number; night: string; next_settle_at: string; settle_hour: number; max_nights: number; player_night_cap: number; sell_pct: number; shop_enabled: boolean;
  pricing: Record<'cheap' | 'fair' | 'premium', [number, number]>;
}
export interface DiscoverRow {
  kind: 'company' | 'real'; id: string; name: string; logo: string; color: string; industry: string; industry_name: string; icon: string; area: string; area_name: string;
  stars: number | null; locations: number; owner: string | null; sales_7d: number; verified: boolean;
}
export interface RankRow { rank: number; id: number; name: string; logo: string; color: string; industry: string; icon: string; stars: number; sales_7d: number; owner: string; mine: boolean }
export interface PublicCompany {
  id: number; name: string; logo: string; color: string; industry: string; industry_name: string; icon: string; blurb: string; hq_area: string; locations: number;
  stars: number; owner: string; sales_7d: number; rank: number | null; founded: string; share: string; areas: string[];
}

type Msg = { message: string };
type WithCompany = Msg & { company: CompanyCard };
export const companyStatus = () => rpc<CompanyStatus>('company_status');
export const companyRegister = (name: string, industry: string, logo: string, color: string, area: string) =>
  rpc<WithCompany & { id: number }>('company_register', { p_name: name, p_industry: industry, p_logo: logo, p_color: color, p_area: area });
export const companyBranchAdd = (id: number, area: string) => rpc<WithCompany>('company_branch_add', { p_id: id, p_area: area });
export const companyBranchUpgrade = (id: number, branch: number) => rpc<WithCompany>('company_branch_upgrade', { p_id: id, p_branch: branch });
export const companyHire = (id: number) => rpc<WithCompany>('company_hire', { p_id: id });
export const companyFire = (id: number) => rpc<WithCompany>('company_fire', { p_id: id });
export const companyManager = (id: number, on: boolean) => rpc<WithCompany>('company_manager', { p_id: id, p_on: on });
export const companyGenerator = (id: number) => rpc<WithCompany>('company_generator', { p_id: id });
export const companySetPricing = (id: number, pricing: string) => rpc<WithCompany>('company_set_pricing', { p_id: id, p_pricing: pricing });
export const companyMarketingBuy = (id: number, kind: string) => rpc<WithCompany>('company_marketing_buy', { p_id: id, p_kind: kind });
export const companyCashout = (id?: number | null) => rpc<Msg & { amount: number; count: number }>('company_cashout', { p_id: id ?? null });
export const companySell = (id: number) => rpc<Msg & { amount: number }>('company_sell', { p_id: id });
export const companyRankings = () => rpc<{ night: string; rows: RankRow[] }>('company_rankings', { p_limit: null });
export const companyDiscover = (q: string, industry: string, area: string, kind: string, offset = 0) =>
  rpc<{ rows: DiscoverRow[]; total: number }>('company_discover', { p_q: q || null, p_industry: industry || null, p_area: area || null, p_kind: kind || 'all', p_limit: 30, p_offset: offset });
export const companyPublic = (id: number) => rpc<PublicCompany | null>('company_public', { p_id: id });

// ---- real businesses ----
export interface RealForm {
  enabled: boolean; buy_enabled: boolean; price_kobo: number; days: number; max_images: number; max_per_player: number; terms: string; contact_email: string;
  categories: { id: string; name: string; icon: string }[];
  areas: { id: string; name: string; tier: number; cap: number; used: number; slots: { id: string; x: number; y: number }[] }[];
  companies: { id: number; name: string; logo: string }[];
}
export interface RealMine {
  id: string; name: string; logo: string; category: string; area: string; area_id: string;
  status: 'awaiting_payment' | 'pending_review' | 'live' | 'rejected' | 'suspended' | 'expired' | 'removed' | 'cancelled';
  images: string[]; days: number; price_kobo: number; starts_at: string | null; ends_at: string | null; created_at: string; reject_reason: string | null;
  refund_status: 'none' | 'pending' | 'processing' | 'refunded' | 'refund_failed'; views: number; taps: number; renewals: number; reports: number; can_renew: boolean; renew_price_kobo: number;
}
export interface RealPin { id: string; name: string; logo: string; x: number; y: number; area: string; category: string }
export interface RealShowcase {
  id: string; name: string; logo: string; category: string; category_name: string; descr: string; phone: string | null; whatsapp: string | null; instagram: string | null;
  website: string | null; address: string; area: string; images: string[]; company: { id: number; name: string; logo: string } | null; verified: boolean; mine: boolean;
  status: string; ends_at: string | null; terms: string; contact_email: string;
}
export interface RealInit { biz_id: string; reference: string; amount_kobo: number; email: string; currency: string; days: number }
export const realBizForm = () => rpc<RealForm>('real_biz_form');
export const realBizMine = () => rpc<RealMine[]>('real_biz_mine');
export const realBizMap = () => rpc<{ pins: RealPin[] }>('real_biz_map');
export const realBizGet = (id: string) => rpc<RealShowcase | null>('real_biz_get', { p_id: id });
export const realBizTrack = (id: string, kind: 'view' | 'tap') => { void rpc('real_biz_track', { p_id: id, p_kind: kind }).catch(() => {}); };
export const realBizReport = (id: string, reason: string) => rpc<{ reported: boolean; message: string }>('real_biz_report', { p_id: id, p_reason: reason });
export const realBizCancel = (id: string) => rpc('real_biz_cancel', { p_id: id });
export const realBizRenewStart = (id: string) => rpc<RealInit>('real_biz_renew_start', { p_id: id });
export interface RealDraft {
  name: string; category: string; desc: string; phone: string; whatsapp: string; instagram: string; website: string; address: string; area: string; slot: string;
  images: string[]; logo: string; company: number | null; terms: boolean;
}
export const realBizCreate = (d: RealDraft) => rpc<RealInit>('real_biz_create', {
  p_name: d.name, p_category: d.category, p_desc: d.desc, p_phone: d.phone, p_whatsapp: d.whatsapp, p_instagram: d.instagram, p_website: d.website,
  p_address: d.address, p_area: d.area, p_slot: d.slot, p_images: d.images, p_logo: d.logo, p_company: d.company, p_terms: d.terms,
});

/** Public URL of an uploaded photo (bucket real-biz). */
export function realImageUrl(path: string): string {
  if (/^(https?:)?\/\//.test(path) || path.startsWith('data:')) return path;
  const base = String(import.meta.env.VITE_SUPABASE_URL ?? '').replace(/\/$/, '');
  return `${base}/storage/v1/object/public/real-biz/${path.split('/').map(encodeURIComponent).join('/')}`;
}

export const EVENT_TEXT: Record<string, string> = {
  good_review: 'Good review', bad_review: 'Bad review', outage: 'NEPA outage', supplier: 'Supplier problem',
};
export const LOGOS = ['🍲', '✂️', '🛒', '👗', '🎪', '💊', '🛵', '💻', '🏢', '🥖', '🍗', '📱', '🚗', '📚', '💈', '🎧', '🏠', '🌽', '🐟', '💎'];
export const COLORS = ['#1f7a3f', '#c0392b', '#2980b9', '#8e44ad', '#d68910', '#16a085', '#2c3e50', '#e84393', '#b8860b', '#6c5ce7'];
