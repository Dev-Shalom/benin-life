// M1 club music (docs/MUSIC.md): asks the server which playlist plays at this club right now (a LIVE event's
// playlist, else the club's, else the default) and hands it to the sound engine, which plays it as a radio on the
// server clock. Re-asks when an event starts / ends (refresh_at_ms), every couple of minutes (admin edits move the
// playlist's anchor) and when the tab comes back. A failed fetch keeps whatever plays now.
import { useEffect } from 'react';
import { rpc } from './api';
import { serverNow } from './clock';
import { usePrefs } from './prefs';
import { setPlaceRadio } from './sound';
import { noteClockSample, type ResolvedMusic } from './radio';
import { canPoll } from './activity';

const POLL_MS = 120_000;
const cache = new Map<string, ResolvedMusic>();
let lastLoc: string | null = null;

export function useClubMusic(locationId: string | null, enabled: boolean) {
  const musicOn = usePrefs((s) => s.music);
  useEffect(() => {
    if (!enabled || !locationId || !musicOn) return;
    let alive = true;
    let timer: number | null = null;
    const cached = cache.get(locationId);
    if (cached) setPlaceRadio(cached.playlist);
    else if (lastLoc !== locationId) setPlaceRadio(null);
    lastLoc = locationId;

    const next = (r: ResolvedMusic | null) => {
      if (!alive) return;
      let wait = POLL_MS + Math.random() * 15_000;
      if (r?.refresh_at_ms != null) wait = Math.min(wait, Math.max(1000, r.refresh_at_ms - serverNow() + 400 + Math.random() * 2500));
      if (!r) wait = 30_000;
      timer = window.setTimeout(() => void load(), wait);
    };
    let busy = false;
    const ask = async (): Promise<ResolvedMusic> => {
      const t0 = Date.now();
      const r = await rpc<ResolvedMusic>('club_music_for', { p_location: locationId });
      noteClockSample(r.now_ms, t0, Date.now()); // the radio's own server-clock estimate (smallest round trip wins)
      return r;
    };
    const load = async () => {
      if (busy) return; // one call at a time: a joined in-flight call would be timed from the wrong start
      const held = cache.get(locationId);
      if (held && !canPoll()) { next(held); return; } // IO: hidden / AFK tab: keep what plays, ask again when it is back
      busy = true;
      if (timer !== null) { window.clearTimeout(timer); timer = null; }
      try {
        let r = await ask();
        if (!alive) return;
        // first time in this club: two more quick samples sharpen the clock estimate (tiny calls; the fastest is kept)
        if (!cache.has(locationId)) {
          for (let i = 0; i < 2 && alive; i++) { try { r = await ask(); } catch { break; } }
          if (!alive) return;
        }
        cache.set(locationId, r);
        setPlaceRadio(r.playlist);
        next(r);
      } catch {
        next(null);
      } finally {
        busy = false;
      }
    };
    void load();
    const onVis = () => { if (document.visibilityState === 'visible') void load(); };
    document.addEventListener('visibilitychange', onVis);
    return () => {
      alive = false;
      if (timer !== null) window.clearTimeout(timer);
      document.removeEventListener('visibilitychange', onVis);
    };
  }, [locationId, enabled, musicOn]);
}
