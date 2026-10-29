// Industry offices RPCs (server: 20261106000100_industry_offices.sql, docs/OFFICES.md). The server decides everything; this only shows it.
import { rpc } from '../lib/api';

export type LeverUnit = 'percent' | 'naira' | 'number' | 'seconds' | 'hour' | 'mult';
export interface IndApproval { up: number; down: number; votes: number; pct: number | null; mine: boolean | null }
export interface IndHolder {
  id: number; user_id: string; username: string; source: string; term_start: string; term_end: string; approval: IndApproval;
  statement: { body: string; at: string } | null;
}
export interface IndLever {
  id: string; office_id: string; config_key: string; label: string; blurb: string; unit: LeverUnit; direction: string; effect: string; step: number; cooldown_hours: number;
  frozen: boolean; band_min: number; band_max: number; lo: number; hi: number; current: number; baseline: number; changed: boolean; changed_by: string | null; changed_at: string | null;
  next_at?: string | null; active?: boolean;
}
export interface IndCheck { key: string; label: string; ok: boolean; message?: string }
export interface IndOffice {
  id: string; name: string; industry: string; title: string; icon: string; blurb: string; salary_per_day: number; term_days: number; min_account_days: number; min_level: number;
  frozen: boolean; election_enabled: boolean; seats: number; max_changes_per_day: number; holder: IndHolder | null; applicants: number;
  requirements: { ok: boolean; hint: string | null; message: string | null; checks: IndCheck[] }; levers: IndLever[];
}
export interface IndChangeRow { office?: string; lever: string; unit: LeverUnit; kind: 'change' | 'restore'; old: number | null; new: number | null; at: string; by?: string | null }
export interface IndMe {
  holder: IndHolder; office_id: string; office: string; title: string; icon: string; salary_per_day: number; salary_paid: number; levers: IndLever[]; changes_today: number;
  max_changes: number; drift_used: number; drift_budget: number; frozen: boolean; low_approval: boolean; can_statement: boolean; statement_next_at: string | null; recent: IndChangeRow[];
}
export interface IndStatus {
  enabled: boolean; now: string;
  settings: { inactive_days: number; statement_max_len: number; pitch_max_len: number; low_approval_pct: number; low_approval_min_votes: number; vote_min_account_days: number };
  me: IndMe | null; my_application: { id: number; office_id: string; office: string; pitch: string; at: string } | null; offices: IndOffice[]; recent: IndChangeRow[];
}
export interface OfficeMine {
  holds: boolean; kind?: 'industry' | 'political'; office_id?: string; office_kind?: string; office?: string; title?: string; icon?: string; term_end?: string; days_left?: number; salary_per_day?: number;
}
type Msg = { message: string };

export const officeMine = () => rpc<OfficeMine>('office_mine');
export const indStatus = () => rpc<IndStatus>('ind_status');
export const indApply = (office: string, pitch: string) => rpc<Msg>('ind_apply', { p_office: office, p_pitch: pitch });
export const indWithdraw = () => rpc<Msg>('ind_withdraw');
export const indSetLever = (lever: string, value: number) => rpc<Msg & { value: number; old: number; announced: boolean }>('ind_set_lever', { p_lever: lever, p_value: value });
export const indVote = (holder: number, up: boolean) => rpc<Msg & { approval: IndApproval }>('ind_vote', { p_holder: holder, p_up: up });
export const indStatement = (body: string) => rpc<Msg>('ind_statement', { p_body: body });
export const indResign = () => rpc<Msg>('ind_resign');

// ---- admin
export interface AdminIndOffice {
  id: string; name: string; industry: string; title: string; icon: string; salary_per_day: number; term_days: number; active: boolean; frozen: boolean; max_changes_per_day: number;
  max_total_drift_pct: number; election_enabled: boolean; seats: number;
  holder: { id: number; user_id: string; username: string; term_start: string; term_end: string; source: string; salary_paid: number; last_seen: string | null; approval: IndApproval; low_approval: boolean; changes_today: number } | null;
  levers: IndLever[];
}
export interface AdminIndApplicant { id: number; office_id: string; office: string; user_id: string; username: string; pitch: string; created_at: string; account_days: number; level: number | null; last_seen: string | null; holds_office: boolean }
export interface AdminIndOverview {
  now: string; enabled: boolean; offices: AdminIndOffice[]; applicants: AdminIndApplicant[];
  history: { id: number; office: string; username: string | null; status: string; term_start: string; ended_at: string | null; ended_reason: string | null; salary_paid: number }[];
  audit: { id: number; office: string; lever: string; unit: LeverUnit; kind: 'change' | 'restore'; old: number | null; new: number | null; reason: string; announced: boolean; at: string; by: string | null }[];
}
export const adminIndOverview = () => rpc<AdminIndOverview>('admin_ind_overview');
export const adminIndAppoint = (office: string, username: string, reason = '') => rpc<Msg>('admin_ind_appoint', { p_office: office, p_username: username, p_reason: reason });
export const adminIndApplication = (id: number, action: 'accept' | 'reject' | 'remove', note = '') => rpc<Msg>('admin_ind_application', { p_application: id, p_action: action, p_note: note });
export const adminIndRemoveHolder = (holder: number, reason: string) => rpc<Msg>('admin_ind_remove_holder', { p_holder: holder, p_reason: reason });
export const adminIndFreeze = (office: string, lever: string | null, frozen: boolean) => rpc<Msg>('admin_ind_freeze', { p_office: office, p_lever: lever, p_frozen: frozen });

/** A lever value in plain words: 1.5 -> "1.5%", naira -> "₦50", hour 8 -> "8:00", mult 0.9 -> "x0.9". */
export function fmtLever(unit: LeverUnit, v: number | null | undefined): string {
  if (v == null) return '–';
  const n = Number(v.toFixed(4));
  switch (unit) {
    case 'percent': return `${n}%`;
    case 'naira': return `₦${n.toLocaleString('en-NG')}`;
    case 'hour': return `${n}:00`;
    case 'seconds': return `${n} s`;
    case 'mult': return `x${n}`;
    default: return String(n);
  }
}
