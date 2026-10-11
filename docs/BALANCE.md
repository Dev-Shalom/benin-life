# Money balance at launch (L1, 2026-10-12)

Numbers read from the local database (same defaults as live unless you changed them in Admin). Nothing here is changed by a migration: these are **suggestions for you to set in Admin**. Every key is in Admin → Settings (search the key), except rents, which are in Admin → Content → Homes.

The clock is real Benin time (`clock.mode` = real). One game day is one real day. Hunger drops about 4 points an hour (`needs.hunger_per_hour` 4 × `needs.decay_speed` 1), so a Sim needs about 2 proper meals a day.

## What a new player has

| | LAPO (Ekenwan face-me) | LAPO (UNIBEN hostel) | LAPO (Uselu self-contain) | Nepo (GRA duplex) |
|---|---|---|---|---|
| Start cash | ₦8,000 | ₦6,000 | ₦4,000 | ₦50,000 + ₦500,000 bank |
| Weekly rent | ₦1,500 | ₦1,000 | ₦4,000 | ₦25,000 |
| Extras | none | none | none | ₦5,000/day allowance, 2 career levels head start, tokunbo car (list ₦2.5M), laptop |

## A LAPO player's first days

| | Per day |
|---|---|
| Food, cheapest way (cook at home ₦600 for 45 hunger, garri ₦300 for 20) | about ₦1,300 to ₦2,000 |
| Rent (face-me) | about ₦215 |
| Starter job (3 shifts a day, `career.max_shifts_per_game_day` 3): Trade ₦2,000, PoS ₦2,500, Health/Transport ₦3,000, Tech ₦3,500 a shift, up to 120% when well fed and rested | ₦6,000 to ₦10,500 |
| Daily reward (7-day ladder ₦1,000 → ₦10,000) | ₦1,000 to ₦10,000 |
| Gem hunt (3 gems × ₦3,000 + ₦5,000 bonus for all three) | up to ₦14,000 |

**Verdict:** a LAPO player covers food and rent from the first day of work; nobody is stuck. After a week of steady shifts (about ₦40,000) they can afford the ₦16,000 move into a self-contain. In the journey test (L1lapoA) one shift paid ₦2,390.

**Can someone go broke for good on day 1?** No. Walking is free, applying for a job is free, sleeping at home is free and restores energy, and a shift only needs hunger ≥ 10 and energy ≥ 15. The worst case is a Sim with no money and hunger under 10 after claiming today's reward: they wait until midnight (Benin time) for the next daily reward (₦1,000 buys three garri) or pick up a gem by walking, then work again. Starving only drains health to a floor of 10. Rent they can't pay becomes rent owed (sleep restores less energy until it is paid) and is never a dead end. So no default is changed in the migration.

**Nepo:** comfortable, not maxed. The ₦500,000 bank covers 20 weeks of duplex rent; good furniture costs ₦0.1M to ₦6.5M per piece and cars ₦1.6M to ₦250M. The one shortcut: selling the free tokunbo car on day 1 pays ₦1.5M (60% of list) into the bank.

## Recommended admin values

| Key | Current | Suggested | Why |
|---|---|---|---|
| `daily.gem_prize` | 3000 | **1000** | Three gems a day pay more than a full day of starter work (₦14,000 vs ₦6,000). Lower so work stays the main income and alt accounts farm less. |
| `daily.gem_all_bonus` | 5000 | **2000** | Same reason. With the line above the hunt pays up to ₦5,000 a day. |
| `cars.resale_pct` | 60 | **45** (optional) | A Nepo can sell the free starter car for ₦1.5M on day 1. At 45% it is ₦1.1M. Also matches `furniture.resale_pct` 45. |
| Content → Homes → GRA duplex weekly rent | 25000 | **50000** | Real GRA duplex rent is about ₦3M to ₦6M a year (₦60,000 to ₦115,000 a week). ₦50,000 still gives a Nepo 10 weeks from the start bank, and makes the allowance and a job matter. |
| Content → Homes → Mini-flat weekly rent | 8000 | 8000 (keep) | In line with real Mission Road prices (₦300k to ₦500k a year). |
| Content → Homes → Uselu self-contain start cash (LAPO) | 4000 | **6000** | LAPO players who pick it start with exactly one week's rent and ₦0 for food. ₦6,000 leaves two days of food. |
| `origin.nepo.allowance_daily` | 5000 | 5000 (keep) | Small next to Nepo pay; a nice daily touch. |
| `career.pay_mult` | 1 | 1 (keep) | Starter pay already covers food and rent from day 1. |
| `career.max_shifts_per_game_day` | 3 | 3 (keep) | Caps grinding at about 1 minute of real work a day per job level. |
| `house.move_in_weeks` | 4 | 4 (keep) | Self-contain move after about a week of work feels right. |
| `bank.transfer_min_account_real_minutes` | 1440 | 1440 (keep) | Stops new alt accounts sending their freebies to a main account on day 1. |
| `origin.nepo_pct` | 10 | 10 (keep) | Nepo should stay rare. |
| Top-up packs (Content → Top-up packs) | ₦200 → ₦20,000 game naira | keep | ₦20,000 is about three days of starter wages: worth it, not game-breaking. |

Change them after launch traffic shows how fast people earn: Admin → Overview → "Money today by reason" shows where the naira comes from (look for `Daily gem hunt` vs `work`).
