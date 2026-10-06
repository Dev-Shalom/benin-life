// Client game clock — P1-SHELL, L1. Mirrors the server's bl_game_clock (20261006000100_real_time.sql):
//   clock.mode = 'real' (default): the real wall clock in clock.timezone (Africa/Lagos = WAT).
//     day = whole local days since the local date of clock.epoch + 1 (Mon 5 Oct 2026 = Day 1),
//     weekday = the real weekday (0 = Monday), game_minutes = (day-1)×1440 + hour×60 + minute.
//   clock.mode = 'accelerated': game_minutes = floor(real minutes since clock.epoch ×
//     clock.game_minutes_per_real_minute + clock.start_hour_offset × 60), day = floor(gm/1440)+1.
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

/** Default `clock.timezone`: Benin City (WAT, UTC+1, no daylight saving). */
export const DEFAULT_TIMEZONE = 'Africa/Lagos';

const fmtCache = new Map<string, Intl.DateTimeFormat>();
function partsFormatter(tz: string): Intl.DateTimeFormat {
  let f = fmtCache.get(tz);
  if (!f) {
    f = new Intl.DateTimeFormat('en-GB', {
      timeZone: tz, year: 'numeric', month: '2-digit', day: '2-digit',
      hour: '2-digit', minute: '2-digit', hourCycle: 'h23',
    });
    fmtCache.set(tz, f);
  }
  return f;
}

function validTimeZone(tz: string): boolean {
  try {
    partsFormatter(tz);
    return true;
  } catch {
    return false;
  }
}

/** Local calendar parts of an instant in a time zone. dayIndex = days since 1970-01-01 (local date). */
export function zonedParts(ms: number, tz: string): { y: number; m: number; d: number; hour: number; minute: number; dayIndex: number } {
  let y = 1970, m = 1, d = 1, hour = 0, minute = 0;
  try {
    for (const p of partsFormatter(tz).formatToParts(new Date(ms))) {
      if (p.type === 'year') y = Number(p.value);
      else if (p.type === 'month') m = Number(p.value);
      else if (p.type === 'day') d = Number(p.value);
      else if (p.type === 'hour') hour = Number(p.value) % 24;
      else if (p.type === 'minute') minute = Number(p.value);
    }
  } catch {
    // Intl without time zone data: assume WAT (UTC+1).
    const t = new Date(ms + 3600_000);
    y = t.getUTCFullYear(); m = t.getUTCMonth() + 1; d = t.getUTCDate(); hour = t.getUTCHours(); minute = t.getUTCMinutes();
  }
  return { y, m, d, hour, minute, dayIndex: Math.floor(Date.UTC(y, m - 1, d) / 86_400_000) };
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

export type ClockMode = 'real' | 'accelerated';

export interface ClockSettings {
  mode: ClockMode;
  timeZone: string; // clock.timezone (real mode)
  epochMs: number; // clock.epoch as epoch ms
  speed: number; // game minutes per real minute
  offsetHours: number;
  nightStart: number;
  nightEnd: number;
}

export function clockSettings(read: <T>(k: string, f: T) => T = getCfg): ClockSettings {
  const tz = String(read('clock.timezone', DEFAULT_TIMEZONE) || DEFAULT_TIMEZONE);
  return {
    mode: read<string>('clock.mode', 'real') === 'accelerated' ? 'accelerated' : 'real',
    timeZone: validTimeZone(tz) ? tz : DEFAULT_TIMEZONE,
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
  if (s.mode === 'real') {
    const p = zonedParts(ms, s.timeZone);
    const day = p.dayIndex - zonedParts(s.epochMs, s.timeZone).dayIndex + 1;
    // 1970-01-01 was a Thursday (weekday 3 with Monday = 0)
    const weekday = (((p.dayIndex + 3) % 7) + 7) % 7;
    return {
      game_minutes: (day - 1) * 1440 + p.hour * 60 + p.minute,
      day, hour: p.hour, minute: p.minute, weekday,
      is_night: isNightHour(p.hour, s),
      mode: 'real',
      date: `${p.y}-${String(p.m).padStart(2, '0')}-${String(p.d).padStart(2, '0')}`,
    };
  }
  // Same order as the server (multiply before dividing) so whole seconds give exact minutes.
  const game_minutes = Math.floor(((ms - s.epochMs) / 1000) * s.speed / 60 + s.offsetHours * 60);
  const dayIdx = Math.floor(game_minutes / 1440);
  const inDay = ((game_minutes % 1440) + 1440) % 1440;
  const hour = Math.floor(inDay / 60);
  const minute = inDay % 60;
  return { game_minutes, day: dayIdx + 1, hour, minute, is_night: isNightHour(hour, s), mode: 'accelerated' };
}

/** Game minutes per real minute: 1 with the real clock, clock.game_minutes_per_real_minute when accelerated. */
export function clockSpeed(s: ClockSettings = clockSettings()): number {
  return s.mode === 'real' ? 1 : Math.max(0.0001, s.speed);
}

/** Real seconds that `gameMinutes` of clock time takes (e.g. "bank opens in"). */
export function realSecondsFor(gameMinutes: number, s: ClockSettings = clockSettings()): number {
  return (gameMinutes / clockSpeed(s)) * 60;
}

const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

/**
 * Calendar label for a clock: the real date with the real clock ("6 Oct", long: "6 October"),
 * "Day N" with the accelerated clock.
 */
export function dateLabel(clock: GameClock, long = false): string {
  const m = clock.date ? /^(\d{4})-(\d{2})-(\d{2})$/.exec(clock.date) : null;
  if (!m) return `Day ${clock.day}`;
  const month = MONTHS[Number(m[2]) - 1] ?? '';
  return `${Number(m[3])} ${long ? month : month.slice(0, 3)}`;
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
