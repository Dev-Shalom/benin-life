# Scaling Benin Life for a launch crowd (S1, 2026-10-11)

What was changed so thousands of players don't knock the game over, what each player costs the backend, and what the
owner must upgrade **before announcing**.

## TL;DR for the owner
| Plan | Realtime connections (= players online at once) | What happens above that |
|---|---|---|
| **Free** (now) | **200** | New tabs can't open Realtime: chat, live alerts and live counts stop for them. The game still loads and plays (the 60 s heartbeat refreshes their Sim), but it feels broken. Also: the project pauses after about a week idle, no backups. |
| **Pro, spend cap ON** (default on Pro) | **500** | Same as above, from player 501. |
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
