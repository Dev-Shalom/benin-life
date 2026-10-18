# R5: daily and weekly challenges

Migration `supabase/migrations/20261018000200_challenges.sql` · tests `supabase/tests/challenges_test.sql` (12 groups) ·
client `src/api/challenges.ts`, `src/state/challenges.ts`, `src/screens/game/Challenges.tsx` + `.css` ·
hooks: `Hud.tsx` (chip in the Today list, sheet), `Game.tsx` (`<ChallengeSync/>`), `state/game.ts` (`challenge_done` event -> toast) ·
admin: `Content.tsx` (Challenge templates, Challenge stats), `Settings.tsx` (category Challenges).

Everything is server-authoritative: the client never sends progress. Reasons to log in every day without shouting at anyone: three small daily
goals, three bigger weekly ones, a chest for finishing a set.

## Model
- `challenge_templates` (admin table): `kind` daily|weekly, `goal`, `target`, `param`, `needs`, rewards (`reward_cash`, `reward_xp` = career XP,
  `reward_skill` + `reward_skill_xp`, `reward_item` + qty), `weight`, gates (`min_skill` + `min_skill_level`, `req_cert`, `needs`), `friends` tag,
  `active`. 32 daily and 13 weekly seeded (English with a little Pidgin, edit in Content -> Challenge templates).
- `player_challenges`: one row per player, kind, period and slot (unique). The goal, target, param and rewards are COPIED from the template when it is
  handed out, so an admin edit never changes a challenge that is already running (title, blurb and icon are read live). `progress`, `refs` (the
  distinct places / players already counted), `completed_at`, `claimed_at`, `expired`.
- `challenge_chests` (primary key user + kind + period = open once), `challenge_rerolls` (used count + the templates already swapped out).
- Players can only read their own rows (RLS); templates are not readable by players at all; there are no client writes. All RPCs are security definer.

## Periods
- Daily: the Benin date (`bl_wat_date()`, midnight Benin time). Weekly: `bl_week_start()` (Monday 00:00 Benin time), the same boundary as the weekly
  top earners (`bl_week_from(week + 7)` is the end of both).
- A finished challenge can only be claimed while its period runs (`expired` hint after that); unfinished old rows are flagged `expired` so the hot
  index stays small. No streak penalty, no carry-over.

## Goals (counted from real events by AFTER triggers, all calling `bl_challenge_bump(uid, goal, amount, ref)`)
| Goal | Counted when | Trigger on |
|---|---|---|
| `hustle_done` | a hustle run finishes (not a loss); param = hustle id | `hustle_runs` status -> done |
| `earn` | a positive ledger row whose reason is in `bl_earn_reasons()` (salary, hustle, harvest, farm_harvest, invest_income: the weekly top earners rule); param = a reason | `ledger` insert |
| `shift` | a career shift is settled (`job_total_shifts` goes up) | `profiles` |
| `class` | a class finishes (pass or fail) | `course_runs` status -> done |
| `yahoo_clean` | a Yahoo job ends `paid` or `cashed` (not `caught`) | `yahoo_runs` |
| `visit_place` | arriving at a different public place (homes never count; each place once per challenge) | `profiles.location_id` |
| `club_spend` | a spray, or a club activity paid while standing in a club | `ledger` (negative `spray` / `activity`) |
| `spray` | naira sprayed | `ledger` (negative `spray`) |
| `dm_send` / `dm_people` | DMs sent / different people DMed | `player_messages` |
| `fish` | a hustle that caught a fish (not "nothing bit") | `hustle_runs` |
| `skill_up` | skill levels gained (works out the level from XP before and after); param = a skill | `player_skills` |
| `buy_item` | a shop, furniture or car purchase; param = an item | `ledger` (negative `shop`, `furniture`, `car_purchase`) |
| `streak` | the daily reward streak reaches the target (keeps the highest value, and starts from the streak held when the challenge is handed out) | `daily_reward_state` |
| `friend_hustle` | a hustle finishes while an accepted friend is standing at the same place (not travelling, seen in the last 10 minutes) | `hustle_runs` |
| `friend_house` | a house visit is admitted (guest AND host count, once per friend) | `player_house_invites` |
| `friend_meet` | arriving at a public place where a friend is standing right now | `profiles.location_id` |

`bl_challenge_bump` is cheap: it calls `bl_chal_open(uid, goal)`, ONE probe of a partial index (`player_challenges_open_idx`, open rows only), and returns
when the player has no open challenge for that goal. The same probe hands out the day's set the first time a player does anything on a new day (so
progress is never lost because the panel was not opened); a player with nothing today pays one more primary-key probe. Triggers that need an extra
lookup (friends, conversation, club) call `bl_chal_open` first.
Not counted: other players' friend goals (only the player who acts gets the progress), place chat messages (DMs only), fish that are not caught.

## Assignment (`bl_challenge_assign`)
- Each player gets `challenges.daily_count` (3) dailies and `challenges.weekly_count` (3) weeklies; only empty slots are filled, so changing the setting
  mid-day adds sets without touching the running ones.
