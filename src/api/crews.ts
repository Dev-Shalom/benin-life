// R11 crews RPCs (server: 20261018001000_crews.sql, docs/CREWS.md). A game mechanic: abstract jobs, fictional crews.
import { rpc } from '../lib/api';

export type CrewRank = 'boss' | 'lieutenant' | 'member' | 'prospect';
export const RANK_LABEL: Record<CrewRank, string> = { boss: 'Boss', lieutenant: 'Lieutenant', member: 'Member', prospect: 'Prospect' };

export interface CrewBadge { tag: string; color: string; emblem: string; name?: string }

export interface CrewMember {
  id: string; username: string; avatar: unknown; rank: CrewRank; joined_at: string; deposited: number; jobs: number; earned: number;
  last_seen: string | null; online: boolean; at_spot: boolean; me: boolean;
}
export interface CrewJob {
  id: string; name: string; icon: string; blurb: string; min_members: number; max_members: number; min_crew_level: number; duration_seconds: number;
  reward_min: number; reward_max: number; bonus_pct: number; caught_pct: number; est_pct: number; skill_cut_pct: number; cooldown_seconds: number;
  cooldown_left: number; buy_in: number; xp: number; skills: { id: string; name: string; icon: string }[]; locked: boolean; locked_reason: string | null;
}
export interface CrewRunMember { id: string; username: string; rank: CrewRank; payout: number; buy_in: number; online: boolean; jailed: boolean }
export interface CrewRun {
  id: number; status: 'lobby' | 'running' | 'paid' | 'caught' | 'cancelled'; job_id: string; name: string; icon: string; blurb: string;
  min_members: number; max_members: number; duration_seconds: number; buy_in: number; reward_min: number; reward_max: number;
  created_at: string; lobby_until: string; started_at: string | null; resolve_at: string | null; resolved_at: string | null;
  started_by: string | null; started_by_id: string | null; members: CrewRunMember[]; member_count: number;
  base_pct: number; caught_pct: number; skill_cut_pct: number; split_bank_pct: number | null; pot: number; bank_share: number; fine: number; note: string | null; joined: boolean;
}
export interface NextLevel { level: number; name: string; xp_needed: number; cost: number; max_members: number; bonus_pct: number; perks: string; xp_ok: boolean; bank_ok: boolean }
export interface Crew {
  id: number; name: string; tag: string; color: string; emblem: string; level: number; level_name: string; perks: string; bonus_pct: number;
  xp: number; xp_from: number; xp_to: number | null; bank: number; split_bank_pct: number; recruiting: boolean; jobs_done: number; jobs_caught: number;
  loot_total: number; created_at: string; members_count: number; max_members: number; next_level: NextLevel | null;
  members: CrewMember[]; pending_invites: { id: number; username: string; created_at: string; expires_at: string }[]; jobs: CrewJob[];
  run: CrewRun | null; last_run: CrewRun | null; week: { rank: number | null; jobs: number; loot: number };
  meeting_places: { id: string; name: string }[];
  me: { rank: CrewRank; is_boss: boolean; can_manage: boolean; deposited: number; jobs: number; earned: number } | null;
}
export interface CrewInvite {
  id: number; created_at: string; expires_at: string; from: string | null;
  crew: { id: number; name: string; tag: string; color: string; emblem: string; level: number; members: number; max_members: number };
}
export interface CrewSettings {
  found_fee: number; found_min_charisma: number; found_min_account_hours: number; rejoin_cooldown_hours: number; emblems: string[]; default_bank_pct: number;
  bank_pct_min: number; bank_pct_max: number; chat_max_len: number; min_deposit: number; rename_fee: number; prospect_share_pct: number; lobby_seconds: number; weekly_enabled: boolean;
}
export interface CrewStatus {
  enabled: boolean; now: string; settings: CrewSettings; can_found: { ok: boolean; hint: string | null; message: string | null };
  cooldown_until: string | null; invites: CrewInvite[]; crew: Crew | null;
}
export interface CrewListed { id: number; name: string; tag: string; color: string; emblem: string; level: number; members: number; max_members: number; recruiting: boolean; jobs_done: number; boss: string | null }
export interface Candidate { id: string; username: string; avatar: unknown; online: boolean; friend: boolean; invited: boolean; eligible: boolean; why: string | null }
export interface BankRow { id: number; kind: string; amount: number; balance_after: number; note: string; username: string | null; created_at: string }
export interface ChatRow { id: number; user_id: string; username: string; body: string; created_at: string; mine: boolean; rank: CrewRank | null }
export interface TopRow { rank: number; crew_id: number; name: string; tag: string; emblem: string; color: string; level: number; jobs: number; loot: number; mine: boolean }
export interface CrewTop {
  enabled: boolean; week_start: string; ends_at: string; rows: TopRow[]; prizes: { rank: number; amount: number }[]; min_jobs: number;
  mine: { rank: number; jobs: number; loot: number } | null;
  last_week: { week_start: string; winners: { rank: number; name: string; tag: string; jobs: number; loot: number; prize: number }[] } | null;
}
type Msg = { message: string };
type WithCrew = Msg & { crew?: Crew };
type WithRun = Msg & { run?: CrewRun };

