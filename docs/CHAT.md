# Chat (V1-6)

Each location has its own chat room. There is no global chat: Lagos Life's global chat ran out of bandwidth at about 50k players online. Accepted friends can also use private direct messages and voice notes in the phone's Messages app. Admitted visitors and the owner share the private home's room chat. See [SOCIAL.md](SOCIAL.md) for friend requests, private homes, knocks, live visits, and shared furniture.

- **Server:** `supabase/migrations/20261005001000_chat.sql`; M3 reply / delete / history: `20261010000300_chat_upgrade.sql`
- **Tests:** `supabase/tests/chat_test.sql`, `supabase/tests/chat_upgrade_test.sql`
- **Client:**
  - `src/api/chat.ts` (RPC wrappers)
  - `src/state/chat.ts` (live state and subscription)
  - `src/panels/ChatPanel.tsx` (the Chat tab, also house chat)
  - `src/panels/chatKit.tsx` (M3: bubble, swipe to reply, quote, menu, reply bar, paging and keyboard helpers shared with DMs)
  - the HUD chat chip in `src/screens/Game.tsx`
  - the Friends and Messages app in `src/screens/game/phone/SocialApp.tsx`
  - the blocked list in `src/screens/game/SimSheet.tsx` (People tab)

## Rules
- You can only read and write in the chat of the place you are at.
  - While travelling you can't send, and `chat_recent` refuses.
  - Being busy, jailed or in hospital doesn't stop chat.
- You can't send if any of these is true:
  - you are banned;
  - you are muted (`profiles.chat_muted_until`; an admin sets it in V1-7);
  - chat is switched off (`chat.enabled`);
  - your Sim is younger than `chat.min_account_real_minutes` (default `0`, so new Sims can join the conversation immediately; admins can raise it).
- Cleaning, in order:
  1. Trim the message.
  2. Turn newlines and tabs into spaces.
  3. Strip control and zero-width characters.
  4. Squeeze repeated spaces.
  5. Refuse an empty message. Text length is not capped by the app.
- Rate limits, all on real time:
  - a wait of `chat.rate_seconds` between messages;
  - at most `chat.burst_per_minute` messages per minute;
  - the same text again within `chat.duplicate_window_seconds` is refused (case and punctuation are ignored).
- **Profanity filter:** the `chat_banned_words` table (admin-editable; `active=false` switches a word off).
  - A word is matched as a whole word, in any case, with common endings (s, es, ed, er, ers, ing, in, y, ty, ted).
  - A match is replaced by asterisks.
  - It is seeded with a short English list plus Nigerian Pidgin and Yoruba street insults (ashawo, olosho, oloshi, werey, toto, gbola…).
  - The stored message is the masked one. The sender sees "Some words were hidden".
- **Report:** `chat_report(id, reason)`.
  - Counts one report per player per message, and you can't report your own message.
  - After `chat.report_hide_count` different reporters (default 3), the message gets `hidden=true`.
  - The reporter's client drops the message right away.
- **Block:** `chat_block(user)` and `chat_unblock(user)`.
  - A block is one-way, and a player can block at most `chat.max_blocks` people.
  - Blocked players' messages are filtered on the server (RLS and `chat_recent`), so realtime never delivers them.
  - The Sim sheet's People tab lists blocked players with an Unblock button.
- **Retention:** each `chat_send` deletes up to 200 messages older than `chat.retention_hours` (336 = 14 days since M3; it was 48 and the migration only moves it when it was still 48). Reports, replies' `reply_to` (set null) and delete-for-me rows cascade. No cron job is needed. DMs are not deleted by this; their history view stops at 14 days.
- **Admin:**
  - `admin_chat_hide(id, hidden default true)` is guarded by `bl_is_admin()` and logged in `admin_audit` (`chat_hide`/`chat_unhide`).
  - The V1-7 admin page can also mute (`chat_muted_until`) and edit `chat_banned_words`.

