// E2 More ways to earn (docs/HUSTLES.md): typed wrappers for the hustle, referral, weekly leaderboard and tip RPCs.
// The server rolls every outcome and holds every naira; the client only shows it.
import { rpc } from '../lib/api';

export type HustleKind = 'bolt' | 'pos' | 'vending' | 'dj' | 'mc' | 'tutor' | 'fishing' | 'mechanic' | 'job' | 'pass' | 'service';

export interface HustleWhy { hint: string; message: string; short: string }

export interface Hustle {
  id: string;
  name: string;
  icon: string;
  blurb: string;
  kind: HustleKind;
  where_text: string;
  req_text: string;
  anywhere: boolean;
  seconds: number;
  cooldown_seconds: number;
  daily_cap: number;
  runs_today: number;
  cap_left: number | null;
  cooldown_until: string | null;
  cost: number;
  pay_min: number;
  pay_max: number;
  pay_mult_now: number;
  hours: string | null;
  hour_mult: Record<string, number>;
  risk: { pct: number; text: string; pay_mult: number } | null;
  loss: { pct: number; min: number; max: number; text: string } | null;
  bonus: { pct: number; min: number; max: number; text: string } | null;
  item: { id: string; name: string; icon: string | null; price: number; owned: boolean; optional: boolean; no_item_pay_mult: number | null;
          sold_at: { id: string; name: string }[] } | null;
  needs_car: boolean;
  pass: { id: string; until: string | null } | null;
  pass_hours: number | null;
  places: { id: string; name: string; open: boolean }[];
  /** True when the place I am at works for this hustle right now. */
  here: boolean;
  here_why: HustleWhy | null;
  /** Requirement problems that are not about the place (null = I could start it at the right place). */
  locked: HustleWhy | null;
}

export interface HustleRun { id: number; hustle_id: string; name: string; icon: string; started_at: string; resolve_at: string; status: string; cost: number; amount: number; outcome: string | null }

export interface HustleResult {
  status: 'done' | 'none' | string;
  hustle_id?: string;
  name?: string;
  icon?: string;
  kind?: HustleKind;
  outcome?: 'ok' | 'bonus' | 'risk' | 'loss' | string;
  amount: number;
  cost?: number;
  net?: number;
  loss?: number;
  bonus?: number;
  fish?: { item: string; name: string; icon: string | null; value: number } | null;
  message?: string;
  already?: boolean;
}

export interface HustleStatus {
  enabled: boolean;
  cash: number;
  bank: number;
  total_earned: number;
  runs_done: number;
  car: { item_id: string; name: string; icon: string | null; price: number; class_id: string; class_name: string; class_icon: string; pay_mult: number; fuel_mult: number; wear_mult: number; wear: number } | null;
  classes: { id: string; name: string; icon: string; min_price: number; pay_mult: number }[];
  location: string;
  hustles: Hustle[];
  run: HustleRun | null;
  resolved: HustleResult | null;
  history: HustleRun[];
}

export interface ReferralRow { username: string; status: 'pending' | 'rewarded' | 'rejected'; created_at: string; rewarded_at: string | null; progress: ReferralProgress }
export interface ReferralProgress { shifts: number; need_shifts: number; hustles: number; need_hustles: number; play_minutes: number; need_minutes: number; met: boolean; pct: number }
export interface ReferralStatus {
  enabled: boolean;
  code: string;
  link: string;
  bonus_referrer: number;
  bonus_referred: number;
  daily_cap: number;
  today: number;
  milestone: { shifts: number; hustles: number; minutes: number };
  invited: number;
  rewarded: number;
  earned: number;
  rows: ReferralRow[];
  referred_by: { username: string; status: 'pending' | 'rewarded' | 'rejected'; bonus: number; progress: ReferralProgress } | null;
}

export interface WeeklyRow { rank: number | null; id: string; username: string; avatar: unknown; origin: string; total: number; me?: boolean }
export interface WeeklyBoard {
  enabled: boolean;
  week_start: string;
  ends_at: string;
  players: number;
  rows: WeeklyRow[];
  me: WeeklyRow | null;
  prizes: { rank: number; amount: number }[];
  min_earned: number;
  reasons: string[];
  last_week: { week_start: string; winners: { rank: number; username: string; total: number; prize: number }[] } | null;
}

export const HUSTLE_LABEL_PREFIX = 'Hustle: ';

export const hustleStatus = () => rpc<HustleStatus>('hustle_status');
export const hustleStart = (id: string) =>
  rpc<{ run_id: number; busy_until: string; resolve_at: string; seconds: number; hustle_id: string; name: string; icon: string; cost: number; started_at: string; message: string }>(
    'hustle_start', { p_id: id });
export const hustleFinish = () => rpc<HustleResult>('hustle_finish');
export const hustleBuy = (id: string) => rpc<{ kind: 'pass' | 'service'; paid: number; until?: string; message: string }>('hustle_buy', { p_id: id });
export const referralStatus = () => rpc<ReferralStatus>('referral_status');
export const referralClaim = (code: string | null) => rpc<{ ok: boolean; message: string }>('referral_claim', { p_code: code });
export const weeklyLeaderboard = (limit = 50) => rpc<WeeklyBoard>('weekly_leaderboard', { p_limit: limit });
