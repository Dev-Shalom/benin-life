# Crime: pickpocketing and jail choices (C1)

Files:
- `supabase/migrations/20261012001200_pickpocket_jail.sql`, `supabase/tests/pickpocket_test.sql`
- `src/api/crime.ts`, `src/state/crime.ts`, `src/screens/game/Crime.tsx`
- Hooks into existing files: `PlaceScene.tsx` (`onTapPlayer`), `Game.tsx`, `StatusBanners.tsx` (jail banner), `TaskPill.tsx`
- Admin: `src/admin/Players.tsx` (Open jail cases)

Street robbery on trips (`crime.npc_*`) is older and separate. It is unchanged.

## How a player steals
1. Inside a public place, tap another real player in the 3D scene. A sheet opens: their name, Add friend / Message, and **Steal 🫳**.
2. **Steal works only when you stand close to them.** The limit is `crime.steal_range_m` (default 3 m), measured on the thief's screen.
   - Player positions inside a place are drawn locally and are not synced between devices.
   - So the server checks something different: same public place, and the victim was seen there recently.
   - When too far, the sheet says "Walk closer: within 3 m (you're N m away)".
3. `steal_attempt(target)` starts a timed action: the "Picking a pocket" pill with a live bar, `crime.steal_seconds` (default 4 s).
   - The action can't be stopped.
   - When the timer runs out, `steal_finish()` rolls the outcome on the server.
   - After a reload, `crime_status()` finishes an action whose time is up.

### Checks (server)
| Check | Rule (setting) |
|---|---|
| Switch | `crime.steal_enabled` (default on) |
| Place | Both players at the same **public** place. Refused at a private player home, a start home, any `home*` scene, the police station, or while visiting a house. |
| Victim present | Not on the road, not in a cell or hospital, and seen at that place within `crime.steal_seen_seconds` (180 s) |
| Thief free | Not busy, jailed, in hospital or on the road (`bl_assert_free`) |
| Newbies | Accounts younger than `crime.steal_newbie_hours` (24 h) can't steal and can't be robbed. New-player protection (`protected_until`) also shields the victim. |
| Thief cooldown | One try per `crime.steal_thief_cooldown_s` (180 s), whatever the outcome |
| Victim cooldown | After a successful theft, nobody can rob that victim for `crime.steal_victim_cooldown_s` (600 s). Also refused while someone else is mid-steal on them. |
| Self | You can't rob yourself |

Locking:
- Both profile rows are locked in id order, at the start and at the roll. Two players robbing each other can never deadlock.
- If two thieves both reach the roll, the second gets `missed`: nothing is taken twice.

### Outcome (server roll at the end of the timer)
- **Caught:** chance `crime.steal_caught_pct` (62%) through `bl_steal_caught_pct(thief, victim, skill_mod)`.
  - **Skill hook:** `skill_mod` is always 0 for now. A future skill passes a positive number to lower the odds; CCTV could pass a negative one.
- **Not caught:** takes a random **5–15%** (`crime.steal_min_pct` / `crime.steal_max_pct`) of the victim's **cash on hand**. Bank money is never touched.
  - At least `crime.steal_min` (₦100) and at most `crime.steal_max` (₦50,000).
  - A victim with less than ₦100 has an "empty pocket": nothing happens.
  - Ledger: thief `steal_gain` "Pickpocketed · <place>", victim `steal_loss` "Stolen from you · <place>".
  - The victim's alert does **not** name the thief: "Someone picked your pocket at <place>: −₦X".
- **Victim walked away** during the timer: `gone`, nothing happens. The thief's cooldown still counts.
- **Caught details:**
  - Nothing is taken.
  - The victim gets "@thief tried to pick your pocket at <place> and was caught by the police."
  - The thief gets a `jail_cases` row and is held at Police HQ (`crime.jail_location`). `wanted` goes up by 1.

Rolls use `bl_rand()`, which is `random()` unless a test pins it with `bl.test_rand`.

