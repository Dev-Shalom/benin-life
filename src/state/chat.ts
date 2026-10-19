// V1-6 location chat — live state (docs/CHAT.md).
// One Realtime channel at a time: INSERTs on chat_messages filtered by `location_id=eq.<where you are>`
// (RLS also limits rows to your current place and drops players you blocked). The last messages are
// loaded once with chat_history(); after that only new rows arrive. No polling. The list is capped.
// M3: UPDATE events carry delete-for-everyone tombstones; scrolling up pages older rows (14 days max).
import { useEffect } from 'react';
import { create } from 'zustand';
import type { RealtimeChannel } from '@supabase/supabase-js';
import { migrateAvatar } from '../art/avatar3d';
import { chatHistory } from '../api/chat';
import { rpc } from '../lib/api';
import { supabase } from '../lib/supabase';
import { startPoller, trackSubscribe, usePollMode } from '../lib/realtime';
import type { AvatarConfig, ChatMessage } from '../lib/types';

/** Most messages kept in memory / rendered (older pages included). */
export const CHAT_CAP = 400;
const PAGE = 30;

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
  /** Apply a realtime UPDATE / delete-for-everyone result (tombstone, or drop when hidden). */
  patch: (row: Partial<ChatMessage> & { id: number }) => void;
  hasOlder: boolean;
  loadingOlder: boolean;
  loadOlder: () => Promise<void>;
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
  patch: (row) => set((s) => {
    if (row.hidden) return { messages: s.messages.filter((m) => m.id !== row.id) };
    if (!s.messages.some((m) => m.id === row.id)) return s;
    return {
      messages: s.messages.map((m) => {
        if (m.id === row.id) return { ...m, body: row.body ?? null, audio_path: row.audio_path ?? null, audio_mime: row.audio_mime ?? null, deleted_at: row.deleted_at ?? m.deleted_at ?? null };
        if (row.deleted_at && m.reply_to === row.id && m.reply) return { ...m, reply: { ...m.reply, deleted: true, snippet: null, voice: false } };
        return m;
      }),
    };
  }),
  hasOlder: false,
  loadingOlder: false,
  loadOlder: async () => {
    const { locationId: loc, messages, loadingOlder, hasOlder } = get();
    if (!loc || loadingOlder || !hasOlder || !messages.length) return;
    set({ loadingOlder: true });
    try {
      const rows = (await chatHistory(loc, messages[0].id, PAGE)) ?? [];
      if (get().locationId !== loc) return;
      set((s) => {
        const have = new Set(s.messages.map((m) => m.id));
        const older = rows.filter((r) => !have.has(r.id)).map(withAvatar);
        return { messages: [...older, ...s.messages].slice(0, CHAT_CAP), hasOlder: rows.length === PAGE && s.messages.length + older.length < CHAT_CAP };
      });
    } catch {
      /* keep what we have; the user can scroll again */
    } finally {
      if (get().locationId === loc) set({ loadingOlder: false });
    }
  },
  reload: async () => {
    const loc = get().locationId;
    if (!loc) return;
    set({ status: get().messages.length ? 'ready' : 'loading', error: null });
    try {
      const rows = await chatHistory(loc, null, PAGE);
      if (get().locationId !== loc) return;
      set((s) => {
        // keep any realtime rows that arrived while loading
        const byId = new Map<number, ChatMessage>();
        for (const r of rows ?? []) byId.set(r.id, withAvatar(r));
        for (const r of s.messages) if (!byId.has(r.id) && r.id > (rows?.[rows.length - 1]?.id ?? 0)) byId.set(r.id, r);
        return { messages: [...byId.values()].sort((a, b) => a.id - b.id).slice(-CHAT_CAP), status: 'ready', hasOlder: (rows?.length ?? 0) === PAGE };
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

/** F1 poll mode: chat poll period — panel open vs closed (unread dot only). */
const CHAT_POLL_OPEN_MS = 8_000;
const CHAT_POLL_CLOSED_MS = 60_000; // IO: 30 s -> 60 s (it only feeds the unread dot)
const CHAT_COLS = 'id,location_id,user_id,username,body,audio_path,audio_mime,created_at,reply_to,deleted_at';

/** F1 poll cursor: newest chat id known for the current place (null = not known yet). */
let chatCursor: number | null = null;

/** F1: rows newer than the newest one we hold (same shape as a Realtime INSERT; add() dedupes by id). */
async function fetchNewChat(loc: string) {
  const held = useChat.getState().messages.reduce((m, x) => Math.max(m, x.id), 0);
  if (chatCursor == null && !held) {
    // empty chat: learn the current top id once, so rows older than the 14-day history never pour in
    const { data, error } = await supabase.from('chat_messages').select('id').eq('location_id', loc).order('id', { ascending: false }).limit(1);
    if (error || useChat.getState().locationId !== loc) return;
    chatCursor = Number((data as { id: number }[] | null)?.[0]?.id ?? 0);
  }
  const after = Math.max(held, chatCursor ?? 0);
  const { data, error } = await supabase.from('chat_messages').select(CHAT_COLS).eq('location_id', loc).gt('id', after)
    .order('id', { ascending: true }).limit(50);
  if (error || useChat.getState().locationId !== loc) return;
  for (const r of (data ?? []) as ChatMessage[]) {
    chatCursor = Math.max(chatCursor ?? 0, r.id);
    useChat.getState().add(r);
  }
}

/**
 * Keep the chat subscribed to the place the player is at (null while travelling / logged out).
 * Mounted once by the game screen so the HUD can show an unread dot while the sheet is closed.
 * F1: in poll mode new rows are fetched every ~8 s while the chat is on screen, ~30 s otherwise.
 */
export function useChatLive(locationId: string | null, uid: string | null) {
  const poll = usePollMode();
  useEffect(() => {
    myId = uid;
    chatCursor = null;
    useChat.setState({ locationId, messages: [], unread: 0, status: locationId ? 'loading' : 'idle', error: null, hasOlder: false, loadingOlder: false });
  }, [locationId, uid]);
  useEffect(() => {
    stop();
    if (!locationId || !uid) return;
    if (poll) {
      void useChat.getState().reload();
      const p = startPoller(() => fetchNewChat(locationId), () => (useChat.getState().viewing ? CHAT_POLL_OPEN_MS : CHAT_POLL_CLOSED_MS));
      // the panel just opened: fetch now instead of waiting for the slow period
      const unsub = useChat.subscribe((s, prev) => { if (s.viewing && !prev.viewing) p.kick(150); });
      return () => { p.stop(); unsub(); };
    }
    channel = trackSubscribe(supabase
      .channel(`chat-${locationId}`)
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'chat_messages', filter: `location_id=eq.${locationId}` },
        (payload) => useChat.getState().add(payload.new as ChatMessage))
      .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'chat_messages', filter: `location_id=eq.${locationId}` },
        (payload) => useChat.getState().patch(payload.new as ChatMessage)),
    'chat', (status) => {
      // (re)load once the channel is live, so nothing falls in the gap (reload merges by id: no duplicates
      // after a poll period); on a realtime failure still show the recent messages.
      if (status === 'SUBSCRIBED' || status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') void useChat.getState().reload();
    });
    return stop;
  }, [locationId, uid, poll]);
}
