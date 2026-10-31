# Daily return pack

The owner's goal: "the major updates that bring players online daily". About 6,000 players registered and few come back every day. Four parts, each built on what already exists (the heartbeat, the push system, the events table, the daily chips, the welcome-back screen):

| Part | What | Docs |
|---|---|---|
| 1 | **Growth** page in Admin: are players coming back, from where, using what | docs/GROWTH.md |
| 2 | **Welcome-back gift** and **"we miss you" pushes** (plus rent-due and takings-ready pushes) | below |
| 3 | **Weekly calendar** of events: Friday Club Night, Saturday Owambe, Sunday Rest, Monday Winners, Wednesday Market Day | below |
| 4 | A HUD **Today** card that gathers the daily reasons in one place | below |

Migrations (in order): `20261108000100_growth` · `20261108000200_return_gift` · `20261108000300_weekly_events` · `20261108000400_today_card`. Tests: `supabase/tests/daily_return_test.sql` (all four parts, run it 5 times). Help articles: Help -> Daily rewards & events.

---

## Part 2: welcome-back gift and nudges
Migration `20261108000200_return_gift.sql`. Client: `src/state/returnGift.ts`, `src/screens/game/ReturnGift.tsx` (+ `.css`), the card inside `src/screens/WelcomeBack.tsx`.

### The gift
- The heartbeat (`get_my_state` -> `bl_growth_touch`, once a player a day) knows the last recorded day. When a player's first heartbeat of a new day is **3 or more days** after it (`return.gift_after_days`), one row is made in `return_gifts` for that absence. A player with no record yet uses the day of `profiles.last_seen` (so a long-gone player returning after the deploy gets a gift once).
- **Amount**: `return.gift_cash` (₦5,000) + `return.gift_per_day` (₦500) for every day beyond the threshold, never above `return.gift_cash_cap` (₦10,000). Plus `return.gift_item_qty` (1) of `return.gift_item` (default `kada_chicken`, Kada fried chicken + chips).
- **Once per absence**: one row per `(player, day they came back)`, and only one unclaimed row at a time (a newer absence replaces an old unclaimed gift). Daily visits never make another. An unclaimed gift is dropped after `return.gift_keep_days` (7).
- **Not earnings**: ledger reason `Welcome-back gift` is not in `bl_earn_reasons()`, so no tax garnish, no weekly top-earner count, no challenge progress, no Money push.
- RPCs (signed-in players only): `return_gift_status()` -> `{pending, away_days, cash, item}`; `return_gift_claim()` pays cash with `bl_add_money` and the food with `bl_give_item` (hint `no_gift` when there is nothing). Switch `return.gift_enabled`.
- **What the player sees**: on the welcome-back screen a warm gold card sits inside the card above Continue ("Welcome back! Benin don miss you", the days away, the cash and the food, a big **Collect gift** button, then a green "Gift don land"). If the welcome-back screen did not show it (it is off, or the player came straight in), the same card opens once as a pop-up in the game. The card is also a line on the Today card (part 4).

### "We miss you" pushes
`bl_return_push_tick()` is called from `bl_push_tick` (the job cron already runs every minute). It does its work at most every `return.tick_seconds` (300).
- About **2, 5 and 10 days away** (`return.push_day_1/2/3`), one personal message each, **never more than three per absence**: each is remembered in `return_nudges (user, the day they were last seen, stage)`, so even if the push itself was dropped it is not retried. A push still goes out up to `return.push_window_days` (2) after its mark.
- **Something real**: stage 1 prefers "👶 Osas misses you" (a baby at home), then "💰 Your shop takings are waiting", then "📖 Today's story has a twist for you". Stage 2 prefers the shop, then the baby, then the story. Stage 3 is "🇧🇯 Benin don miss you" (mentioning the gift).
- **Opt-in and quiet**: it uses `bl_push_enqueue` in the Game events category, so the master switch, the player's own Game events switch (off by default), a saved device, the hourly cap and dedupe all apply. Nothing is sent before `return.push_from_hour` (9) or from `return.push_to_hour` (20), Benin time. A player never gets two of these within 20 hours.
- **Bounded**: at most `return.push_batch` (200) players per tick, found through the indexed `seen_bucket` range for each stage (never a scan of everyone). `return_nudges` older than 60 days is trimmed.

### "Something needs you" gaps
Already pushing before this pack: DMs and house chat, money received, friend and love events, kids needing care, daily story and its follow-ups, club events, broadcasts. Added (Money category, once a day per player at most, never to someone in the game right now, `return.gap_push_enabled`):
- **Rent is due tomorrow** (needs `rent.enabled`): "🏠 Rent is due tomorrow - Your rent is ₦12,000."
- **Your takings are ready**: a business not collected for `return.takings_hours` (12), once per collect cycle; only owners seen in the last 2 days (the lapsed pushes cover the rest).
"A friend messaged you" already exists (Messages category), so it was not added again.

