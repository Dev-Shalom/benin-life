# "Fix it" update

Twelve fixes from real player feedback, done easiest first, one commit each. Migrations are `20261110000100` and up, tests are in
`supabase/tests/fixit_test.sql` (one group per item with server logic). Player-facing words are in quotes.

## 1. Candidate registration pop-up repeated
- **Cause:** the "Candidate registration is open" banner (`ElectionBanner` in `src/screens/game/PollingStrip.tsx`) showed on every load for the whole 48 h registration window, even to people who had already declared.
- **Now:** it shows at most once per election cycle per player per browser (`src/lib/seenPrompts.ts`, key `bl.seen.<user>.reg.<cycle>`), never to someone who already declared, and has **"Don't show again this election"**. The Benin Votes badge and the Elections tab still show registration. Voting-day banner is unchanged (it always shows).

## 2. Club money shout-out covered the screen
- **Cause:** the spray / bottles takeover (`.hx`) was a fixed full-screen layer (z 80) with a blurred backdrop and one giant button, so it swallowed every tap for 3.5 to 9 s.
- **Now:** a compact card under the HUD (max 40% of the height). Everything in it has `pointer-events: none` except a 40 px **close (X)** button, so the game stays playable. Holds are shorter: spray tiers 2.2 / 2.5 / 2.8 / 3.2 / 3.6 / 4.2 / 5.0 s (was 3.5 to 9 s), shutdown 4 s (was 6), VIP arrival 2.4 s (was 3). The money-pick notes layer already ignored taps.
- Files: `src/styles/hype.css` (Fix it 2 block), `src/screens/game/Hype.tsx`, `src/state/hype.ts`.

## 3. Spray / bottle notifications were annoying
- New per-player setting **Settings -> Club spray alerts** (table `club_alert_prefs`, RPCs `club_alert_prefs_get` / `club_alert_prefs_set`, migration `20261110000100_club_alert_prefs.sql`):
  - "Shout-outs in my club": the card in the club you stand in. **On** by default. Your own spray always shows.
  - "Big sprays in other clubs": the app-wide strip. **Off** by default.
  - "Phone pings for club hype": a push. **Off** by default. `bl_push_on_hype` is patched (guarded replace) to need this switch **and** the existing `push.enabled`, `push.cat_events`, the player's Game events category, a saved device and the usual rate limits.
- Client: `src/state/clubAlerts.ts`, `src/state/hype.ts` (filters), `ClubAlertsSettings` in `src/screens/game/NotificationsSettings.tsx`.

## 4. Can't sleep on the bed in the second room
- **Cause (found by driving the real app):** the server never cared where a bed stands (every bed kind, also one in an extension room, passes `bl_furniture_for` and `do_activity('sleep')`, now covered by test group 4). The client was the problem: a queued home task only remembered the furniture *group*, so the Sim always walked to the **first** piece that hosts the activity (the main-room bed), and when the sleep started the pose code picked that first piece again and walked there. Tapping the bed in the extension / second bedroom looked like nothing worked.
- **Now:** the task keeps the tapped piece (`piece` in `src/state/tasks.ts`, `HomeSheet`), the Sim walks to that exact bed and stays on it for the pose. From "Things to do" (no tap) the nearest piece that hosts the activity is used. Files: `HomeScene.tsx`, `TaskRunner.ts`, `tasks.ts`, `HomeSheet.tsx`.
- Note: the three biggest beds (6 ft, king, luxury king) are refused in some spots of a small extension room because they would block its doorway; that is the existing placement rule (the message says "You are blocking the door"), move the bed along the wall.

## 5. Gang Boss handed over by mistake
- Migration `20261110000200_gang_boss_handback.sql`, tests group 5. New tables `crew_boss_log` (the audit trail of every Boss move, no client access) and `crew_boss_requests`.
- **New Boss:** "Hand it back" any time (`crew_boss_handback`), only while the last Boss move was a handover to them.
- **Previous Boss:** "Ask for it back" within `crew.boss_request_hours` (24, admin Settings) of the handover (`crew_boss_request`); the Boss taps "Give it back" or "No" (`crew_boss_respond`). One request at a time, it dies with the 24 hours.
- A normal "Make Boss" (`crew_transfer`) is now logged by a guarded patch. Gang app -> Overview shows the **Boss rank** card only when one of these applies (`crew_boss_state`).
- **Admin:** the Grant toolbox's Gang section now has **Make Boss** (`admin_crew_set_boss`: audited in `admin_audit` as `grant_crew_boss` and `crew_boss_log`, the old Boss becomes Lieutenant, both players get an alert). Before, admin could only set Lieutenant / Member / Prospect.

