# Growth: are players coming back, and from where?

Part 1 of the Daily return pack (docs/DAILY_RETURN.md). Migration `supabase/migrations/20261108000100_growth.sql` · tests `supabase/tests/daily_return_test.sql` (part 1) · admin `src/admin/Growth.tsx` + `Growth.css` · client `src/lib/growth.ts`.

Open **Admin -> Growth**. It is cards and simple bars, made for a phone.

## What it shows
- **Active today / yesterday, weekly active, monthly active, online now, new in 30 days.**
- **Active players per day** and **new sign-ups per day** for the last 30 days (Benin time, WAT).
- **Do they come back?** Day-1 and day-7 return by sign-up day. Day 1 = share of that sign-up day who were seen again the next day. Day 7 = seen again exactly 7 days later. A number shows only when that day is over, so it never looks worse than it is.
- **Where players came from**, with day-1 and day-7 return for each source.
- **What players open**: phone apps, players per app (last 7 days, with today in brackets).

The page is worked out once every `growth.cache_seconds` (default 300 s = 5 minutes) and shared. The Refresh button forces it. "Online now" is always live (it uses the same indexed check as the map counts).

## Where the numbers come from (cheap on purpose)
| Table | What | Written |
|---|---|---|
| `player_days (user_id, day)` | one row for each WAT day a player was seen | by the heartbeat (`get_my_state`), **at most once per player per day** |
| `player_return_state (user_id, last_day, prev_day)` | the last day we recorded | same time; it is how the heartbeat knows "already done today" (one primary-key read, no write) |
| `player_sources (user_id, heard, channel)` | the answer and the channel link | once, at sign-up |
| `app_day_counts (day, app, players)` | players who opened an app that day | once per player per app per day |
| `player_app_days (user_id, day, app)` | dedupe for the line above | trimmed to 14 days when the page refreshes |
| `growth_cache` | the saved page | every few minutes |

Nothing touches the `profiles` table. All tables have RLS on and are closed to players; only the security-definer functions read or write them. History starts at deploy: one statement seeds each player's last-seen day so the charts are not empty on day one.

`profiles.last_seen` alone only knows the latest day, which is why `player_days` exists. The hook lives in `get_my_state` inside the branch that already saves `last_seen` (about once a minute), through `bl_growth_touch`, which never raises (a measuring problem cannot break the game).

## Where players came from
Two separate things, kept apart:
1. **Channel links** (measured): `https://playbeninlife.app/?src=tiktok`. The first `?src=` a person opens is kept in the browser (`bl.src`) until the Sim exists, then saved once. Allowed: lowercase letters, numbers and `_`, 2 to 24 characters. Use any name you like: `?src=tiktok`, `?src=whatsapp`, `?src=instagram`, `?src=uniben_flyer`.
2. **"How did you hear about Benin Life?"** (asked): one optional tap at the end of the creator's Dream step: TikTok, WhatsApp, A friend, Campus, Instagram, X, Google, Other. Tap again to clear. Nobody has to answer.

**Player invite links are different and still work**: `?ref=CODE` (docs/BALANCE.md referral rules, `src/lib/referral.ts`). `?src=` is a new parameter, so a channel can never be mistaken for a player code, and the server refuses a channel word as a referral code.

In the breakdown, a player's source is, in order: their channel link, their answer, "A friend" if they used a player invite link, otherwise "Not said". First answer wins; it is never overwritten.

## Settings (Admin -> Settings -> Growth)
`growth.cache_seconds` (300), `growth.sources_days` (60, how many days of sign-ups the source table looks at).

## Reading it
- Day 1 under about 20% means the first session is not giving a reason to return. Part 2 (welcome-back gift, lapsed pushes), part 3 (weekly events) and part 4 (the Today card) are the answer; check this page after each goes live.
- A source with few players (say under 30) is noise. Look at the biggest sources first.
- "Not said" will be large at first: only new sign-ups see the question.

## Tests
`bash scripts/sql-test.sh -- supabase/tests/daily_return_test.sql`: a day is recorded once however many heartbeats (and a second touch writes nothing), the next day adds a row, cohort maths (size, day 1, day 7, "not measurable yet"), first answer wins and junk is ignored, a channel word is not a referral code and a real player referral still works and counts as "A friend", app opens once per player per app per day, the cache, admin-only, grants and RLS.
