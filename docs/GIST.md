# Benin Gist

One phone app where everyone in Benin Life can post, like, comment, tip and chat in groups. **Messages is its own app again** (26 Oct 2026, players asked for it back): Messages has Chats, Groups and Friends; Benin Gist has Feed and Groups. Both are `SocialApp.tsx` with `mode='messages' | 'gist'`. `gist:chats` and `gist:friends` links open Messages.

- Server: `supabase/migrations/20261031000100_benin_gist.sql`, links to profiles: `20261031000200_gist_links.sql`
- Tests: `supabase/tests/gist_test.sql` (18 groups)
- Client: `src/api/gist.ts`, `src/state/gist.ts`, `src/lib/image.ts`, `src/screens/game/phone/SocialApp.tsx` (the shell), `src/screens/game/phone/gist/` (`GistFeed`, `GistGroups`, `GroupChat`, `gistKit`, `gist.css`), `src/admin/Gist.tsx`
- Reused: `chatKit` bubbles (a money bubble and a sender name were added), `tip_player`, `bank_transfer`, `chat_blocks`, `profiles.chat_muted_until`, `bl_chat_clean` / `bl_chat_mask`, `bl_push_enqueue`, `events`, the `player-voice` bucket.

## The app: four tabs
| Tab | What |
|---|---|
| Feed | Gists (text, optional photo). **For you** or **Following** (friends + people you follow + you). Tap a `#tag` or a place chip to filter. Like, comment (one level of replies), tip, report, delete your own. Tap a name: profile with their gists, Follow, Add friend / Message, Send money. |
| Groups | The place or house chat ("chat where you are"), My groups (unread counts), Discover (search, Active / New / Biggest), create a group. |
| Chats | The M4 DMs, as before (streaks, Send money chip, requests). |
| Friends | R7 friends and requests, as before. |

The phone app id is now `gist`. `messages` is an alias, and `go=dm:<id>`, `go=house`, `go=friends` still work. New links: `go=gist`, `go=gist:post:<id>`, `go=gist:group:<id>`, `go=gist:feed|groups|chats|friends`.

## Rules (defaults, all admin settings under Settings -> Benin Gist)
| Setting | Default |
|---|---|
| `gist.enabled` master switch | on |
| `gist.photos_enabled` | **off** (Storage cost; turn on when ready) |
| `gist.photo_max_kb` | 300 (bucket hard cap 512 KB, JPEG / PNG / WebP only; the phone shrinks to 1080 px first) |
| `gist.post_max_len` / `comment_max_len` / `message_max_len` | 280 / 200 / 500 |
| `gist.min_account_minutes` (age to write; reading is always allowed) | 30 |
| `gist.posts_per_hour` | 6 |
| `gist.comments_per_minute` | 6 |
| `gist.likes_per_minute` | 40 |
| `gist.group_messages_per_minute` | 20 |
| `gist.groups_per_day` | 3 |
| `gist.group_member_cap` | 200 (a starter group can have its own cap; "Benin Gist General" is 500) |
| `gist.max_groups_joined` / `max_follows` | 50 / 500 |
| `gist.add_friends_only` (admins add only friends) | on |
| `gist.feed_page` | 20 |
| `gist.hot_half_life_hours`, `like_weight`, `comment_weight` | 12, 1, 3 |
| `gist.group_half_life_hours` (Discover "active") | 12 |
| `gist.report_hide_count` | 3 |
| `gist.post_keep_days` / `message_keep_days` | 60 / 30 |
| `gist.notify_window_minutes` | 30 |
| `gist.places` | real Benin places (Ring Road, Ugbowo, GRA, Oba Market, ...) |

A muted player (`chat_muted_until`) or one banned from Gist can read but not write. Bad words are masked like chat. A blocked pair never sees each other's gists, comments or group messages, and cannot tip or send money to each other.