## Config (category `chat`)
| key | default |
|---|---|
| chat.enabled | true |
| chat.rate_seconds | 3 |
| chat.burst_per_minute | 8 |
| chat.duplicate_window_seconds | 120 |
| chat.min_account_real_minutes | 0 |
| chat.recent_limit | 30 |
| chat.report_hide_count | 3 |
| chat.retention_hours | 336 (14 days; was 48) |
| chat.max_blocks | 200 |
| chat.delete_everyone_hours | 48 (M3: window for "Delete for everyone", 0–720) |
| chat.history_days | 14 (M3: how far scrolling up goes, 1–14, hard cap 14) |

## RPCs
| RPC | Args | Returns |
|---|---|---|
| `chat_send` | p_body, p_reply_to | message row + `{message, masked}` (hints: chat_off, muted, traveling, too_new, empty, too_fast, duplicate, banned, no_home) |
| `chat_send_voice` | p_audio_path, p_audio_mime, p_reply_to | location or private-home voice message row; guarded by chat, travel, mute, rate, and room access rules |
| `chat_recent` | p_location, p_limit | last `min(p_limit, chat.recent_limit)` visible rows at your current place, oldest first, with `avatar` and `mine` (hint not_here) |
| `chat_history` | p_location, p_before, p_limit | M3: rows older than `p_before` (null = newest), oldest first, max 60, at most `chat.history_days` back; drops hidden, blocked and deleted-for-me rows (hint not_here). The client uses this instead of `chat_recent` |
| `chat_delete_for_me` | p_kind ('place' or 'dm'), p_message_id | `{message, id}`; adds a row to `chat_hidden_messages` |
| `chat_delete_for_everyone` | p_kind, p_message_id | `{message, id, deleted_at, audio_path}`; author only (hint not_author), within `chat.delete_everyone_hours` (hint too_late) |
| `chat_report` | p_message_id, p_reason | `{message, reports, hidden}` |
| `chat_block` / `chat_unblock` | p_user | `{message, id, username?}` |
| `chat_blocked` | – | `[{id, username, avatar, created_at}]` |
| `admin_chat_hide` | p_message_id, p_hidden | `{message, id, hidden}` |

The chat guard `bl_chat_me()` locks the caller's profile row with `FOR UPDATE` but **writes nothing**. If it wrote, every message would set off a profile realtime event and a `get_my_state` refresh for the sender. It also skips the needs decay and the rent charge.

## Tables
- `chat_messages` (id, location_id, user_id, username snapshot, body, audio_path, audio_mime, created_at, hidden, reply_to, deleted_at)
- `chat_hidden_messages` (M3 delete for me: user_id + chat_message_id or player_message_id; clients read only their own rows)
- `chat_reports` (message_id, reporter_id, reason; unique per pair)
- `chat_blocks` (blocker_id, blocked_id)
- `chat_banned_words` (word, active)

Clients get select only on `chat_messages` and on their own `chat_blocks` rows. There are no insert, update or delete grants. `chat_reports` and `chat_banned_words` are server-only.

## RLS and realtime (bandwidth)
- **Policy `chat_messages_here`:** a row is visible when all of these hold:
  - it is `not hidden`;
  - `location_id` = the caller's `profiles.location_id`;
  - its author isn't blocked by the caller.
- **The client subscribes to INSERT only**, with `filter: location_id=eq.<current place>`.
  - There is a single channel (`chat-<location>`), owned by `useChatLive()` on the game screen.
  - The channel is replaced when the player arrives somewhere else, and dropped while travelling.
- **Realtime checks the same policy for each subscriber.** So a player who forged a filter for another place still gets nothing.
- **Data cost:**
  - Each message reaches only the players at that place, as one row of about 300 bytes. There is no polling.
  - On opening, the client loads `chat_recent` once (30 rows), after the channel is subscribed so nothing falls in the gap.
  - The list in memory is capped at 60.
  - Avatars: `chat_recent` rows include them. A realtime row from someone new triggers one `get_public_profile` call per sender, and the result is cached.
