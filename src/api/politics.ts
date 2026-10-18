// R12 politics RPCs, "Benin Votes" (server: 20261018001100_politics.sql, docs/POLITICS.md). A fictional, light, satirical game system.
import { rpc } from '../lib/api';

export interface PartyBadge { id: string; name: string; abbr: string; color: string }
export interface PolPolicy { id: string; name: string; icon: string; blurb: string; kind: string; value: number; weekday?: number | null; set_at?: string | null; by?: string; term_end?: string }
export interface PolHolder {
  id: number; office_id: string; office: string; kind: 'councillor' | 'chairman' | 'governor' | 'commissioner'; title: string; icon: string; ward_id: string | null; ward: string | null;
  user_id: string; username: string; party: PartyBadge | null; term_start: string; term_end: string; salary_per_day: number; salary_paid: number; policy: PolPolicy | null;
}
export interface PolSeat { office_id: string; office: string; kind: string; title: string; icon: string; ward_id: string | null; ward: string | null; holder: PolHolder | null }
export interface PolCheck { key: string; label: string; ok: boolean; message?: string }
export interface PolOffice {
  id: string; name: string; kind: string; title: string; icon: string; blurb: string; elected: boolean; ward_scoped: boolean; salary_per_day: number; fee: number;
  min_charisma: number; min_account_days: number; requirements: { ok: boolean; hint: string | null; message: string | null; checks: PolCheck[] } | null;
}
export interface PolParty { id: string; name: string; abbr: string; color: string; blurb: string; seeded: boolean; mine: boolean }
export interface PolWard { id: string; name: string; poll_unit: string | null; poll_unit_name: string | null }
export interface PolCycle {
  id: number; status: 'registration' | 'campaign' | 'voting'; reg_start: string; camp_start: string; vote_start: string; vote_end: string; term_days: number; voting_open: boolean; next_at: string;
}
export interface PolCandidate {
  id: number; slot_key: string; office_id: string; office: string; ward_id: string | null; ward: string | null; user_id: string; username: string; title: string | null;
  party: PartyBadge | null; promise: string; rallies: number; rally_points: number; posters: number; supporters: number; endorsers: string[]; endorse_n: number;
  crews: { name: string; tag: string; color: string; emblem: string }[]; points: number; momentum_pct: number; momentum: string; mine: boolean;
  my_backing: 'support' | 'endorse' | 'crew' | null; declared_at: string;
}
export interface PolPowers {
  can_announce?: boolean; announce_next_at?: string | null; can_set_policy?: boolean; can_ward_notice?: boolean;
  policies?: { id: string; name: string; icon: string; blurb: string; kind: string; value: number }[];
  commissioners?: { office_id: string; office: string; icon: string; title: string; user_id: string | null; username: string | null }[];
}
export interface PolStatus {
  enabled: boolean; now: string;
  settings: {
    party_fee: number; rally_cost: number; poster_cost: number; poster_max: number; vote_min_account_days: number; promise_max_len: number; announce_max_len: number;
    ward_announce_max_len: number; term_days: number; rally_cooldown_minutes: number; endorse_min_charisma: number; registration_hours: number; campaign_hours: number; voting_hours: number;
  };
  cycle: PolCycle | null; next_cycle_at: string | null; last_cycle: { id: number; closed_at: string } | null;
  me: {
    id: string; account_days: number; ward: { id: string; name: string; poll_unit: string | null; poll_unit_name: string | null }; at_polling_unit: boolean; can_vote_account: boolean;
    candidacy: PolCandidate | null; office: PolHolder | null; powers: PolPowers; voted: string[]; next_rally_at: string | null;
  };
  government: PolSeat[]; policy: PolPolicy | null; offices: PolOffice[]; parties: PolParty[]; wards: PolWard[];
}
export interface PolBallotRace {
  office_id: string; office: string; icon: string; ward_id: string | null; ward: string | null; slot_key: string; voted: boolean;
  candidates: { id: number; username: string; party: PartyBadge | null; promise: string; title: string | null }[];
}
export interface PolBallot {
  voting_open: boolean; phase: string; opens_at: string | null; closes_at: string | null; ward: { id: string; name: string }; unit: { id: string; name: string };
  at_unit: boolean; eligible: { ok: boolean; hint?: string; message?: string }; can_vote: boolean; races: PolBallotRace[];
}
export interface PolResultRace {
  office_id: string; office: string; icon: string; ward_id: string | null; ward: string | null; total_votes: number; tie: 'rally' | 'coin' | null;
  winner: { username: string; party: PartyBadge | null; votes: number };
  candidates: { username: string; party: PartyBadge | null; votes: number; won: boolean }[];
}
export interface PolResult { cycle_id: number; closed_at: string; term_days: number; voters: number; votes: number; races: PolResultRace[] }
type Msg = { message: string };

