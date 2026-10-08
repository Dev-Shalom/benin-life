import { rpc, GameError } from '../lib/api';
import { supabase } from '../lib/supabase';
import type { AvatarConfig } from '../lib/types';

export type FriendStatus = 'none' | 'incoming' | 'outgoing' | 'friend' | 'blocked' | 'self';

export interface SocialPlayer {
  id: string;
  username: string;
  avatar: AvatarConfig | null;
}

export interface SocialFriend extends SocialPlayer {
  at_home: boolean;
  last_seen: string;
  conversation_id: number | null;
  last_message: string | null;
  last_message_at: string | null;
  last_sender_id: string | null;
  unread: number;
}

export interface FriendRequest extends SocialPlayer {
  direction: 'incoming' | 'outgoing';
  created_at: string;
}

export interface HouseInvite {
  id: number;
  host_id: string;
  guest_id: string;
  host_username: string;
  guest_username: string;
  home_name: string;
  status: 'invited' | 'knocking';
  created_at: string;
  expires_at: string;
  role: 'host' | 'guest';
}

export interface DirectMessage {
  id: number;
  conversation_id: number;
  sender_id: string;
  sender_username: string;
  body: string | null;
  audio_path: string | null;
  audio_mime: string | null;
  created_at: string;
  read_at: string | null;
  mine: boolean;
}

export interface HouseInfo {
  owner_id: string;
  username: string;
  housing_id: string;
  origin: 'lapo' | 'nepo';
  home_location_id: string;
}

export interface HouseFurniturePlacement {
  owner_id: string;
  furniture_key: string;
  x: number;
  z: number;
  rotation: number;
}

type Result = { message: string; status?: string };

export const socialSearchPlayers = (query: string) => rpc<SocialPlayer[]>('social_search_players', { p_query: query });
export const socialFriendStatus = (user: string) => rpc<FriendStatus>('social_friend_status', { p_user: user });
export const socialAddFriend = (user: string) => rpc<Result>('social_add_friend', { p_user: user });
export const socialFriendRequests = () => rpc<FriendRequest[]>('social_friend_requests');
export const socialRespondFriend = (user: string, accept: boolean) => rpc<Result>('social_respond_friend', { p_user: user, p_accept: accept });
export const socialCancelFriendRequest = (user: string) => rpc<Result>('social_cancel_friend_request', { p_user: user });
export const socialFriends = () => rpc<SocialFriend[]>('social_friends');
export const socialRemoveFriend = (user: string) => rpc<Result>('social_remove_friend', { p_user: user });
export const socialOpenConversation = (user: string) => rpc<{ id: number; friend_id: string }>('social_open_conversation', { p_user: user });
export const socialMessageHistory = (conversation: number, before: number | null = null, limit = 50) =>
  rpc<DirectMessage[]>('social_message_history', { p_conversation_id: conversation, p_before: before, p_limit: limit });
export const socialMarkRead = (conversation: number) => rpc<{ read: number }>('social_mark_messages_read', { p_conversation_id: conversation });
export const socialSendMessage = (conversation: number, body: string | null, path: string | null = null, mime: string | null = null) =>
  rpc<DirectMessage>('social_send_message', { p_conversation_id: conversation, p_body: body, p_audio_path: path, p_audio_mime: mime });
export const socialSendHouseInvite = (user: string) => rpc<{ id: number; status: string; message: string }>('social_send_house_invite', { p_user: user });
export const socialHouseInvites = () => rpc<HouseInvite[]>('social_house_invites');
export const socialRespondHouseInvite = (id: number, accept: boolean) =>
  rpc<{ id: number; status: string; message: string }>('social_respond_house_invite', { p_invite_id: id, p_accept: accept });
export const socialCancelHouseInvite = (id: number) => rpc<Result>('social_cancel_house_invite', { p_invite_id: id });
export const socialHomeAdmit = (id: number, admit = true) =>
  rpc<{ id: number; status: string; message: string }>('social_home_admit', { p_invite_id: id, p_admit: admit });
export const socialHouseInfo = () => rpc<HouseInfo>('social_house_info');
export const socialHomePlaceFurniture = (key: string, x: number, z: number, rotation: number) =>
  rpc<HouseFurniturePlacement>('social_home_place_furniture', { p_furniture_key: key, p_x: x, p_z: z, p_rotation: rotation });
export const socialHomeOffer = (guest: string, item: string) => rpc<Result>('social_home_offer', { p_guest: guest, p_item: item });

export async function uploadHouseVoiceMessage(location: string, sender: string, blob: Blob, rawMime: string) {
  const mime = rawMime.toLowerCase().split(';')[0];
  const ext = MIME_EXT[mime];
  if (!ext) throw new GameError('This device recorded an unsupported voice format. Please try a browser that supports audio/webm or audio/mp4.', 'unsupported_audio');
  const path = `chat/${location}/${sender}/${crypto.randomUUID()}.${ext}`;
  const { error } = await supabase.storage.from('player-voice').upload(path, blob, { contentType: mime, upsert: false });
  if (error) {
    const tooLarge = /size|large|limit|413/i.test(error.message);
    throw new GameError(tooLarge ? 'This voice note is larger than your storage plan allows.' : 'Voice note upload failed. Check your connection and try again.', error.statusCode ?? undefined);
  }
  return { path, mime };
}

const MIME_EXT: Record<string, string> = {
  'audio/webm': 'webm', 'audio/mp4': 'mp4', 'audio/ogg': 'ogg',
  'audio/mpeg': 'mp3', 'audio/aac': 'aac', 'audio/wav': 'wav',
};

export async function uploadVoiceMessage(conversation: number, sender: string, blob: Blob, rawMime: string) {
  const mime = rawMime.toLowerCase().split(';')[0];
  const ext = MIME_EXT[mime];
  if (!ext) throw new GameError('This device recorded an unsupported voice format. Please try a browser that supports audio/webm or audio/mp4.', 'unsupported_audio');
  const path = `${conversation}/${sender}/${crypto.randomUUID()}.${ext}`;
  const { error } = await supabase.storage.from('player-voice').upload(path, blob, { contentType: mime, upsert: false });
  if (error) {
    const tooLarge = /size|large|limit|413/i.test(error.message);
    throw new GameError(tooLarge
      ? 'This voice note is larger than your storage plan allows. Please record a shorter note.'
      : 'Voice note upload failed. Check your connection and try again.', error.statusCode ?? undefined);
  }
  return { path, mime };
}

export async function discardVoiceUpload(path: string) {
  await supabase.storage.from('player-voice').remove([path]);
}

export async function socialVoiceUrl(path: string) {
  const { data, error } = await supabase.storage.from('player-voice').createSignedUrl(path, 3600);
  if (error || !data?.signedUrl) throw new GameError('Could not load this voice note. Reopen the conversation and try again.', error?.statusCode ?? undefined);
  return data.signedUrl;
}