- **Hidden messages:** a message hidden by reports or an admin stops passing RLS, so no event reaches others; it disappears the next time they open the chat.
- **M3 tombstones:** the client also subscribes to UPDATE on the same filter. "Delete for everyone" clears body and audio and sets `deleted_at`; that UPDATE reaches everyone in the room, who see "This message was deleted" at once. Updates are rare (only deletes), so the cost stays small.
- **Scaling later:** if one place ever gets very busy, RLS checks per subscriber grow with the crowd. Two options:
  - switch to Realtime Broadcast from the database (`realtime.broadcast_changes` on a `chat:<location>` topic, private channels);
  - shard a busy place into rooms.
  - The RPC surface stays the same either way.

## UI
- **Location sheet:** the Chat tab is always the last tab at every place. No `chat` action is needed in `locations.actions`.
  - It shows each message's avatar portrait, name, time and text.
  - Your own bubbles are green and on the right.
  - Tapping someone's message (or its ⋯ button) opens Report (with a reason) or Block @name.
  - The text/voice composer has no app character counter. When text is present, the microphone control becomes Send; when empty, it starts voice recording. Playback uses a custom player with speed choices and no visible download control.
  - Server errors appear inline.
  - Note at the top: "Be respectful — 18+ only".
- **Unread:** messages from others that arrive while the Chat tab isn't on screen count as unread. The count shows on:
  - a small "N new in chat" chip above the "You're at" chip (it opens the sheet on Chat);
  - the Chat tab's badge;
  - the Messages app icon on the phone.
- **Phone → Messages:** a "Chat at <place>" button ("Chat with your neighbours" at home). This opens the same live, place-based chat; private one-to-one messages are not part of this feature.
- **NPC conversations (2026-10-08, pushed in `247d1b4`):** tapping a named NPC in the 3D place or People list opens short scripted reply choices. This is separate from location chat and does not persist a relationship. Private player-to-player chat is in Phone → Messages; see `docs/SOCIAL.md`.

