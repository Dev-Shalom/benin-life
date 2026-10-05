// V1-3: typed wrappers for the career RPCs (server: supabase/migrations/20261005000700_careers.sql).
import { rpc } from '../lib/api';
import type { GameState, JobsCatalog, WorkFinishResult } from '../lib/types';

export const getJobsCatalog = () => rpc<JobsCatalog>('jobs_catalog');
export const applyForJob = (track: string) => rpc<{ message: string; track: string; level: number; title: string }>('job_apply', { p_track: track });
export const quitJob = () => rpc<{ message: string }>('job_quit');
export const workShift = () => rpc<{ message: string; busy_until: string; pay: number; xp: number; perf: number }>('work_shift');
export const workFinish = () => rpc<WorkFinishResult>('work_finish');

/** Can the player start a shift where they stand? */
export function worksHere(state: GameState, locationId = state.profile.location_id): boolean {
  const job = state.career?.job;
  return Boolean(job && job.locations.some((l) => l.id === locationId));
}

/** A shift that has ended but is not paid yet. */
export function shiftDue(state: GameState, nowMs: number): boolean {
  const ends = state.profile.job_shift_ends_at;
  return Boolean(ends) && Date.parse(ends!) <= nowMs;
}

/** The job's workplace closest to where the player is (straight-line map distance). */
export function nearestWorkplace(state: GameState, byId: Record<string, { x: number; y: number }>): string | null {
  const job = state.career?.job;
  if (!job || !job.locations.length) return null;
  const here = byId[state.profile.location_id] ?? state.location;
  let best: string | null = null;
  let bestD = Infinity;
  for (const l of job.locations) {
    const p = byId[l.id];
    const d = p ? Math.hypot(p.x - here.x, p.y - here.y) : 1e9;
    if (d < bestD) {
      bestD = d;
      best = l.id;
    }
  }
  return best;
}
