// The Court RPCs (server: 20261111000100_court.sql + 20261111000200_court_rpcs.sql, docs/COURT.md). The server decides everything:
// what can be sued over (only things the game recorded), who may speak, who may rule, and all the money. This only shows it.
import { rpc } from '../lib/api';
import type { AvatarConfig } from '../lib/types';

export type CourtKind = 'pickpocket' | 'rent_owed' | 'eviction' | 'overcharge';
export type CourtRole = 'plaintiff' | 'defendant' | 'judge' | 'plaintiff_lawyer' | 'defendant_lawyer' | 'gallery' | 'visitor';

export interface CourtPerson { id: string; username: string; avatar: AvatarConfig | null; title: string | null }
export interface CourtLawyer {
  user_id: string; username: string; avatar: AvatarConfig | null; title: string | null; fee: number; bio: string; wins: number; losses: number; rank: string;
  available: boolean; available_now: boolean; open_cases: number; me: boolean;
}
export interface CourtMyLawyer extends CourtLawyer { retired: boolean; banned: boolean; ban_reason: string | null; next_rank: string | null; wins_to_next: number | null }
export interface CourtCard {
  id: number; case_no: string; tier: 'high' | 'customary'; court: string; kind: CourtKind; title: string; claim: number; status: 'scheduled' | 'ruled' | 'dismissed'; live: boolean;
  hearing_at: string; ruling_deadline: string; verdict: 'guilty' | 'not_guilty' | null; verdict_by: 'judge' | 'auto' | 'admin' | null; ruled_at: string | null; created_at: string;
  plaintiff: CourtPerson; defendant: CourtPerson; judge: CourtPerson | null; gallery: number; gallery_size: number; role: CourtRole;
  lawyers: { side: 'plaintiff' | 'defendant'; username: string; status: string }[];
}
export interface CourtHire { id: number; side: 'plaintiff' | 'defendant'; status: string; fee: number; lawyer: CourtLawyer; mine: boolean }
export interface CourtStatement { id: number; side: 'plaintiff' | 'defendant' | 'bench'; kind: 'statement' | 'note' | 'ruling'; as_lawyer: boolean; body: string; at: string; author: string | null }
export interface CourtCase extends CourtCard {
  evidence: Record<string, unknown>; filing_fee: number; verdict_note: string; restitution_paid: number; restitution_debt: number; fine: number; fine_paid: number;
  cred_hit: number; jail_seconds: number; overridden: boolean; hires: CourtHire[]; statements: CourtStatement[]; can_see: boolean;
  me: { role: CourtRole; participant: boolean; can_post: boolean; statements_left: number; can_rule: boolean; rule_from: string; can_hire: boolean; in_gallery: boolean };
  settings: { statement_max_len: number; min_hearing_minutes: number; gallery_size: number };
}
export interface CourtCheck { key: string; label: string; ok: boolean }
export interface CourtStatus {
  now: string; enabled: boolean; judge: boolean; lawyer: CourtMyLawyer | null; lawyer_requirements: { ok: boolean; checks: CourtCheck[] };
  cases: CourtCard[]; hire_requests: { hire: number; fee: number; side: 'plaintiff' | 'defendant'; client: CourtPerson; case: CourtCard }[]; judge_queue: CourtCard[];
  debts: { owed: number; collect_pct: number; items: { case_no: string; kind: 'restitution' | 'fine'; owed: number; amount: number }[] };
  blocked: string | null;
  settings: {
    filing_fee: number; customary_fee: number; customary_max: number; lookback_hours: number; hearing_delay_minutes: number; ruling_window_minutes: number; gallery_size: number;
    statement_max_len: number; fine_pct: number; cut_pct: number; lawyer_min_fee: number; lawyer_max_fee: number; debt_collect_pct: number; cred_hit: number;
    types: Record<CourtKind, boolean>;
  };
}
export interface CourtEvent {
  ok: true; kind: CourtKind; ref: string; title: string; sub: string; at: string; claim: number; defendant: string; defendant_name: string | null; tier: 'high' | 'customary'; fee: number; filed: boolean;
}
export interface CourtEvents { events: CourtEvent[]; blocked: string | null; lookback_hours: number; filing_fee: number; customary_fee: number; customary_max: number }
export interface CourtLive { live: CourtCard[]; upcoming: CourtCard[]; recent: CourtCard[] }
type Msg = { message: string; closed?: boolean; expired?: boolean };

