import { rpc } from '../lib/api';

export interface StoryChoice { id: string; label: string }
export interface StorylineState {
  enabled: boolean;
  week_start: string;
  episode?: { id: string; title: string; summary: string; choices: StoryChoice[] };
  choice?: { id: string; result: { reply?: string }; created_at: string } | null;
}
export interface StorylineResult { message: string; jailed_until?: string | null; story: StorylineState }

export const storylineCurrent = () => rpc<StorylineState>('storyline_current');
export const storylineChoose = (choice: string) => rpc<StorylineResult>('storyline_choose', { p_choice: choice });
