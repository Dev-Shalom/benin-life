# E4 Money sinks

Owner: "People should still earn big, but the money in circulation must not pile up. In Lagos Life they just keep sending money to each other. There should be charges, tax, a way to take money from them."

Migration `supabase/migrations/20261019000400_money_sinks.sql`, test `supabase/tests/money_sinks_test.sql`, help article `taxes-bills`. Everything below is a Setting in **Admin -> Settings -> Economy** (category `economy`), and each sink has a master switch so tests and the owner can pin it off: `economy.transfer_fees_enabled`, `economy.tax_enabled`, `economy.bills_enabled`, `economy.vat_enabled`, `economy.luxury_enabled`, `economy.prestige_enabled`.

Every sink is a plain ledger debit with no matching credit: the money is destroyed, never paid to another player. New ledger reasons: `tax_income, transfer_fee, stamp_duty, bill_house, bill_car, bill_business, ground_rent, vat, luxury_levy, donation, city_party, chief_title`. None is ever earned (`bl_earn_reasons()` drops them even if an admin lists them). No balance can go negative: sinks use `bl_sink_pay` (refuses) or `bl_sink_take` (takes what is there).

## 1. Transfer charges
- Fee on the amount, **marginal tiers**: 1 % up to N50k, 2 % up to N500k, 3 % above (`economy.fee_tier*`), at least N10 (`economy.fee_min`). N5,000 still costs N50, as before.
- **Stamp duty** N50 on transfers of N10k or more (`economy.stamp_duty`, `economy.stamp_duty_min`), own ledger row.
- **Soft cap**: once the day's total sent (game day, same counter as the daily limit) plus this transfer passes N100k (`economy.fee_soft_cap`), the percentage fee doubles (`economy.fee_soft_cap_mult`). Stamp duty stays N50. With the N200k daily limit the cap bites from N100k.
- **Preview**: `bank_transfer_quote(amount, kind)` is shown while typing and on the confirm card (Bank Send, DM "send money", house-visit gift). `bank_info().transfer.fee_rules` carries the rules.
- **Tips** pay the same fee (`economy.tip_fees_enabled`). Market fees (5-8 %) untouched. Switch off = the old flat `bank.transfer_fee` and free tips.

## 2. Weekly income tax
- Lazy settle from `bl_me()` (every gameplay call) and `bank_sinks()`: no cron. The week is the ISO week in Benin time, the same as the Top earners. Earned income = positive ledger rows whose reason is in `leaderboard.earn_reasons` (`bl_week_earned`).
- Bands (marginal, per week): 0 % to N500k, 5 % to N5M, 10 % to N50M, 15 % above (`economy.tax_band*`). Example: N6M earned = N325,000.
- Taken from the bank, then cash. What cannot be paid becomes `profiles.tax_owed`; **future earnings pay it first** (`bl_add_money` calls `bl_tax_garnish`). `tax_pay()` pays by hand. Receipt alert: "Edo State Internal Revenue: You paid N325,000 tax this week...". Records in `tax_records`.
- Exempt: a week that ends before the account is `economy.tax_exempt_days` (7) old. Only the last `economy.tax_catchup_weeks` (8) missed weeks are settled.
- **Politics**: Governor policy `tax_holiday` (kind `tax_cut`, value 50 = every rate cut by half) is on the whitelist (`gov_policies_kind_check` widened). The rates and the holiday show in Benin Votes (Government tab) and in Bank -> Bills. Admin edits the cut in Content -> Policies.

## 3. Weekly bills (Bank -> Bills)
Issued at the Monday boundary (lazy, once per asset per week, `player_bills`), due `economy.bill_due_days` (3) later.
| Asset | Bill | Default |
|---|---|---|
| House | service charge + light, a % of the weekly rent (so by tier) + upkeep of built upgrades | 20 % + 10 % of rent, 0.3 % of upgrades a week |
| Car (each) | insurance + servicing, % of price | 0.5 % a week |
| Business (each) | council tax, % of value (separate from running costs) | 0.5 % a week |
| Land | ground rent, % of what the plots cost | 0.1 % a week |
- **Autopay** on the due date from bank then cash when the money is there (`economy.bills_autopay`); otherwise a one-time late fee (`economy.bill_late_fee_pct`, 10 %) and a retry every 30 real minutes. Players can pay any bill early or "Pay all".
- An asset is only **blocked** when its bill is `economy.bill_block_days` (14) past due: a car cannot drive or run Bolt (`bl_travel_quote`, `bl_hustle_car`), a business earns nothing (`bl_biz_settle`). Houses and land are never blocked (rent has its own owed-rent rule). Nothing is ever seized; paying unblocks at once.
- Grace: no bills while the account is younger than `economy.bill_grace_days` (7) at the week boundary.

