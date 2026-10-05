# Creator data: traits, dreams, start homes, rent, origin overrides (R3a)

Files: `supabase/migrations/20261005000400_creator.sql`, `supabase/tests/creator_test.sql`, wrappers in `src/api/creator.ts`, types in `src/lib/types.ts` (`// R3a`). The 5-step creator UI (R3b) is `src/screens/CreateSim.tsx` + `src/screens/creator/*` + `src/screens/OriginReveal.tsx`; see "Client (R3b)" below.

Test (after `npx supabase db reset`):
```
bash scripts/sql-test.sh -- supabase/tests/core_test.sql supabase/tests/map_geo_test.sql \
  supabase/tests/origin_test.sql supabase/tests/time_test.sql supabase/tests/creator_test.sql
```

## Flow
Client order: **Look → Personality → Dream → Birth lottery reveal → Choose home**.

| Step | Call | What happens |
|---|---|---|
| Look, Personality, Dream | `creator_catalog()` (anon too) or plain selects on `traits`, `dreams`, `start_homes` | Nothing is written. |
| End of Dream | `create_profile_v2(p_username, p_gender, p_avatar, p_traits text[], p_dream text)` | Same validation as v1, plus exactly `creator.trait_count` (2) distinct active traits and an active dream (hints `bad_traits`, `bad_dream`). Rolls the origin (or applies `origin.force_next`). Inserts the profile with `home_chosen = false` at `creator.arrival_location` (Uselu Motor Park), cash 0, no housing. **Pays nothing, no welcome event.** Returns GameState; `creator.homes` lists the homes for the rolled origin. |
| Reveal | – | The client shows `GameState.origin` (perks, no percentages). |
| Choose home | `choose_start_home(p_home)` | Once only (hint `home_already_chosen`). The home must be active (`bad_home`) and allowed for the origin (`home_locked`; the error message is the home's `locked_quip`). Moves the Sim in (location, home, housing), pays the home's start cash for the origin + `origin.<tier>.start_bank` (ledger `start_bonus`, meta `{origin, home}`), gives the tier's items, resets needs to the start levels, starts new-player protection now, sets `weekly_rent` + the first `rent_due_at`, and writes the welcome event (tier template + "Rent is ₦X a week."). Returns GameState + `message`. |

**Until a home is chosen** every gameplay RPC refuses: `bl_me()` raises "Hold on, choose where you will live first." with hint `no_home`. `update_avatar` and `choose_start_home` use `bl_me_any()` (no home check), so the player can still go back to the Look step. `get_my_state` works and its `creator` block lets the client route back to the home step after a reload:

```ts
creator: { home_chosen: boolean; traits: string[]; dream: string | null; start_home: string | null;
           homes: StartHomeOption[] | null /* only while home_chosen is false */ }
rent:    { weekly: number; due_at: string | null; owed: number; enabled: boolean }
```
Sims without a home are hidden from `players_here`. `src/api/creator.ts` has `needsHome(state)` and `isNoHomeError(e)`; `GameError` now carries the server `hint`.

**v1 `create_profile`** keeps its all-in-one behaviour (roll incl. `force_next`, origin home, starter pack, welcome) with `traits = '{}'`, `dream = null`, no rent. The client no longer calls it (R3b uses v2 only).

## Tables (RLS on; select for anon + authenticated; writes only via admin/RPC)
- **`traits`** (id, name, emoji, description, effects jsonb, sort, active). `effects.decay.<need>` multiplies that need's decay rate (`hunger, energy, hygiene, fun, social, stress`); several traits multiply together. Applied in `bl_decay_row`, so decay stays path-independent and `get_my_state` stays read-only. Other keys (`skill_xp`, `work_pay`, `night_fun_bonus`, `party_fun_bonus`, `culture_fun_bonus`, `social_bonus`, `work_performance`, `dirty_stress_mult`, `food_fun_bonus`) are stored for Phase 2. Deactivating a trait hides it from new Sims; existing Sims keep its effect.
- **`dreams`** (id, name, emoji, description, goal jsonb, sort, active). Goal types: `career_top` (optional `track`), `net_worth` (`amount`), `skill` (`skill`, `level`), `friends` (`count`, `level`), `startup_funded`. Progress tracking is Phase 2.
- **`start_homes`** (id, name, emoji, location_id, district, tag, description, weekly_rent, start_cash jsonb per origin, allowed_origins text[] — empty = all, locked_quip, housing_id, sort, active). A missing origin key in `start_cash` falls back to `origin.<tier>.start_cash`.
- **`admin_audit`** (id, admin_id, action, target_user, data, created_at) — admins can select.
- **`profiles`** adds `traits text[]`, `dream`, `start_home`, `home_chosen bool default true` (true for every v1/older profile), `weekly_rent`, `rent_due_at`, `rent_owed`.
- Two new locations for homes: `uniben_hostel` (522,140, Ugbowo, scene `home_face_me`) and `uselu_selfcon` (420,228, Uselu west of Lagos Rd, scene `home_flat`), both ≥ 34 units from every pin; map_geo/core tests now expect 39 locations, and `mapGeo.ts` has their short labels.

## Seeds (all table data, admin-editable)
Traits: Hustler 💼, Foodie 🍲 (hunger ×1.15), Owambe Spirit 🎉 (fun ×1.2), Gym Rat 💪 (hunger ×1.1), Smooth Talker 😏 (social ×1.1), Lazy Bone 😴 (energy ×0.8), Neat Freak 🧼 (hygiene ×0.75), Night Crawler 🦉 (energy ×1.1), Tech Bro/Sis 💻 (social ×1.15), Musical 🎶 (fun ×0.85), Bini to the Bone 🗿.

Dreams: Oga at the Top, GRA Landlord (net worth ₦5,000,000), Afrobeats Star (Music 10), Everybody's Padi (4 best friends), Benin Tech Unicorn (startup funded), Igun Guild Elder (top of Bronze Art).

| Home | Location | Tag | Rent/wk | LAPO cash | Nepo cash | Who |
|---|---|---|---|---|---|---|
| 🎓 UNIBEN Hostel · Ugbowo | uniben_hostel | Student life | ₦1,000 | ₦6,000 | ₦40,000 | all |
| 🏚️ Face-me-I-face-you · Ekenwan | ekenwan_room | Hard start | ₦1,500 | ₦8,000 | ₦80,000 | all |
| 🏚️ Face-me-I-face-you · Aduwawa | aduwawa_room | Hard start | ₦1,200 | ₦8,500 | ₦80,000 | all |
| 🏠 Self-contain · Uselu | uselu_selfcon | Balanced | ₦4,000 | ₦4,000 | ₦70,000 | all |
| 🏢 Mini-flat · Mission Road | mission_rd_flats | Big spender | ₦8,000 | – | ₦60,000 | Nepo only |
| 🏰 Duplex · GRA | gra_duplex | Big spender | ₦25,000 | – | ₦50,000 | Nepo only |

Bank comes from the origin (`origin.nepo.start_bank` ₦500,000, LAPO ₦0), and so do items (Nepo: car + laptop).

## Rent
- `rent_due_at` = the first `rent.due_weekday` (5 = Saturday) at 00:00 game time that is at least `rent.first_due_grace_game_days` (1) game days after moving in; afterwards each following Saturday (computed from the game clock each time, so it survives clock-config changes). Game day 1 counts as Monday; `bl_game_clock` now returns `weekday` (0 = Mon … 6 = Sun).
- **Charging** happens lazily in `bl_me()` (`bl_charge_rent`), never in `get_my_state`. For every rent day passed (at most `rent.max_catchup_weeks` = 4 charged at once; older weeks are forgiven) it takes `rent_owed + weekly_rent × weeks`, **bank first, then cash**, ledger reason `rent`; any shortfall goes to `rent_owed` and a `rent_owed` event ("Landlord don knock!"); full payment writes a `rent_paid` event. It never raises for lack of money. Eviction is the P2-ECON housing hook (read `rent_owed`).
- **`rent.enabled` is ON since V1-4** (`20261005000800_shops.sql`, `docs/SHOPS.md`). It was seeded false in R3a (no income before jobs). While off, the due date silently rolls forward in gameplay calls; V1-4 adds a trigger that rolls every overdue due date forward whenever it is switched on, so turning it on never back-charges. V1-4 also adds `pay_rent()` (phone Houses app) and a light penalty while owing: sleep/nap energy × `rent.owed_sleep_energy_pct` (60 %).

## Origin overrides (FEEDBACK item 12)
- **`origin.force_next`** (text: `''` or an `origin_tiers` id; a config trigger rejects anything else). `bl_roll_origin()` checks it first: when set, that tier wins, the key resets to `''` and a `config_audit` row (admin_id null) records the reset. It is one-shot and lives in the same transaction as the profile insert, so a failed create leaves it armed. Works for v1 and v2.
  - **Seeded to `nepo`** with `on conflict do nothing`: it is armed only when the key is first inserted. Re-running the migration never re-arms it; after that, set it from the admin panel or SQL: `update game_config set value = '"nepo"' where key = 'origin.force_next';`.
- **`origin.nepo_pct`** stays the fixed roll percentage the admin sets.
- **`admin_set_origin(p_user, p_origin, p_apply_perks default false)`**: requires `bl_is_admin()` (hint `not_admin`), validates the tier (`bad_origin`) and player (`no_player`), sets `profiles.origin`, writes `admin_audit` (`set_origin`, `{old, new, apply_perks, cash, bank, items}`) and an `origin_changed` event ("Dad has been in touch: you are now a Nepo baby." for Nepo).
  - **With `p_apply_perks` and a home already chosen** it tops up, never takes away: cash += max(0, start cash of the new tier − old tier at the player's start home, or `origin.<tier>.start_cash` for v1 Sims); bank += max(0, new − old `start_bank`); plus the new tier's starter items the player doesn't own yet (ledger reason `admin_origin`). Home, housing and rent don't change. The allowance follows the new tier automatically.
  - A Sim still choosing a home gets no top-up: `choose_start_home` pays the new tier's pack at move-in.

## Config (all admin-tunable)
`origin.force_next` "nepo" (one-shot) · `creator.trait_count` 2 · `creator.arrival_location` "uselu_park" (validated) · `rent.enabled` false (seed; **true since V1-4**) · `rent.due_weekday` 5 · `rent.first_due_grace_game_days` 1 · `rent.max_catchup_weeks` 4.

## Copy pass (FEEDBACK items 1 and 2)
- "Dad" replaces "Papa" in origin taglines and welcome text, the allowance config labels and every `claim_allowance` message.
- Location blurbs, the activity names that were full Pidgin, the two starter item descriptions and some config descriptions are now mostly clear English. Pidgin stays in street moments: markets, motor parks, Third East at night, the robbery message, keke banter, the landlord and the LAPO voice.
- Player-facing errors redefined in plain English: log in, no Sim yet, banned, busy/jailed/hospital/on the road, create validation, travel and activity errors. "Your money no reach" and "That place no dey for map o." stay as they are.

## Phase 2 hooks
- Skills: read `traits.effects.skill_xp` for XP multipliers; the `*_bonus` keys are for activity fun/social boosts.
- Dreams: track `dreams.goal` progress on the Goals tab.
- Housing (P2-ECON): moving house sets `weekly_rent`/`housing_id`/`home_location_id`; eviction reads `rent_owed`. (`rent.enabled` was turned on in V1-4.)
- Admin panel: edit the `traits`, `dreams` and `start_homes` rows, the `creator.*`, `rent.*` and `origin.force_next` config, and call `admin_set_origin`.

## Client (R3b)
- **`CreateSim.tsx`** runs the 5 steps on one live `AvatarStage` (mounted once for the whole flow; the stage shrinks on steps 4-5 on phones). Top bar: back, step title, 5-segment progress, shuffle (Look only), "Next". The step content sits in a bottom sheet with a sticky Continue (phones) or a right-hand panel (desktop >= 900px).
- **Look** (`creator/LookPanel.tsx`): name (3-20 letters/numbers/_, inline error), Woman/Man, presets with an "Edited" marker, then Outfit / Hair / Face / Skin & body / Extras tabs.
- **Personality / Dream / Home** (`creator/Panels.tsx`): data from `creator_catalog()` (skeletons while loading, retry on failure). A third trait tap replaces the oldest pick and says so above Continue.
- **Commit point:** Continue on Dream calls `create_profile_v2` and applies the GameState. A taken or invalid username jumps back to Look with the error under the name field (traits and dream are kept).
- **Birth lottery** (`OriginReveal.tsx`): coin toss (~1.2 s, tap to skip; fades only with reduced motion), then the tile, title, tagline and perk rows built from `GameState.origin` (bank, items, Dad's allowance, career head start, LAPO's easy loan). No percentages. Copy in `ORIGIN_COPY` / `ORIGIN_UI` (`src/lib/pidgin.ts`). Coming back to the step shows the result without the toss.
- **Home:** cards from `GameState.creator.homes` (start cash for the origin, weekly rent, tag pill). Locked homes are greyed with the server's `locked_quip`. Move in calls `choose_start_home`, applies the result, refreshes and enters `/play`.
- **Routing:** `RequirePlayer` (App.tsx) sends `noprofile` and "profile but no home" to `/create`; `/create` with a home redirects to `/play`. A Sim without a home always lands on the Home step (the lottery stays reachable with back or the origin chip).

