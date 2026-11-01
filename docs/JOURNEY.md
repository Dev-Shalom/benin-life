# New-player journey ("Your first days")

A short quest line over a new player's first 3 days, so they reach day 3 with goals, money and friends. Migration `supabase/migrations/20261109000100_journey.sql`, test `supabase/tests/journey_test.sql`.

## Steps and rewards (Admin -> Content -> Journey steps)
| Day | Step | Reward |
|---|---|---|
| 1 | Take the quick tour | ₦500 |
| 1 | Eat something or rest at home | ₦500 |
| 1 | Get a job and finish one shift | ₦1,500 + meat pie |
| 1 | Buy something for your home | ₦1,000 |
| 1 | Read today's story | ₦500 |
| 2 | Claim your daily reward | ₦1,000 + energy drink |
| 2 | Earn ₦15,000 in total | ₦1,500 |
| 2 | Add a friend or send a message | ₦1,000 |
| 2 | Join a Benin Gist group or post | ₦1,000 |
| 2 | Visit 3 places on the map | ₦1,000 |
| 3 | Come back for day 3 | ₦1,000 |
| 3 | Learn a skill or start a course | ₦1,500 |
| 3 | Save money in the bank | ₦1,000 |
| 3 | Check your dream | ₦500 |
| end | Finish everything | ₦3,000 + Kada chicken + "Benin Newcomer" badge |

All steps: ₦14,500 + the ₦3,000 bonus, less than a day of starter work, so it cannot be farmed. Rewards are "New player reward" in the ledger: not earnings, no tax.

## Rules
- Day 2 steps unlock on the player's 2nd distinct play day (player_days, WAT), day 3 on the 3rd. Steps are checked from real game data on the server; the client only shows them.
- Offered to accounts younger than `journey.max_age_days` (7). `journey.offer_existing` (off) can also offer it to older players with fewer than `journey.low_level_shifts` (10) shifts.
- One push when day 2 and day 3 unlock (not before 10:00 Benin time, existing push caps), plus in-game alerts when a step completes.
- Everything under Settings -> Journey; `journey.enabled` switches it off. `journey.reward_pct` scales all step rewards.

## Where players see it
A "Your first days" card in the left rail (next to the Today list) with the next steps, Go buttons and a progress bar; tap for the full list by day. A small celebration when a step is claimed. Admin -> Growth shows a funnel: how many players reached each step.
