// Benin Gist: the small always-on piece (docs/GIST.md). One cheap RPC, gist_summary(), tells the game the master switches and how many of my
// groups have unread messages (cached columns, no message scan). It runs on a slow poll (the shared poller: visible tab, not AFK, slower
// when idle) and right after a gist alert arrives. Feed and group messages are NOT kept here: the feed is paged by RPC and the one open
// group chat has its own channel.
import { useEffect } from 'react';
import { create } from 'zustand';
import { gistSummary, type GistSummary } from '../api/gist';
import { startPoller } from '../lib/realtime';
import { useGame } from './game';

interface GistStore {
  summary: GistSummary | null;
  /** My groups with unread messages. */
  unreadGroups: number;
  load: () => Promise<void>;
  /** After reading a group locally: lower the badge without waiting for the next poll. */
  groupRead: () => void;
}

export const useGist = create<GistStore>((set, get) => ({
  summary: null,
  unreadGroups: 0,
  load: async () => {
    try {
      const summary = await gistSummary();
      set({ summary, unreadGroups: summary.unread_groups });
    } catch {
      /* off, or offline: keep the last numbers */
    }
  },
  groupRead: () => set({ unreadGroups: Math.max(0, get().unreadGroups - 1) }),
}));

/** Mounted once on the game screen. */
export function useGistLive(playerId: string | null) {
  const lastGistEvent = useGame((s) => s.events.find((e) => e.kind.startsWith('gist_'))?.id ?? 0);
  useEffect(() => {
    if (!playerId) return;
    const p = startPoller(() => useGist.getState().load(), () => 180_000, { immediate: true });
    return p.stop;
  }, [playerId]);
  useEffect(() => {
    if (playerId && lastGistEvent) void useGist.getState().load();
  }, [playerId, lastGistEvent]);
}
