// R7 Friends tab (docs/LOUNGE.md "Friends"). ONE read, friends_overview(), returns everything the tab shows; the tab polls it only
// while it is open. Actions reuse the social_* RPCs (add, accept, message, house invite) plus the three new ones below.
import { rpc } from '../lib/api';
import type { AvatarConfig } from '../lib/types';

export interface FriendLocation {
  /** Null for "At home" and "On the road" (no place to travel to). */
  id: string | null;
  name: string;
  district?: string;
  scene?: string;
  open?: boolean;
  private?: boolean;
  traveling?: boolean;
}

export interface FriendCard {
  id: string;
  username: string;
  /** R11: crew tag, colour and emblem. */
  crew?: { tag: string; color: string; emblem: string } | null;
  /** R12: office title (Hon., Gov. ...). */
  title?: string | null;
  avatar: AvatarConfig | null;
  online: boolean;
  last_seen: string | null;
  location: FriendLocation | null;
  /** The friend turned "Show my location to friends" off (only set while they are online). */
  location_hidden: boolean;
  can_join: boolean;
  /** Why not: offline | hidden | travelling | private | inactive | closed | same | no_membership | nowhere. */
  join_hint: string | null;
  join_reason: string | null;
  join_to: string | null;
  yahoo_ready: boolean;
  house_invite: 'invited' | 'knocking' | null;
  conversation_id: number | null;
  unread: number;
  at_home: boolean;
}

export interface FriendsRequest {
  id: string;
  username: string;
  avatar: AvatarConfig | null;
  direction: 'incoming' | 'outgoing';
  created_at: string;
}

export interface FriendsOverview {
  me: {
    share_location: boolean;
    home_chosen: boolean;
    place: { id: string | null; name: string | null; scene: string | null; can_invite: boolean; reason: string | null };
    lounge_guest_slots: number;
    lounge_guests_active: number;
  };
  online_seconds: number;
  poll_seconds: number;
  requests: FriendsRequest[];
  friends: FriendCard[];
}

export const friendsOverview = () => rpc<FriendsOverview>('friends_overview');
export const friendsSetPrivacy = (show: boolean) => rpc<{ share_location: boolean; message: string }>('friends_set_privacy', { p_show: show });
export const friendJoinCheck = (friend: string) => rpc<{ dest: string; name: string }>('friend_join_check', { p_friend: friend });
export const friendInvitePlace = (friend: string) => rpc<{ message: string; place: string }>('friend_invite_place', { p_friend: friend });

/** "last seen 3h ago" */
export function lastSeenLabel(iso: string | null | undefined, now = Date.now()): string {
  if (!iso) return 'a while ago';
  const s = Math.max(0, Math.round((now - Date.parse(iso)) / 1000));
  if (!Number.isFinite(s)) return 'a while ago';
  if (s < 60) return 'just now';
  if (s < 3600) return `${Math.floor(s / 60)}m ago`;
  if (s < 86400) return `${Math.floor(s / 3600)}h ago`;
  return `${Math.floor(s / 86400)}d ago`;
}
