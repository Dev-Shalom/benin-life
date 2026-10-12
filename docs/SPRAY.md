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

Not built yet: picking up the sprayed notes (a later task).