### Admin (Settings -> Welcome back, category `return`)
All the numbers above are settings. The Growth page shows whether the day-1 and day-7 numbers move after this goes live.

### Tests
`daily_return_test.sql` part 2: nothing at 2 days, base at 3, scaling at 8, cap at 40, an old player's first heartbeat, once per absence, status/claim/ledger/bag, new absence = new gift, not earnings (tax is not taken), switch off, expiry, admin cap, grants/RLS; pushes at 2/5/10 days, max three, opted-out and device-less get nothing, the baby and shop lines, quiet hours, throttle, batch of 10 then the rest, switches; rent due tomorrow, takings ready, not twice, active players skipped, category and hourly cap hold.

---

## Part 3: "This week in Benin" (weekly events)
Migration `20261108000300_weekly_events.sql`. Client: `src/state/weekly.ts`, `src/screens/game/Weekly.tsx` (+ `.css`), the banner inside `EventBanner` (`src/screens/game/Events.tsx`), a "This week" pill in the Stories app, deep link `go=week`.

The existing events system (docs/EVENTS.md) is tied to a place and a ticket, and it cannot say "the whole city rests on Sunday", announce winners or lower a market's prices. So the weekly programme is a small layer on the same idea: **nothing is created and nothing is scheduled**. `bl_weekly_catalog()` lists five events by Benin weekday; `weekly_calendar()` works out the current Monday-to-Sunday week the moment somebody asks. Switch an event off and it simply is not in the answer.

| Day | Event | What it does | Default reward (all settings) |
|---|---|---|---|
| Friday | 🪩 Friday Club Night | Check in at **any club** (`locations.scene = 'club'`) | ₦1,000 + fun +15 |
| Saturday | 🎉 Saturday Owambe | Check in at the party place (`weekly.sat_owambe_place`, default Golden Tulip Essential) | ₦1,500 + fun +20 |
| Sunday | 🛋️ Sunday Rest Day | Check in **at home** (Church can replace this later) | stress -20, energy +10, no cash |
| Monday | 🏆 Monday Winners | Last week's top 3 earners (the weekly prize winners that already exist) are announced as a **broadcast** to everyone, once | none |
| Wednesday | 🛒 Wednesday Market Day | Everything at Oba Market (`weekly.wed_market_place`) is **15% cheaper** all day | 15% off |

- **Check in** (`weekly_event_checkin()`): the right place, not travelling, not in jail, once per event per day (table `weekly_event_checkins`). Hints: `no_event`, `not_here` (the message says where to go), `already`. Cash goes through `bl_add_money` with the reason `Weekly event: Friday Club Night`; it is not an earn reason (no tax, no leaderboard). Needs go through `bl_adjust_needs`.
- **Market discount**: patched into `bl_dealer_net` (one guarded replace) through `bl_weekly_discount`, so the shop list, the buy button and the tax all agree. On any other day it exits on the first line without a query.
- **Monday announcement**: made by the first `weekly_calendar()` call on Monday or by the cron tick, whichever comes first; `weekly_event_runs` makes it once. It settles last week first (`bl_weekly_settle`), and does nothing if nobody earned enough to win.
- **Morning push** (`bl_weekly_tick`, called from `bl_push_tick`): one per player at or after `weekly.push_hour` (9), before the quiet-hours end (`return.push_to_hour`, 20), Game events category (opt-in), only players seen in the last 14 days, `weekly.push_batch` (200) per tick, logged in `weekly_push_log` so nobody gets two; when a tick sees fewer than a batch it writes a "done" marker so the rest of the day costs nothing. Monday has no push (the broadcast is the announcement). Opens `go=week`.
- **Admin**: Settings -> Weekly events: `weekly.enabled`, one `weekly.<key>_enabled` per event, the rewards, the discount, the place ids, the push. Nothing else to schedule.
- **Client**: the day's event shows in the same top banner slot as place events (only when no place event is showing; phones hide it after 8 s; the x hides it for the day on this device). Tapping it, the Stories "This week" pill, the Today card or the push opens the calendar sheet: Monday to Sunday, today in gold with a **Check in** button (or **Go to Oba Market**), the Monday winners listed.
- **Tests**: part 3 of `daily_return_test.sql`: the right event on each weekday and the whole week, check-in at the wrong and right place, once a day and again next week, Thursday has none, the Saturday and Sunday rewards, the Monday broadcast once and with the winner named and off when switched off, Oba cheaper on Wednesday (list and price, other markets unchanged, switch and discount are settings), each event and the master switch off, the morning push (too early, one each, opted-out gets none, once a day, next week again, Monday none, switch, batch of 10), grants and RLS. `supabase/tests/_helpers.sql` now switches the Wednesday discount and the new pushes off for every suite, so no older test depends on the weekday.
