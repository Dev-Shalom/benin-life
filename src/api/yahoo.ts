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

export interface YahooRun {
  id: number; job_id: string; name: string; icon: string; started_at: string; resolve_at: string; status: string; caught_pct: number; amount: number;
  /** R6: a cash-out run remembers its option and the launder fee. */
  mode?: CashMode | null;
  fee?: number;
}

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
  /** R6: the launder fee kept by the contact (cash-outs) and the option used. */
  fee?: number;
  mode?: CashMode | null;
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

// ---- R6 Yahoo strategy: cash-out options and group missions (docs/YAHOO.md "R6") ----
export type CashMode = 'full' | 'half' | 'launder';

export interface CashOption {
  mode: CashMode;
  label: string;
  /** Moves out of the yahoo balance. */
  amount: number;
  /** Kept by the contact (launder only). */
  fee: number;
  /** What lands in cash. */
  net: number;
  /** The EFCC chance after my Yahoo level. */
  caught_pct: number;
  /** Before the level cut. */
  base_caught_pct: number;
  seconds: number;
  ok: boolean;
  why: string | null;
}

export interface CashQuote {
  enabled: boolean;
  dirty: number;
  job_id: string | null;
  min: number;
  contact: string;
  fee_pct: number;
  /** Why I can't start one right now (no laptop, wrong place, cooldown…), else null. */
  blocked: string | null;
  cooldown_until: string | null;
  options: CashOption[];
}

export interface GroupMission {
  id: string;
  name: string;
  icon: string;
  blurb: string;
  min_members: number;
  max_members: number;
  duration_seconds: number;
  reward_min: number;
  reward_max: number;
  caught_pct: number;
  min_yahoo_level: number;
  invite_seconds: number;
  cooldown_seconds: number;
  level_ok: boolean;
  cooldown_until: string | null;
}

export type GroupStatusName = 'inviting' | 'running' | 'paid' | 'caught' | 'cancelled';

export interface GroupMember {
  id: string;
  username: string;
  status: 'invited' | 'accepted' | 'declined' | 'dropped' | 'expired';
  host: boolean;
  me: boolean;
  level: number | null;
  payout: number;
  seized: number;
  laptop_seized: string | null;
}

export interface YahooGroup {
  id: number;
  mission_id: string;
  name: string;
  icon: string;
  blurb: string;
  status: GroupStatusName;
  host_id: string;
  host: string;
  i_am_host: boolean;
  my_status: GroupMember['status'] | null;
  min_members: number;
  max_members: number;
  duration_seconds: number;
  created_at: string;
  /** The start timer (invite window). */
  start_at: string;
  started_at: string | null;
  resolve_at: string | null;
  resolved_at: string | null;
  base_caught_pct: number;
  /** With the crew's average Yahoo level. */
  caught_pct: number;
  ready: number;
  per_min: number;
  per_max: number;
  pot: number;
  per_member: number;
  members: GroupMember[];
}

export interface GroupFriend { id: string; username: string; avatar?: unknown; online: boolean; ready: boolean }

export interface GroupStatus {
  enabled: boolean;
  spot: { ok: boolean; place: 'hk' | 'home' | null; hint?: string; message: string };
  has_laptop: boolean;
  level: number;
  bonus_pct: number;
  places: { id: string; name: string }[];
  missions: GroupMission[];
  friends: GroupFriend[];
  group: YahooGroup | null;
  invites: YahooGroup[];
  last: YahooGroup | null;
}

export interface GroupResult {
  status: 'paid' | 'caught' | string;
  group: YahooGroup;
  amount: number;
  seized: number;
  laptop_seized: string | null;
  case?: JailCase | null;
}

export const yahooCashoutQuote = () => rpc<CashQuote>('yahoo_cashout_quote');
export const yahooCashoutStart = (mode: CashMode) =>
  rpc<{ run_id: number; busy_until: string; resolve_at: string; seconds: number; job_id: string; name: string; caught_pct: number; skill_caught_pct: number;
        amount: number; fee: number; net: number; mode: CashMode; message: string }>('yahoo_cashout_start', { p_mode: mode });
export const yahooGroupStatus = () => rpc<GroupStatus>('yahoo_group_status');
export const yahooGroupCreate = (mission: string, friends: string[]) =>
  rpc<{ group: YahooGroup; message: string }>('yahoo_group_create', { p_mission: mission, p_friends: friends });
export const yahooGroupRespond = (group: number, accept: boolean) =>
  rpc<{ group: YahooGroup; message: string }>('yahoo_group_respond', { p_group: group, p_accept: accept });
export const yahooGroupStart = (group: number) => rpc<{ group: YahooGroup; message: string }>('yahoo_group_start', { p_group: group });
export const yahooGroupCancel = (group: number) => rpc<{ group: YahooGroup; message: string }>('yahoo_group_cancel', { p_group: group });
export const yahooGroupFinish = () => rpc<GroupResult>('yahoo_group_finish');