## 6. Unpaid land levy blocked buying and could not be paid
- **Cause:** the server was right (one open deal at a time, `invest_land_levy(deal, pay)` pays or walks away, a deal past `invest.land_deal_minutes` is released by the next buy). The client only kept the levy deal in the sheet that opened it: close the sheet and the deal stayed open with no way to see or pay it, and every new purchase said "You still have a land deal open".
- **Now:** Invest -> High risk shows an **Open land deal** card at the top of Land (from `invest_overview().pending_deal`) with plots, the levy, the total, **Pay levy** and **Walk away**, and a note that new land is blocked until one is picked. A cold deal is not shown and is released on the next buy. No server change; test group 6 covers show / block / walk / pay / expiry.

## 7. Laptops (MacBook, Dell) could not be bought
- **Cause:** `shop_buy` was fine (`items.sold_at` has the Benin City Mall and the Bronze Tech Hub). But players buy from the **buy cards inside a place**, which are rows in `zone_actions`, and the premium laptops had none: the mall aisle only had the fairly-used laptop, the Tech Hub had no laptop card, HK Quarters only the ThinkPad.
- **Now** (migration `20261110000300_laptop_cards.sql`, data only): cards for ThinkPad, EliteBook, Dell XPS 13, MacBook Air and MacBook Pro in the ShopRite aisles (**Benin City Mall**); the same plus the fairly-used laptop on the **Bronze Tech Hub** Hot desks; the fairly-used laptop and EliteBook at **HK Quarters**. Wi-Fi joint still sells the cheaper ones. Help article "Yahoo and EFCC" now says where to buy. Test group 7 buys every laptop at every place that lists it.

## 8. "Delete my account"
- **Settings -> Account -> Delete my account** (not shown to admins): step 1 says what goes and that it **cannot be undone** (and points to "Start a new life" for a fresh start with the same login), step 2 asks the player to type `DELETE`.
- Server: edge function `supabase/functions/delete-my-account` (deployed by the functions workflow, `verify_jwt = true`) calls `self_delete_start('DELETE')` with the player's JWT (migration `20261110000400_delete_my_account.sql`): checks the text, refuses admins, writes an `admin_audit` row (`self_delete_account`, username + email + balances snapshot, `admin_id` null) **before** deleting. Then it removes billboard / voice files (`bl_user_storage_paths`) and calls `auth.admin.deleteUser`. A failed delete is logged (`self_delete_account_failed`) and the player is told nothing was lost.
- **Same path as the admin delete, nothing new to orphan:** every game row goes by the `auth.users` cascade (docs/ADMIN.md "Delete account"); visitors are sent home by the `profiles` BEFORE DELETE trigger; payments stay anonymised; the audit row stays. `life_restart()` is different on purpose: it archives the Sim and keeps the login. Test group 8 deletes an account that has prefs, a device and furniture and checks every table with a foreign key to `auth.users` or `profiles` is empty for that id.
- The two new Fix it tables are covered: `club_alert_prefs` cascades, `crew_boss_requests` references `auth.users` with cascade; `crew_boss_log` keeps only ids as an audit trail (like `admin_audit`).

## 9. Phone banking
Bank app -> **Move** tab. Deposit and withdraw anywhere, any time, fee **1 %, at least N50** (admin: Settings -> Bank, `bank.phone_fee_pct`, `bank.phone_fee_min`, `bank.phone_enabled`, `bank.phone_max_amount`). The fee is shown before you confirm, paid on top, and is a pure sink. In person at Bronze Bank in banking hours is free as before; existing limits and fees on the counter and PoS are untouched. Per-go maximum defaults to the PoS maximum (N100,000) so the phone is not a loophole. See docs/BANK.md "Phone banking".

## 10. Choose which car to drive, and see your cars at home
- Migration `20261110000600_primary_car.sql`, test group 10. Table `player_primary_car` (user id, item id, cascade on delete). `bl_primary_item` (the pick while still owned and not blocked) and `bl_driving_item` (the pick, else the most expensive vehicle = the old rule, so nobody who never picks sees a change).
- Used by (guarded patches): **`bl_hustle_car`** (Bolt class, pay, fuel and wear multipliers, and with it `hustle_start`, the hustle cost / pay and challenge checks), **`bl_travel_quote`** (the "Your own car / motorcycle / bicycle" option, so fare, time and the **robbery risk shown for that ride**; the robbery roll itself uses the mode of the trip), **`garage_home`** (the car list puts the driven car first and marks `primary`). Selling the picked car falls back to the old rule by itself. `car_set_primary(item)` and `car_primary_get()` are the player RPCs.
- UI: **Phone -> Cars -> My cars** and the **garage sheet** show **Drive this car** on each car and a green **Driving** badge on the active one (`src/screens/game/DriveButton.tsx`, `src/state/primaryCar.ts`).
- 3D home: the driven car is drawn first. Without a garage the pad takes one car and the other cars line up on the street in front of the compound; every owned car is drawn up to **6 (3 on Low graphics)**, so a rich player stays light (`buildParking` in `room.ts`, merged geometry, no extra draw calls).

