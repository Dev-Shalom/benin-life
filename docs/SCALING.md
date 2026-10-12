# Scaling Benin Life for a launch crowd (S1, 2026-10-11)

What was changed so thousands of players don't knock the game over, what each player costs the backend, and what the
owner must upgrade **before announcing**.

## TL;DR for the owner
| Plan | Realtime connections (= players online at once) | What happens above that |
|---|---|---|
| **Free** (now) | **200** | F1: new tabs fall back to polling (chat, alerts, people here, house visits keep working, a few seconds slower; pill "Busy right now — live updates slowed"). Polling costs ~6× the requests/egress of a live player, so Free holds ~500 online for a few hours (see "Realtime fallback"). Also: the project pauses after about a week idle, no backups. |
| **Pro, spend cap ON** (default on Pro) | **500** | Same fallback from player 501; ~1,300 online on Micro. |
| **Pro, spend cap OFF** | **10,000** (2,500 msg/s) | Pay-as-you-go for extra Realtime use. Players are then limited by database CPU (see compute below). |

**Before you announce to "thousands": do these in Supabase:**
1. **Billing → upgrade to Pro** ($25/month, includes $10 compute credit).
2. **Billing → Spend cap → turn it OFF** (otherwise Realtime stops at 500 players). Set a billing alert/budget email you are comfortable with.
3. **Settings → Compute and Disk → Small** ($15/month, 2 GB RAM, 90 direct / 400 pooler connections) for up to about 1,000 players online; **Medium** ($60/month, 4 GB, 120 / 600) for 1,000–3,000. You can scale up and down at any time (hourly billing, a short restart of about 2 minutes, do it before the announcement, not during the peak).
4. **Authentication → Emails → SMTP**: custom SMTP (see docs/DEPLOY.md "Password reset emails at scale"). The built-in sender only sends **2 emails per hour for the whole project**, so "Forgot password" fails for almost everyone.
5. **Settings → Usage / Reports → Realtime**: watch "concurrent peak connections" and "messages per second" during the first hours.

Supported players online at once **for this app** (estimates from the request rates below; Postgres Changes and CPU are the
next limits after connections):
| Setup | Players online at once |
|---|---|
| Free | ~200 (hard Realtime limit) |
| Pro, spend cap on, Micro | ~500 (hard Realtime limit) |
| Pro, spend cap off, Micro (default compute) | ~800–1,000 (database CPU/connections become the limit) |
| Pro, spend cap off, Small | ~1,500 |
| Pro, spend cap off, Medium | ~3,000–4,000 |
| Pro, spend cap off, Large+ | 5,000+ (then move the per-player profile feed from Postgres Changes to Broadcast, see "Next limits") |

Limits come from the official Supabase docs (Realtime limits page and pricing page, checked 2026-10-11): Free 200
connections / 100 msg/s / 100 joins/s; Pro 500 / 500 / 500; Pro without spend cap 10,000 / 2,500 / 2,500. Compute: Micro
$10 (1 GB, 60 direct / 200 pooler connections), Small $15 (2 GB, 90 / 400), Medium $60 (4 GB, 120 / 600), Large $110
(8 GB, 160 / 800). These numbers change; re-check https://supabase.com/docs/guides/realtime/limits and
https://supabase.com/pricing.

## Realtime fallback (F1, 2026-10-12): stay on a cheap plan
When the plan's Realtime limit is full (Free 200 connections / 100 msg/s, Pro with spend cap 500 / 500), players over
the limit no longer get a half-broken game: their tab **switches to polling** and everything keeps working, only slower
(chat within ~8 s, house movement within ~4 s, alerts within ~30 s). Players already connected stay live.
A small pill shows **"Busy right now — live updates slowed"** (not an error).

**Owner switch:** Admin → Settings → Admin → `realtime.mode` (`auto` default, or `poll_only`). `poll_only` sends every
open tab to polling within a second (seen over the live config channel) and keeps new tabs off Realtime: use it when
Reports → Realtime shows the connection or message limit being hit. Back to `auto`: tabs return to live within ~90 s.

### How a tab decides (src/lib/realtime.ts)
- Every channel subscribes through `trackSubscribe()`, which reports its status and listens for server `system` errors.
- **At once** when a join/system message says quota: `too_many_*`, `TooManyChannels`, `ConnectionRateLimitReached`,
  `ChannelRateLimitReached`, `ClientJoinRateLimitReached`, "tenant events per second", "rate limit", "quota"…
- **3 separate failure incidents within 90 s** (`CHANNEL_ERROR`, `TIMED_OUT`, socket heartbeat `timeout`/`error`; a burst
  within 3 s counts once, so one network blip never flips the mode; any successful join resets the count).