export const polStatus = () => rpc<PolStatus>('pol_status');
export const polCandidates = () => rpc<PolCandidate[]>('pol_candidates');
export const polBallot = () => rpc<PolBallot>('pol_ballot');
export const polResults = (limit = 5) => rpc<PolResult[]>('pol_results', { p_limit: limit });
export const polPartyCreate = (name: string, abbr: string, color: string) => rpc<Msg & { id: string }>('pol_party_create', { p_name: name, p_abbr: abbr, p_color: color });
export const polDeclare = (office: string, ward: string | null, promise: string, party: string | null) => rpc<Msg>('pol_declare', { p_office: office, p_ward: ward, p_promise: promise, p_party: party });
export const polSetPromise = (promise: string) => rpc<Msg>('pol_set_promise', { p_promise: promise });
export const polWithdraw = () => rpc<Msg>('pol_withdraw');
export const polRally = () => rpc<Msg & { points: number; attendees: number }>('pol_rally');
export const polPoster = () => rpc<Msg>('pol_poster');
export const polBack = (candidate: number, kind: 'support' | 'endorse' | 'crew') => rpc<Msg>('pol_back', { p_candidate: candidate, p_kind: kind });
export const polUnback = (candidate: number, kind: string | null = null) => rpc<Msg>('pol_unback', { p_candidate: candidate, p_kind: kind });
export const polReportVoteBuying = (candidate: number, reason: string) => rpc<Msg>('pol_report_vote_buying', { p_candidate: candidate, p_reason: reason });
export const polVote = (candidate: number) => rpc<Msg>('pol_vote', { p_candidate: candidate });
export const polAppoint = (office: string, username: string) => rpc<Msg>('pol_appoint', { p_office: office, p_username: username });
export const polSack = (office: string) => rpc<Msg>('pol_sack', { p_office: office });
export const polAnnounce = (body: string) => rpc<Msg>('pol_announce', { p_body: body });
export const polSetPolicy = (policy: string) => rpc<Msg>('pol_set_policy', { p_policy: policy });
export const polWardNotice = (body: string) => rpc<Msg>('pol_ward_notice', { p_body: body });
export const polResign = () => rpc<Msg>('pol_resign');

// admin
export interface AdminPolCandidate {
  id: number; cycle_id: number; user_id: string; username: string; office_id: string; office: string; ward: string | null; party: PartyBadge | null; promise: string; status: string;
  dq_reason: string | null; fee_paid: number; rally_points: number; rallies: number; posters: number; won: boolean; final_votes: number | null; supporters: number; endorsements: number;
  reports: number; flagged: boolean; report_texts: string[]; declared_at: string;
}
export interface AdminPolOverview {
  now: string; enabled: boolean; auto_cycle: boolean;
  cycle: { id: number; status: string; reg_start: string; camp_start: string; vote_start: string; vote_end: string; term_days: number; created_by: string | null; next_at: string; votes_cast: number; voters: number } | null;
  shown_cycle: number | null; candidates: AdminPolCandidate[]; holders: PolHolder[];
  history: { id: number; status: string; reg_start: string; vote_end: string; closed_at: string | null; cancel_reason: string | null; candidates: number; votes: number | null }[];
}
export interface AdminPolTallies {
  cycle: number; closed_at: string;
  races: { office: string; ward: string | null; tie: string | null; total_votes: number; candidates: { username: string; party: PartyBadge | null; votes: number; rally_points: number; won: boolean }[] }[];
}
export const adminPolOverview = () => rpc<AdminPolOverview>('admin_pol_overview');
export const adminPolStart = (reg: number | null, camp: number | null, vote: number | null, term: number | null) =>
  rpc<Msg & { id: number }>('admin_pol_start', { p_reg_hours: reg, p_camp_hours: camp, p_vote_hours: vote, p_term_days: term });
export const adminPolAdvance = () => rpc<Msg & { status: string }>('admin_pol_advance');
export const adminPolCancel = (reason: string) => rpc<Msg>('admin_pol_cancel', { p_reason: reason });
export const adminPolDisqualify = (candidate: number, reason: string) => rpc<Msg>('admin_pol_disqualify', { p_candidate: candidate, p_reason: reason });
export const adminPolDismissReports = (candidate: number) => rpc<Msg>('admin_pol_dismiss_reports', { p_candidate: candidate });
export const adminPolRemoveHolder = (holder: number, reason: string) => rpc<Msg>('admin_pol_remove_holder', { p_holder: holder, p_reason: reason });
export const adminPolTallies = (cycle: number) => rpc<AdminPolTallies>('admin_pol_tallies', { p_cycle: cycle });
