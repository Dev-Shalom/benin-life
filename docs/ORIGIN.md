# Starting class roll: LAPO baby vs Nepo baby (P1-ORIGIN)

Files: `supabase/migrations/20261005000200_origin.sql`, `supabase/tests/origin_test.sql`, `src/screens/OriginReveal.tsx`, HUD badge and Dad chip in `src/screens/game/Hud.tsx`, copy in `src/lib/pidgin.ts` (`ORIGIN_COPY`, `ORIGIN_UI`), types in `src/lib/types.ts` (`// P1-ORIGIN`).

Test (all three must print PASSED):
```
BL_PSQL="psql -h /tmp -p 54322 -U postgres -d postgres" bash scripts/sql-test.sh \
  supabase/migrations/20261004000100_core.sql supabase/migrations/20261004000200_core_seed.sql \
  supabase/migrations/20261005000100_map_geo.sql supabase/migrations/20261005000200_origin.sql \
  -- supabase/tests/core_test.sql supabase/tests/map_geo_test.sql supabase/tests/origin_test.sql
```

## Data
- **`origin_tiers`** (id pk, name, tagline, welcome, chance_key, is_default, sort, perks jsonb). RLS on; `select` for anon and authenticated; no client writes. Exactly one default tier (unique partial index). `welcome` is the welcome-event body, with the placeholders `{name}`, `{home}`, `{cash}` and `{bank}`.
  - `lapo`: the default tier, `perks = {"micro_loan_access": "easy"}`. This is the Phase 2 loans hook.
  - `nepo`: `chance_key = 'origin.nepo_pct'`, `perks = {"papa_allowance": true}`.
- **`profiles.origin`**: text, not null, default `'lapo'`, FK to `origin_tiers(id)`.
- **`profiles.allowance_claimed_day`**: int, null. It holds the game day of the last Papa claim.
- Both columns appear in `get_my_state().profile` automatically.
- **Starter items** are seeded only if missing (`on conflict do nothing`). P2-ECON owns the full catalog and may update them.
  - `tokunbo_car`: vehicle, ₦2,500,000. Owning it unlocks the car travel mode.
  - `laptop`: gadget, ₦250,000.

## Config (category `origin`, admin-tunable)
| key | LAPO | Nepo |
|---|---|---|
| `origin.nepo_pct` (percent) | — | 10 |
| `origin.<tier>.start_cash` | 5,000 | 50,000 |
| `origin.<tier>.start_bank` | 0 | 500,000 |
| `origin.<tier>.home_location` | `ekenwan_room` | `gra_duplex` |
| `origin.<tier>.housing` | `face_me_ekenwan` | `duplex_gra` |
| `origin.<tier>.items` (comma-separated ids) | "" | `tokunbo_car,laptop` |
| `origin.<tier>.career_head_start` (levels) | 0 | 2 |
| `origin.<tier>.allowance_daily` (naira per game day) | 0 | 5,000 |

**Fallback rule:** if a tier has no `origin.<tier>.start_cash|start_bank|home_location|housing` key, the matching `start.*` key is used. A missing items, head-start or allowance key means none. The LAPO keys mirror the `start.*` defaults, so editing `start.cash` no longer changes LAPO babies; edit `origin.lapo.start_cash` instead. The `start.*` descriptions now say they are fallbacks. Other `start.*` keys (needs, health, stress, protection) still apply to every tier.

**Adding a tier:** insert an `origin_tiers` row with a `chance_key`, add that percent key, and add whichever `origin.<tier>.*` keys differ from the fallbacks. The client shows the tier's name and tagline with generic copy, and uses its home scene and items automatically.

## The roll (`bl_roll_origin()`)
- It makes **one** `bl_rand() * 100` roll.
- It walks the non-default tiers by `sort`, adding each tier's percent to a running total. The first tier whose cumulative total is above the roll wins. Percents stack: with tier A at 5% and Nepo at 10%, a roll under 5 gives A, 5 to under 15 gives Nepo, and anything else gives the default tier.
- It is deterministic under `set local bl.test_rand`. With the default 10%, a roll of 0.0999 gives Nepo and 0.10 gives LAPO.

