# Chat (V1-6)

Each location has its own chat room. There is no global chat: Lagos Life's global chat ran out of bandwidth at about 50k players online. Private messages (DMs) come after v1, and the phone's Messages app says "Coming soon" for them.

- **Server:** `supabase/migrations/20261005001000_chat.sql`
- **Tests:** `supabase/tests/chat_test.sql`
- **Client:**
  - `src/api/chat.ts` (RPC wrappers)
  - `src/state/chat.ts` (live state and subscription)
  - `src/panels/ChatPanel.tsx` (the Chat tab)
  - the HUD chat chip in `src/screens/Game.tsx`
  - the Messages app in `src/screens/game/Phone.tsx`
  - the blocked list in `src/screens/game/SimSheet.tsx` (People tab)

## Rules
- You can only read and write in the chat of the place you are at.
  - While travelling you can't send, and `chat_recent` refuses.
  - Being busy, jailed or in hospital doesn't stop chat.
- You can't send if any of these is true:
  - you are banned;
  - you are muted (`profiles.chat_muted_until`; an admin sets it in V1-7);
  - chat is switched off (`chat.enabled`);
  - your Sim is younger than `chat.min_account_real_minutes`.
- Cleaning, in order:
  1. Trim the message.
  2. Turn newlines and tabs into spaces.
  3. Strip control and zero-width characters.
  4. Squeeze repeated spaces.
  5. Refuse an empty message, or one longer than `chat.max_len`.
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
- **Retention:** each `chat_send` deletes up to 200 messages older than `chat.retention_hours` (48). Reports cascade. No cron job is needed.
- **Admin:**
  - `admin_chat_hide(id, hidden default true)` is guarded by `bl_is_admin()` and logged in `admin_audit` (`chat_hide`/`chat_unhide`).
  - The V1-7 admin page can also mute (`chat_muted_until`) and edit `chat_banned_words`.

## Config (category `chat`)
| key | default |
|---|---|
| chat.enabled | true |
| chat.max_len | 200 |
| chat.rate_seconds | 3 |
| chat.burst_per_minute | 8 |
| chat.duplicate_window_seconds | 120 |
| chat.min_account_real_minutes | 5 |
| chat.recent_limit | 30 |
| chat.report_hide_count | 3 |
| chat.retention_hours | 48 |
| chat.max_blocks | 200 |

## RPCs
| RPC | Args | Returns |
|---|---|---|
| `chat_send` | p_body | message row + `{message, masked}` (hints: chat_off, muted, traveling, too_new, empty, too_long, too_fast, duplicate, banned, no_home) |
| `chat_recent` | p_location, p_limit | last `min(p_limit, chat.recent_limit)` visible rows at your current place, oldest first, with `avatar` and `mine` (hint not_here) |
| `chat_report` | p_message_id, p_reason | `{message, reports, hidden}` |
| `chat_block` / `chat_unblock` | p_user | `{message, id, username?}` |
| `chat_blocked` | – | `[{id, username, avatar, created_at}]` |
| `admin_chat_hide` | p_message_id, p_hidden | `{message, id, hidden}` |

The chat guard `bl_chat_me()` locks the caller's profile row with `FOR UPDATE` but **writes nothing**. If it wrote, every message would set off a profile realtime event and a `get_my_state` refresh for the sender. It also skips the needs decay and the rent charge.

## Tables
- `chat_messages` (id, location_id, user_id, username snapshot, body, created_at, hidden)
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
- **Hidden messages:** UPDATE events aren't subscribed to. A message hidden by reports or an admin disappears for others the next time they open the chat (`chat_recent`).
- **Scaling later:** if one place ever gets very busy, RLS checks per subscriber grow with the crowd. Two options:
  - switch to Realtime Broadcast from the database (`realtime.broadcast_changes` on a `chat:<location>` topic, private channels);
  - shard a busy place into rooms.
  - The RPC surface stays the same either way.

## UI
- **Location sheet:** the Chat tab is always the last tab at every place. No `chat` action is needed in `locations.actions`.
  - It shows each message's avatar portrait, name, time and text.
  - Your own bubbles are green and on the right.
  - Tapping someone's message (or its ⋯ button) opens Report (with a reason) or Block @name.
  - The input has a character counter, and the Send button shows a countdown during the rate limit.
  - Server errors appear inline.
  - Note at the top: "Be respectful — 18+ only".
- **Unread:** messages from others that arrive while the Chat tab isn't on screen count as unread. The count shows on:
  - a small "N new in chat" chip above the "You're at" chip (it opens the sheet on Chat);
  - the Chat tab's badge;
  - the Messages app icon on the phone.
- **Phone → Messages:** a "Chat at <place>" button ("Chat with your neighbours" at home), plus the "Private messages — Coming soon" card.
