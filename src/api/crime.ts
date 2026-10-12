// C1 pickpocket + jail cases (docs/CRIME.md). The server rolls every outcome; the client only shows it.
import { rpc } from '../lib/api';

export interface JailCase {
  id: number;
  /** Y1: 'efcc' = caught doing Yahoo work (EFCC copy, laptop seized, yahoo balance gone). */
  kind?: 'police' | 'efcc';
  meta?: { laptop?: string | null; laptop_name?: string | null; seized?: number; job_name?: string } | null;
  status: 'open' | 'bailed' | 'served' | 'escaped' | 'released';
  /** false = the "Police don catch you!" popup still waits for a choice. */
  decided: boolean;
  reason: string;
  bail_amount: number;
  escape_attempts: number;
  jail_seconds: number;
  jail_until: string;
  created_at: string;
  location_id: string | null;
  place: string | null;
  can_afford: boolean;
  escape_caught_pct: number;
  escape_time_mult: number;
  escape_bail_mult: number;
}

export interface StealResult {
  status: 'success' | 'caught' | 'gone' | 'empty' | 'missed' | 'cancelled' | 'none';
  amount: number;
  victim?: string;
  place?: string;
  case?: JailCase | null;
  message?: string;
  already?: boolean;
}

export interface CrimeStatus {
  case: JailCase | null;
  attempt: { id: number; resolve_at: string; target: string } | null;
  resolved: StealResult | null;
  cooldown_until: string | null;
}

export const STEAL_LABEL = 'Picking a pocket';

export const stealAttempt = (target: string) =>
  rpc<{ attempt_id: number; busy_until: string; seconds: number; target: string; message: string }>('steal_attempt', { p_target: target });
export const stealFinish = () => rpc<StealResult>('steal_finish');
export const crimeStatus = () => rpc<CrimeStatus>('crime_status');
export const jailCaseBail = () => rpc<{ message: string; paid: number; bank: number; cash: number }>('jail_case_bail');
export const jailCaseGoToJail = () => rpc<{ message: string; case: JailCase; jail_until: string }>('jail_case_go_to_jail');
export const jailCaseEscape = () => rpc<{ escaped: boolean; message: string; case?: JailCase; location_id?: string }>('jail_case_escape');