## RPCs
- **`create_profile(p_username, p_gender, p_avatar)`** keeps the same signature, validation and errors. After validation it:
  1. Rolls the tier.
  2. Checks the tier's home with `bl_location`. A bad config raises the Pidgin "no dey for map" error and creates nothing.
  3. Inserts the profile with `origin`, home, location and housing.
  4. Pays cash and bank through `bl_add_money` (reason `start_bonus`, meta `{origin}`).
  5. Puts the starter items in `inventory`. Unknown item ids are skipped, so a config typo never blocks sign-up.
  6. Writes the `welcome` event from the tier template, using the real home name and amounts, with data `{origin}`.
- **`get_my_state()`** is the same as core plus an `origin` block (type `OriginInfo`): `{id, name, tagline, perks, career_head_start, allowance_daily, allowance_claimable, start_cash, start_bank, items:[{id,name,category}]}`.
  - It is still read-only. The only write is the core's throttled `last_seen` update.
  - This migration redefines `get_my_state`. **Any later redefinition must keep the `origin` key.**
- **`claim_allowance()`** returns `{message, amount, account:'bank', bank, day}`. The message reads, for example, "Papa don send ₦5,000 enter your account. No spend am anyhow o."
  - It pays into **bank**: it's a transfer from Papa, and bank money can't be street-robbed.
  - Once per game day, based on the `bl_game_clock` day.
  - It works while busy, travelling or in hospital, because it's a bank transfer. It is blocked while jailed ("Papa hear say you dey cell…").
  - It raises a Pidgin error with hint `no_allowance` when the tier's allowance is 0, and `already_claimed` on a second claim the same day.
  - The ledger reason is `allowance`, with meta `{origin, day}`.
- Helpers `bl_origin_cfg`, `bl_origin_num`, `bl_origin_items`, `bl_roll_origin` and `bl_origin_info` are internal: execute is revoked from public, anon and authenticated.

## Client
- *(Superseded by R3b: the reveal is now step 4 of the creator, inside the sheet, after `create_profile_v2`. See `docs/CREATOR.md` "Client (R3b)". The notes below describe the P1 version.)*
- **CreateSim** holds the `create_profile` GameState locally and shows `OriginReveal`.
  - The flow: a coin toss of about 1.2 s (tap to skip), then the title, the home scene card with the avatar, staggered perk tiles and the "Oya enter Benin" button.
  - The button applies the state and navigates to `/play`.
  - Animations are CSS transform and opacity only. Nepo gets a confetti burst of 18 pieces that plays once. `prefers-reduced-motion` gives fades only.
  - The reveal replaced the old hard-coded "Ekenwan" toast.
  - If the page is reloaded mid-reveal, the player simply lands in the game, because the profile already exists.
- **HUD**: a class badge (NEPO or LAPO) sits on the portrait. A "Dad ₦5,000" chip appears next to the protection chip while `origin.allowance_claimable` is true. Tapping it calls `claim_allowance`, shows a toast and refreshes.
- **Toasts** on the game screen now sit left of the HUD side buttons, so they no longer cover the bell. They stay below the HUD rows (the 150 px offset already existed).

## R3a changes (`20261005000400_creator.sql`, see `docs/CREATOR.md`)
- **`origin.force_next`** (text, '' or a tier id): one-shot override. The next profile created (v1 or v2) gets that tier and the key resets to '' (audited in `config_audit` with admin_id null). Seeded to `nepo` only when the key is first inserted, so re-running the migration never re-arms it.
- **`admin_set_origin(p_user, p_origin, p_apply_perks default false)`**: admin only; audit row in `admin_audit` and an `origin_changed` event. With perks it tops up (never takes away) the cash/bank difference and missing starter items.
- **Creator v2:** `create_profile_v2` rolls the tier but pays nothing; `choose_start_home` pays the home's start cash for the tier (falls back to `origin.<tier>.start_cash`), `origin.<tier>.start_bank` and the tier items. v1 `create_profile` is unchanged in behaviour.
- **Copy:** "Dad" replaces "Papa" in taglines, welcome text, config labels and `claim_allowance` ("Dad sent ₦5,000 to your account. Spend it wisely."). The perk key `papa_allowance` is unchanged (internal).

## Phase 2 hooks
- **Careers:** add `origin.career_head_start` (`bl_origin_num(origin,'career_head_start')`) to `job_level` on the first hire.
- **Loans:** read `origin_tiers.perks->>'micro_loan_access'` for the player's tier.
- **Admin panel:** edit `origin_tiers` rows and the `origin.*` config.
