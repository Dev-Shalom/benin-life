// Family & Love, stage 1 (docs/LOVE.md). ONE read, love_overview(), feeds the Us and Family tabs and the ask inbox; the Link-ups list is
// love_candidates() (paged). Every number and rule lives on the server (Settings -> Love); this file only types the answers.
import { rpc } from '../lib/api';
import type { AvatarConfig } from '../lib/types';

export interface LovePerson {
  id: string;
  username: string;
  avatar: AvatarConfig | null;
  street_cred?: number;
  title?: string | null;
}

export interface LoveIncoming { id: number; created_at: string; expires_at: string; from: LovePerson }
export interface LoveOutgoing { id: number; created_at: string; expires_at: string; state: 'pending' | 'noreply'; to: LovePerson }

export interface LoveFlirt { id: string; text: string; icon: string; points: number; cost: number; min_level: number }

export interface LoveDate {
  id: string;
  name: string;
  icon: string;
  place_id: string | null;
  place_name: string | null;
  cost_each: number;
  fun_gain: number;
  social_gain: number;
  bond_points: number;
  cooldown_hours: number;
  min_status: 'talking' | 'couple';
  /** I am standing at the date's place (or it has none). */
  me_here: boolean;
}

export interface LoveLogRow { id: number; kind: 'started' | 'flirt' | 'date' | 'couple' | 'ended'; mine: boolean; text: string; icon: string | null; points: number; created_at: string }

export interface LoveRelationship {
  id: number;
  status: 'talking' | 'couple';
  level: number;
  started_at: string;
  couple_at: string | null;
  days_together: number;
  partner: { id: string; username: string; avatar: AvatarConfig | null };
  /** Seconds until I can flirt again (0 = now). */
  flirt_cooldown_seconds: number;
  /** Level points the pair can still earn today. */
  daily_room: number;
  /** date id -> seconds left on its cooldown. */
  date_cooldowns: Record<string, number>;
  log: LoveLogRow[];
  recent_dates: { id: number; text: string; icon: string | null; points: number; created_at: string }[];
  invite: { id: number; date_id: string; mine: boolean; expires_at: string } | null;
}

export interface LoveOverview {
  enabled: boolean;
  poll_seconds: number;
  couple_level: number;
  max_partners: number;
  me: {
    open: boolean;
    show_relationship: boolean;
    asks_left: number;
    asks_cap: number;
    ask_block: { code: string; msg: string } | null;
    min_account_days: number;
  };
  rules: {
    breakup_days: number; breakup_hours: number; ask_expire_hours: number; decay_after_days: number; decay_per_day: number;
    date_expire_minutes: number; flirt_cooldown_minutes: number; daily_cap: number;
  };
  incoming: LoveIncoming[];
  outgoing: LoveOutgoing[];
  relationships: LoveRelationship[];
  flirts: LoveFlirt[];
  dates: LoveDate[];
}

export type CandidateState = 'ask' | 'pending' | 'incoming' | 'later';
export interface LoveCandidate extends LovePerson {
  crew?: { tag: string; color: string; emblem: string } | null;
  online: boolean;
  here: boolean;
  state: CandidateState;
}
export interface LoveCandidates { enabled: boolean; closed?: boolean; rows: LoveCandidate[]; has_more: boolean; filter: string; offset?: number; page?: number }

export type LoveFilter = 'all' | 'here' | 'online';

interface Msg { message: string }
export interface FlirtResult extends Msg { gained: number; level: number; capped: boolean; couple_now: boolean; spent: number }
export interface DateResult extends Msg { accepted: boolean; expired?: boolean; gained?: number; level?: number; couple_now?: boolean }

export const loveOverview = () => rpc<LoveOverview>('love_overview');
export const loveCandidates = (filter: LoveFilter = 'all', offset = 0) => rpc<LoveCandidates>('love_candidates', { p_filter: filter, p_offset: offset });
export const loveSetOpen = (open: boolean) => rpc<Msg & { open: boolean }>('love_set_open', { p_open: open });
export const loveSetShowRelationship = (show: boolean) => rpc<Msg & { show: boolean }>('love_set_show_relationship', { p_show: show });
export const loveAsk = (target: string) => rpc<Msg & { ask_id: number; asks_left: number }>('love_ask', { p_target: target });
export const loveRespond = (ask: number, accept: boolean) => rpc<Msg & { accepted: boolean; expired?: boolean }>('love_respond', { p_ask: ask, p_accept: accept });
export const loveWithdraw = (ask: number) => rpc<Msg>('love_withdraw', { p_ask: ask });
export const loveFlirt = (rel: number, flirt: string) => rpc<FlirtResult>('love_flirt', { p_rel: rel, p_flirt: flirt });
export const loveDateInvite = (date: string, rel: number | null = null) => rpc<Msg & { invite_id: number }>('love_date_invite', { p_date: date, p_rel: rel });
export const loveDateRespond = (invite: number, accept: boolean) => rpc<DateResult>('love_date_respond', { p_invite: invite, p_accept: accept });
export const loveBreakup = (rel: number | null = null) => rpc<Msg>('love_breakup', { p_rel: rel });
export const loveReport = (target: string, reason: string) => rpc<Msg>('love_report', { p_target: target, p_reason: reason });

/** Public bits of a player's profile that the Ask button needs (get_public_profile). */
export interface PublicLove {
  love_open?: boolean;
  proud_parent?: number;
  proud_tier?: 'gold' | 'silver' | 'bronze' | null;
  relationship?: { status: 'talking' | 'couple'; partner: { id: string; username: string } } | null;
}
export const lovePublic = (id: string) => rpc<PublicLove>('get_public_profile', { p_id: id });

// admin
export interface LoveReportRow {
  id: number; status: 'open' | 'reviewed' | 'dismissed'; reason: string; created_at: string;
  reporter: { id: string; username: string }; reported: { id: string; username: string }; rel_id: number | null; rel_status: string | null;
}
export interface AdminLoveOverview {
  enabled: boolean; open_players: number; talking: number; couples: number; ended_7d: number; pending_asks: number; open_reports: number; reports: LoveReportRow[];
}
export const adminLoveOverview = () => rpc<AdminLoveOverview>('admin_love_overview');
export const adminLoveReportSet = (id: number, status: 'reviewed' | 'dismissed') => rpc<Msg>('admin_love_report_set', { p_id: id, p_status: status });
export const adminLoveEnd = (rel: number, reason = '') => rpc<Msg>('admin_love_end', { p_rel: rel, p_reason: reason });
