// V1-6 location chat — live state (docs/CHAT.md).
// One Realtime channel at a time: INSERTs on chat_messages filtered by `location_id=eq.<where you are>`
// (RLS also limits rows to your current place and drops players you blocked). The last messages are
// loaded once with chat_recent(); after that only new rows arrive. No polling. The list is capped.
import { useEffect } from 'react';
import { create } from 'zustand';
import type { RealtimeChannel } from '@supabase/supabase-js';
import { migrateAvatar } from '../art/avatar3d';
import { chatRecent } from '../api/chat';
import { rpc } from '../lib/api';
import { supabase } from '../lib/supabase';
import type { AvatarConfig, ChatMessage } from '../lib/types';

/** Most messages kept in memory / rendered. */
export const CHAT_CAP = 60;

interface ChatStore {
  locationId: string | null;
  messages: ChatMessage[];
  status: 'idle' | 'loading' | 'ready' | 'error';
  error: string | null;
  /** New messages from others since the chat tab was last on screen. */
  unread: number;
  /** The chat tab is on screen (no unread counting). */
  viewing: boolean;
  setViewing: (v: boolean) => void;
  /** Add a message (own send result or realtime row); dedupes by id. */
  add: (m: ChatMessage) => void;
  /** Drop a player's messages (after a block or report). */
  dropUser: (userId: string) => void;
  dropMessage: (id: number) => void;
  reload: () => Promise<void>;
}

let channel: RealtimeChannel | null = null;
let myId: string | null = null;
const avatars = new Map<string, AvatarConfig | null>();
const pendingAvatar = new Map<string, Promise<void>>();

function withAvatar(m: ChatMessage): ChatMessage {
  const mine = m.mine ?? (myId != null && m.user_id === myId);
  if (m.avatar !== undefined) {
    const a = m.avatar ? migrateAvatar(m.avatar) : null;
    avatars.set(m.user_id, a);
    return { ...m, avatar: a, mine };
  }
  return { ...m, avatar: avatars.get(m.user_id), mine };
}

/** Realtime rows carry no avatar: fetch each unknown sender once, then patch their messages. */
function fetchAvatar(userId: string) {
  if (avatars.has(userId) || pendingAvatar.has(userId)) return;
  const p = rpc<{ avatar: AvatarConfig | null }>('get_public_profile', { p_id: userId })
    .then((r) => {
      const a = r?.avatar ? migrateAvatar(r.avatar) : null;
      avatars.set(userId, a);
      useChat.setState((s) => ({ messages: s.messages.map((x) => (x.user_id === userId ? { ...x, avatar: a } : x)) }));
    })
    .catch(() => {
      avatars.set(userId, null);
    })
    .finally(() => pendingAvatar.delete(userId));
  pendingAvatar.set(userId, p);
}

export const useChat = create<ChatStore>((set, get) => ({
  locationId: null,
  messages: [],
  status: 'idle',
  error: null,
  unread: 0,
  viewing: false,
  setViewing: (viewing) => set(viewing ? { viewing, unread: 0 } : { viewing }),
  add: (raw) => {
    if (raw.location_id !== get().locationId) return;
    const m = withAvatar(raw);
    if (m.avatar === undefined) fetchAvatar(m.user_id);
    set((s) => {
      if (s.messages.some((x) => x.id === m.id)) return s;
      const messages = [...s.messages, m].sort((a, b) => a.id - b.id).slice(-CHAT_CAP);
      return { messages, unread: !m.mine && !s.viewing ? s.unread + 1 : s.unread };
    });
  },
  dropUser: (userId) => set((s) => ({ messages: s.messages.filter((m) => m.user_id !== userId) })),
  dropMessage: (id) => set((s) => ({ messages: s.messages.filter((m) => m.id !== id) })),
  reload: async () => {
    const loc = get().locationId;
    if (!loc) return;
    set({ status: get().messages.length ? 'ready' : 'loading', error: null });
    try {
      const rows = await chatRecent(loc, 30);
      if (get().locationId !== loc) return;
      set((s) => {
        // keep any realtime rows that arrived while loading
        const byId = new Map<number, ChatMessage>();
        for (const r of rows ?? []) byId.set(r.id, withAvatar(r));
        for (const r of s.messages) if (!byId.has(r.id) && r.id > (rows?.[rows.length - 1]?.id ?? 0)) byId.set(r.id, r);
        return { messages: [...byId.values()].sort((a, b) => a.id - b.id).slice(-CHAT_CAP), status: 'ready' };
      });
    } catch (e) {
      if (get().locationId === loc) set({ status: 'error', error: e instanceof Error ? e.message : 'Chat is not loading.' });
    }
  },
}));

function stop() {
  if (channel) void supabase.removeChannel(channel);
  channel = null;
}

/**
 * Keep the chat subscribed to the place the player is at (null while travelling / logged out).
 * Mounted once by the game screen so the HUD can show an unread dot while the sheet is closed.
 */
export function useChatLive(locationId: string | null, uid: string | null) {
  useEffect(() => {
    myId = uid;
    stop();
    useChat.setState({ locationId, messages: [], unread: 0, status: locationId ? 'loading' : 'idle', error: null });
    if (!locationId || !uid) return;
    channel = supabase
      .channel(`chat-${locationId}`)
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'chat_messages', filter: `location_id=eq.${locationId}` },
        (payload) => useChat.getState().add(payload.new as ChatMessage))
      .subscribe((status) => {
        // (re)load once the channel is live, so nothing falls in the gap; on a realtime failure still
        // show the recent messages (new ones then appear on the next open).
        if (status === 'SUBSCRIBED' || status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') void useChat.getState().reload();
      });
    return stop;
  }, [locationId, uid]);
}