## 4. VAT and luxury levy
- The price shown IS the price paid. `bl_dealer_price` now returns the VAT-inclusive price (old price: `bl_dealer_net`), so `shop_list`, `shop_buy` and the interiors agree. Furniture and Boutique add the same VAT in the client (`src/lib/tax.ts`) and the server (`bl_gross`). Shop cards say "incl. VAT" / "incl. VAT + luxury levy"; the purchase message says "(incl. VAT N3,375)".
- 7.5 % VAT (`economy.vat_pct`), exempt item categories `food, drink, fish, health, hygiene, phone, offering`. Luxury levy 5 % extra on categories `vehicle, gadget, souvenir`, laptops from N1M, Boutique items from N1M, furniture from N5M. VAT and levy are their own ledger rows (`vat`, `luxury_levy`). A business owner's visitor cut is on the net price.

## 5. Prestige sinks (Bank -> Status)
- **Donate to the city**: from N10k; money destroyed; Benin Philanthropists board (`donors_top`), badge by total (Helper / Benefactor / Philanthropist / City Patron, `economy.donor_tiers`), Charisma XP (1 per N100k, max 100 per donation), badge on the public profile.
- **City party**: N20M, only at a club / lounge / buka / hotel / stadium, one at a time per venue, 12 h wait per host. Announcement to everyone (broadcast), Fun +40 for everyone in the venue and for anyone who arrives in the next 30 minutes (applied on their next call).
- **Chief titles** (`economy.chief_tiers`): Chief N10M, High Chief N50M, Grand Chief N200M, "of" one of the 8 wards. Upgrades pay the difference. Shown as the title badge next to the name (shares the slot of the office title, which wins): places, chat, profiles, friends. Fictional only: nothing from the Oba's palace.

## 6. Admin -> Economy
`admin_economy_overview(days)`: total money (cash + bank + Yahoo balance + gang banks + business takings), made vs destroyed per day and by category for 14 or 30 days (ledger, admin accounts left out), top 20 holders, tax collected / owed, bills open, each sink's total, money supply growth (whole window and last 7 days) with a Stable / Growing fast / Shrinking flag, switches, and links to the settings. "Made" and "destroyed" skip moves between pockets (`economy.internal_reasons`: transfers, tips, bank deposits, Market, pickpocket, gang bank moves, invest buy / sell). Yahoo balance and gang bank gains only count as "made" when they reach a player's cash or bank.

## Files
Migration above; tests `money_sinks_test.sql` (and pins at the top of `bank, buy_catalogue, hustles, invest_save, places, polish, politics, sell_receipts, shops, wardrobe` tests); client `src/api/economy.ts`, `src/lib/tax.ts`, `phone/BankBills.tsx`, `phone/BankStatus.tsx`, `phone/FeeLine.tsx`, `BankApp.tsx`, `PoliticsApp.tsx`, `admin/Economy.tsx`; Help article `taxes-bills`. No tour step (not a key moment).

## Estimated effect (defaults, from the E3 stages in BALANCE.md)
- **Mid-game** (about N189k a day gross, N1.3M a week): income tax about N41k a week, bills about N58k a week (flat + Bolt car + one business + some land), VAT on the non-food part of about N150k a day of buys. Roughly **10 %** of daily money creation leaves (about N19k a day).
- **Rich** (about N1.14M a day, N8M a week): tax about N525k a week, bills about N1.0M a week (a N150M car alone is N750k), VAT + luxury on big buys. Roughly **20-25 %** (about N260k a day), before voluntary donations, parties and titles.
- **New / low earners**: nothing for 7 days, then tax 0 under N500k a week and bills of a few hundred naira a week.
