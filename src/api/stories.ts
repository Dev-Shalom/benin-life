// Daily stories with a twist (docs/DAILY_STORIES.md). The server picks today's story, rolls the outcome (the twist), applies the effects,
// plants follow-ups and moves the hidden path. This file only types the answers: the client never sees chances, weights or path numbers.
import { rpc } from '../lib/api';

export type StoryTone = 'good' | 'bad' | 'twist' | 'funny' | 'info';

export interface StoryChoice {
  id: string;
  label: string;
  /** Naira the choice costs, paid up front (0 = free). */
  cost: number;
  affordable: boolean;
}

export interface StoryStreakPaid { days: number; cash: number }

export interface StoryResult {
  text: string;
  tone: StoryTone;
  outcome: string;
  choice: string;
  choice_label: string;
  /** Short lines for the chips: "Got ₦1,000", "Fun +5". */
  effects: string[];
  /** A follow-up was planted: "Something tells you this isn't over…" */
  seed: boolean;
  /** A subtle line about the player's path, or null. Never a number. */
  whisper: string | null;
  spent: number;
  gain: number;
  icon: string;
  streak: { streak: number; best: number; paid: StoryStreakPaid[]; cash: number } | null;
}

export interface Story {
  /** The instance id (what answer takes). */
  id: number;
  /** The story's own id. */
  story: string;
  kind: 'daily' | 'chapter';
  title: string;
  body: string;
  icon: string;
  speaker: string;
  choices: StoryChoice[];
  status: 'pending' | 'answered' | 'expired';
  day: string;
  show_at: string;
  result: StoryResult | null;
}

export interface StreakStep { days: number; cash: number; reached: boolean; claimed: boolean }
export interface StoryStreak {
  streak: number;
  best: number;
  read_today: boolean;
  steps: StreakStep[];
  next: { days: number; cash: number; left: number } | null;
}

/** "Your path so far": words only. */
export interface PathCard { title: string; notes: string[] }

export interface StoryBadge { waiting: number; daily: boolean; chapters: number }

export interface StoryToday {
  enabled: boolean;
  day: string;
  today?: Story[];
  chapters?: Story[];
  streak?: StoryStreak;
  path?: PathCard;
  badge?: StoryBadge;
}

export interface StoryAnswer { story: Story; reveal: StoryResult; streak: StoryStreak; path: PathCard; badge: StoryBadge }

export const storyToday = () => rpc<StoryToday>('story_today');
export const storyAnswer = (story: number, choice: string) => rpc<StoryAnswer>('story_answer', { p_story: story, p_choice: choice });
