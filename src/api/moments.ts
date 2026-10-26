// Life moments (docs/MOMENTS.md): the BitLife-style pop-ups. The server decides everything (when a card comes, what a choice costs, what it does);
// this file only types the answers. The effects and chances of a choice never reach the client.
import { rpc } from '../lib/api';
import type { StoryBadge } from './stories';

export interface MomentChoice {
  id: string;
  label: string;
  /** Naira the choice costs, paid up front (0 = free). */
  cost: number;
  affordable: boolean;
  /** The free "Ignore" choice (what "Remind me later" turns into after the last snooze). */
  ignore: boolean;
}

export interface Moment {
  /** The instance id (what answer / snooze take). */
  id: number;
  /** The moment's own id (doc_malaria, landlord_levy ...). */
  moment: string;
  kind: 'random' | 'kids_ill' | 'kids_school' | 'kids_uni' | 'system';
  title: string;
  body: string;
  icon: string;
  /** "Dr. Osagie · Central Hospital" */
  speaker: string;
  choices: MomentChoice[];
  snoozes_left: number;
  created_at: string;
  child_id: number | null;
}

/** A card the other parent already dealt with ("Already handled by @x"). Shown once. */
export interface HandledMoment { id: number; title: string; icon: string; speaker: string; outcome: string }

export interface MomentsPending {
  enabled: boolean;
  moments: Moment[];
  handled: HandledMoment[];
  poll_seconds: number;
  /** How long "Remind me later" hides a card. */
  snooze_hours?: number;
  /** The Stories badge (docs/DAILY_STORIES.md): rides on this one cheap poll. */
  story?: StoryBadge;
}

export interface MomentResult {
  outcome: string;
  tone: 'good' | 'bad' | 'info';
  icon: string;
  spent: number;
  success: boolean;
  /** Short lines for the toast: "Paid ₦3,000", "Fun +10". */
  effects: string[];
  cured?: boolean;
  /** The child was already better / the card was handled: nothing was charged. */
  handled?: boolean;
  moment?: string;
  choice?: string;
}

export interface SnoozeResult { expired: boolean; outcome: string; tone: 'info'; remind_at?: string; snoozes_left?: number }

export const momentsPending = () => rpc<MomentsPending>('moments_pending');
export const momentsAnswer = (instance: number, choice: string) => rpc<MomentResult>('moments_answer', { p_instance: instance, p_choice: choice });
export const momentsSnooze = (instance: number) => rpc<SnoozeResult>('moments_snooze', { p_instance: instance });
export const momentsSeen = (instance: number) => rpc<{ ok: boolean }>('moments_seen', { p_instance: instance });
export const momentsOpen = (instance: number) => rpc<Moment>('moments_open', { p_instance: instance });
