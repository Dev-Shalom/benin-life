// R4 School and certificates (docs/SCHOOL.md): typed wrappers for the course RPCs. The server rolls every exam, holds every naira and
// hands out XP and certificates; the client only shows it.
import { rpc } from '../lib/api';

export const CLASS_LABEL_PREFIX = 'Class: ';

export interface CourseWhy { hint: string; message: string; short: string; wait_seconds?: number }

export interface CoursePlace { id: string; name: string; open: boolean }

export interface Course {
  id: string;
  name: string;
  icon: string;
  blurb: string;
  where_text: string;
  places: CoursePlace[];
  fee: number;
  classes: number;
  class_game_minutes: number;
  class_seconds: number;
  cooldown_days: number;
  energy_cost: number;
  hours: string | null;
  skill: { id: string; name: string; icon: string; xp_per_class: number; level: number } | null;
  prereq: {
    certs: { id: string; name: string; ok: boolean }[];
    skill: { id: string; name: string; icon: string; need: number; have: number; ok: boolean } | null;
  };
  exam: { base_pct: number; per_level_pct: number; chance_now: number; text: string; fails: number } | null;
  modules: string[];
  module_now: string | null;
  cert: { id: string; name: string; icon: string; pay_bonus_pct: number } | null;
  unlocks: string[];
  state: 'new' | 'enrolled' | 'completed';
  done: number;
  enrolled_at: string | null;
  wait_seconds: number;
  next_class_at: string | null;
  final_next: boolean;
  /** Why I can't enrol (state new), null = I can. */
  enrol_why: CourseWhy | null;
  /** Why a class can't start now, not counting the place (state enrolled). */
  locked: CourseWhy | null;
  /** True when the place I am at works for a class right now. */
  here: boolean;
  here_why: CourseWhy | null;
}

export interface Certificate { id: string; name: string; icon: string; earned_at: string }

export interface CourseRun {
  id: number; course_id: string; name: string; icon: string; class_no: number; started_at: string; resolve_at: string;
  status: string; outcome: string | null; xp: number; message: string | null;
}

export interface CourseResult {
  status: 'done' | 'none' | string;
  course_id?: string;
  name?: string;
  icon?: string;
  class_no?: number;
  classes?: number;
  done?: number;
  outcome?: 'ok' | 'pass' | 'fail' | string;
  xp?: number;
  exam_chance?: number | null;
  message?: string;
  already?: boolean;
  graduated?: { cert: string; name: string; icon: string; unlocks: string[]; new: boolean } | null;
}

export interface CourseStatus {
  enabled: boolean;
  cash: number;
  bank: number;
  location: string;
  degree_cert: string | null;
  courses: Course[];
  certificates: Certificate[];
  run: CourseRun | null;
  resolved: CourseResult | null;
  history: CourseRun[];
}

export const courseStatus = () => rpc<CourseStatus>('course_status');
export const courseEnrol = (id: string) => rpc<{ course_id: string; name: string; paid: number; classes: number; message: string }>('course_enrol', { p_id: id });
export const courseStartClass = (id: string) =>
  rpc<{ run_id: number; busy_until: string; resolve_at: string; seconds: number; course_id: string; name: string; icon: string; class_no: number; classes: number;
    started_at: string; exam: boolean; message: string }>('course_start_class', { p_id: id });
export const courseFinishClass = () => rpc<CourseResult>('course_finish_class');