export const crewStatus = () => rpc<CrewStatus>('crew_status');
export const crewBrowse = (q = '') => rpc<{ crews: CrewListed[] }>('crew_browse', { p_q: q });
export const crewCreate = (name: string, tag: string, color: string, emblem: string) => rpc<WithCrew>('crew_create', { p_name: name, p_tag: tag, p_color: color, p_emblem: emblem });
export const crewCandidates = (q = '') => rpc<{ players: Candidate[] }>('crew_invite_candidates', { p_q: q });
export const crewInvite = (username: string) => rpc<Msg>('crew_invite', { p_username: username });
export const crewInviteCancel = (id: number) => rpc<Msg>('crew_invite_cancel', { p_invite: id });
export const crewInviteRespond = (id: number, accept: boolean) => rpc<WithCrew>('crew_invite_respond', { p_invite: id, p_accept: accept });
export const crewJoinOpen = (id: number) => rpc<WithCrew>('crew_join_open', { p_crew: id });
export const crewLeave = () => rpc<Msg>('crew_leave');
export const crewKick = (id: string) => rpc<Msg>('crew_kick', { p_user: id });
export const crewSetRank = (id: string, rank: string) => rpc<Msg>('crew_set_rank', { p_user: id, p_rank: rank });
export const crewTransfer = (id: string) => rpc<Msg>('crew_transfer', { p_user: id });
export const crewDisband = () => rpc<Msg>('crew_disband');
export const crewOptions = (split: number | null, recruiting: boolean | null) => rpc<WithCrew>('crew_options', { p_split: split, p_recruiting: recruiting });
export const crewRename = (name: string) => rpc<WithCrew>('crew_rename', { p_name: name });
export const crewDeposit = (amount: number) => rpc<Msg & { bank: number }>('crew_deposit', { p_amount: amount });
export const crewUpgrade = () => rpc<WithCrew>('crew_upgrade');
export const crewBankLog = () => rpc<{ rows: BankRow[] }>('crew_bank_log_list', { p_limit: 60 });
export const crewChatSend = (body: string) => rpc<ChatRow>('crew_chat_send', { p_body: body });
export const crewChatRecent = (after = 0) => rpc<{ rows: ChatRow[] }>('crew_chat_recent', { p_after: after, p_limit: 60 });
export const crewReport = (id: number, reason: string) => rpc<Msg>('crew_report', { p_crew: id, p_reason: reason });
export const crewTop = () => rpc<CrewTop>('crew_top', { p_limit: 20 });
export const crewJobOpen = (job: string) => rpc<WithRun>('crew_job_open', { p_job: job });
export const crewJobJoin = (run: number) => rpc<WithRun>('crew_job_join', { p_run: run });
export const crewJobLeave = (run: number) => rpc<Msg>('crew_job_leave', { p_run: run });
export const crewJobCancel = (run: number) => rpc<Msg>('crew_job_cancel', { p_run: run });
export const crewJobStart = (run: number) => rpc<WithRun>('crew_job_start', { p_run: run });

// admin
export interface AdminCrewRow {
  id: number; name: string; tag: string; emblem: string; color: string; level: number; members: number; bank: number; boss: string | null;
  jobs_done: number; jobs_caught: number; loot_total: number; reports: number; flagged: boolean; recruiting: boolean; created_at: string;
}
export interface AdminCrewList { stats: { crews: number; members: number; bank: number; open_reports: number; jobs_7d: number }; rows: AdminCrewRow[] }
export interface AdminCrewDetail {
  crew: Record<string, unknown> & { id: number; name: string; tag: string; level: number; bank: number };
  members: { id: string; username: string; rank: CrewRank; joined_at: string; deposited: number; jobs: number; earned: number; last_seen: string | null }[];
  reports: { id: number; reason: string; status: string; by: string | null; created_at: string }[];
  bank_log: { kind: string; amount: number; balance_after: number; note: string; created_at: string }[];
  runs: { id: number; job: string | null; status: string; pot: number; members: number; created_at: string }[];
}
export const adminCrewsList = (q = '', limit = 200) => rpc<AdminCrewList>('admin_crews_list', { p_q: q, p_limit: limit });
export const adminCrewGet = (id: number) => rpc<AdminCrewDetail>('admin_crew_get', { p_crew: id });
export const adminCrewDisband = (id: number, reason: string) => rpc<Msg>('admin_crew_disband', { p_crew: id, p_reason: reason });
export const adminCrewRename = (id: number, name: string, tag: string | null, reason: string) => rpc<Msg>('admin_crew_rename', { p_crew: id, p_name: name, p_tag: tag, p_reason: reason });
export const adminCrewDismissReports = (id: number) => rpc<Msg>('admin_crew_dismiss_reports', { p_crew: id });
