# E2: More ways to earn (hustles, referral, weekly top earners, tips)

Owner-approved plan: `docs/ECONOMY_PLAN.md` section 3. Every pay, cooldown, cost, chance and cap is editable in Admin
(Content → Hustles / Bolt car classes / Fish; Settings → Side hustles / Referral bonus / Leaderboards / Tips).

Files:
- `supabase/migrations/20261014000400_hustles.sql`, `supabase/tests/hustles_test.sql` (15 groups)
- `src/api/hustles.ts`, `src/state/hustles.ts`, `src/lib/referral.ts`
- `src/screens/game/Hustles.tsx` (`<HustleHost/>`), `src/screens/game/phone/HustlesApp.tsx` + `.css` (the Hustles phone app)
- Hooks: `PlaceCard.tsx` (hustle cards), `TaskRunner.ts` / `tasks.ts` (kind `hustle`), `TaskPill.tsx` (💪, a hustle can't be stopped),
  `Phone.tsx` (Hustles app), `RanksApp.tsx` + `pay.css` ("This week" tab), `Game.tsx`, `main.tsx` (`?ref` capture), `Auth.tsx`
  (code goes into the signup metadata), `CreateSim.tsx` (claim after `create_profile_v2`), `api/shops.ts` (Work tools / Fish sections),
  `art/map/mapGeo.ts` + `art/city3d/model.ts` (pins), admin `Earn.tsx`, `Content.tsx`, `Settings.tsx`, `api.ts`, `AdminApp.tsx`.

## How a hustle works
- A row in `hustles`. A zone card (`zone_actions.kind = 'hustle'`, ref = hustle id) queues like any action: the Sim walks to the zone,
  then `hustle_start(id)` runs. The Hustles phone app can also start one (no walking).
- A timed action: busy label `Hustle: <name>`, live bar in the task pill, **cannot be stopped**, outcome rolled on the server by
  `hustle_finish()` (also after a reload: `hustle_status()` settles an overdue run).
- Order of checks (`bl_hustle_why`): switch, place (and the place's opening hours), the hustle's own Benin hour window, car (+ wear),
  tool item, stall pass, energy (`hustles.min_energy` 10), daily cap (Benin day), cooldown; then money for the cost (cash first, then bank).
- Rolls (`bl_hustle_resolve`): loss (fraud) → bad luck → bonus; then the pay (`pay_min..pay_max` × car class × time of day ×
  "no tool" multiplier, rounded to ₦100). Pay goes to cash with ledger reason `hustle` ("Hustle: <name>"); cost is `hustle_cost`
  ("Fuel: …", "Ingredients: …", "Bait: …", "Parts: …"); fraud is `hustle_loss`.
- Instant buys (`hustle_buy`): `pass` (stall rent) and `service` (car service). Ledger `hustle_pass` / `hustle_service`.
- Hustle DJ / MC sets post a club shout-out (`place_announcements`, kind `shoutout`) and give street cred.

## The hustles (defaults; ₦ per run)
| Hustle | Where | Time | Pay | Cost | Cooldown | Daily cap | Needs | Risk |
|---|---|---|---|---|---|---|---|---|
| Bolt driver shift | any public place (not home) | 40 s | ₦9k–₦15k × car class; rush hours ×1.2/×1.25, night ×0.8 | fuel ₦3,200 × class | 90 s | 5 | own car, car not worn out | 8%: rider cancels, half fare. +10% car wear per run |
| PoS agent batch | any market or PoS stand (open hours 6–20) | 25 s | ₦2.5k–₦6.5k commission (×1.2 at 7–10 and 17–19, ×1.15 at 12–14) | – | 60 s | 6 | PoS machine ₦35k (markets, PoS stands) | 12% network down (no pay), 4% fraud (lose ₦5k–₦20k) |
| Rent a food stall | Oba Market | instant | – | ₦3,000 for 24 h (renting again adds a day) | – | – | – | – |
| Sell jollof rice | Oba Market | 35 s | ₦6.5k–₦11k; lunch (11–15) ×1.5, 17–20 ×1.2, morning ×0.6 | ingredients ₦4,500 | 40 s | 4 | rented stall | 10%: pay ×0.4 |
| Sell puff-puff | Oba Market | 20 s | ₦2.8k–₦5k; 6–10 and 16–20 ×1.3 | ₦1,500 | 30 s | 4 | stall | 10% |
| Sell fried yam & egg | Oba Market | 30 s | ₦4.5k–₦8k; breakfast ×1.6, afternoon ×0.5–0.8 | ₦2,500 | 35 s | 4 | stall | 10% |
| DJ set | any open club | 60 s | ₦15k–₦35k (×0.4 warm-up slot without a controller); 15% crowd tip ₦10k–₦30k | – | 180 s | 2 | DJ controller ₦220k (Tech Hub, Mall) for full pay | +3 street cred, shout-out |
| MC the night | any open club | 45 s | ₦8k–₦18k; 20% tip ₦5k–₦15k | – | 120 s | 3 | nothing | +2 street cred, shout-out |
| Tutor a student | UNIBEN | 40 s | ₦6k–₦12k; 10% parents' bonus ₦5k–₦15k | – | 60 s | 4 | daytime 8 AM–5 PM | – |
| Go fishing | Ikpoba River Bank | 25 s | a random fish (see below) | bait ₦300 | 20 s | 10 | fishing rod ₦8k; 5 AM–7 PM | 10% nothing bites |
| Quick fix | Sapele Rd Mechanic Village (7 AM–7 PM) | 30 s | ₦3.5k–₦8k | parts ₦1,000 | 45 s | 5 | – | – |
| Engine job | Mechanic Village | 50 s | ₦9k–₦18k | parts ₦3,000 | 90 s | 2 | – | 10%: customer argues, half pay |
| Service your car | Mechanic Village | instant | – | ₦20,000 × class wear | – | – | own car with wear | resets wear to 0 |

Why these numbers (Nigeria, Oct 2026): a Bolt driver in a Benin-size city grosses roughly ₦25k–₦45k a day and spends about a third
on fuel and a fifth on upkeep, so five 40-second shifts at about ₦12k gross minus ₦3.2k fuel and wear ≈ ₦45k a day for a ₦1.8M car
that costs a few weeks of that to buy. PoS agents earn ₦300–₦500 commission per ₦20–₦30k batch (≈1–1.5%) with real fraud and
network risk. Home lessons pay ₦3k–₦10k an hour. A PoS terminal costs ₦20k–₦45k, a beginner DJ controller ₦150k–₦300k, a rod and
line ₦3k–₦15k. A day's market stall rent is a few thousand naira. Daily caps keep the total small against shifts
(₦2k–₦120k each): one player cannot do everything in a day, and most are location-bound.

### Bolt car classes (`hustle_car_classes`)
The best car owned decides the class by price: Economy ≥ ₦1.7M (Kia Rio, tokunbo saloon; pay ×1, fuel ×1, wear ×1), Comfort ≥ ₦6M
(Camry "Muscle", Lexus; ×1.5, ×1.3, ×1), Premium ≥ ₦40M (Hilux, new Camry, C300; ×2.2, ×1.7, ×1.4), Black ≥ ₦150M (GLE, Cybertruck,
Escalade, G-Wagon, Urus; ×3.5, ×2.4, ×2). The bicycle and the Boxer are below the lowest class. Wear: `wear_pct` (10) × class per shift;
at 100% Bolt is refused until the car is serviced. NPC passengers only; picking up real players comes later.

### Fishing (`hustle_fish`, items category `fish`, price = value, sold at any market with Sell at 100%)
Small tilapia ₦1,200 (weight 40), tilapia ₦2,500 (25), catfish ₦5,500 (17), big mudfish ₦9,000 (8), giant catfish ₦30,000 (2),
old slippers ₦150 (8). Average catch ≈ ₦3.4k. Fish are sold with the normal market Sell (ledger `shop_sell`, so fish sales are not
counted in the weekly earnings).

## New places
- **Ikpoba River Bank (Ikpoba Bridge)**, `ikpoba_riverbank`, district Ikpoba Hill, map (655, 455): the east bank just past the
  Akpakpava Rd bridge before Ramat Park (the Ikpoba River runs N–S at x≈655–695, docs/MAP_GEO.md). Scene `farm` (earth yard kit) with
  its own zones: river, fishing spot, bait & tackle kiosk (sells the rod), shade trees. Always open; fishing itself 5 AM–7 PM.
- **Sapele Rd Mechanic Village**, `mechanic_village`, district Sapele Rd, map (590, 800), open 7 AM–7 PM. Scene `workshop`
  (the bronze-casting furnace and display are hidden here); the repair bay holds the three cards.
- Zone cards also sit at: motor park keke rank and street corner (Bolt), market traders row and PoS kiosk (PoS agent + buy the
  machine), Oba Market "Your food stall" (rent + 3 foods), club DJ booth (DJ) and dance floor (MC), UNIBEN lecture hall (tutoring).

## The Hustles phone app
💪 Hustles on the home grid. Two tabs:
- **Hustles**: earnings so far, the running hustle's live bar, the last result, your Bolt car (class, multipliers, wear bar), then every
  hustle grouped (On the road / Markets / Clubs at night / Daytime work) with where to go, pay range, time, cooldown, runs left today,
  hours, cost, tool owned or needed (and where it is sold), risk / loss / bonus chips and one button: Start, "Go to <place>",
  "Needs <item> · <shop>", Wait 0:25, Done for today or Busy.
- **Invite & earn**: your referral card (below).

## Referral
- Every player has a code (7 upper-case characters, made on first view) and the link `https://playbeninlife.app/?ref=CODE`
  (`referral.base_url`).
- `src/lib/referral.ts` keeps `?ref` in localStorage (`bl.ref`) from the first visit; signup also puts it into the auth metadata
  (`referral_code`, survives email confirmation on another device); after `create_profile_v2` the app calls `referral_claim(code)`
  silently (server refusals are not shown), and `<HustleHost/>` retries it when the game opens.
- Rules (`referral_claim`): switch `referral.enabled`; code must exist and not be the player's own (`self`); one referral per new
  account (`referred_id` is unique, `already_referred`); the account must be younger than `referral.max_account_age_hours` (48,
  `too_late`); the inviter may sign up at most `referral.daily_cap` (5) a Benin day and `referral.max_total` (100) ever (`capped`);
  banned inviters are refused.
- Milestone (any ONE; `bl_referral_progress`): `referral.min_shifts` (1) finished work shifts, `referral.min_hustles` (3) finished
  hustles, or `referral.play_minutes` (60) minutes of play (each `referral_status()` check-in adds at most 5 minutes; the app checks in
  every 90 s while the Invite tab is open and on game start). It is checked on every check-in and when a hustle finishes. A finished work shift is picked up at the next check-in
  (a shift finishing does not call it directly).
- Reward: both get cash (`referral.bonus_referrer` / `referral.bonus_referred`, default ₦20,000 each), ledger "Referral bonus", an
  event for each, paid once (status `pending → rewarded` in one update). A banned inviter at payout time → `rejected`.
- Admin: Earn page lists every referral (inviter, new player, status, play minutes, bonus).

## Weekly top earners
- Earned = positive ledger rows whose reason is in `leaderboard.earn_reasons` (default `salary, hustle, harvest, farm_harvest,
  invest_income`) in one ISO week (Monday 00:00 to Sunday 24:00, Benin time). Hustle costs are not subtracted. Transfers, gifts,
  admin gifts, tips, sales, Yahoo cash-outs, weekly prizes and referral bonuses do not count. Add reasons in Settings if wanted.
  Admins and banned players are hidden (`leaderboard.hide_admins`).
- The Ranks phone app has a **🔥 This week** tab: podium, list, your pinned row, the prizes, the minimum, and last week's winners.
- Settling is lazy and idempotent: the first call after a week closes (`weekly_leaderboard()` or `hustle_status()`) inserts the week
  row in `weekly_earn_weeks` (unique) and pays; later calls do nothing. Up to 8 missed weeks are settled. The week before the migration
  was marked `skipped`, so nothing is paid retroactively.
- Prizes (config): 1st ₦200,000, 2nd ₦100,000, 3rd ₦50,000 into the **bank** (ledger "Weekly top earners prize"), only if the player
  earned at least `leaderboard.weekly_min_earned` (₦20,000). Winners get a targeted broadcast popup (the A2 `broadcasts` table, one row
  per winner, `broadcast.last_id` bump) and an event. Admin: Earn page shows each week with its winners.

## Tips (for Benin Gist, built later)
`tip_player(username, amount, note)`: server only for now (a `-- BENIN GIST HOOK` comment marks it). From the tipper's bank first, then
cash, into the creator's bank; ledger "Tip to @x" / "Tip from @x"; table `tips`; event to the creator. Limits `tips.min_amount` (₦100),
`tips.max_amount` (₦1M), `tips.daily_max` (₦5M), no self-tips, new-account wait like transfers (`bank.transfer_min_account_real_minutes`,
skipped for trusted accounts). `tips_mine()` lists my tips. Tips are not weekly earnings.

## Tables and RPCs
- Catalogues (authenticated read, admin write): `hustles`, `hustle_car_classes`, `hustle_fish`, `weekly_earn_weeks`, `weekly_earn_winners`.
- Own rows (read): `hustle_players`, `hustle_passes`, `hustle_runs`, `referral_codes`, `referrals`, `tips`. No client writes anywhere.
- Players: `hustle_status`, `hustle_start`, `hustle_finish`, `hustle_buy`, `referral_claim`, `referral_status`, `weekly_leaderboard`,
  `tip_player`, `tips_mine`. Admin: `admin_earn_overview`. Private (revoked from clients): `bl_hustle_*`, `bl_referral_*`, `bl_weekly_*`,
  `bl_week_*`, `bl_earn_reasons`.
- Guarded edits of live functions: `place_interior`, `bl_zone_action_check`, `bl_ledger_label`, `bl_admin_table_spec`; the
  `zone_actions_kind_check` constraint gained `hustle`.

## Tests
`bash scripts/sql-test.sh -- supabase/tests/hustles_test.sql` (15 groups): grants and anon, seeds, Bolt (no car, at home, fuel, fare,
risk, classes, wear → service, rush multiplier), PoS (tool, closed market, fraud, network, rush), food stall (rent, extend, profit by
time of day, expiry), DJ / MC, tutoring (bonus, daytime, daily cap), fishing (rod, bait, weighted fish, sell, daylight), mechanic,
general rules (cooldown, energy, switch, admin edit, overdue settle), cards and status, referral (all refusals, three milestones, paid
once, caps, RLS, admin), tips, weekly leaderboard (income only, prizes once, popup, minimum, admin history), RLS.
Pins: `bl.test_offset_seconds` moves the Benin clock (markets close at 20:00, clubs open 21/22–05:00), `bl.test_rand` pins the rolls.
Also updated: `map_geo_test.sql` (two more places). Note: `places_test.sql` has a hype-man price assertion that fails on Fridays and Saturdays
(weekend club prices ×1.5); that is not an E2 effect.

## Not done / later
- Picking up real players for Bolt, a DJ controller upgrade ladder, and hustle ranks.
- Fish sales are `shop_sell`, so they are not weekly earnings (fishing pays nothing in cash).
- The referral milestone does not hook the work-shift code directly (checked at the next check-in).
