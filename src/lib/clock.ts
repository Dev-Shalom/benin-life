// Client game clock — P1-SHELL. Mirrors the server formula (ARCHITECTURE §4):
//   game_minutes = floor(real minutes since clock.epoch × clock.game_minutes_per_real_minute
//                        + clock.start_hour_offset × 60)
//   day = floor(game_minutes / 1440) + 1   (clock.epoch defaults to 2026-10-05T00:00:00Z = Day 1)
//   night = hour >= clock.night_start_hour || hour < clock.night_end_hour
// Real "now" is corrected for device clock skew using GameState.server_time.
import { useEffect, useState } from 'react';
import type { GameClock } from './types';
import { getCfg, useConfig } from './config';

/** Default `clock.epoch` (must match the seed in 20261005000300_time_tuning.sql). */
export const DEFAULT_CLOCK_EPOCH = '2026-10-05T00:00:00Z';
export const GAME_EPOCH_MS = Date.parse(DEFAULT_CLOCK_EPOCH);

/** Parse an ISO epoch string; falls back to the default when missing or unparseable. */
export function parseEpoch(iso: string): number {
  const ms = Date.parse(iso);
  return Number.isNaN(ms) ? GAME_EPOCH_MS : ms;
}

let skewMs = 0;

/** Call with GameState.server_time; t0/t1 = Date.now() before/after the request (halves latency). */
export function syncServerTime(serverIso: string, t0 = Date.now(), t1 = t0): void {
  const server = Date.parse(serverIso);
  if (Number.isNaN(server)) return;
  skewMs = server - (t0 + t1) / 2;
}

export function getSkewMs(): number {
  return skewMs;
}

/** Server-corrected epoch ms. Use for every countdown. */
export function serverNow(): number {
  return Date.now() + skewMs;
}

export interface ClockSettings {
  epochMs: number; // clock.epoch as epoch ms
  speed: number; // game minutes per real minute
  offsetHours: number;
  nightStart: number;
  nightEnd: number;
}

export function clockSettings(read: <T>(k: string, f: T) => T = getCfg): ClockSettings {
  return {
    epochMs: parseEpoch(read('clock.epoch', DEFAULT_CLOCK_EPOCH)),
    speed: read('clock.game_minutes_per_real_minute', 12),
    offsetHours: read('clock.start_hour_offset', 6),
    nightStart: read('clock.night_start_hour', 20),
    nightEnd: read('clock.night_end_hour', 6),
  };
}

export function isNightHour(hour: number, s: Pick<ClockSettings, 'nightStart' | 'nightEnd'>): boolean {
  // Same as server bl_game_clock: wraps midnight when start > end.
  return s.nightStart > s.nightEnd
    ? hour >= s.nightStart || hour < s.nightEnd
    : hour >= s.nightStart && hour < s.nightEnd;
}

/** Game clock at a given real epoch ms. */
export function gameClockAt(ms: number, s: ClockSettings = clockSettings()): GameClock {
  // Same order as the server (multiply before dividing) so whole seconds give exact minutes.
  const game_minutes = Math.floor(((ms - s.epochMs) / 1000) * s.speed / 60 + s.offsetHours * 60);
  const dayIdx = Math.floor(game_minutes / 1440);
  const inDay = ((game_minutes % 1440) + 1440) % 1440;
  const hour = Math.floor(inDay / 60);
  const minute = inDay % 60;
  return { game_minutes, day: dayIdx + 1, hour, minute, is_night: isNightHour(hour, s) };
}

/** Real seconds that `gameMinutes` takes at current speed. */
export function realSecondsFor(gameMinutes: number, s: ClockSettings = clockSettings()): number {
  return (gameMinutes / Math.max(0.0001, s.speed)) * 60;
}

/** Ticking server-corrected now (ms). One timer per component; default 1s. */
export function useNow(intervalMs = 1000): number {
  const [now, setNow] = useState(serverNow);
  useEffect(() => {
    const id = window.setInterval(() => setNow(serverNow()), intervalMs);
    return () => window.clearInterval(id);
  }, [intervalMs]);
  return now;
}

/** Live game clock + server-corrected now, re-rendering every second and on config edits. */
export function useGameClock(intervalMs = 1000): { clock: GameClock; now: number } {
  const now = useNow(intervalMs);
  const { cfg } = useConfig();
  const clock = gameClockAt(now, clockSettings(cfg));
  return { clock, now };
}

/** 0 = Monday … 6 = Sunday (game day 1 is a Monday; the server sends clock.weekday since R3a). */
export function weekdayOf(clock: GameClock): number {
  return clock.weekday ?? (((clock.day - 1) % 7) + 7) % 7;
}
