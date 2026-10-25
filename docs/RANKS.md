# Ranks

## Money ranges on leaderboards

Players must not see another player's exact money in a ranking. Boards show a range instead ("₦1M – ₦10M"); the top range is "₦10B+". The ORDER still follows the real value, so rank 1 is really the richest.

Settings (Admin -> Settings -> Leaderboards, migration `20261025000200_rank_bands`):

- `ranks.hide_amounts` (bool, default on). Off = the old exact numbers everywhere.
- `ranks.band_edges` (text, naira, lowest first, default `1000000,10000000,100000000,1000000000,10000000000`). Labels are built from the edges with a short format (K / M / B / T: ₦250K, ₦1.5B): "Under ₦1M", "₦1M – ₦10M", ... "₦10B+". Bad text falls back to the defaults. 0 or no amount = no band (nothing shown).

Boards that return `band` (and `null` for the exact number) while the setting is on: `leaderboard_rich`, `leaderboard_vip` (still only when `leaderboard.vip_show_amounts` is on; your own row always shows), `weekly_leaderboard` (rows, `me`, last week's winners), `crew_top` (rows, `mine`, last week's winners) and `donors_top` (rows). Your own row shows the band too.

What stays exact: prizes and `min_earned` / `min_jobs` thresholds, tier thresholds, everything in `admin_*` RPCs, your own bank / cash in `get_my_state`, and your own donated total in `donors_top.me` (the Bank text). `get_public_profile` shows no money, so it needs no band.

SQL helpers (private, not callable by clients): `bl_money_band(numeric)` (the label), `bl_money_short(numeric)`, `bl_ranks_hide()`. Test: `supabase/tests/rank_bands_test.sql`. Client: `RanksApp.tsx` and the Philanthropists list in `BankStatus.tsx` show `band` when present, else the old number.
