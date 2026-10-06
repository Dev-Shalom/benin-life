# Bank, PoS and transfers (V1-5)

Server: `supabase/migrations/20261005000900_bank.sql` (idempotent: config `on conflict do nothing`, `create or replace`, `create index if not exists`; no new tables). Tests: `supabase/tests/bank_test.sql`.
Client: `src/api/bank.ts`, `src/panels/BankPanel.tsx` (action `bank`), `src/panels/PosPanel.tsx` (action `pos`), `src/panels/bank/{BankUI.tsx,bankHooks.ts}`, phone `src/screens/game/phone/BankApp.tsx`, Wallet link, HUD tip chip (`useBankTip` in `Hud.tsx`). Types: `src/lib/types.ts` section "V1-5".

## Why bank
Street robbery (`bl_roll_street_robbery`, DB_CORE) takes **cash only**, and with no cash the robbery chance is 0. Money in the bank is safe. Salary is paid in cash (CAREERS); Chowdeck and rent pay from the bank first (SHOPS).

## Where money moves
| Where | What | When | Cost |
|---|---|---|---|
| Bronze Bank (`bronze_bank`, action `bank`) | `bank_deposit`, `bank_withdraw` | banking hours, game time `bank.open_hour` (8) to `bank.close_hour` (16); open = close means always open; open > close wraps midnight | free |
| PoS stands (action `pos`: Ring Road PoS Line, New Benin PoS Junction, Sapele Road PoS Stand) | `pos_cashout` (bank → cash), `pos_deposit` (cash → bank) | any hour | `pos.fee_pct` (1.5 %) of the amount, at least `pos.fee_min` (₦100), rounded up to ₦10, paid **on top** from the same account; max `pos.max_amount` (₦100,000) per go |
| Phone, anywhere (also while busy or travelling; not in jail) | `bank_transfer` to another player, bank → bank | any time | `bank.transfer_fee` (₦50) |

All counter RPCs use `bl_me()` + `bl_assert_free()` and the location's `actions`. The smallest amount is `bank.min_amount` (₦100).

Transfer limits (anti-farming): `bank.transfer_min_amount` (₦100), `bank.transfer_daily_limit` (₦200,000 sent per game day, fees not counted), `bank.transfer_daily_count` (10 per game day), `bank.transfer_cooldown_real_seconds` (15), `bank.transfer_min_account_real_minutes` (1440 = 24 h since S1 migration 20261006001000; was 30: brand-new Sims wait). Not to yourself; banned players can't receive. The two profile rows are locked in id order (no deadlock). Notes are one line, max 80 chars.

## Ledger reasons
`bank_deposit` / `bank_withdraw` (one row per account, `meta.location`), `pos_cashout` / `pos_deposit` (amount rows) + `pos_fee` (`meta.kind` cashout|deposit), `transfer_out` (`meta.to_username`, `note`, `day` = game day for the limits) + `transfer_fee`, `transfer_in` (receiver, `meta.from_username`). Events: `transfer_in` to the receiver ("Money in from @X"), `transfer_out` to the sender.

## RPCs
| RPC | Args | Returns |
|---|---|---|
| `bank_info` | – | cash, bank, min_amount, bank_hours {open_hour, close_hour, open, opens_in_game_minutes, opens_in_real_seconds}, pos {fee_pct, fee_min, max_amount, max_cashout, max_deposit}, transfer {fee, min_amount, daily_limit, sent_today, left_today, count_today, daily_count, cooldown_real_seconds, new_account_wait_real_seconds}, tip_cash_threshold, places [{id,name,district,kind}] |
| `bank_history` | p_limit (≤100) | own ledger rows, newest first: id, account, delta, balance_after, reason, **label** (`bl_ledger_label`: "Salary · Intern", "Bought Puff-puff", "PoS charge", "Sent to @X", "From @X"…), note, created_at |
| `bank_recipient` | p_username (case-insensitive, leading @ ok) | {id, username, avatar} — the confirm step |
| `bank_deposit` / `bank_withdraw` | p_amount | {message, amount, cash, bank} |
| `pos_cashout` / `pos_deposit` | p_amount | {message (with a line of PoS banter), amount, fee, cash, bank} |
| `bank_transfer` | p_username, p_amount, p_note | {message, amount, fee, bank, to {id, username}, sent_today, left_today} |

Error hints: `not_here`, `closed` (says when it opens and lists the PoS stands), `bad_amount`, `not_enough_cash`, `not_enough_bank` (fee included), `unknown_player`, `self`, `limit` (daily amount/count, cooldown, new account), `jailed`, plus the usual `busy`/`traveling` from `bl_assert_free`.

Helpers (revoked from clients): `bl_hour_text`, `bl_bank_open`, `bl_bank_opens_in`, `bl_pos_fee`, `bl_pos_max` (largest amount whose amount + fee fits a balance), `bl_check_amount`, `bl_places_with`, `bl_ledger_label`, `bl_transfer_stats`, `bl_find_player`, `bl_assert_at`, `bl_assert_bank_open`, `bl_pos_banter`.

## UI
- **Bank tab** (Bronze Bank): cash/bank tiles, "Money in the bank can't be stolen on the street.", hours strip (open / closed with real-time wait + PoS stand links), Deposit | Withdraw, amount with chips ₦1k / ₦5k / All.
- **PoS tab**: operator banter, Cash out | Deposit, chips (All = `max_cashout` / `max_deposit`, so the charge fits), live charge preview (client `posFee` mirrors `bl_pos_fee`).
- **Phone Bank app**: balance card, cash row, tabs Send (username, amount, note → confirm card with fee and total → Send), History, Where (each place with open/closed or PoS charge; tap → map + that place's tab).
- **Wallet panel**: "Open the Bank app" link (`openPhone('bank')`).
- **HUD tip** "Bank your cash": at night (`clock.night_*`), while free, cash > `bank.tip_cash_threshold` (₦20,000) → nearest PoS (or Bronze Bank when open).

## Config (admin-tunable, categories `bank`, `pos`)
`bank.open_hour` 8, `bank.close_hour` 16, `bank.min_amount` 100, `bank.transfer_fee` 50, `bank.transfer_min_amount` 100, `bank.transfer_daily_limit` 200000, `bank.transfer_daily_count` 10, `bank.transfer_cooldown_real_seconds` 15, `bank.transfer_min_account_real_minutes` 1440 (S1; was 30), `bank.tip_cash_threshold` 20000, `pos.fee_pct` 1.5, `pos.fee_min` 100, `pos.max_amount` 100000.
