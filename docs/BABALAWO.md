# Babalawo shrine (B2)

Owner-approved spec: `docs/LIFESTYLE_PLAN.md` section 1. Every number below is that spec's number, and every one is admin-editable.

Files:
- `supabase/migrations/20261012001500_babalawo.sql`, `supabase/tests/babalawo_test.sql`
- `src/api/shrine.ts`, `src/state/shrine.ts`, `src/screens/game/Shrine.tsx` (popups + charm chips), `src/panels/BabalawoPanel.tsx` (the Babalawo tab)
- Hooks into existing files: `PlaceCard.tsx` (shrine cards), `TaskRunner.ts` + `state/tasks.ts` (task kind `shrine`), `TaskPill.tsx`, `SimSheet.tsx` (Charms), `Game.tsx` (`<ShrineHost/>`), `api/shops.ts` (Offerings section in the shop and Bag)
- 3D: `place3d/model.ts` + `engine/props.ts` (props `shrine_hut`, `fire_pit`, `offering_mat`; mud-wall shrine kit), `feel/rigs.ts` (firelight rig), `city3d/engine/build.ts` (hut on the city map), `map/mapGeo.ts` (grove, dirt spur, pin label), `scenes/shrine.tsx` (sheet header art; sign no longer names anybody)
- Admin: `src/admin/Content.tsx` (Shrine services), `src/admin/Players.tsx` (Charms box), `src/admin/Settings.tsx` (Babalawo shrine category)

## The place
- **Baba's Shrine** (`babas_shrine`), district Evbuomore, map (760, 730): the far end of Sakponba Road, on a short dirt spur off the Upper Sakponba bush road, in a small sacred grove near the Ikpoba river. Open 24 hours. Public place, scene `shrine`, tabs Babalawo / Things to do / Chat. Map pill: 🪔 Baba's Shrine (tier 1).
- Baba is fictional and never named. The old in-town "Baba Osagie Shrine" (`baba_shrine`) was renamed "Old Sakponba shrine" and hidden once (`shrine.old_hidden_seeded`); admin can switch it back on in Content → Places. Its cheap ₦2,000 "Consult Baba" activity now only shows there.
- Interior (place zones for this place only): **Baba's hut** (mud walls, thatch, red and white cloth, Baba's stool on a raffia mat, carved staff, calabashes, cowrie tray, oil lamp, chalk line), **Charm altar**, **Fire pit** ("Sit quietly by the fire"), **Offering mat** (kola, schnapps, white cloth, palm oil, a white chicken in a basket; "Check your offerings" opens the Bag). Low orange firelight rig. NPCs: "Baba" (Babalawo, at the hut) and "Omo Baba" (helper), plus the shrine type's people.

## Offerings (Oba Market, category `offering`)
| Item | id | Price |
|---|---|---|
| Kola nut 🌰 | kola_nut | ₦240 |
| Alligator pepper 🌶️ | alligator_pepper | ₦600 |
| Cowries 🐚 | cowries | ₦2,400 |
| White cloth 🏳️ | white_cloth | ₦3,600 |
| Palm oil 🫙 | palm_oil | ₦4,200 |
| Schnapps 🍾 | schnapps | ₦7,800 |
| White chicken 🐓 | white_chicken | ₦9,600 |
| Goat 🐐 | goat | ₦102,000 |
| Cow 🐄 | cow | ₦1,440,000 |

They are "keep" items (no Use button), sellable back at a market at 50%. A cow gets a receipt (≥ `receipts.min_amount`).

## Services (`shrine_services`, Admin → Content → Shrine services)
| Service | Cash + offerings | Effect (kind, value) | Lasts | Fails |
|---|---|---|---|---|
| Consultation (Ifá reading) | ₦50,000 + 1 kola nut | a random reading (the `lines` column) + **Baba's luck: +5% job pay** (`luck`, 5) | 1 day | never (0%) |
| Road opener | ₦250,000 + 2 kola nuts + 1 palm oil | +20% job pay (`road_opener`, 20) | 7 days | 10% |
| Protection charm | ₦420,000 + 1 schnapps + 1 white chicken | pickpocket caught 62% → 45% (`protection`, 45) | 3 days | 10% |
| Vanishing charm | ₦750,000 + 2 goats + 1 cowries | escape caught 52% → 30% (`vanishing`, 30) | next 3 escapes | 10% |
| Home guard | ₦300,000 + 1 white cloth + 1 palm oil | thieves targeting you +50% more likely caught (`home_guard`, 50), capped at 95% | 7 days | 10% |
| Attraction charm | ₦150,000 + 5 alligator pepper | dates say yes more often (`attraction`, 20) — stored for the coming dating life | 5 days | 10% |
| Fame bath | ₦800,000 + 2 schnapps | +50% club hype (`fame_bath`, 50) | 3 days | 10% |
| EFCC blindfold | ₦1,200,000 + 2 goats | Yahoo EFCC caught −15 points (`efcc_blindfold`, 15) — used by Y1 Yahoo jobs (docs/YAHOO.md) | 3 days | 10% |
| Money charm | ₦3,000,000 + 2 cows + 1 schnapps + 1 white cloth | cash on each return after 8+ h (see below) | 14 days | 10% |
| Cleansing | ₦50,000 + 1 white chicken | removes curse, bad luck and madness | instant | never (0%) |

