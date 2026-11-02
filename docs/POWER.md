# Power cuts, the filling station and the black market

Owner request: "NEPA don take light". NEPA is the in-game name for the power company; it is kept. Migrations `20261113000100_power.sql`, `20261113000200_fuel_market.sql`, `20261113000300_power_office.sql`. Tests `supabase/tests/power_test.sql`, `supabase/tests/fuel_market_test.sql`. Client: `src/api/power.ts`, `src/state/power.ts`, `src/screens/game/Power.tsx` (chip, sheet, pop-ups), `Fuel.tsx` (station strip, the yard), `src/admin/Power.tsx`.

All numbers are `game_config` rows with a label, a description and a min and max: category **power** (Admin -> Settings -> Power cuts), **fuel**, **blackmarket**. Gear, areas and the shelf are Content tables: Power gear, Power areas, Black market shelf.

## 1. Power cuts
- **By area.** Each area has `power.outage_pct.<area>` (the share of time the light is off). The server decides from a hash of area + cycle + the `power.salt` word, so everybody in an area gets the same cut. A cut lasts `power.cut_min_minutes` to `power.cut_max_minutes` (15 to 60 real minutes). No cron, no row per player per cut: everything is computed when asked.
- **The home decides the area**: your city home (start home), a bought or rented property (its own area), or the host's home while you visit.
- **Blackout** (Admin -> Power): start a city-wide blackout for N real hours (limit `power.blackout_max_hours`, 12), end it any time. Both are audited (`power_blackout_start`, `power_blackout_end`). Optional random city-wide blackout: `power.random_blackout_chance_pct` (0 = never, the default) and `power.random_blackout_minutes`.
- **Reads.** `power_status()` is the player's one read (about once a minute, `power.poll_seconds`): area, mains on/off, `until`, backup kind, source (mains, generator, battery, solar, none), `lit`, fuel and battery levels, hours left, and one-off `notices`. It settles the player's own backup, so it is a volatile function. `power_area_status(area)` is the cheap, cacheable read (same answer for everybody in an area, no player).

Default outage chance per area (admin can change them; the NEPA MD can move each 75 to 125 percent):

| Area | % of time off | Area | % of time off |
|---|---|---|---|
| GRA | 8 | Ring Road | 25 |
| Ugbowo | 20 | Uselu | 22 |
| Sapele Road | 25 | Okhoro | 33 |
| Airport Road | 22 | Aduwawa | 38 |
| Ikpoba Hill | 30 | Ekenwan | 40 |
| New Benin | 28 | | |

## Generators, inverters, batteries, solar
Kept in the Power gear table (`power_gear`), pointing at the existing furniture and house upgrades.

| Gear | Tank / size | Burn or load |
|---|---|---|
| Tiger gen (petrol) | 5 L | 0.9 L an hour |
| Firman 2.8KVA gen (petrol) | 15 L | 1.5 L an hour |
| Soundproof diesel gen | 100 L | 6 L an hour, no noise |
| 1.5KVA inverter | 1.2 kWh | |
| 3.5KVA solar inverter | 3.6 kWh, 0.5 kW panels | |
| Solar panels | | +1.5 kW by day |
| 200Ah tubular battery (new, Buy) | +1.2 kWh | |
| 5kWh lithium battery (new, Buy) | +5 kWh | |
| Solar and inverter upgrade | 4.8 kWh, 2 kW panels | |
| Generator house upgrade | makes any generator soundproof | |

- **Fuel burns by real time**, times `power.speed_mult` (3: a fast-forward so a 15-60 minute cut matters; 1 = pure real time). Batteries drain by the home's load (`power.load_base_kw` 0.25 kW plus every placed appliance from the gear table) at the same speed. A generator left on burns fuel even when NEPA is on (the message says so).
- **Generator**: the player turns it on and off. At 0 litres it stops ("Your fuel don finish"). Petrol and diesel are items (litre, jerrycan); the player pours them from the Power sheet (`power_refuel`). Noise: sleeping with a noisy generator running adds `power.gen_noise_stress` (4) stress; soundproof ones and the Generator house add none.
- **Inverter**: takes over **by itself** when NEPA goes, drains by load, recharges slowly on the mains (`power.mains_charge_kw` 0.5), solar charges for free by day (`power.sun_start_hour` to `power.sun_end_hour`, strongest at midday). A new battery starts at `power.batt_start_pct` (50). Empty: "Battery don finish".
- **Lazy and exact.** The row in `player_power` is settled from its last settle to now in exact pieces (each piece has one mains state, one sun hour and one generator state), so nothing is counted twice and a long absence costs at most a day of pieces.
- **Bad fuel and faults.** Adulterated fuel (grey petrol or diesel, `power.bad_fuel_pct` 25) or a faulty tokunbo generator makes it burn `power.bad_fuel_burn_mult` (1.6) times the fuel for `power.bad_fuel_minutes` (45) or until a mechanic (`power.repair_cost`, a sink, ledger `power_repair`). A weak battery holds only a share of its size until serviced.

## Effects (admin switch `power.effects_enabled`)
With no light (no mains, no running generator, no battery): the 3D room goes dark (`powered={lit}` on `HomeView` at its one call site in `Game.tsx`), activities in `power.needs_light_activities` (watch_tv) are refused ("No light"), home furniture bonuses shrink to `power.dark_bonus_pct` (25), house-upgrade bonuses stop, and sleep and naps give `power.dark_rest_pct` (85) of the energy. Backup that runs means none of this. Businesses are not affected (their own NEPA events from the Business system stay as they are).

