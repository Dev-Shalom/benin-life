// V1-6: typed wrappers for the chat RPCs (server: 20261005001000_chat.sql).
import { rpc } from '../lib/api';
import type { BlockedPlayer, ChatMessage, ChatSendResult } from '../lib/types';

export const chatRecent = (location: string, limit = 30) => rpc<ChatMessage[]>('chat_recent', { p_location: location, p_limit: limit });
export const chatSend = (body: string) => rpc<ChatSendResult>('chat_send', { p_body: body });
export const chatSendVoice = (path: string, mime: string) => rpc<ChatSendResult>('chat_send_voice', { p_audio_path: path, p_audio_mime: mime });
export const chatReport = (id: number, reason: string) =>
  rpc<{ message: string; reports: number; hidden: boolean }>('chat_report', { p_message_id: id, p_reason: reason });
export const chatBlock = (user: string) => rpc<{ message: string; id: string; username: string }>('chat_block', { p_user: user });
export const chatUnblock = (user: string) => rpc<{ message: string; id: string }>('chat_unblock', { p_user: user });
export const chatBlocked = () => rpc<BlockedPlayer[]>('chat_blocked');