export const courtStatus = () => rpc<CourtStatus>('court_status');
export const courtEvents = () => rpc<CourtEvents>('court_events');
export const courtFile = (kind: CourtKind, ref: string, lawyer: string | null) => rpc<Msg & { case: CourtCase; fee: number }>('court_file', { p_kind: kind, p_ref: ref, p_lawyer: lawyer });
export const courtLawyers = (q: string, filter: 'all' | 'available' | 'top') => rpc<CourtLawyer[]>('court_lawyers_list', { p_q: q, p_filter: filter, p_limit: 30 });
export const courtLawyerRegister = (fee: number, bio: string) => rpc<Msg & { lawyer: CourtLawyer }>('court_lawyer_register', { p_fee: fee, p_bio: bio });
export const courtLawyerUpdate = (fee: number | null, bio: string | null, available: boolean | null) => rpc<Msg>('court_lawyer_update', { p_fee: fee, p_bio: bio, p_available: available });
export const courtLawyerRetire = () => rpc<Msg>('court_lawyer_retire');
export const courtHire = (caseId: number, lawyer: string) => rpc<Msg>('court_hire', { p_case: caseId, p_lawyer: lawyer });
export const courtHireRespond = (hire: number, accept: boolean) => rpc<Msg>('court_hire_respond', { p_hire: hire, p_accept: accept });
export const courtHireCancel = (hire: number) => rpc<Msg>('court_hire_cancel', { p_hire: hire });
export const courtCase = (id: number) => rpc<CourtCase>('court_case', { p_id: id });
export const courtLive = () => rpc<CourtLive>('court_live');
export const courtPost = (caseId: number, body: string) => rpc<Msg & { id?: number }>('court_post', { p_case: caseId, p_body: body });
export const courtRule = (caseId: number, verdict: 'guilty' | 'not_guilty', note: string) => rpc<Msg>('court_rule', { p_case: caseId, p_verdict: verdict, p_note: note });
export const courtJudgeTake = (caseId: number) => rpc<Msg>('court_judge_take', { p_case: caseId });
export const courtGalleryJoin = (caseId: number) => rpc<{ joined: boolean; participant: boolean; count: number }>('court_gallery_join', { p_case: caseId });
export const courtGalleryLeave = (caseId: number) => rpc<{ left: boolean }>('court_gallery_leave', { p_case: caseId });
export const courtAfter = (caseId: number, after: number) => rpc<{ status: CourtCard['status']; verdict: CourtCard['verdict']; gallery: number; statements: CourtStatement[] }>('court_after', { p_case: caseId, p_after: after });

// ---- admin
export interface AdminCourtCase extends CourtCard { filing_fee: number; verdict_note: string; overridden: boolean; restitution_paid: number; restitution_debt: number; fine: number; jail_seconds: number }
export interface AdminCourtJudge { office_id: string; name: string; salary_per_day: number; active: boolean; holder: { id: number; user_id: string; username: string; term_end: string; last_seen: string | null; open_cases: number } | null }
export interface AdminCourtLawyer extends CourtLawyer { banned: boolean; ban_reason: string | null; retired: boolean }
export interface AdminCourtOverview {
  now: string; enabled: boolean;
  stats: { open: number; ruled: number; dismissed: number; auto: number; overridden: number; lawyers: number; debt_owed: number; fees_burned: number };
  cases: AdminCourtCase[]; judges: AdminCourtJudge[]; lawyers: AdminCourtLawyer[];
}
export const adminCourtOverview = (status: string | null) => rpc<AdminCourtOverview>('admin_court_overview', { p_status: status });
export const adminCourtOverride = (caseId: number, verdict: 'guilty' | 'not_guilty', reason: string) => rpc<Msg>('admin_court_override', { p_case: caseId, p_verdict: verdict, p_reason: reason });
export const adminCourtDismiss = (caseId: number, reason: string) => rpc<Msg>('admin_court_dismiss', { p_case: caseId, p_reason: reason });
export const adminCourtAppointJudge = (username: string, reason = '') => rpc<Msg>('admin_court_appoint_judge', { p_username: username, p_reason: reason });
export const adminCourtRemoveJudge = (holder: number, reason: string) => rpc<Msg>('admin_court_remove_judge', { p_holder: holder, p_reason: reason });
export const adminCourtBanLawyer = (user: string, banned: boolean, reason = '') => rpc<Msg>('admin_court_ban_lawyer', { p_user: user, p_banned: banned, p_reason: reason });

export const KIND_LABEL: Record<CourtKind, string> = { pickpocket: 'Pickpocket', rent_owed: 'Rent owed', eviction: 'Unfair eviction', overcharge: 'Overcharge' };
export const KIND_ICON: Record<CourtKind, string> = { pickpocket: '🫳', rent_owed: '🏠', eviction: '🚪', overcharge: '🏷️' };
export const KIND_HELP: Record<CourtKind, string> = {
  pickpocket: 'Somebody picked your pocket and the game recorded it.',
  rent_owed: 'A tenant was moved out of your home owing rent.',
  eviction: 'A landlord gave you notice soon after you moved in.',
  overcharge: 'You paid far above value on the Market and the game flagged it.',
};
export function roleLabel(r: CourtRole): string {
  return r === 'plaintiff' ? 'You are suing' : r === 'defendant' ? 'You are the defendant' : r === 'judge' ? 'You are the judge'
    : r === 'plaintiff_lawyer' ? 'You are the plaintiff\'s lawyer' : r === 'defendant_lawyer' ? 'You are the defendant\'s lawyer' : r === 'gallery' ? 'You are watching' : 'Public case';
}
