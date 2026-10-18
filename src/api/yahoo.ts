// Y1 Yahoo lifestyle (docs/YAHOO.md). In-game satire: the server rolls every outcome and keeps every naira of the
// dirty "yahoo balance"; the client only shows it.
import { rpc } from '../lib/api';
import type { JailCase } from './crime';
import type { SkillCard } from './skills';

export interface YahooLaptop {
  item_id: string;
  name: string;
  icon: string | null;
  label: string;
  tier: number;
  pay_bonus_pct: number;
  efcc_minus_pts: number;
  speed_pct: number;
  price?: number;
  owned?: boolean;
  sold_at?: string[];
}

export interface YahooJob {
  id: string;
  name: string;
  icon: string;
  blurb: string;
  kind: 'job' | 'cashout';
  /** With my laptop's speed. */
  seconds: number;
  base_seconds: number;
  pay_min: number;
  pay_max: number;
  /** EFCC caught chance with my laptop + charms. */
  caught_pct: number;
  base_caught_pct: number;
  min_tier: number;
  min_laptop: string | null;
  locked: 'no_laptop' | 'laptop_too_weak' | 'skill_level' | 'cert' | null;
  /** R3: EFCC chance after my Yahoo level (the base and laptop numbers stay in caught_pct). */
  skill_caught_pct?: number;
  min_skill_level?: number;
  /** R4: certificate gate: the short lock text ("Needs ICT certificate"). */
  req_cert?: string | null;
  cert_short?: string | null;
  skill?: SkillCard | null;
  cooldown_until: string | null;
}

export interface YahooRank { id: string; name: string; icon: string; min_earned: number; hype_pct?: number; perks?: string | null }

export interface YahooRun { id: number; job_id: string; name: string; icon: string; started_at: string; resolve_at: string; status: string; caught_pct: number; amount: number }

export interface YahooResult {
  status: 'paid' | 'cashed' | 'caught' | 'none' | string;
  job_id?: string;
  name?: string;
  icon?: string;
  amount: number;
  seized?: number;
  laptop_seized?: string | null;
  message?: string;
  rank_up?: YahooRank | null;
  case?: JailCase | null;
  already?: boolean;
}

export interface YahooLedgerRow { id: number; delta: number; balance_after: number; reason: string; label: string; created_at: string }

export interface YahooStatus {
  enabled: boolean;
  dirty: number;
  total_earned: number;
  jobs_done: number;
  cashed_out: number;
  busts: number;
  cash: number;
  bank: number;
  mifi_until: string | null;
  desk_until: string | null;
  prices: { mifi: number; mifi_days: number; desk: number; desk_hours: number; cashout_min: number; bail: number; escape_caught_pct: number };
  cafes: { id: string; name: string }[];
  where: { ok: boolean; place: 'home' | 'cafe' | null; hint?: string; message: string };
  laptop: YahooLaptop | null;
  laptops: YahooLaptop[];
  iphone: boolean;
  charms: { blindfold: number | null; bad_luck: number | null };
  rank: YahooRank;
  next_rank: YahooRank | null;
  ranks: YahooRank[];
  jobs: YahooJob[];
  run: YahooRun | null;
  resolved: YahooResult | null;
  ledger: YahooLedgerRow[];
}

export const YAHOO_LABEL_PREFIX = 'Yahoo: ';

export const yahooStatus = () => rpc<YahooStatus>('yahoo_status');
export const yahooBuyPass = (kind: 'mifi' | 'desk') =>
  rpc<{ pass: string; until: string; paid: number; message: string }>('yahoo_buy_pass', { p_kind: kind });
export const yahooJobStart = (job: string, amount?: number | null) =>
  rpc<{ run_id: number; busy_until: string; resolve_at: string; seconds: number; job_id: string; name: string; caught_pct: number; amount: number; message: string }>(
    'yahoo_job_start', { p_job: job, p_amount: amount ?? null });
export const yahooFinish = () => rpc<YahooResult>('yahoo_finish');