## 11. Balance: less robbery and EFCC, faster early skills
Numbers old -> new and the guard rule are in docs/BALANCE.md "Fix it 11". In short: trip robbery base 6 -> 4.5 % (ceiling 35 -> 25 %), one robbery takes 10 to 35 % of the cash on you (was 20 to 60 %, hard cap 35 %, the bank is never touched), pickpocket success 38 -> 30 % and a steal takes at most 10 % (was 15), Yahoo catch chances 12/16/20/24/14 -> 10/14/17/20/12 %, and skill XP x1.5 while a skill is level 1 to 3. Settings only move while they still equal their old default.

## 12. "Money disappeared", "my transfer didn't arrive", "someone sent me 2T and it vanished"
### What the code and the ledger design say (investigated, not guessed)
- **Nothing moves without a trace.** Every cash / bank change goes through `bl_add_money`, which updates the balance and writes a `ledger` row (reason, meta, balance after) in the same statement. A scan of every function that updates `profiles` money found no write that skips it (the mass gift writes its own ledger rows). Yahoo money is a separate balance with its own `yahoo_ledger`. Gang, company and business pots have their own logs.
- **Transfers are atomic and arrive in full.** `bank_transfer` takes amount from the sender's bank, the fee (and the stamp duty over N10,000) from the sender on top, and credits the **whole amount to the receiver's BANK** with a `transfer_in` row and an alert. Test group 12 proves: receiver +100,000, sender -(100,000 + fee), and the only money destroyed is the fee.
- **Plausible causes, most likely first:**
  1. **It landed in the bank, not the pocket.** Transfers, gifts and Paystack top-ups credit the bank; the pocket (cash) is what a player watches. The old History tab hid it after 40 rows.
  2. **Bills and taxes take it quietly.** Weekly bills (house, car insurance, business council tax, ground rent) and weekly income tax are collected on the due date from the bank first, then cash (`bl_sinks_settle`): a rich player with a car sees a big drop on Monday. They were in the ledger but read as "Bill: car".
  3. **A big transfer was refused, not lost.** The daily limit is N200,000 (`bank.transfer_daily_limit`), 10 transfers a day, 15 s apart, and new accounts (24 h, unless trusted) cannot send. A "2T" transfer cannot go through; the sender sees the error but may think it was sent (test: refused with the limit message, nothing moves). 2T can only come from an **admin grant or a mass gift** (cap `admin.grant_max`).
  4. **Admin take.** `admin_grant_money` uses one ledger reason for gifts and takes; the old label said "Admin Grant" for a debit, with no note. Now "Taken by a Benin Life admin" with the admin's note.
  5. **Street robbery and pickpockets** take cash only (labelled "Robbed on the street" / "Stolen from you"); the bank is never touched.
  6. **EFCC seizure.** Yahoo money in flight is seized when caught; it is in `yahoo_ledger`, which the old History did not show at all.
  7. **Starting a new life** (`life_restart`) archives the Sim and deletes the profile with its ledger (`profile_archive` keeps the last 100 rows for support); **deleting an account** removes everything. A player who restarted after receiving money has no history.
  8. **Other sinks:** spray (cash), club tips, fees (PoS, market, phone banking, transfer, stamp duty), VAT and luxury levy inside shop prices, travel fares, rent auto-charge, activity costs.
  9. **Mass gifts only reach the people targeted when sent** (everyone / LAPO / Nepo / joined after / online now); a player outside that audience, or one a gift would push past N9Q, is skipped.
- **Real bug found and fixed while testing:** none in the money paths. The history reading had gaps (above), and a paging trap: rows written by one action share one timestamp, so paging by time alone would skip or repeat rows. The new cursor is (time, key) and test group 12 walks every page and sees each row exactly once.

### What changed (migration `20261110000800_money_history.sql`, UI `src/screens/game/phone/MoneyHistory.tsx`)
- **Bank -> History** is now a real money history: every row says what it was in words, the note / reason, the account (Bank, Cash, Yahoo balance), the category (Admin, Bills and upkeep, Fees, Crime ...), the balance after, grouped by day, filter **All / Money in / Money out**, "Show older" paging, and a **summary** for the last 7 days (money in, money out, the biggest drains by category, Yahoo seized). Moving money between your own cash and bank (deposits, withdrawals, PoS, phone banking) is shown but never counted as spending.
- RPCs `money_history(limit, before, filter, before_key)` and `money_history_summary(days)`: read-only, own rows only, not granted to anon. Admin gifts and takes are labelled apart; Yahoo seizures are included.
- Help article "Cash and bank" says where to look.