- Fail chance: the service's `fail_pct`, or `shrine.fail_pct` (10) when empty. A failed charm keeps the money and offerings and shows Baba's `fail_line`.
- One of each charm at a time (`already_active`); only one money charm ever active (also a unique index), even while its weekly call is open.
- The attraction card says "Works with the dating life (coming soon). Baba keeps it ready on you till then." The EFCC blindfold card now says it works on Yahoo jobs (Y1 rewrote that note). Features read them with `bl_charm_value(uid, 'attraction')` / `bl_charm_value(uid, 'efcc_blindfold')`.
- Changes in Content apply to new charms; a bought charm keeps its value in `player_charms.data.value`.

## How a visit works
1. At Baba's Shrine, tap a shrine card on the hut or altar (second tap confirms: "Tap again · ₦420K"), or "Ask Baba" twice in the Babalawo tab (the tab closes). The task queue walks the Sim to the hut or altar, then calls `shrine_start(service)`.
2. `shrine_start` checks: switch, at a place with the `babalawo` tab (not visiting a house), free, place open, no running visit, no duplicate charm, every offering in the Bag (`missing_offerings` names what is missing), enough **cash** (`not_enough_cash`). It then takes the cash (ledger `shrine`, "Baba: <service>"), removes the offerings, sets the busy timer "With Baba: <service>" (`seconds` column, 10–20 s; can't be stopped), and issues a receipt for ₦500k+.
3. When the timer ends, `shrine_finish()` (or the next `shrine_status()`) rolls `bl_rand()` against the fail chance and stores the charm in `player_charms` (`expires_at`, `uses_left`, `data`). The result popup shows Baba's line (and the reading for a consultation).

## Effects (server-side)
| Charm | Where | Rule |
|---|---|---|
| Protection | `bl_steal_caught_pct(thief, victim, skill_mod)` | base `crime.steal_caught_pct` capped at the charm value (45), then + bad luck points, − `skill_mod` (hook kept), clamp 0–100 |
| Home guard | same function, the **victim's** charm | if the result is below `shrine.guard_cap_pct` (95): × (1 + 50/100), capped at 95; never lowers it. 62 → 93; a protected thief 45 → 67.5 |
| Vanishing | `jail_case_escape()` → `bl_escape_pct_use(uid)` | `crime.escape_caught_pct` capped at 30, + bad luck; each escape attempt (caught or not) spends one use; 0 uses = `used`. The popup shows the chance via `bl_escape_pct_peek` (in `bl_crime_case_json`) |
| Road opener, Baba's luck, bad luck | `work_shift()` → `bl_charm_pay(uid, pay)` | pay × (1 + road% + luck% − bad-luck%), rounded to ₦10 |
| Madness | `work_shift()` → `bl_charm_assert_can_work(uid)` | refused, hint `madness` |
| Fame bath | `bl_hype_announce()` → `bl_charm_hype_amount(uid, amount)` | the announced hype amount × 1.5 (bigger takeover tier / ticker) |
| Attraction, EFCC blindfold | `bl_charm_value(uid, kind[, key])` | stored only |

The consultation's "small luck buff" is +5% job pay for 1 day (not the −3 pts caught option).

## Money charm
- Bought like any service. `data`: `last_payout_at` (purchase time), `next_payout_at`, `payouts`, `demand_due_at` (purchase + `shrine.demand_days` 7), `demand_open`.
- `bl_money_charm_tick(uid)` runs from `shrine_status()` (client: on game start, every 5 min while visible, when the tab comes back, after a `baba_*` alert), `shrine_info()`, `shrine_start()` and `shrine_demand_pay()`. It locks the charm row, so it is idempotent and can't double-pay:
  1. **Baba calls:** when `demand_due_at` has passed (and is before the charm's end), the demand opens with a deadline of due + `shrine.demand_hours` (24 h), and an alert "Baba is calling you". Server time only: a player away for more than the deadline gets the backfire on return.
  2. **Backfire:** deadline passed and unpaid → lose `shrine.backfire_cash_pct` (50%) of cash on hand (ledger `shrine_backfire`, "Baba: charm backfired"), `madness` for `shrine.madness_game_days` (1 game day = 24 h on the real clock), `bad_luck` for `shrine.bad_luck_days` (3 days: +`shrine.bad_luck_caught_pts` 10 pts pickpocket/escape caught, −`shrine.bad_luck_pay_pct` 10% job pay), charm status `backfired`, backfire popup.
  3. **End:** after 14 days (no open call) the charm is `expired`.
  4. **Payout:** at most once per `shrine.money_payout_hours` (8 h) since the last payout, random `shrine.money_payout_min`..`max` (₦150,000–₦300,000, rounded to ₦1,000) into cash (ledger `shrine_blessing`, "Baba's blessing") + a "Baba's blessing" popup. No payout while Baba's call is unanswered.
- With 14 days and a 7-day demand there is one call (day 7); the day-14 one would land on the charm's end, so it is skipped.
- **Baba is calling you** popup (not dismissable): Pay (1 goat from the Bag + ₦300,000 cash, `shrine_demand_pay`, from anywhere; next call 7 days after the last due date) or Ignore (`shrine_demand_ignore`: the popup stops, the deadline still runs). The chip shows "Baba is calling!".
- Popups use the A2 broadcast card (`bl-modal` + `bcast-*`); blessing / backfire notices live in `shrine_notices` until `shrine_notice_seen`.

## Tables and RPCs
- `shrine_services` (authenticated read, admin write via `admin_row_upsert`), `player_charms` (players read their own rows, no client writes), `shrine_visits` and `shrine_notices` (server-only).
- Players: `shrine_info()`, `shrine_start(text)`, `shrine_finish()`, `shrine_status()`, `shrine_notice_seen(bigint[])`, `shrine_demand_pay()`, `shrine_demand_ignore()`. Security definer, revoked from anon.
- Admin: `admin_player_charms(uuid)`, `admin_charm_clear(uuid, bigint)` (one charm or all active; audited `charm_clear`).
- Private (revoked from clients): `bl_charm_value`, `bl_charm_active`, `bl_charm_live`, `bl_charm_pay`, `bl_charm_hype_amount`, `bl_charm_assert_can_work`, `bl_escape_pct_peek`, `bl_escape_pct_use`, `bl_money_charm_tick`, `bl_shrine_*`.
- `zone_actions.kind` gained `shrine` (ref = service id), shown by `place_interior` with price, seconds, effect, duration, offerings, what is missing and `charm_until`. Panel cards may open the `babalawo` tab.
- Guarded edits of live functions: `bl_steal_caught_pct`, `jail_case_escape`, `bl_crime_case_json`, `work_shift`, `bl_hype_announce`, `bl_zone_action_check`, `place_interior`, `bl_ledger_label`, `bl_admin_table_spec`.

## Admin
- Content → **Shrine services**: every price, offering list, effect value, duration, uses, fail %, action seconds and Baba's lines; On switch per service.
- Settings → **Babalawo shrine**: `shrine.*` (fail chance, money charm payout / hours, demand days / cash / goats / hours, backfire %, madness, bad luck, guard cap, switch). `shrine.fail_pct` is in the most-used list.
- Players → a player → **Charms**: active and past charms with time / uses left; Clear one or Clear all (audited).

## Tests
`bash scripts/sql-test.sh -- supabase/tests/babalawo_test.sql` (13 groups): grants / anon / helpers private; place, offering prices, service prices + offerings, cow receipt, interior cards; refusals (missing items, cash, not here, switch, busy, unknown); a service consumes cash + offerings, timer, ledger label, receipt ≥ ₦500k, duplicate refused; fail roll (`bl.test_rand`, per-service 0%, 100%); effects (protection 45, skill hook, home guard 93 / 67.5 / cap 95, road opener + luck on a real shift, fame bath on a real announcement, attraction / EFCC values, vanishing 3 uses on real escapes); durations / uses expire; money charm payout once per 8 h, min / max, one money charm; weekly demand paid / blocked payouts / ignored / backfire once (half cash, madness blocks shifts, bad luck +10 pts / −10% pay / escape +10); cleansing; RLS; admin list / clear / audit / Content edit; ledger labels.

Also updated for B2: `map_geo_test` (new location), `places_test` (babalawo tab), `soft_launch_test` (the hidden old shrine).