- Weighted random WITHOUT a random number generator: key = -ln(u) / weight with u taken from `md5(player || kind || period || template id)`. The same
  player and period always give the same set (deterministic), different players differ, every day differs. Pass 1 prefers goal types the player does
  not hold yet (variety), pass 2 fills what is left.
- Skipped when the player cannot do it yet (`bl_chal_can`): `min_skill` level (skills on), `req_cert` (school on), and `needs`:
  `job` (shift goals), `laptop` (Yahoo), `enrolled` (classes, a course in progress), `friend` (any friend, implied for DM and friend goals), or an item id
  (e.g. `fishing_rod`; implied needs are listed in the function). A hustle goal with a param follows that hustle's own gates: skill level,
  certificate, car, pass and the required kit (a DJ set needs the controller, even though the hustle can be done badly without it).
- One reroll per day (`challenges.rerolls_per_day`, weekly default 0): swap an unfinished challenge for another one. Progress on it is lost, a
  swapped-out template never comes back that period, and `no_alternative` says when nothing else fits.

## Rewards
- Claim (`challenge_claim`): once only (row lock + `claimed_at`), pays cash into the ledger with reason `challenge` (label "Challenge: <title>",
  meta has title, kind, template, period), career XP (only while the player has a job; it feeds the next promotion check), skill XP (through
  `bl_chal_skill_xp`, which writes the normal level-up event) and an item.
- Chest (`challenge_claim_chest('daily'|'weekly')`): every challenge of the period finished. Once per period. Defaults: daily chest ₦3,000 + 20 career
  XP + an energy drink; weekly chest ₦20,000 + 100 career XP + kada chicken.
- `challenges.reward_mult` multiplies every cash reward when it is paid (2 = double-cash weekend).
- Rewards never count as earnings: `challenge` is not in `bl_earn_reasons()`, and the function is patched so it is dropped even if an admin types it
  into `leaderboard.earn_reasons`. A challenge payout never moves an `earn` challenge either.

## Events and push
- Finishing a challenge writes an `events` row `challenge_done` (title "<icon> <title> done!", `data.chest_ready` when it was the last of the set).
  The app turns it into a small toast and refreshes the list.
- Push (events category) when a player finishes the whole weekly set: one push, deduped per week, skipped while the player is active in the game, and
  only for players who opted in to the events category (it is off by default). Switch: `challenges.push_weekly` (default on). Dailies never push.

## UI
- HUD: a "Challenges · 1/3 today" row in the Today list (with a red dot when a reward or a chest is ready, a trophy in the folded pill). It hides when
  there is nothing left to do. Tap = the sheet.
- Sheet: tabs Today / This week (red count of things to claim), each with the time left, one card per challenge (icon, title, "with friends" tag,
  progress bar and count, reward chips, Claim, "Swap · 1 left") and the chest card at the bottom (lock, glow when ready, Open).

## Admin
- Content -> Challenge templates (all fields, Active switch, cash inline) and Challenge stats (read-only: assigned, completed, claimed, % and last
  completion per template, from the view `challenge_template_stats`).
- Settings -> Challenges: `challenges.enabled`, `daily_count`, `weekly_count`, `rerolls_per_day`, `rerolls_per_week`, `reward_mult`,
  `daily_chest_cash` / `_xp` / `_item`, `weekly_chest_cash` / `_xp` / `_item`, `push_weekly`.

## Defaults the owner should know
- Cash per daily challenge ₦800 to ₦4,500 (most ₦1,000 to ₦3,000); a full set of three is about ₦5,000 to ₦9,000 plus the ₦3,000 chest. Weeklies pay
  ₦6,000 to ₦15,000 each, a full set ₦25,000 to ₦35,000 plus the ₦20,000 chest. That is roughly the same size as a shift or two a day, so work stays
  the main income; if it feels generous set `challenges.reward_mult` below 1 or lower the chests.
- There is no "gems" currency in the game (gems are only the daily gem hunt), so the "gems" reward from the brief was replaced by an item reward
  (`reward_item`).
- There is no general "player level", so level gating is by skill level and certificate.
- Weekly rerolls are off (0); the daily chest and weekly chest each include an item (set the item id empty to drop it).
- A finished challenge not claimed before the day or week ends is lost (no grace period). The Claim button and the time left are on the card.
- Spray and club spending are counted from ledger rows; friend goals only reward the player who acts (the friend waiting gets nothing).

## Tests
`bash scripts/sql-test.sh -- supabase/tests/challenges_test.sql`: grants and RLS, seeds and settings, deterministic assignment, gating (certificate,
skill, job, friends, hustle kit), progress from a real hustle / shift / earnings, claim once (cash, career XP, skill XP, item, snapshot rewards),
reroll limits, chests (daily, weekly, push), reset on the next day and the next week (time travel with `bl.test_offset_seconds`, lazy hand-out on the
first action of a new day), rewards excluded from weekly earnings, every other goal, the no-op path, the master switch, the reward multiplier and the
admin editor and stats.
