// S1-D feedback box (supabase/migrations/20261012000900_feedback.sql).
import { rpc } from '../lib/api';
import { pokeAdminPush } from '../lib/billboards';

export type FeedbackKind = 'suggestion' | 'bug' | 'review';
export type FeedbackStatus = 'new' | 'planned' | 'done' | 'ignored';

export interface FeedbackRow {
  id: number;
  kind: FeedbackKind;
  rating: number | null;
  body: string;
  status: FeedbackStatus;
  reply: string | null;
  replied_at: string | null;
  created_at: string;
}

export interface FeedbackMine {
  enabled: boolean;
  left_today: number;
  per_day: number;
  rows: FeedbackRow[];
}

export const feedbackMine = () => rpc<FeedbackMine>('feedback_mine');

export async function feedbackSubmit(kind: FeedbackKind, body: string, rating: number | null) {
  const meta = {
    app_version: String(import.meta.env.VITE_BUILD_ID ?? 'dev'),
    device: navigator.userAgent.slice(0, 300),
    viewport: `${window.innerWidth}x${window.innerHeight}`,
  };
  const r = await rpc<{ id: number; message: string; left_today: number }>('feedback_submit', {
    p_kind: kind, p_body: body, p_rating: kind === 'review' ? rating : null, p_meta: meta,
  });
  pokeAdminPush(); // the owner's phone gets "New suggestion from @you"
  return r;
}

export const FEEDBACK_KINDS: { id: FeedbackKind; label: string; emoji: string; hint: string }[] = [
  { id: 'suggestion', label: 'Suggestion', emoji: '💡', hint: 'Wetin you wan make we add or change?' },
  { id: 'bug', label: 'Bug', emoji: '🐞', hint: 'Wetin happen? Where you dey, and wetin you tap before e spoil?' },
  { id: 'review', label: 'Review', emoji: '⭐', hint: 'How you see Benin Life so far?' },
];

export const FEEDBACK_STATUS: Record<FeedbackStatus, string> = {
  new: 'Sent', planned: 'Planned', done: 'Done', ignored: 'Closed',
};
