# Push notifications for players (P1)

Every player can get phone notifications (Web Push) with a master switch and five category switches. It reuses the owner/billboard push setup (docs/BILLBOARDS.md): the same `push_subscriptions` table, the same VAPID keys and the same service worker.

## What the player sees
- **Settings -> Notifications** (Sim sheet -> Settings; also Phone -> Settings). One "Allow notifications" switch (it asks the browser, saves this device and turns pings on; off = the server sends this player nothing, on any device) and five switches: **Messages**, **Money received**, **Friends & invites**, **Game events**, **Announcements**.
- Defaults: Messages, Money, Friends **on**; Game events and Announcements **off**. Nothing is sent until the player turns notifications on and the browser allows it.
- A category the owner switched off for everyone shows "Off for everyone for now".
- **One-time prompt** ("Make we ping you?"): shown once per device, never on load. It appears right after the player's first DM, or about 4 minutes into a session, whichever comes first. "Not now" is final; Settings stays.
- **iPhone / iPad (iOS 16.4+)**: web push works only from the Home Screen app. In Safari the Settings section shows "Share -> Add to Home Screen" instead; the prompt card is not shown.
- Tapping a notification opens the right screen (below).

## What triggers a push
| Category | Event | Text (examples) | Opens |
|---|---|---|---|
| Messages | DM (`player_messages`) | `@ada` / first 60 chars. Voice note: "Voice note" | that chat |
| Messages | House chat (`chat_messages` in a home) to the others in that home | `House chat: @ada` / first 60 chars | house chat |
| Money | `ledger` rows `transfer_in`, `tip_in`, `admin_gift` | "Money don land" / "₦5,000 from @ada" (a tip's note is never included) | Bank app |
| Friends | `events`: friend_request, friend_accepted, house_invite, house_knock | "New friend request" / "@ada wan add you as friend" | Messages (requests if any) |
| Friends | Family & love (docs/LOVE.md), category Friends: somebody asked you out, said yes, sent a flirt (folded into "3 new flirts for you"), invited you on a date, you became a couple, a break-up; kids (docs/LOVE.md "Stage 2"): a baby invite, expecting, your baby is here, a child needs attention (hungry / sleepy / bored / unwell, from the sweep in `bl_push_tick`), unwell, with relatives, grown up | "💞 @name wants to link up" / the flirt line / "You are now a couple 💞" | Family app (`go=family:linkups`, `family:us`, `family:family`) |
| Game events | `events`: weekly_prize, referral_bonus | the game's own title and body | Ranks / Hustles app |
| Game events | Benin Votes (docs/POLITICS.md): registration open, voting day, results are out (to every player with a device; winners get their own "You won" push) | "Benin Votes: voting day!" / "The polling units are open..." | Benin Votes app |
| Game events | club event starts (`bl_push_tick`) | "Amapiano Night is starting" / "At 360 Signature. Come join!" | that place |
| Game events | hype (`place_announcements`) to the others in that club | "🔥 Kingdom" / first 100 chars | that place |
| Announcements | Admin -> Broadcast messages (everyone / LAPO / Nepo / joined after / online now) | the broadcast title and first 100 chars | Alerts app |

There is no player-to-player "date invite" in the game yet (dates are NPC link-ups), so "invites" means house invites and knocks. Mass gifts arrive as a **Money** push, not an announcement. The weekly-prize broadcast has no author, so it is sent once, as the weekly_prize event.

Club event starts go to ticket holders and to every player who turned on Game events (setting `push.events_to_all`; set it off to tell ticket holders only). Each player hears about each occurrence once.

## Rules the database applies (`bl_push_enqueue`)
1. Master switch `push.enabled` and the category switch `push.cat_*` (Admin -> Settings -> Push notifications).
2. The player must have a saved device, notifications on, and the category on.
3. **Never the sender** (the actor is skipped), and a player who blocked the sender gets nothing.
4. **Chat pushes skip a player who was active in the game in the last `push.skip_active_seconds`** (default 20 s): they already see it live. Money, friends and announcements are not skipped. Also, when the game is open and in front, the service worker shows no system notification (the game shows it live).
5. **One push per chat per `push.convo_window_seconds`** (default 120 s). Extra messages in that window fold into one waiting row: "3 new messages from @ada" (title) with the latest message as the body. It is sent when the window ends.
6. **Hourly cap** `push.max_per_user_hour` (default 20).
7. Text is short English with light Pidgin and holds nothing beyond `@name: first 60 chars`.
8. Pushes still unsent after `push.max_age_minutes` (60) are dropped; the log is deleted after `push.keep_days` (7).

If a player switches notifications or a category off after a push was queued, it is skipped at send time.

## Sending
```
action -> trigger -> bl_push_enqueue -> push_outbox (pending)
cron (every minute) or the sender's game  ->  Edge Function player-push
   bl_push_tick  (club events started, stuck rows back, expire, cleanup)
   bl_push_claim (due rows, for update skip locked: never sent twice)
   send to every device (VAPID, RFC 8291), mark sent / retry (3 tries) / failed
   404 or 410 from the push service -> that device is deleted
```
This follows the repo's existing pattern (outbox rows created by the database, an Edge Function that drains them, called by the game after actions, like `admin-push`). No `pg_net` or `pg_cron` is used by the repo today, so none is required: the game itself pokes `player-push` (throttled, once per 8 s per player) after it sends a DM, money, a friend request, an invite or an announcement, so those pushes go out at once. A Cron job is only needed for the **bundled** pushes (they wait 2 minutes) and club event starts. Set it up once (below).

Files: `supabase/migrations/20261017000300_player_push.sql`, `supabase/functions/player-push/index.ts`, `supabase/functions/_shared/playerPush.ts` (+ `.test.ts`), `public/sw.js`, `src/lib/push.ts`, `src/lib/pushPoke.ts`, `src/lib/deeplink.ts`, `src/screens/game/NotificationsSettings.tsx`, `src/screens/game/PushPrompt.tsx`, Admin: `src/admin/Settings.tsx`.

## Database
- `push_prefs(user_id, master, messages, money, friends, events, admin)`: one row per player, RLS: a player can only read their own row; all writes go through `push_prefs_set`.
- `push_outbox`: closed to players and anon (RLS on, no grants). Columns include `status` (pending, sending, sent, failed, skipped), `group_key`, `count`, `send_after`, `attempts`, `error`.
- Player RPCs: `push_state()`, `push_prefs_set(jsonb)`, `push_subscribe(...)` (at most 8 devices per player), `push_unsubscribe(endpoint)`. Admin RPC: `admin_push_stats()`.
- Private helpers `bl_push_*` are revoked from anon and authenticated; `bl_push_tick` and `bl_push_claim` are for the service role only.
- No existing game function was edited: everything hooks in with triggers on `player_messages`, `chat_messages`, `ledger`, `events`, `broadcasts`, `broadcast_reads`, `place_announcements`. A failing push never fails the game action (every trigger and `bl_push_enqueue` swallow errors).

## Admin
Admin -> Settings -> **Push notifications** tab:
- `push.enabled` (everything), `push.cat_messages / money / friends / events / admin` (each category for everyone), `push.events_to_all`.
- Rate limits: `push.convo_window_seconds`, `push.max_per_user_hour`, `push.skip_active_seconds`, `push.max_age_minutes`, `push.keep_days`.
- A counter card on the same tab: **Sent (24 h)**, **Failed (24 h)** with the last error, **Waiting** (it warns when the oldest due push is over 2 minutes old: the Cron job is not running), players with a device, plus totals for the kept days.

## Owner setup (one time, about 5 minutes)
The VAPID keys are the ones already set for admin alerts. If "Notify me" on /admin/ads works for you, skip steps 1 and 2.
1. GitHub -> repo -> Settings -> Secrets and variables -> Actions: add `VAPID_PRIVATE_KEY` (the 43-character key) and `VAPID_SUBJECT` (`mailto:you@example.com`). See docs/BILLBOARDS.md "Owner setup".
2. **Deploy the function.** It is automated: the GitHub Action "Supabase Edge Functions" (`.github/workflows/supabase-functions.yml`) now includes `player-push` and runs on every push to `main` that touches `supabase/functions/**` or `supabase/config.toml`. After this change lands on `main`, check Actions -> Supabase Edge Functions is green (or press Run workflow). The migration goes out with the normal database workflow.
3. **Cron (this part is manual, in the Supabase dashboard).** Open your project -> Integrations -> Cron (turn the Cron integration on if it asks) -> Create job:
   - Name: `player-push`
   - Schedule: every 1 minute (`* * * * *`)
   - Type: Supabase Edge Function -> function `player-push`, method POST
   - HTTP header `Authorization: Bearer <your anon key>` (Project settings -> API keys; the dashboard usually fills this in), timeout 5000 ms.
   Save and make sure the job is enabled. Without it, instant pushes still work (the game pokes the function), but "3 new messages" bundles and club-event starts are not sent.
4. Test: on your phone open the game (iPhone: from the Home Screen icon), Settings -> Notifications -> Allow notifications. Ask a friend (or a second account) to DM you while the game is closed. Then check Admin -> Settings -> Push notifications: Sent goes up and Waiting stays near 0.
5. If Failed grows, read "last error" on that card. `device gone` just means a phone removed the site; the dead device is deleted automatically.

To turn it all off in an emergency: Admin -> Settings -> Push notifications -> `push.enabled` off. Nothing is queued or sent.

## Tests
- SQL: `bash scripts/sql-test.sh -- supabase/tests/player_push_test.sql` (grants and RLS flags, prefs and defaults, device cap, DM / house chat / money / tip / gift / friends / broadcast / weekly prize / hype / club event enqueue, no self-push, master off, category off, global off, active-player skip, blocked sender, collapse into "3 new messages", the 2-minute window, hourly cap, claim once, stuck rows, expiry, cleanup, RLS, admin stats).
- Deno: `deno test supabase/functions/_shared/playerPush.test.ts` (sent, 410/404 device removed, retry, no device, no VAPID key).
- Deep links were checked in a browser: `/play?go=bank`, `?go=friends`, `?go=dm:<id>`, `?go=place:<id>` open the right screen.

## Limits
- Presence is coarse: "active" means the game tab sent a heartbeat in the last 20 s (`profiles.last_seen`), not "has this exact chat open". The service worker adds the second check (game in front = no system notification).
- Hype pushes go to players currently inside that club. Club event starts need the Cron job.
- Web push on iPhone needs the Home Screen app (iOS 16.4+). Browsers that block notifications cannot be asked again by the game; Settings explains how to allow them.

## Sound and vibration (25 Oct 2026)
- **Game closed or in the background:** the phone itself plays the notification sound. A web page cannot choose a custom sound for a closed app (Chrome, Safari and Firefox do not allow it); it can only ask for the default sound and a vibration. `public/sw.js` now sets `silent: false` and `vibrate: [180, 80, 180]`. If a player hears nothing, it is the phone: Android Settings > Apps > Chrome (or the installed Benin Life app) > Notifications > the site's channel must be on with sound; the phone must not be in silent / Do Not Disturb. On iPhone the game must be added to the Home Screen (Share > Add to Home Screen) for push to work at all.
- **Game open and in front:** the service worker shows no system notification (the game shows it live) and posts `bl-push`; `Game.tsx` now plays the in-game `alert` cue for it (same cue as an `events` row; `playCue` already drops duplicates within 0.7 s).

## Benin Gist alerts (2026-10-31)
Likes (Game events category), comments, replies, mentions and replies in a group (Messages), being added to a group (Friends) and tips (Money) send an `events` row and a push. Many on one gist inside `gist.notify_window_minutes` become one alert that counts up ("5 people liked your gist"). See docs/GIST.md.

## Daily story alerts (2026-11-01)
"Your story for today is waiting" (once per Benin day, after `stories.push_hour`, only to players who have not read it yet and were seen in the last 3 days) and "Your story continues" (a follow-up is due) are sent from `bl_push_tick` through `bl_push_enqueue`, in the **Game events** category, so the master switch, the category switch, the hourly cap and deduping all apply. Admin switch `stories.push_enabled`. They open the Stories app (`go=stories`). See docs/DAILY_STORIES.md.
