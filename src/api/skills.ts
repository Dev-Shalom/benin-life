// R3 Skills (docs/SKILLS.md): typed wrapper for skills_status(). XP is awarded on the server inside the hustle / Yahoo / shift /
// activity RPCs; the client only reads it.
import { rpc } from '../lib/api';

/** Small card on hustle / Yahoo job JSON (null when the thing has no skill). */
export interface SkillCard {
  skill: string;
  name: string;
  icon: string;
  level: number;
  min_level: number;
  ok: boolean;
  /** Hustles: + % pay from the skill now (0 at level 1). */
  pay_boost_pct: number;
  /** Yahoo skill: % cut of the EFCC chance now. */
  caught_cut_pct: number | null;
}

export interface SkillRow {
  id: string;
  name: string;
  icon: string;
  blurb: string;
  train_text: string;
  xp: number;
  level: number;
  level_xp: number;
  next_xp: number | null;
  pct: number;
  pay_pct: number | null;
  caught_cut_pct: number | null;
  next_unlocks: string[];
  train: { kind: 'hustle' | 'yahoo' | 'career' | 'activity'; ref: string; name: string; xp: number }[];
}

export interface SkillsStatus {
  enabled: boolean;
  max_level: number;
  curve: { level: number; xp: number }[];
  skills: SkillRow[];
}

export const skillsStatus = () => rpc<SkillsStatus>('skills_status');