## The case and the popup
`jail_cases`:
- Columns: user, reason, place, bail_amount, escape_attempts, jail_seconds, jail_until, decided, status (open / bailed / served / escaped / released).
- At most one open case per player.
- Players can read only their own rows (RLS). There are no client writes.
- Prices and odds live only on the server.

The **"Police don catch you!"** popup:
- Same card as the A2 gift popup (`bl-modal` + `bcast-*`). It can't be dismissed.
- It shows while the case is open and **undecided**, so it comes back after a reload or on login.

The three buttons:
- **Bail yourself · ₦20,000,000** (`crime.bail_base`).
  - Takes the bank first, then cash. Ledger `bail` "Bail".
  - Issues a receipt through `bl_receipt_issue`, because ₦20M is above `receipts.min_amount`.
  - Frees you at once.
  - The button is disabled when you can't afford it; the price stays visible.
- **Go to jail · 0:45**: serve the time.
  - Base time is the existing `action.jail_max_seconds` (45 s). The timer runs from the arrest.
  - The popup closes and the normal jail rules apply: you can't act, and the jail banner shows.
- **Try to escape**: caught again with `crime.escape_caught_pct` (52%).
  - **Fail:** jail time × `crime.escape_time_mult` (2) and bail × `crime.escape_bail_mult` (2), compounding.
    - Example: 45 s / ₦20M → 90 s / ₦40M → 180 s / ₦80M.
    - The popup comes back as "Dem catch you again!" with Stay in jail, the new bail and Try to escape again.
    - Jail time per case is capped at `crime.case_jail_max_seconds` (24 h).
  - **Success:** free, and you slip back to the place where you were caught.

While in the cell, the jail banner shows **Bail ₦X** (the current price) and **Escape**. The old `police_bail()` (₦5,000 story bail) sends you to the case price while a case is open. When the time runs out, the case becomes `served` the next time it is read.

## Admin
- **Settings → Crime & robbery:** every `crime.steal_*`, `crime.bail_base`, `crime.escape_*` and `crime.case_jail_max_seconds` key. Steal switch, caught chance and bail are also in the most-used list.
- **Players:** an **Open jail cases** box at the top. It shows player, reason, bail, failed escapes, seconds left, and whether they are deciding or serving.
  - Tap the player name to open the player.
  - **Release** (tap twice) calls `admin_jail_release`. It is audited as `jail_release` with the case, bail and reason, and the player gets an alert.

## RPCs
- Players: `steal_attempt(uuid)`, `steal_finish()`, `crime_status()`, `jail_case_bail()`, `jail_case_go_to_jail()`, `jail_case_escape()`.
- Admins: `admin_jail_cases(status, limit)`, `admin_jail_release(case_id, reason)`.
- All are security definer and revoked from anon.
- Private helpers (`bl_crime_*`, `bl_steal_*`) are revoked from clients.
- `crime_attempts` is server-only. A victim can never look up who tried.

## Balance notes
- An escape works 48% of the time and each failure only raises the price. Spamming Escape is usually the cheapest way out: about 2 tries on average.
- To make jail matter, raise `crime.escape_caught_pct`, or raise `action.jail_max_seconds`. That second key also affects story jail.
- ₦20M bail is far above a new player's money, so most caught players will escape or sit 45 s.

## Tests
`bash scripts/sql-test.sh -- supabase/tests/pickpocket_test.sql` (12 groups):
1. Grants and anon refused
2. Odds: seeded about 62%, skill hook, forced 0/100, pinned roll
3. Refusals: switch, self, newbie both ways, protection, private home, police station, other place, offline victim, victim on the road, busy, travelling, jailed
4. Success: cash only, 5–15%, ₦50k cap, ₦100 minimum, empty pocket, victim gone, ledger labels, alert without the thief's name, timer
5. Cooldowns
6. Caught opens a case
7. Bail: bank first, receipt, ledger
8. Go to jail, then served
9. Escape success, escape fail compounding, `police_bail` routing
10. Concurrent double steal
11. Admin list, release and audit
12. RLS
