# Custom spray (SP1)

In every club (any place whose scene is `club`), players choose exactly how much cash to spray. The hype man
shouts it out to everyone in that club: the bigger the spray, the bigger the moment.

## How it works

- **Where:** the "Spray money" card on the **Dance floor**, the **DJ booth**, and "VIP spray" in the **VIP section**
  (the Activities tab also opens it). Each one opens the **Spray money sheet**: an amount field (numeric keypad,
  ₦ with commas, short preview like ₦1.2 MILLION / ₦3 BILLION / ₦2 TRILLION), quick chips (₦5k, ₦20k, ₦100k,
  ₦500k, ₦1M, ₦10M, ₦100M, ₦1B, All my cash), the tier the MC will shout, and Spray.
- **Server:** `spray_custom(p_location, p_amount numeric, p_vip boolean)`. It checks:
  - the player is standing in that club, and the club is **open** (hours). Dancing (busy) is fine; on the road,
    in jail or in hospital is not;
  - the amount is whole naira, at least `club.spray_min` (₦1,000) or `club.vip_spray_min` (₦100,000) for VIP, and
    at most `club.spray_max` (₦10T). The parameter is numeric, so a giant number is refused cleanly (`too_much`)
    and never overflows bigint;
  - the player has the **cash in hand**. The bank does not count: "Withdraw at the PoS first" (`no_cash`);
  - the per-player cooldown `club.spray_cooldown_s` (10 s).

  The profile row and the `player_spray` row are locked, so two taps can never both pass. The money leaves the
  economy. The ledger reason is `spray`, shown as "Sprayed at <club>". The spray gives a little fun and social, plus
  street cred from the Nice tier up.
- **Shout-out:** a `place_announcements` row (kind `spray`, the real `amount`, plus `tier`, `vip`, `points`) goes out
  on the existing hype broadcast: live Realtime for everyone in the club, the F1 poll fallback otherwise. The
  sprayer's own takeover shows at once from the RPC result. Sprays of at least `hype.global_min` also reach the
  app-wide strip. Billionaire and Trillionaire sprays skip the global cooldown.
- `get_spray_status(p_location)` gives the sheet its numbers: cash, min and max, chips, cooldown left, whether VIP is
  OK, and the player's points.

## Tiers (Admin → Settings → Clubs, `club.spray_tier_*`)

| Tier | From | Takeover |
|---|---|---|
| Small | ₦1,000 | short (3.5 s), light naira rain |
| Nice | ₦50,000 | 4 s |
| Big | ₦500,000 | 4.6 s, full rain |
| Huge | ₦5,000,000 | 5.4 s, bigger aura, loud cue |
| Oga | ₦50,000,000 | 6.4 s, crown |
| Billionaire | ₦1,000,000,000 | 7.6 s, gold notes, hot edges and light sweep, always app-wide |
| Trillionaire | ₦1,000,000,000,000 | 9 s, gold notes + fireworks, big crown |

Each tier has its own MC pool in `hype_templates` (kind `spray_<tier>`, 9 lines each, English with light Pidgin,
always naming @{name}). Lines never repeat at a place until the pool has cycled (`bl_hype_pick`). Placeholders:
`{name} {place} {amount}` (₦2,000,000,000,000) and `{short}` (₦2 TRILLION). On screen the takeover shows the
**amount big** (full digits, sized to fit one line) and the short words under it.

**Hype points** are log-scale, so trillions don't break the leaderboards:
`round(club.spray_points_scale × log10(1 + hype_amount / 1000))`. That gives about 30 for ₦1k, 300 for ₦1M,
900 for ₦1T and 1,000 for ₦10T. `hype_amount` is the amount × fame bath charm × Yahoo rank / iPhone
(`bl_charm_hype_amount`, `bl_yahoo_hype_amount`) × the VIP bonus. The amount shown on screen is always the real spray.
Totals are kept in `player_spray` (server-only).

## VIP spray

