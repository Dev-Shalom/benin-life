// V2 house interactions: tap a person in the house -> cook for them, watch a movie, gist, dance, play,
// greet. Server-authoritative (supabase/migrations/20261011000100_house_interactions.sql); the other
// player is notified through the events table (kind 'house_interact') and answers with Accept / Not now.
import { rpc } from '../lib/api';
import { supabase } from '../lib/supabase';
import type { HomePose } from '../art/home3d/model';

export interface InteractionType {
  kind: string;
  label: string;
  icon: string;
  description: string;
  effects: Record<string, number>;
  requires: string[];
  cost: number;
  seconds: number;
  sort: number;
  active: boolean;
}

export interface InteractRequestResult { id: number; kind: string; label: string; expires_at: string; status: 'pending'; message: string }
export interface InteractRespondResult {
  id: number;
  status: 'accepted' | 'declined' | 'expired';
  kind?: string;
  label?: string;
  role?: 'target';
  busy_until?: string;
  message: string;
}

let cache: Promise<InteractionType[]> | null = null;
/** The admin-editable catalogue (active rows, sorted). Cached for the session. */
export function loadInteractionTypes(): Promise<InteractionType[]> {
  cache ??= (async () => {
    const { data, error } = await supabase.from('interaction_types').select('*').eq('active', true).order('sort');
    if (error) {
      cache = null;
      return [];
    }
    return (data ?? []) as InteractionType[];
  })();
  return cache;
}

export const interactRequest = (user: string, kind: string) =>
  rpc<InteractRequestResult>('social_interact_request', { p_user: user, p_kind: kind });
export const interactRespond = (id: number, accept: boolean) =>
  rpc<InteractRespondResult>('social_interact_respond', { p_id: id, p_accept: accept });

/** What each player's Sim does during an interaction (slot 0 = the one who asked, 1 = the one who accepted).
 * `activity` = walk to the piece that hosts this home activity and take its pose; `pose` = a standing
 * animation where they are. Unknown kinds (new admin rows) just stand together. */
export const IX_ROLE: Record<string, [IxRole, IxRole]> = {
  cook_meal: [{ activity: 'cook_home' }, { activity: 'sit_rest' }],
  movie: [{ activity: 'relax_sofa' }, { activity: 'relax_sofa' }],
  gist: [{ activity: 'sit_rest' }, { activity: 'sit_rest' }],
  play_game: [{ activity: 'sit_rest' }, { activity: 'sit_rest' }],
  dance: [{ pose: 'dance' }, { pose: 'dance' }],
  greet: [{ pose: 'greet' }, { pose: 'greet' }],
};
export interface IxRole { activity?: string; pose?: HomePose }

/** Broadcast tag for a remote avatar's activity: `activity#slot@pose` (each part optional). */
export function encodeAct(activity: string | null | undefined, slot?: number | null, pose?: HomePose | null): string | null {
  if (!activity && !pose) return null;
  return `${activity ?? ''}${slot != null ? `#${slot}` : ''}${pose ? `@${pose}` : ''}`;
}

export function decodeAct(tag: string | null | undefined): { activity: string | null; slot: number | null; pose: HomePose | null } {
  const m = /^([^#@]*)(?:#(\d))?(?:@(\w+))?$/.exec(tag ?? '');
  if (!m) return { activity: null, slot: null, pose: null };
  return { activity: m[1] || null, slot: m[2] != null ? Number(m[2]) : null, pose: (m[3] as HomePose) || null };
}
