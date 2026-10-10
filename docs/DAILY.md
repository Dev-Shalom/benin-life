# D1: Daily reward and daily gem hunt

Migration `supabase/migrations/20261009000300_daily.sql` · tests `supabase/tests/daily_test.sql` · client `src/state/daily.ts`, `src/screens/game/Daily.tsx` + `Daily.css`, gem mesh in `src/art/place3d/engine/PlaceScene.tsx`.

Everything is decided on the server and keyed to the **WAT calendar day**: `bl_wat_date()` = `bl_now()` in `bl_clock_tz()` (default Africa/Lagos), so the day flips at midnight Benin time and tests can time-travel with `set_config('bl.test_offset_seconds', ...)`. Money moves only through `bl_add_money` (ledger), items through `bl_give_item`.

## Daily reward (7-day ladder)
- Table `daily_reward_steps` (day 1–7: `cash`, optional `item_id`, `label`), editable in admin **Content → Daily reward**. Seed: ₦1,000 · ₦1,500 · ₦2,000 · ₦2,500 + Kada chicken · ₦4,000 · ₦5,000 · ₦10,000 + Energy drink. The energy drink (`energy_drink`, +25 energy) is a reward-only item: not sold anywhere, not sellable.
- Table `daily_reward_state` (per player: `last_claim_date`, `streak_day`, `total_claims`).
- `daily_reward_status()` → `{enabled, date, ready, claimed, day, next, steps[{day, cash, item_id, item_name, item_icon, label, state: claimed|today|upcoming}], total_claims}`.
- `daily_reward_claim()`: once per WAT day (row lock + date check; a second call raises `already_claimed`). Yesterday claimed → next day (after day 7 back to day 1); any missed day → day 1 (gentle reset, nothing is taken away). Ledger reason `Daily reward (day N)`.
- Switch `daily.reward_enabled` (off = chip hidden, claims refused).

## Daily gem hunt
- `bl_gem_places(date)` picks `daily.gems_per_day` (default 3, max 10) places by `md5(date || ':' || place id)`, so every player gets the same hunt and it changes each WAT day. Eligible: `locations.active`, no `private_home_owner_id`, not a home scene or start home, not police/hospital, and always open (no opening hours), so a gem is never behind a closed door.
- Table `gem_finds` (`user_id, hunt_date, location_id` primary key = one find per gem per player per day; `prize`, `bonus`).
- `gem_hunt_status()` → `{enabled, date, total, found, found_all_players, prize, all_bonus, next_prize, here, gems[{idx, district, found, location_id, place_name, here}]}`. Hints are the **district** only; the exact place is revealed once found or while you stand in it (`here`), which is how the place interior knows to draw the gem.
- `gem_find(p_location)`: you must be at that place and not travelling (`not_here`), it must hold a gem today (`no_gem`), once per gem (`already_found`). Pays `daily.gem_prize` (default ₦3,000); the last gem also pays `daily.gem_all_bonus` (default ₦5,000), once per day. Ledger reasons `Daily gem hunt`, `Daily gem hunt bonus (all found)`.
- Switch `daily.gems_enabled` (off = chip and gems hidden, finds refused).

## Client
- Two chips in the HUD left rail (with the needs tips): **Daily reward ready · day N** (opens the 7-day sheet with the Claim button and a small confetti burst) and **Daily gem hunt · X/Y** with "N found · next prize ₦…" (opens the district hints). On phones (< 600 px) they are one-line chips stacked under the tips ("Daily reward · day N", "Gems X/Y · next ₦3,000"); when the rail is folded (map / place view) they show as 🎁 💎 icons in the summary pill. The reward chip only shows while a claim is ready; the gem chip shows until all of today's gems are found (and hides when the hunt is off).
- Inside a place that holds today's (unfound) gem, a glowing, bobbing gem floats in the interior; tapping it calls `gem_find`.

## Security
- RPCs: `execute` to `authenticated` only (revoked from `public`/`anon`). Helpers `bl_wat_date`, `bl_gem_places` are revoked from `public`, `anon`, `authenticated`.
- RLS on all three tables. Players get `select` only: the ladder (all rows), their own state, their own finds. No client insert/update/delete; all writes go through the security-definer RPCs.

## Tests
`bash scripts/sql-test.sh -- supabase/tests/daily_test.sql`: claim once per day + ledger label + day-7 item + grants, streak +1 next day, missed day resets to 1, deterministic pick that drops hidden places / private homes (checked over 40 days), `gem_find` needs you there and not travelling, no double find, all-found bonus + counters (own vs all players), players cannot write the tables or read others' finds, switches off.