## For you ranking (server)
`rank_key = round(1e6 * (ln(1 + likes*w1 + comments*w2) + created_epoch_hours * ln2 / half_life))`, stored on the post and updated when it is liked or commented. Because the time term does not depend on "now", ordering by `rank_key` equals ordering by "score with time decay", so one index (`rank_key desc, id desc`) serves the whole feed and paging uses a (key, id) cursor. Changing the half-life only affects new activity.

## Groups
- Public (anyone joins from Discover) or private (owner / admins add friends). Name, emoji, description.
- Roles: owner, admin, member. Owner/admin: add, remove (the person cannot rejoin by themselves; adding lifts it), mute for a time, pin a message, edit. Only the owner makes admins, flips public/private, deletes. A game admin counts as admin everywhere.
- Messages: text, voice notes (file in `player-voice/group/<group>/<me>/...`, readable only by members), reply, delete for everyone (author in `chat.delete_everyone_hours`, or a group admin), report. Unread = a cached `last_msg_id` against your read pointer (no scan).
- **Send money** in a group: pick a member, amount, note. It calls `bank_transfer` (fee, limits, cooldown, new-account wait all apply). If it succeeds a gold **money bubble** is posted. If not, nothing is posted. Money bubbles stay as a receipt.
- Five official starter groups: Benin Gist General, UNIBEN Students, Ring Road Hustlers, Owambe & Clubs, Buy & Sell (names and caps editable in Admin -> Gist -> Groups).

## Scale and bandwidth (read docs/SCALING.md, docs/DISK_IO.md first)
- **No global Realtime.** The feed is RPC-paged (20 per page, pull to refresh, load more). Only `gist_messages` is in the Realtime publication, and a client subscribes to **one channel for the one group it has open** (INSERT + UPDATE, filter `group_id`). RLS: members only, blocked pairs hidden. In poll mode (F1) it polls `gist_group_after` every ~10 s while open.
- The app badge uses `gist_summary()` on a slow poll (180 s, visible tab, not AFK) and right after a gist alert. It reads cached columns only.
- Cached counts on rows (likes, comments, tips, members, last message). Trending tags are cached 10 minutes for everybody. Indexes: feed rank, feed by id, per user, GIN on tags, comments by post, group discover / new / big, messages by group.
- Housekeeping is lazy (once per 30 minutes, small batches): old gists, old messages, stale alert rows, empty groups.
- Photo files of deleted or expired gists stay in Storage until Admin -> Gist -> Photo clean-up removes them.

## Notifications
Every gist alert is an `events` row (kinds `gist_like`, `gist_comment`, `gist_reply`, `gist_mention`, `gist_group_add`, `gist_group_reply`) and a push through `bl_push_enqueue` (so master switch, category switch, hourly cap, "skip if the player is active" and per-chat folding all apply; there are no quiet hours in the push system).
- **Batched:** many likes / comments on one gist inside `gist.notify_window_minutes` update ONE alert ("5 people liked your gist"); the pending push folds the same way.
- Likes go to the **Game events** push category (off by default for players), comments / replies / mentions / group replies to **Messages**, "added you to a group" to **Friends**. A tip arrives as the normal **Money** push.
- Plain group messages never alert anyone. Replies to you and @mentions do.

## Moderation (Admin -> Gist)
Reports of gists, comments, groups and group messages, grouped by target with a preview. Hide / unhide, delete, dismiss, **Ban author 24 h** (and hide their gists), a Bans list, Groups (rename, icon, description, cap, hide, delete), Photo clean-up. Everything is written to the audit log. Auto-hide: a gist, comment or message is hidden at `gist.report_hide_count` different reporters; a group is only hidden by an admin.

## Safety notes
No foreign key to `profiles` in the big migration. The FKs (cascade delete of a player's gist rows; a group just loses its owner) are in the small `gist_links` migration, which takes the profiles lock with retries. All tables have RLS and no client grants; the only direct read is `gist_messages` (members). Storage policies call small security-definer helpers (`gist_file_used`, `gist_is_member`, `gist_is_admin`) because players cannot read those tables.

## Not built
Reposts, photos in groups, per-message read ticks in groups (unread counts and a read pointer only), comment likes, quiet hours.