- **Watchdog:** channels exist but none has joined for 25 s (socket refused or unreachable; realtime-js reports that
  only once per channel and then waits silently).
- In poll mode every feature removes its channels, so the socket disconnects and **stops retrying**. A probe joins one
  tiny channel every **2–5 min** (random; doubled up to 10 min after a quick relapse; never while the tab is hidden).
  When it joins, the tab goes live again: features resubscribe and catch up once (`get_my_state`, events since the
  last id, chat history merge), deduped by id, so nothing shows twice.
- Mixed rooms work: a live player's place list adds polling players (only when `world_counts` says Presence is missing
  someone: no cost otherwise); in a house, live tabs receive polling members' moves as Postgres Changes on the house
  channel and then post their own moves too ("bridge").

### What polls in poll mode (visible tab only, ±20 % jitter)
| Feature | Live mode | Poll mode |
|---|---|---|
| Own state | Postgres Changes `me-<uid>` + 60 s heartbeat | `get_my_state` every ~17.5 s (+ after every action, as before) |
| Alerts / DMs / friend requests / interaction asks (events) | Postgres Changes | `events?id=gt.<last>` every ~30 s (usually `[]`) |
| People at my place | Presence `place:<id>` | new `players_here_ids` (ids + last_seen, no avatars) every ~25 s; names/avatars load only when the set changes |
| Map counts / online pill | `world_counts` 60–75 s | unchanged |
| Place + house chat | Postgres Changes | `chat_messages?id=gt.<last>` every ~8 s with the chat open, ~30 s closed (unread dot) |
| Open DM conversation | Postgres Changes | `player_messages?id=gt.<last>` every ~10 s; Messages app list every 30 s (60 s live) |
| House room (others' avatars) | broadcast + presence | `house_room_state` every ~4 s with others there, ~20 s alone; own moves via `house_room_move` on walk start / stop / pose change (≤ 1 per 2.5 s while walking) + 60 s keep-alive. Others walk the posted path (existing walk-to) |
| House furniture | Postgres Changes | every ~60 s while at home |
| Hype (club) / global ticker | Postgres Changes | `place_announcements?id=gt.<last>` every ~60 s in a club (~3 min elsewhere), global every ~3 min |
| Game config | Postgres Changes | the `realtime.mode` row every ~90 s, everything every ~6 min |
| Billboards, Daily, events calendar, admin | already polled | unchanged |

Not live in poll mode (acceptable): chat "delete for everyone" tombstones and DM read ticks appear on the next open.

### Cost of a polling player (counted + measured)
Measured (Playwright, two players, websocket blocked, 2 min idle at Uselu Motor Park): 13.0 REST calls/min with chat
closed (2 of them one-off place loads, so ~11 steady), 18.5 with chat open. Counted from the intervals:

| Situation | Requests / min / player |
|---|---|
| Idle at a place, chat closed | **~12** (get_my_state 3.4, players_here_ids 2.4, events 2, chat 2, world_counts 0.9, hype 0.7, config 0.7) |
| Chat open | ~17.5 |
| In a house with visitors (walking now and then) | ~30 (+ house_room_state 15, moves 2–4) |
| Alone at home | ~15 (+ house_room_state 3) |
| Hidden tab | 0 |
| Live player (for comparison) | ~2 |

Database time (local Postgres 17, per call): get_my_state 3.0 ms, world_counts 0.6 ms, players_here(_ids) 0.25 ms,
the `id > last` selects and house_room_state < 0.3 ms (indexed, usually 0 rows). ≈ **13 ms DB time per polling player
per minute**, plus PostgREST/Kong overhead (~1–2 ms CPU a request) ≈ 0.6 ms CPU per second per polling player.

Egress per polling player: get_my_state ≈ 4 KB (uncompressed), every other poll ≈ 0.3–0.5 KB with headers (empty
arrays), so **~20 KB/min ≈ 1.2 MB per hour played** (≈ 0.25 MB/h when the API gzips). A live player ≈ 0.3 MB/h.

### How many players each plan holds with the fallback (estimates)
| Plan | Live (Realtime) | + polling on top | Real limit |
|---|---|---|---|
| **Free** (Nano compute, 5 GB egress / month) | 200 | **~300 more** at once (shared CPU; ~60 req/s) → **~500 online** | **Egress**: 5 GB ≈ 4,000 polling player-hours a month (≈ 130 h a day). Fine for a soft launch / a spike of a few hours; above that, upgrade. The project still pauses after a week idle. |
| **Pro, spend cap ON** (Micro, 250 GB egress) | 500 | **~800 more** (~160 req/s on Micro) → **~1,300 online** | CPU first; egress 250 GB ≈ 200,000 polling player-hours / month. Small compute ($15) → ~1,500 pollers → ~2,000 online. |
| Pro, spend cap OFF | 10,000 | rarely needed | see the table at the top |

The numbers assume players mostly idle at places (the common case). Busy house parties cost ~2.5× an idle player.
Watch Reports → Database CPU; when it stays above ~70 %, either scale compute or turn the cap off (live is ~6×
cheaper per player than polling).

**Files:** `src/lib/realtime.ts` (detector, probe, `bindRealtime`, `startPoller`, `trackSubscribe`), `src/state/net.ts`
(heartbeat feeds it; no "Reconnecting…" while polling on purpose), `src/ui/NetBanner.tsx` (pill), `src/lib/config.ts`
(switch + config polling), `src/state/{game,presence,chat,hype,houseRoom}.ts`, `src/screens/Game.tsx` (furniture),
`src/screens/game/phone/{DmConversation,SocialApp}.tsx`, `src/admin/Settings.tsx` (quick knob),
`supabase/migrations/20261012001000_realtime_fallback.sql` (config row, `house_room_positions` + RLS + publication +
leave trigger, `house_room_move`, `house_room_state`, `players_here_ids`), test `supabase/tests/realtime_fallback_test.sql`.
Dev: `window.__rt` (`store`, `fail(msg)`, `force(bool)`, `probe()`).

## What each player costs (measured / counted from the code)
Idle = Sim standing at a place, phone and map closed, tab visible. Hidden = tab in the background.

| | Before S1 | After S1 |
|---|---|---|
| HTTP RPCs, idle, visible (measured, 3 min) | **2.0+ / min**: get_my_state 2/min (the 60 s heartbeat bumps `last_seen`, the Realtime echo of that UPDATE triggered a second get_my_state), events 1/3 min, daily 1/5 min, **plus** players_here on every presence change at your place | **~2.0 / min**: get_my_state ~1.3/min (echo skipped), world_counts ~0.7–0.9/min, events 1/5 min, daily 1/5 min |
| HTTP RPCs, Messages app open | +9 / min (3 RPCs every 20 s) | +3 / min (every 60 s, visible only; DMs/requests arrive live) |
| HTTP RPCs, map open | +0.33 / min billboards | +0.2 / min |
| HTTP RPCs, hidden tab | events + billboards + Messages + travel quote kept polling (up to ~11 / min) | **0** (every poller checks `document.visibilityState`) |
| Realtime connection | 1 per tab | 1 per tab |
| Realtime channels | `me-<uid>`, `game_config_live`, `hype-global`, **global presence `online`**, `chat-<place>`, `hype-<club>`, house rooms | same, but presence is **per place** `place:<id>` (and skipped at places with 40+ players) |
| Presence messages | every join / leave / move broadcast to **every** online player: N² — 2,000 players moving every ~3 min ≈ **22,000 msg/s** (40× over the Pro no-cap limit) | only to players at the same place, and never at a place with 40+ players: worst case ≈ 40 × (joins+leaves there); 2,000 players spread over 37 places ≈ **a few hundred msg/s** |

Server side per call (EXPLAIN ANALYZE with 20,000 synthetic players, 200k ledger rows, 60k chat rows, local Postgres 17):
| Query | Before | After |
|---|---|---|
| players online (`players_online` / new `world_counts`) | 8 ms seq scan | **0.7 ms** (partial index `profiles_online_idx`), world_counts 2.3 ms incl. per-place counts |
| `leaderboard_rich` (Ranks app) | **190 ms** (3 full rankings, config flag read per row) | **39 ms** (one ranking, flag read once) |
| admin stats "money today" | 44 ms parallel seq scan of ledger | 28 ms (`ledger_created_idx`), admins only |
| players_here, chat history, DM history | < 0.2 ms (indexed) | unchanged |
| deleting a user | seq scans on 11 FK columns without an index | every FK to a user is indexed |

## What changed (files)
**Client**
- `src/lib/api.ts`: one RPC wrapper for everything. Read-only RPCs (allow-list regex) are **deduped while in flight** and **retried up to 3 times with full-jitter exponential backoff** (0–0.5 s, 0–1 s, … capped at 4 s; +1 s on 429) on network errors, 429 and 5xx. Writes (money, purchases, travel) are retried **only** on 429/503 (the server refused before running), so nothing can run twice. 429 shows "Too many people dey play right now…".
- `src/state/net.ts` + `src/ui/NetBanner.tsx` (mounted in `App.tsx`): a small "Reconnecting…" pill at the bottom when the browser is offline, two RPCs in a row failed with a connection error, or Realtime heartbeats failed for 45 s+. Never blocks the game; disappears by itself.
- `src/lib/supabase.ts`: Realtime `reconnectAfterMs` = 1 s + random(0 .. min(30 s, 2^tries s)), so a Realtime restart doesn't bring every tab back in the same second.
- `src/state/game.ts`: the Realtime echo of get_my_state's own `last_seen` bump no longer triggers a second get_my_state (skipped only when no game action was sent in that window).
- `src/state/presence.ts`: global `online` presence replaced by per-place `place:<id>` presence (joined at the place, left on travel / logout, not joined where 40+ other players are) + `world_counts()` polled every 60–75 s (jittered) while visible. Consumers updated: `Game.tsx` (map crowd numbers), `Hud.tsx` (online pill, no more fallback poll), `LocationSheet.tsx` (people-here list: live at your place, 60 s/180 s safety poll while visible), `PlaceCard.tsx`.
- Visibility-gated / slower polls: `state/events.ts` (3 → 5 min), `phone/SocialApp.tsx` (20 → 60 s), `game/travel.ts` (45 → 60 s), `Game.tsx` billboards (3 → 5 min), `admin/AdminApp.tsx` (30 s, visible only). Already OK: game heartbeat 60 s visible-only, Daily 5 min, Admin Overview 30 s visible-only, UpdateNotice 3 min (Vercel static file, not Supabase).
- Crash safety: the root `ErrorBoundary` (main.tsx) shows "Reload" instead of a white screen; 3D views have their own boundaries; RPC errors become toasts. Unchanged, checked.
- Code splitting: already in place (Game, admin, 3D city/home/place scenes, phone apps are lazy chunks). The two big chunks (three.js 188 kB gzip, CityScene 196 kB gzip) load only in the game.

**Database** (`supabase/migrations/20261012000800_admin_delete.sql`)
- `world_counts()`: online count + other players per public place in one query.
- Indexes: `profiles_online_idx`, `ledger_created_idx`, FK indexes on admin_audit.admin_id, billboard_reports.user_id, chat_blocks.blocked_id, chat_reports.reporter_id, config_audit.admin_id, event_tickets.user_id, house_interactions.host_id, player_friendships.user_b, player_messages.sender_id, profiles.home_visit_host_id, social_streak_days.user_b. Dropped exact duplicates `chat_messages_loc_id_idx`, `player_messages_conv_id_idx` (every chat/DM insert was writing two identical indexes).
- `bl_rich_ranked` / `bl_vip_ranked` as plpgsql (flag read once) and `leaderboard_rich` / `leaderboard_vip` rank once per call.
- Admin stats stay behind `bl_admin_guard()`; players can't run them.

**Static assets** (`vercel.json`): `/assets/*` (hashed) `public, max-age=31536000, immutable`; `/art/*` 1 day + stale-while-revalidate; icons 1 day; `sw.js`, `version.json`, `manifest.webmanifest`, `index.html` `no-cache, must-revalidate` (SPA routes get Vercel's default `max-age=0, must-revalidate` for HTML).

## Measurement
Local stack, Playwright, one player standing at Uselu park, every REST call counted:
- before the echo fix: 3 min idle visible = 6 × get_my_state + 3 × world_counts;
- after: 3 min idle visible = **4 × get_my_state + 2 × world_counts** (6 calls ≈ 2/min); 2 min hidden = **0 calls**.
- Realtime channels for that tab: `me-<uid>`, `game_config_live`, `hype-global`, `place:uselu_park`, `chat-uselu_park`,
  `hype-uselu_park` (no global presence). Presence store: online 1, here = uselu_park.
- Peak cost per active player (walking, working, opening apps) is about 4–8 RPCs/min.

## Next limits (in order) and what to do if you hit them
1. **Realtime connections** (plan limit): Pro + spend cap off.
2. **Postgres Changes throughput.** Every tab listens to its own `profiles` row, its `events`, `game_config`, global hype and its place's chat via Postgres Changes. Supabase checks each change against subscribers on one database thread. Profile updates are the busiest (every action). Signs: Realtime "lag" in Reports, alerts arriving late. The game still works: the 60 s heartbeat (`get_my_state`) and RPC results update the screen. Fix if needed: move the per-player feed to Broadcast from a trigger (`realtime.send`), or drop the `profiles` subscription and rely on RPC results + heartbeat.
3. **Database CPU / connections**: ~2–6 RPCs per player per minute. 2,000 players ≈ 70–200 RPC/s. Scale compute (Small → Medium) when CPU stays above ~70 % in Reports → Database.
4. **Egress**: the site itself is on Vercel; Supabase egress is RPC JSON + chat voice notes + billboard images. Pro includes 250 GB.
5. **Auth emails**: custom SMTP (DEPLOY.md).
