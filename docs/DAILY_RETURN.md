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