## M3 messaging upgrade (2026-10-10)
Applies to place chat, house chat and DMs (same `chatKit` UI).
- **Layout:** mine on the right (green), others on the left with their face; every bubble shows the name and time, and a day pill separates days. In the location sheet the composer is sticky at the bottom of the sheet with the safe-area padding. In the phone it sits above the phone's home bar. `useViewportVars()` publishes `--vvh` / `--kb` from `visualViewport` while a chat is open; sheets and the phone shrink and lift with the on-screen keyboard (100dvh does not).
- **History:** scrolling near the top loads the next 30 (place) / 50 (DM) older rows and keeps the reading position; it stops at `chat.history_days` (14). The list in memory is capped at 400.
- **Reply:** swipe a bubble right (touch, about 56 px, light haptic), press **r**, use the hover ↩ (desktop), or choose Reply in the menu. The composer shows "Replying to …" with ×, and Escape clears it. The row stores `reply_to`. Server rows carry `reply` = {id, username, snippet, voice, deleted, unavailable}. Live rows are matched against the loaded list. Tapping the quote scrolls to the original and flashes it, loading older pages if needed.
- **Menu:** long-press (touch), right-click, Enter on a focused bubble, or the hover ⋯ open a sheet over the thread with Reply, Copy text, Delete for me, Delete for everyone (own messages within `chat.delete_everyone_hours`), Report… and Block (place chat, others' messages).
- **Delete for everyone:** server tombstone (body and audio cleared, `deleted_at`). The client then removes the voice file through Storage, because the orphan-cleanup policy allows it once nothing references the path; direct deletes on `storage.objects` are blocked. You can't reply to a deleted message, and quotes of it read "This message was deleted". Admin hide and mute are unchanged.

## M4 Messages redesign (2026-10-10)
Phone → Messages now follows the reference screenshots (docs/references/lagos-life/messages-*.jpg), with Benin Life branding. Code: `src/screens/game/phone/SocialApp.tsx` (list), `src/screens/game/phone/DmConversation.tsx` (conversation), DM look in `src/panels/chatKit.tsx` (`MessageRow dm receipt`), styles under "M4" in `src/styles/game.css`. The app draws its own header (the phone's app bar is hidden for Messages).
- **List:** big "Messages" title, back arrow, bell with the alerts badge (opens Alerts). Tabs **Chats** (badge = chats with unread) / **Groups** (the chat of where you are: House chat at home or when visiting, else "Chat at <place>"; opens the existing ChatPanel). Pinned **Benin Life team** card from `news.latest_title` / `news.latest_body` (tap = sheet with the body). **Message someone: @username**: an exact friend match opens the DM; otherwise it searches players and shows Message (friend) or the friend button (Add friend / Accept / Requested). Filters **All / Unread (n) / Read** and ⋯ → Mark all read. **Message requests** row → incoming friend requests (Accept / Decline), door knocks and house invites (Let in / Knock), and your outgoing requests / invites (Cancel). **Search your chats** filters by name or last text. Rows: portrait, @name, preview ("You: …", "Voice note", "This message was deleted", "@x sent you ₦…"), date (time today / Yesterday / "6 Oct", red when unread), red unread count.
- **Conversation:** back, big @name, ⋯ (Unfriend / Block). "🔒 Private · only you and @name can see this". **Streak card** ("🔥 Start a streak" / "🔥 N-day streak", status line, **What counts?** sheet). Chips: **🏠 Invite** (sends a house invite; shows Invited, or Let in / At your door when they knock), **🚪 Visit** (Knock when they invited you, Knocking… while waiting, otherwise sends "Can I come and visit? 🚪" to ask for an invite; there is no knock without an invite), **💸 Send money** (sheet with amount + note; calls `bank_transfer` with its fee, daily limit and the 24 h new-account wait shown on the button; server errors toast; on success a DM "💸 Sent you ₦X" is sent so both sides see it).
- **Thread:** day separators ("Mon 5 Oct", en-GB), a red **New messages** divider above the first message that was unread when the chat opened (kept after the read receipt lands). Theirs light grey left, mine blue (#2F7BE5) right with white text; time (24 h) inside the bubble bottom-right; mine show ✓ sent, ✓✓ delivered (friend's `last_seen` is after the message), ✓✓ light-blue when `read_at` is set (live via the Realtime UPDATE). All M3 features remain (swipe / hover reply with quote, long-press menu, delete for me / everyone, 14-day paging, voice notes).
- **Composer:** horizontally scrolling quick replies ("How far? 👋", "I dey o 😄", "Wetin dey happen?", "Where you dey?", "Come my house 🏠", "LOL 😂", "On my way 🚶🏾", "Thank you o 🙏🏾"; the order rotates per chat/day and after each use; tap sends), emoji button with a 30-emoji popover (inserts at the cursor), rounded "Message @name…" field, green mic / send. Sits above the phone's home bar.
- **Server (`20261010000500_messages_v2.sql`, tests `messages_v2_test.sql`):** `social_streak_days` (pair, WAT day, a_active, b_active; RLS on, no client grants) filled by triggers: a message marks the sender's side for that WAT day; an admitted house visit marks both. `social_streak(p_user)` → `{streak, today_me, today_them, last_day, today}` for the caller and p_user only: consecutive both-sided WAT days ending today or yesterday (one indexed range read per call). `social_friends` adds `last_voice`, `last_deleted`. Read receipts reuse `player_messages.read_at` / `social_mark_messages_read` (unchanged). Config keys `news.latest_title`, `news.latest_body` (docs/ADMIN.md).

## Benin Gist group chats (2026-10-31)
Real group chats that players create live in Phone -> Benin Gist -> Groups (docs/GIST.md). They reuse the DM bubbles in `src/panels/chatKit.tsx` (reply, delete, quote, voice notes); `chatKit` gained a money bubble (`ThreadMessage.money`, `MoneyCard`) and an optional sender name (`MessageRow senderName`). Tables `gist_*`, RPCs `gist_group_*`, one Realtime channel per OPEN group (`gist_messages`, RLS: members only, blocked pairs hidden). Place chat, house chat and DMs are unchanged. There is still no global chat: Discover lists public groups, and every group has a member cap (default 200).