- From the VIP section (VIP table / Big Boys' VIP booth zone). The chips start higher: ₦100k, ₦1M, ₦10M, ₦100M,
  ₦1B, ₦10B (`club.vip_spray_chips`). The minimum is `club.vip_spray_min` (₦100k).
- The player needs a VIP booking at a club in the last `club.vip_spray_window_h` hours (8): any of
  `club.vip_spray_activities` (VIP table, Big Boys' VIP booth, VIP at Amapiano Night). The owner can switch this
  off with `club.vip_spray_needs_booking`.
- **+`club.vip_hype_bonus_pct`** (25 %) hype, its own MC pool (`spray_vip`, 10 lines), and a distinct takeover:
  black-and-gold theme, gold notes and gold confetti, a gold "👑 VIP 👑" band and crown over the @name, the label
  "VIP SPRAY · <TIER>", and a slightly longer hold (+0.9 s). The app-wide strip turns gold with a **VIP** badge.

## Files

- `supabase/migrations/20261012001650_custom_spray.sql`, `supabase/tests/custom_spray_test.sql`
- `src/api/spray.ts`, `src/state/spray.ts`, `src/screens/game/SpraySheet.tsx`, `src/styles/spray.css`
- The takeover: `src/screens/game/Hype.tsx`, `hypeFx.ts` (gold notes, fireworks option, `vip` palette),
  `src/state/hype.ts` (tier holds, `pushHype`), `src/styles/hype.css` (SP1 block)
- Cards: `src/screens/game/PlaceCard.tsx`, `src/panels/ActivitiesPanel.tsx`
- Admin: Settings → Clubs (all numbers), Content → Hype lines (the pools)

# Pick the money (SP2)

Every spray (normal and VIP) drops part of the money on the floor. Everyone else in the club taps the notes to put
cash in their pocket.

## Rules (all in Admin → Settings → Clubs)

| Key | Default | Meaning |
|---|---|---|
| `club.pick_enabled` | on | Master switch. Off = sprays work, no drop, `money_pick` refuses. |
| `club.pick_pct` | 20 | Share of the spray that falls. It comes **out of** the sprayed money: the sprayer pays nothing extra, the other 80 % and every unpicked note leave the economy. |
| `club.pick_seconds` | 5 | Notes stay this long, then vanish. |
| `club.pick_note` | 10,000 | Naira per tap, added to **cash**. A share under one note = no drop. |
| `club.pick_grace_s` | 1.5 | A late batch still counts this long after expiry (network delay). |
| `club.pick_max_taps_per_sec` | 12 | Anti-cheat: counted taps <= (seconds since the drop + 0.5) x this. |
| `club.pick_max_per_player` | 50 | Most taps one player can count per drop (so at most ₦500k). |
| `club.pick_self` | off | On = the sprayer can pick their own drop. |
| `club.pick_summary` | on | When a drop ends the MC names the top picker. |
| `club.pick_poll_s` | 3 | Slow-mode (poll fallback) check interval. |

Example: ₦1M spray = ₦200k drop = 20 notes. ₦2T spray = ₦400B drop (40M notes), but a player still gets 50 taps at most.

## Server

- `spray_custom` creates the row in `money_drops` (`bl_money_drop_create`) and returns it as `drop` (patched by a
  guarded replacement of the live function definition; the migration fails loudly if the anchor ever changes).
- `money_pick(p_drop, p_taps)`: the client batches taps (~300 ms). The drop row is locked `FOR UPDATE`, so racing
  pickers can never take `remaining` below zero. Checks: in that club now, not on the road / in a cell / in hospital,
  not the sprayer (unless `pick_self`), not past expiry + grace (returns `expired`, no error, and settles the drop),
  the rate allowance and the per-player cap. Credits `min(taps, allowance left, notes left)` x note to cash; ledger
  reason `money_pick`, shown as "Picked money at <club>". All bigint arithmetic.
- `money_drops_live(p_location)`: active drops with `ms_left` (server clock), for the poll fallback and players who
  walk in mid-drop. `money_drops` is readable by players (RLS) and published for Realtime; `money_drop_picks` is server-only.
- **Announcements:** a player's first pick in a drop writes `place_announcements` kind `pick`: "@username is picking
  money! 💸" plus an MC line from the pool `pick` (12 lines, `{user}`, non-repeating via `bl_hype_pick`). At most once per
  player per drop. When the drop is empty or ends, one `pick_top` line "@top picked ₦X" (pool `pick_top`).

## Client

- `src/screens/game/MoneyPick.tsx` + `src/styles/moneyPick.css`: falling notes (green, **gold for VIP**) on a layer at
  z 86, above the hype takeover (z 80). The layer is `pointer-events: none`; only notes take taps (pointerdown), so the
  takeover's "Tap to skip" and the notes never swallow each other. A live "+₦X" counter, a coin ting per tap. The
  sprayer's own notes fall but cannot be tapped.
- `src/state/moneyPick.ts`: drops, batched taps (one call per drop every 300 ms, one in flight), the counter, the pick
  notices. `src/state/hype.ts` feeds drops from Realtime (INSERT on `money_drops`, same channel as the hype feed), the
  poll fallback and the spray result; leaving the club clears everything.
- Admin: Settings → Clubs (numbers), Content → Hype lines (kinds `pick`, `pick_top`).

## Files

`supabase/migrations/20261012001660_money_pick.sql`, `supabase/tests/money_pick_test.sql`, `src/api/moneyPick.ts`,
`src/state/moneyPick.ts`, `src/screens/game/MoneyPick.tsx`, `src/styles/moneyPick.css`.
