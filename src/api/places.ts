// L2 place interiors (docs/PLACES.md): typed wrapper for place_interior().
import { rpc } from '../lib/api';
import type { SceneType } from '../lib/types';

export type ZoneActionKind = 'activity' | 'job' | 'shop' | 'panel';

export interface ZoneAction {
  /** zone_actions.id */
  id: string;
  kind: ZoneActionKind;
  /** activity id | item id | career track id | panel id */
  ref: string;
  name: string;
  icon: string;
  /** Activities: price; shop: item price. */
  cost?: number;
  effects?: Record<string, number> | null;
  game_minutes?: number;
  max_seconds?: number | null;
  min_seconds?: number | null;
  scale_by_need?: boolean | null;
  night_only?: boolean;
  risky?: boolean;
  home_only?: boolean;
  rush?: { from?: number; to?: number; pct?: number } | null;
  /** Shop: item category ('vehicle' = a car) and how many the player owns. */
  category?: string;
  owned?: number;
  /** Job: is it the player's own job, title and pay per shift. */
  mine?: boolean;
  title?: string | null;
  pay?: number | null;
  /** Why it can't be done now ("Opens 9 PM", "Night only", "Only in your own home"), or null. */
  locked: string | null;
}

export interface PlaceZone {
  id: string;
  key: string;
  label: string;
  icon: string;
  /** What the 3D interior draws there (src/art/place3d/engine/props.ts). */
  prop: string;
  x: number;
  z: number;
  w: number;
  d: number;
  rot: number;
  note: string | null;
  actions: ZoneAction[];
}

export interface PlaceInterior {
  location: { id: string; name: string; district: string; scene: SceneType; blurb: string; open_hour: number | null; close_hour: number | null };
  here: boolean;
  home: boolean;
  open: boolean;
  /** "Opens 9 PM" while closed. */
  opens: string | null;
  /** "9 PM – 5 AM" or null (always open). */
  hours: string | null;
  night: boolean;
  part: 'morning' | 'afternoon' | 'evening' | 'night';
  moods: { icon: string; line: string }[];
  zones: PlaceZone[];
}

export const placeInterior = (location?: string) => rpc<PlaceInterior>('place_interior', location ? { p_location: location } : {});
