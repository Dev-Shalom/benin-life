// Benin Gist (docs/GIST.md): typed wrappers for the gist_* RPCs (server: supabase/migrations/20261031000100_benin_gist.sql).
// The feed is paged by RPC with cursors; there is no "all posts" Realtime channel. The only Realtime a player ever opens is
// INSERT / UPDATE on gist_messages for the ONE group chat on screen.
import { GameError, rpc } from '../lib/api';
import { supabase } from '../lib/supabase';
import type { AvatarConfig, ReplyPreview } from '../lib/types';

export interface GistUser { id: string; username: string; avatar: AvatarConfig | null }

export interface GistPost {
  id: number;
  user: GistUser;
  body: string;
  photo_path: string | null;
  tags: string[];
  likes: number;
  comments: number;
  tips: number;
  tip_total: number;
  liked: boolean;
  mine: boolean;
  created_at: string;
}

export interface GistComment {
  id: number;
  post_id: number;
  parent_id: number | null;
  user: GistUser;
  body: string;
  reply_to_name?: string | null;
  mine: boolean;
  created_at: string;
  replies?: GistComment[];
}

export interface GistSummary {
  enabled: boolean;
  photos_enabled: boolean;
  photo_max_kb: number;
  post_max_len: number;
  comment_max_len: number;
  message_max_len: number;
  feed_page: number;
  group_cap: number;
  places: string[];
  can_post: boolean;
  why: string | null;
  why_hint: string | null;
  my_groups: number;
  unread_groups: number;
}

export interface FeedCursor { key: number | null; id: number }
export interface FeedPage { posts: GistPost[]; next: FeedCursor | null }
export type FeedView = 'foryou' | 'following' | 'new';

export interface GistProfile {
  id: string;
  username: string;
  avatar: AvatarConfig | null;
  me: boolean;
  posts: number;
  followers: number;
  following: number;
  i_follow: boolean;
  friend_status: 'none' | 'incoming' | 'outgoing' | 'friend' | 'blocked' | 'self';
  joined: string;
}

export interface GistGroup {
  id: number;
  name: string;
  emoji: string;
  description: string;
  is_public: boolean;
  system: boolean;
  owner_id: string | null;
  members: number;
  cap: number;
  hidden: boolean;
  last_msg_at: string | null;
  last_msg_user: string | null;
  last_msg_text: string | null;
  created_at: string;
  role: 'owner' | 'admin' | 'member' | null;
  muted_until: string | null;
  unread: number;
  joined?: boolean;
  pinned?: GroupMessage | null;
  can_manage?: boolean;
  is_owner?: boolean;
  banned?: boolean;
}

export interface GroupMember {
  id: string;
  username: string;
  avatar: AvatarConfig | null;
  role: 'owner' | 'admin' | 'member';
  muted_until: string | null;
  joined_at: string;
}

export interface GroupMessage {
  id: number;
  group_id: number;
  user_id: string;
  username: string;
  avatar: AvatarConfig | null;
  kind: 'text' | 'voice' | 'money' | 'system';
  body: string | null;
  audio_path: string | null;
  audio_mime: string | null;
  amount: number | null;
  to_user: string | null;
  to_username: string | null;
  reply_to: number | null;
  reply: ReplyPreview | null;
  created_at: string;
  deleted_at: string | null;
  mine: boolean;
}

type Msg = { message: string };

// ----- feed and posts
export const gistSummary = () => rpc<GistSummary>('gist_summary');
export const gistFeed = (view: FeedView, cursor: FeedCursor | null = null, tag: string | null = null, limit: number | null = null) =>
  rpc<FeedPage>('gist_feed', { p_view: view, p_key: cursor?.key ?? null, p_id: cursor?.id ?? null, p_limit: limit, p_tag: tag });
export const gistPostGet = (id: number) => rpc<GistPost>('gist_post_get', { p_id: id });
export const gistPost = (body: string, photoPath: string | null = null) => rpc<GistPost>('gist_post', { p_body: body, p_photo_path: photoPath });
export const gistDeletePost = (id: number) => rpc<Msg & { photo_path: string | null }>('gist_delete_post', { p_id: id });
export const gistLike = (id: number, like = true) => rpc<{ liked: boolean; likes: number; id: number }>('gist_like', { p_post: id, p_like: like });
export const gistFollow = (user: string, follow = true) => rpc<{ following: boolean; id: string }>('gist_follow', { p_user: user, p_follow: follow });
export const gistProfile = (user: string) => rpc<GistProfile>('gist_profile', { p_user: user });
export const gistUserPosts = (user: string, before: number | null = null) =>
  rpc<{ posts: GistPost[]; next: { id: number } | null }>('gist_user_posts', { p_user: user, p_before: before });
export const gistTrending = () => rpc<{ tag: string; n: number }[]>('gist_trending');
export const gistComment = (post: number, body: string, parent: number | null = null) =>
  rpc<{ comment: GistComment; comments: number }>('gist_comment', { p_post: post, p_body: body, p_parent: parent });
export const gistComments = (post: number, after = 0) =>
  rpc<{ comments: GistComment[]; has_more: boolean }>('gist_comments', { p_post: post, p_after: after, p_limit: 20 });
export const gistDeleteComment = (id: number) => rpc<Msg & { comments: number }>('gist_delete_comment', { p_id: id });
export const gistTipPost = (post: number, amount: number, note: string | null = null) =>
  rpc<{ message: string; amount: number; tips: number; tip_total: number; post_id: number }>('gist_tip_post', { p_post: post, p_amount: amount, p_note: note });
export type ReportKind = 'post' | 'comment' | 'group' | 'message';
export const gistReport = (kind: ReportKind, id: number, reason: string) =>
  rpc<Msg & { reports: number; hidden: boolean }>('gist_report', { p_kind: kind, p_id: id, p_reason: reason });

