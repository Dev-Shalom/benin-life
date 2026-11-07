// Steering inputs and counts shared by the on-screen controls, the scene and the report to the server (no three.js). docs/DRIVE.md.
// The scene only COUNTS what happened (clean overtakes, tight gaps, hits, off-road moments). The server clamps those counts
// (drive_report) and decides what they are worth; the client never reports seconds.

export interface SteerInput {
  /** Pending lane steps: -1 = one lane to the left, +1 = to the right. The scene consumes it. */
  lane: number;
  brake: boolean;
  boost: boolean;
}

export interface SteerStats {
  passes: number;
  gaps: number;
  hits: number;
  offroad: number;
}

export const newSteer = (): SteerInput => ({ lane: 0, brake: false, boost: false });
export const newStats = (): SteerStats => ({ passes: 0, gaps: 0, hits: 0, offroad: 0 });

/** How long after the last touch the player counts as driving (then the autopilot takes over again). */
export const MANUAL_MS = 8000;

/** What the speedometer shows for a scene speed in m/s (the scene is compressed, so scale it to feel like a road). */
export const kmh = (v: number) => Math.round(v * 3.6 * 1.35);

/** Litres in the tank at a point of the trip: it falls with progress, and stays at the server's level once the dry card was answered. */
export function fuelAt(trip: { fuel_before: number; need_l: number; dry_done?: boolean } | null, progress: number, nowLevel: number): number {
  if (!trip) return nowLevel;
  if (trip.dry_done) return nowLevel;
  return Math.max(0, trip.fuel_before - trip.need_l * Math.min(1, Math.max(0, progress)));
}

/** Counts the server has not seen yet. */
export function newCounts(now: SteerStats, sent: SteerStats): SteerStats {
  return {
    passes: Math.max(0, now.passes - sent.passes),
    gaps: Math.max(0, now.gaps - sent.gaps),
    hits: Math.max(0, now.hits - sent.hits),
    offroad: Math.max(0, now.offroad - sent.offroad),
  };
}

export const anyCounts = (c: SteerStats) => c.passes + c.gaps + c.hits + c.offroad > 0;
