// L4 events (docs/EVENTS.md): typed wrappers for events_on_today() and event_buy_ticket().
import { rpc } from '../lib/api';
import type { SceneType } from '../lib/types';

export type EventKind = 'match' | 'concert' | 'club_night' | 'market_day' | 'church' | 'owambe' | 'premiere' | 'party' | 'promo';

export interface PlaceEvent {
  id: string;
  location_id: string;
  location_name: string;
  scene: SceneType;
  district: string;
  /** With this week's variant filled in ("Bendel Insurance vs Enyimba"). */
  title: string;
  description: string;
  kind: EventKind | string;
  icon: string;
  /** Local (WAT) date the occurrence starts on; tickets are per occurrence. */
  occurs_on: string;
  starts_at: string;
  ends_at: string;
  live: boolean;
  /** "4 PM – 6 PM" */
  time_label: string;
  starts_label: string;
  ticket_price: number;
  free: boolean;
  capacity: number | null;
  sold: number;
  has_ticket: boolean;
  perks: { effects?: Record<string, number>; street_cred?: number };
  /** Event-only action cards ("⚽ Watch the match live"). */
  actions: string[];
}

export interface TicketResult {
  message: string;
  free?: boolean;
  ticket?: { id: number; event_id: string; occurs_on: string; price: number };
  from_bank?: number;
  from_cash?: number;
  event: PlaceEvent;
}

export const eventsOnToday = (location?: string | null) =>
  rpc<PlaceEvent[]>('events_on_today', location ? { p_location: location } : {});

export const buyTicket = (eventId: string) => rpc<TicketResult>('event_buy_ticket', { p_event: eventId });
