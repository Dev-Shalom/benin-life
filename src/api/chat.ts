// V1-6: typed wrappers for the chat RPCs (server: 20261005001000_chat.sql; M3 reply/delete/history: 20261010000300_chat_upgrade.sql).
import { rpc } from '../lib/api';
import type { BlockedPlayer, ChatMessage, ChatSendResult } from '../lib/types';

export const chatRecent = (location: string, limit = 30) => rpc<ChatMessage[]>('chat_recent', { p_location: location, p_limit: limit });
/** M3: paged history (oldest first), rows older than `before`, at most chat.history_days (14) back. */
export const chatHistory = (location: string, before: number | null = null, limit = 30) =>
  rpc<ChatMessage[]>('chat_history', { p_location: location, p_before: before, p_limit: limit });
export const chatSend = (body: string, replyTo: number | null = null) =>
  rpc<ChatSendResult>('chat_send', { p_body: body, p_reply_to: replyTo });
export const chatSendVoice = (path: string, mime: string, replyTo: number | null = null) =>
  rpc<ChatSendResult>('chat_send_voice', { p_audio_path: path, p_audio_mime: mime, p_reply_to: replyTo });
/** M3 delete. kind 'place' = place and house chat, 'dm' = private messages. */
export type ChatKind = 'place' | 'dm';
export const chatDeleteForMe = (kind: ChatKind, id: number) =>
  rpc<{ message: string; id: number }>('chat_delete_for_me', { p_kind: kind, p_message_id: id });
export const chatDeleteForEveryone = (kind: ChatKind, id: number) =>
  rpc<{ message: string; id: number; deleted_at: string; audio_path: string | null }>('chat_delete_for_everyone', { p_kind: kind, p_message_id: id });
export const chatReport = (id: number, reason: string) =>
  rpc<{ message: string; reports: number; hidden: boolean }>('chat_report', { p_message_id: id, p_reason: reason });
export const chatBlock = (user: string) => rpc<{ message: string; id: string; username: string }>('chat_block', { p_user: user });
export const chatUnblock = (user: string) => rpc<{ message: string; id: string }>('chat_unblock', { p_user: user });
export const chatBlocked = () => rpc<BlockedPlayer[]>('chat_blocked');