## Pop-ups
Life-moment card look, but they are not life moments: not counted against `moments.daily_cap`, held while a club spray, another popup, a task or the road owns the screen, never in a club or lounge. Shown once per cut (`power_ack`):
- no backup: "NEPA don take light. You no get generator or inverter." [Buy a backup] [OK]
- generator with fuel: "Turn on your generator?" with the fuel level [Turn on] [Not now]; no fuel: [Find a filling station]
- inverter: a quiet toast "Inverter don take over. About N hours left."
- city-wide: "NEPA don take light for all of Benin"
- light back: "Light don come back", with a reminder to switch the generator off
- "Your fuel don finish" and "Battery don finish".
One opt-in push per outage per player ("NEPA don take light"), Game events category, through `bl_push_enqueue` (so the master and category switches, caps and dedupe apply). It is queued ahead when the app is open and sent when the cut starts.

The HUD chip (under the top pill) shows NEPA / generator hours / battery % / no light; it opens the Power sheet. The same panel is the **Power** tab of the Houses app. Deep link `go=power`. The old random "NEPA don take light" life moment is switched off (weight 0): the real thing replaces it.

## 2. Filling stations
- Seven system stations on the map (scene motorpark): Sapele Road, Airport Road, Ring Road, Uselu, Ugbowo, Ikpoba Hill, New Benin. They sell petrol, a 5 L petrol can, diesel, a 20 L diesel can through the normal shop list.
- A player who owns a **Filling station** business (docs/BUSINESS.md) sells the same shelf at their own pumps, so the existing visitor cut (`business.visit_cut_pct`) pays them on the price net of tax. Otherwise it is the system station.
- Price a litre: `fuel.petrol_price` 1,050 and `fuel.diesel_price` 1,250, moving by up to `fuel.daily_pct` (6) each Benin day, fixed by the date (the same for everybody, like Oba Market), and plus or minus 2 percent between stations. Real range about 900 to 1,200 for petrol. A can is `fuel.can_discount_pct` (2) cheaper. Fuel is VAT-free (added to the VAT-exempt categories).
- **Scarcity** (Admin -> Power, or the rare random one `fuel.random_scarcity_chance_pct` 2 a day, `fuel.random_scarcity_hours` 10): price x `fuel.scarcity_price_mult` (1.6), `fuel.scarcity_dry_pct` (35) of stations (fixed by date and station) sell nothing, queues of `fuel.queue_seconds_scarce` (25) real seconds (normal days `fuel.queue_seconds`, 0).
- The **pump attendant** on each station panel talks Pidgin and says whether the price is up, down, scarce or dry.
- Cooking gas is **not** added: gas cylinders are furniture in Buy and cooking already works with them.

## 3. The black market (the Yard)
- A hidden place `bm_yard` (Ogida timber sheds). It is invisible on the map (RLS on `locations`) until the player has `blackmarket.unlock_cred` (20) street cred **or** belongs to a crew (`blackmarket.crew_unlocks`). This is the one hook (street cred); the crew door is the second. A one-off whisper tells a player who just got in.
- Opens at night only: `blackmarket.open_hour` 21 to `blackmarket.close_hour` 5 (Benin time).
- Sells grey fuel (`blackmarket.fuel_mult` 0.8 of the station price on a normal day, `blackmarket.fuel_scarcity_mult` 1.9 in a scarcity, always in stock) and tokunbo gear at 70 percent of the shop price: Tiger gen, Firman gen, 1.5KVA inverter, tubular battery, solar panels. Cash only, the panel shows every price and risk. Dark panel (`Fuel.tsx`).
- Every deal can go wrong, in this order: **police raid** (`blackmarket.raid_pct` 4; a normal jail case with bail, wanted +1, street cred `-blackmarket.cred_raid_loss`; crew members cut it by `blackmarket.crew_raid_cut_pct` 40; "hot nights" (`blackmarket.hot_night_pct` 8, fixed by date) multiply it by `blackmarket.hot_raid_mult` 4), **scam** (6), **robbery on the way out** (6: goods and `blackmarket.robbery_cash_pct` of cash, capped), **hot goods** (the offer's own %, police take them back, wanted +1), then **faulty** gear (the offer's own %). A clean deal gives `blackmarket.cred_gain` (1) street cred.
- **Expected value**: prices are set so the price over the risk-adjusted value is 0.9 to 1.1 (the test checks every offer). Cheaper, but not free money.

## NEPA Managing Director
The office is switched on (docs/OFFICES.md). One lever per area, the area's outage chance, inside 75 to 125 percent of the default, one move a day per lever, the office's drift and daily-change caps, admin freeze works. The MD can never touch the blackout button, fuel scarcity, fuel prices or the black market.

## Tests
`bash scripts/sql-test.sh -- supabase/tests/power_test.sql` and `.../fuel_market_test.sql`. Times are pinned with `bl.test_offset_seconds`; risks are forced with their settings or `bl.test_rand`.

## Not built
Businesses earning less in a cut (the Business system already has its own NEPA event), a per-area CDN cache header (the cacheable read exists), cooking gas.