// ----- groups
export const gistGroupCreate = (name: string, emoji: string, description: string, isPublic: boolean) =>
  rpc<GistGroup>('gist_group_create', { p_name: name, p_emoji: emoji, p_description: description, p_public: isPublic });
export const gistGroupsMine = () => rpc<GistGroup[]>('gist_groups_mine');
export const gistGroupsDiscover = (query: string, sort: 'active' | 'new' | 'big', offset = 0) =>
  rpc<GistGroup[]>('gist_groups_discover', { p_query: query || null, p_sort: sort, p_offset: offset });
export const gistGroupGet = (id: number) => rpc<GistGroup>('gist_group_get', { p_group: id });
export const gistGroupJoin = (id: number) => rpc<GistGroup>('gist_group_join', { p_group: id });
export const gistGroupLeave = (id: number) => rpc<Msg>('gist_group_leave', { p_group: id });
export const gistGroupMembers = (id: number, offset = 0) => rpc<GroupMember[]>('gist_group_members', { p_group: id, p_offset: offset, p_limit: 50 });
export const gistGroupAdd = (id: number, username: string) => rpc<Msg>('gist_group_add', { p_group: id, p_username: username });
export const gistGroupRemove = (id: number, user: string) => rpc<Msg>('gist_group_remove', { p_group: id, p_user: user });
export const gistGroupSetRole = (id: number, user: string, role: 'admin' | 'member') => rpc<Msg>('gist_group_set_role', { p_group: id, p_user: user, p_role: role });
export const gistGroupMute = (id: number, user: string, minutes: number) => rpc<Msg & { muted_until: string | null }>('gist_group_mute', { p_group: id, p_user: user, p_minutes: minutes });
export const gistGroupPin = (id: number, message: number | null) => rpc<Msg>('gist_group_pin', { p_group: id, p_message: message });
export const gistGroupUpdate = (id: number, patch: { name?: string; emoji?: string; description?: string; isPublic?: boolean }) =>
  rpc<GistGroup>('gist_group_update', { p_group: id, p_name: patch.name ?? null, p_emoji: patch.emoji ?? null, p_description: patch.description ?? null, p_public: patch.isPublic ?? null });
export const gistGroupDelete = (id: number) => rpc<Msg>('gist_group_delete', { p_group: id });
export const gistGroupSend = (group: number, body: string | null, audioPath: string | null = null, audioMime: string | null = null, replyTo: number | null = null) =>
  rpc<GroupMessage>('gist_group_send', { p_group: group, p_body: body, p_audio_path: audioPath, p_audio_mime: audioMime, p_reply: replyTo });
export const gistGroupSendMoney = (group: number, username: string, amount: number, note: string | null) =>
  rpc<{ message: GroupMessage; transfer: { message: string } }>('gist_group_send_money', { p_group: group, p_username: username, p_amount: amount, p_note: note });
export const gistGroupHistory = (group: number, before: number | null = null, limit = 40) =>
  rpc<GroupMessage[]>('gist_group_history', { p_group: group, p_before: before, p_limit: limit });
export const gistGroupAfter = (group: number, after: number) => rpc<GroupMessage[]>('gist_group_after', { p_group: group, p_after: after });
export const gistGroupMarkRead = (group: number, upto: number | null = null) => rpc<{ read: number }>('gist_group_mark_read', { p_group: group, p_upto: upto });
export const gistGroupDeleteMessage = (id: number) =>
  rpc<Msg & { id: number; deleted_at: string; audio_path: string | null }>('gist_group_delete_message', { p_id: id });

// ----- files
const VOICE_EXT: Record<string, string> = { 'audio/webm': 'webm', 'audio/mp4': 'mp4', 'audio/ogg': 'ogg', 'audio/mpeg': 'mp3', 'audio/aac': 'aac', 'audio/wav': 'wav' };

/** player-voice/group/<group>/<me>/<uuid>.<ext>: the storage policy lets only members of that group upload and play it. */
export async function uploadGroupVoice(group: number, me: string, blob: Blob, rawMime: string) {
  const mime = rawMime.toLowerCase().split(';')[0];
  const ext = VOICE_EXT[mime];
  if (!ext) throw new GameError('This device recorded an unsupported voice format. Please try a browser that supports audio/webm or audio/mp4.', 'unsupported_audio');
  const path = `group/${group}/${me}/${crypto.randomUUID()}.${ext}`;
  const { error } = await supabase.storage.from('player-voice').upload(path, blob, { contentType: mime, upsert: false });
  if (error) throw new GameError('Voice note upload failed. Check your connection and try again.', error.statusCode ?? undefined);
  return { path, mime };
}

/** gist-photos/<me>/<uuid>.jpg (public bucket, 512 KB cap, images only). */
export async function uploadGistPhoto(me: string, blob: Blob) {
  const type = blob.type === 'image/webp' || blob.type === 'image/png' ? blob.type : 'image/jpeg';
  const ext = type === 'image/webp' ? 'webp' : type === 'image/png' ? 'png' : 'jpg';
  const path = `${me}/${crypto.randomUUID()}.${ext}`;
  const { error } = await supabase.storage.from('gist-photos').upload(path, blob, { contentType: type, upsert: false, cacheControl: '31536000' });
  if (error) throw new GameError(/size|large|limit|413/i.test(error.message) ? 'That photo is too big.' : 'Photo upload failed. Check your connection and try again.', error.statusCode ?? undefined);
  return path;
}

export async function discardGistPhoto(path: string) {
  await supabase.storage.from('gist-photos').remove([path]);
}

export function gistPhotoUrl(path: string) {
  return supabase.storage.from('gist-photos').getPublicUrl(path).data.publicUrl;
}
