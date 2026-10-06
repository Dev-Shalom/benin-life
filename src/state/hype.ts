// P2 club hype — live state (docs/PLACES.md "P2 hype"). Rows come ONLY from the server (place_announcements,
// written by do_activity / shop_buy); the client just listens:
//   club channel    INSERTs filtered by location_id=eq.<the club you're in>  -> banner + hype-man bubble + chat line
//                   + the Doremi stinger and the crowd cheer
//   global channel  INSERTs filtered by global=eq.true (big spends)          -> a slim ticker for ~6 s, soft cue
// Recent lines of the club (last 30 min) are loaded once on entry so the chat shows them too.
import { useEffect } from 'react';
import { create } from 'zustand';
import type { RealtimeChannel } from '@supabase/supabase-js';
import { supabase } from '../lib/supabase';
import { playHype } from '../lib/sound';

export interface Announcement {
  id: number;
  location_id: string;
  user_id: string;
  username: string;
  kind: 'vip' | 'bottles' | 'spray' | 'shoutout' | 'shutdown' | 'vip_arrival' | string;
  amount: number;
  qty: number;
  text: string;
  ticker: string | null;
  global: boolean;
  created_at: string;
}

const BANNER_MS = 7000;
const TICKER_MS = 6000;

interface HypeStore {
  locationId: string | null;
  /** The place is a club (all hype kinds); elsewhere only VIP arrivals (PAY) show. */
  inClub: boolean;
  /** The club's recent lines (chat shows them as hype messages). */
  recent: Announcement[];
  /** The banner on screen now, and the ones waiting (max 3). */
  banner: Announcement | null;
  queue: Announcement[];
  /** The app-wide ticker on screen now. */
  ticker: Announcement | null;
}

export const useHype = create<HypeStore>(() => ({ locationId: null, inClub: false, recent: [], banner: null, queue: [], ticker: null }));

let bannerTimer = 0;
let tickerTimer = 0;

function showNext() {
  window.clearTimeout(bannerTimer);
  const { queue } = useHype.getState();
  const next = queue[0] ?? null;
  useHype.setState({ banner: next, queue: queue.slice(1) });
  if (!next) return;
  playHype(next.kind === 'vip_arrival' && !useHype.getState().inClub ? 'global' : 'club');
  // the hype man says it too (PlaceScene shows a bubble over him and he points + jumps)
  window.dispatchEvent(new CustomEvent('bl:hype', { detail: { text: next.text, kind: next.kind } }));
  bannerTimer = window.setTimeout(showNext, BANNER_MS);
}

function onClubRow(a: Announcement) {
  const s = useHype.getState();
  if (a.location_id !== s.locationId || s.recent.some((x) => x.id === a.id)) return;
  if (!s.inClub && a.kind !== 'vip_arrival') return;
  useHype.setState({ recent: [...s.recent, a].slice(-20) });
  if (s.banner) useHype.setState({ queue: [...s.queue, a].slice(-3) });
  else {
    useHype.setState({ queue: [a] });
    showNext();
  }
}

function onGlobalRow(a: Announcement) {
  // in that club already: the banner says it louder
  if (a.location_id === useHype.getState().locationId || !a.ticker) return;
  window.clearTimeout(tickerTimer);
  useHype.setState({ ticker: a });
  playHype('global');
  tickerTimer = window.setTimeout(() => useHype.setState({ ticker: null }), TICKER_MS);
}

/** Dismiss the banner now (tap). */
export function dismissHypeBanner() {
  showNext();
}

let clubCh: RealtimeChannel | null = null;
let globalCh: RealtimeChannel | null = null;

/** Mounted once by the game screen: `clubId` = the place you're at (null on the road), `uid` = signed in,
 *  `inClub` = that place is a club (all hype kinds); elsewhere only VIP arrivals (PAY) are shown. */
export function useHypeLive(clubId: string | null, uid: string | null, inClub = true) {
  useEffect(() => {
    if (!uid) return;
    const ch = supabase
      .channel('hype-global')
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'place_announcements', filter: 'global=eq.true' },
        (p) => onGlobalRow(p.new as Announcement))
      .subscribe();
    globalCh = ch;
    return () => {
      void supabase.removeChannel(ch);
      if (globalCh === ch) globalCh = null;
      window.clearTimeout(tickerTimer);
      useHype.setState({ ticker: null });
    };
  }, [uid]);

  useEffect(() => {
    window.clearTimeout(bannerTimer);
    useHype.setState({ locationId: clubId, inClub, recent: [], banner: null, queue: [] });
    if (!clubId || !uid) return;
    let alive = true;
    const load = async () => {
      const since = new Date(Date.now() - 30 * 60 * 1000).toISOString();
      const { data } = await supabase.from('place_announcements').select('*')
        .eq('location_id', clubId).gte('created_at', since).order('id', { ascending: false }).limit(10);
      if (!alive || useHype.getState().locationId !== clubId) return;
      const have = useHype.getState().recent;
      const rows = ((data ?? []) as Announcement[]).filter((x) => inClub || x.kind === 'vip_arrival');
      const merged = [...rows.reverse(), ...have.filter((x) => !(data ?? []).some((d: Announcement) => d.id === x.id))];
      useHype.setState({ recent: merged.sort((a, b) => a.id - b.id).slice(-20) });
    };
    const ch = supabase
      .channel(`hype-${clubId}`)
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'place_announcements', filter: `location_id=eq.${clubId}` },
        (p) => onClubRow(p.new as Announcement))
      .subscribe((status) => {
        if (status === 'SUBSCRIBED' || status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') void load();
      });
    clubCh = ch;
    return () => {
      alive = false;
      void supabase.removeChannel(ch);
      if (clubCh === ch) clubCh = null;
    };
  }, [clubId, uid, inClub]);
}
