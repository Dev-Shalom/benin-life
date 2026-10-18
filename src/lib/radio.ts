// M1 club radio (docs/MUSIC.md): a playlist played like a radio station. Where you are in the playlist is a pure
// function of the SERVER clock, so every player hears the same track at the same second, leaving and coming back
// continues where the club is now, and the playlist loops forever.
//   position = (serverNow - anchor) mod total playlist duration
//   shuffle  = a seeded order per loop cycle (seed = playlist id + cycle number), identical on every client
// This file is the pure part (testable, no DOM): the schedule maths and the order. The element / WebAudio side is
// ClubRadio in src/lib/clubRadio.ts.

export interface RadioTrack { id: string; title: string; artist: string; url: string; duration_ms: number }
export interface RadioPlaylist {
  id: string;
  name: string;
  shuffle: boolean;
  /** Server epoch ms. Moves only when the playlist is edited. */
  anchor_ms: number;
  total_ms: number;
  tracks: RadioTrack[];
}
/** The answer of the club_music_for RPC. */
export interface ResolvedMusic {
  location_id: string;
  source: 'event' | 'club' | 'default' | 'none';
  event_id: string | null;
  playlist: RadioPlaylist | null;
  now_ms: number;
  refresh_at_ms: number | null;
}

export interface RadioSlot {
  /** Loop cycle number since the anchor (0, 1, 2 ...). */
  cycle: number;
  /** Index inside the cycle's order. */
  index: number;
  track: RadioTrack;
  /** Where in the track the radio is now, ms. */
  offsetMs: number;
  remainingMs: number;
  /** What plays next (the next cycle's first track at the loop point). */
  next: RadioTrack;
  /** Unique id of this slot (cycle * 1000 + index), so a repeated track still counts as a new slot. */
  key: number;
}

/** FNV-1a 32-bit hash of a string. */
export function hashSeed(s: string): number {
  let h = 0x811c9dc5;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 0x01000193);
  }
  return h >>> 0;
}

/** mulberry32: a tiny seeded PRNG, the same sequence in every browser. */
export function mulberry32(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function shuffled(tracks: RadioTrack[], playlistId: string, cycle: number): RadioTrack[] {
  const out = tracks.slice();
  const rnd = mulberry32(hashSeed(`${playlistId}:${cycle}`));
  for (let i = out.length - 1; i > 0; i--) {
    const j = Math.floor(rnd() * (i + 1));
    [out[i], out[j]] = [out[j], out[i]];
  }
  return out;
}

/** The track order of one loop cycle. In order = the playlist order; shuffle = seeded by playlist id + cycle.
 *  With 3+ tracks, a cycle never opens with the track the previous cycle ended on (swap the first two). */
export function cycleOrder(p: RadioPlaylist, cycle: number): RadioTrack[] {
  if (!p.shuffle || p.tracks.length < 2) return p.tracks;
  const order = shuffled(p.tracks, p.id, cycle);
  if (cycle > 0 && p.tracks.length > 2) {
    const prev = shuffled(p.tracks, p.id, cycle - 1);
    if (order[0].id === prev[prev.length - 1].id) [order[0], order[1]] = [order[1], order[0]];
  }
  return order;
}

/** Sum of the track lengths (what the server calls total_ms). */
export function totalMs(p: RadioPlaylist): number {
  let s = 0;
  for (const t of p.tracks) s += t.duration_ms;
  return s;
}

/** Where the radio is at server time `nowMs`. null when the playlist can't play (no tracks / no length). */
export function locate(p: RadioPlaylist, nowMs: number): RadioSlot | null {
  const total = totalMs(p);
  if (!p.tracks.length || total <= 0) return null;
  const elapsed = Math.max(0, nowMs - p.anchor_ms);
  const cycle = Math.floor(elapsed / total);
  let pos = elapsed - cycle * total;
  const order = cycleOrder(p, cycle);
  for (let i = 0; i < order.length; i++) {
    const d = order[i].duration_ms;
    if (pos < d || i === order.length - 1) {
      const next = i + 1 < order.length ? order[i + 1] : cycleOrder(p, cycle + 1)[0];
      return { cycle, index: i, track: order[i], offsetMs: Math.min(pos, d), remainingMs: Math.max(0, d - pos), next, key: cycle * 1000 + i };
    }
    pos -= d;
  }
  return null;
}

/** Gain for a track at `offsetMs` of `durationMs`: a short fade in at the start and out at the end (the crossfade). */
export function fadeGain(offsetMs: number, durationMs: number, fadeMs: number): number {
  if (fadeMs <= 0) return 1;
  return Math.max(0, Math.min(1, offsetMs / fadeMs, (durationMs - offsetMs) / fadeMs));
}

/** Same playlist, same schedule? (a poll that returns the same thing must not restart the music) */
export function samePlaylist(a: RadioPlaylist | null, b: RadioPlaylist | null): boolean {
  if (a === b) return true;
  if (!a || !b) return false;
  if (a.id !== b.id || a.anchor_ms !== b.anchor_ms || a.shuffle !== b.shuffle || a.tracks.length !== b.tracks.length) return false;
  for (let i = 0; i < a.tracks.length; i++) {
    if (a.tracks[i].id !== b.tracks[i].id || a.tracks[i].duration_ms !== b.tracks[i].duration_ms || a.tracks[i].url !== b.tracks[i].url) return false;
  }
  return true;
}

// ---------- the radio's own server clock ----------
// The game's skew (GameState.server_time) is one sample of a possibly slow request, so its error can be half that
// request's round trip (seconds on a bad connection). The radio therefore keeps its own estimate from the tiny
// club_music_for calls, NTP style: offset = server now - the middle of the request, and it keeps the sample with
// the SMALLEST round trip (newer equal-quality samples replace it, an old best expires after 10 minutes).
let clockOffset: number | null = null;
let bestRtt = Infinity;
let bestAt = 0;

/** Feed one measurement: serverMs = the server's clock when it answered, t0/t1 = Date.now() before / after the call. */
export function noteClockSample(serverMs: number, t0: number, t1: number): void {
  const rtt = t1 - t0;
  if (!(rtt >= 0) || !Number.isFinite(serverMs)) return;
  const now = Date.now();
  if (clockOffset === null || rtt <= bestRtt + 15 || now - bestAt > 600_000) {
    clockOffset = serverMs - (t0 + t1) / 2;
    bestRtt = rtt;
    bestAt = now;
  }
}

/** Server epoch ms for the radio. `fallbackMs` (the game's serverNow()) is used until the first sample. */
export function radioNow(fallbackMs: number): number {
  return clockOffset === null ? fallbackMs : Date.now() + clockOffset;
}

export function radioClockInfo(): { offsetMs: number | null; rttMs: number } {
  return { offsetMs: clockOffset, rttMs: bestRtt === Infinity ? -1 : bestRtt };
}
