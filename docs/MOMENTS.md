# Life moments (the BitLife-style pop-ups)

Migration `supabase/migrations/20261028000100_life_moments.sql`, test `supabase/tests/life_moments_test.sql`, client `src/screens/game/MomentsHost.tsx`, `src/state/moments.ts`, `src/api/moments.ts`. Reusable: school requests (step B) and cooking (step C) create cards through `bl_moment_create(user, moment_id, context, due)`; the kids use it for the doctor.

## How it plays
A card pops up like the Babalawo card: speaker line, icon, a short story, up to 4 choices stacked, and "Remind me later". One card at a time, a toast tells the outcome. It is held while another popup, the spray sheet, a money drop, a task, travel, or a club or lounge floor owns the screen.

## Server (all lazy, no cron, no new realtime)
- `moments_pending()`: the one cheap read. It expires old cards, rolls at most one random card when the player's `player_moment_state.next_roll_at` has passed (a primary-key read), and returns at most `moments.max_shown` (2) due cards plus "handled by your partner" notes. The app asks every `moments.poll_seconds` (90) through `startPoller` (canPoll, idleFactor) and on open.
- Rolling: not while busy, travelling, in a cell or a bed, or in a club or lounge (retry in 10 min); at most `moments.daily_cap` (3) per Benin day (kids cards count; a sick child always gets its card); never on top of 2 unanswered cards; wait of `gap_min`..`gap_max` minutes (45..180) between cards; per-moment `cooldown_days`; pick by `weight` among moments whose conditions pass.
- `moments_answer(instance, choice)`: pays the choice's `cost` first (ledger `life_moment`, a sink), rolls the optional `chance`, applies the effects, schedules follow-ups, returns `{outcome, tone, effects[], spent, success}`. All or nothing: any failing effect (money, missing item) undoes everything and the card stays open. Gains (`cash` +) use the same reason and are **never earnings**.
- `moments_snooze`: hides for `moments.snooze_hours` (2); after `moments.max_snoozes` (3) the next one is Ignore (the choice marked `ignore` is applied). Cards also expire as Ignore after `moments.expire_hours` (36) from when they were due. `moments_open` brings a hidden card back (the "See the doctor" button). `moments_seen` clears a "handled by" note.
- Doctor cards (`kind kids_ill`) go to BOTH parents; the first parent whose treatment cures the child resolves it, and the other card turns into "Already handled by @x 💛".

## Writing a moment (Admin -> Content -> Life moments)
Fields: id, title, body (`{name}`, `{child}`, `{partner}`), icon, speaker, kind (`random`, `kids_ill`, `system`), conditions, choices, cooldown days, weight, push, on/off.
- **Conditions** (JSON): `min_days`, `max_days` (account age), `has_child` (`["nursery","primary"]` or `["any"]`), `at` (place ids), `need_below` / `need_above` (`{"fun":40}`), `hours` (`[16,24]`, Benin time, `[22,5]` wraps), `min_cash`, `max_cash` (cash + bank), `has_item`.
- **Choices** (JSON list, 1 to 4): `{id, label, cost, effects, outcome, chance, fail_effects, fail_outcome, ignore, next_moment, next_delay_hours, next_chance}`. `chance` (0-100) picks `effects` or `fail_effects`; the cost is paid either way. An Ignore choice must be free.
- **Effects (the whole closed list)**: `cash {amount, up_to?}` (negative pays, `up_to` takes what the player has), `needs {delta:{hunger,energy,hygiene,fun,social,health,stress,bladder}}` (each -50..50), `kid_need {need, delta, all?}`, `kid_cure`, `kid_ignore` (counts as an ignored warning), `item {id, qty}` (negative uses), `skill_xp {skill, xp}`, `street_cred {delta}`, `follow_up {moment, delay_hours, chance}`. Anything else, unknown ids, amounts over `moments.max_cash_effect`, more than 8 effects, or banned words are refused when the row is saved (and checked again when the card runs). No code can run.

## Seeds (16)
Everyday: landlord levy, NEPA takes light (evening), a friend needs a loan (lend: 35 % chance he repays ₦5,500 a day later through the `loan_repaid` follow-up), owambe invite, okada scare, money on the road, a "job offer" scam, church harvest, Mama Eki's gift (markets). Doctor: malaria, fever, teething, cough, running stomach, rash (Hospital 92 % / Chemist about 55-70 % and can worsen / Ignore; a failed treatment re-offers the card in 1 hour).

## Decisions
Random cards are never rolled in clubs, lounges, or while busy; doctor cards are held on the client in a club. No push for random cards (they only exist when the player is online); doctor cards push through the Friends category.
