# Yahoo lifestyle (Y1)

Owner-approved spec: `docs/LIFESTYLE_PLAN.md` section 2. Every number below is that spec's number, and every one is admin-editable.

**Tone.** This is in-game satire. It uses slang only. The jobs are abstract buttons ("Chat a client", "Romance job", "Big job"). Nothing in the game describes how a real scam works, who it targets, or which platforms it uses. Keep it that way in any copy change.

Files:
- `supabase/migrations/20261012001600_yahoo.sql`, `supabase/tests/yahoo_test.sql`
- `src/api/yahoo.ts`, `src/state/yahoo.ts`, `src/screens/game/Yahoo.tsx` (`<YahooHost/>`, `<YahooBadge/>`), `src/screens/game/phone/YahooApp.tsx` + `YahooApp.css` (the phone app)
- R6 (see the section "R6 Yahoo strategy"): `supabase/migrations/20261018000300_yahoo_strategy.sql`, `supabase/tests/yahoo_strategy_test.sql`, `src/screens/game/phone/YahooCashOut.tsx` (cash-out sheet), `src/screens/game/phone/YahooGroups.tsx` (group missions section)
- Hooks into existing files:
  - `Phone.tsx`: the Yahoo app.
  - `Game.tsx`: `<YahooHost/>`.
  - `Crime.tsx`: EFCC copy in the caught popup, plus the rank badge on the tap-a-player sheet.
  - `api/crime.ts`, `state/crime.ts`: case `kind` / `meta`, and the `efcc_caught` event.
  - `TaskPill.tsx`: 💻 icon; a job can't be stopped.
  - `SimSheet.tsx`: the rank badge.
  - `panels/shop/ShopUI.tsx`: laptop feature chips.
  - `api/shops.ts`: the Laptops section.
  - `OriginReveal.tsx`.
- Admin:
  - `src/admin/Content.tsx`: Laptops (Yahoo), Yahoo jobs and Yahoo ranks.
  - `src/admin/Settings.tsx`: the Yahoo life category, plus two keys in the most-used list.
  - `src/admin/api.ts`.

## Gear (items, prices in Admin → Content → Items)
Laptops are in the new item category `laptop`, shown as a "Laptops" section in shops and the Bag. Prices are Nigerian prices researched in October 2026:

| Item | id | Price | Sold at | Source / reasoning |
|---|---|---|---|---|
| Fairly-used Laptop (old starter item) | laptop | ₦45,000 (unchanged) | Bronze Tech Hub, Wi-Fi Joint, Benin City Mall | Kept for tech jobs. It is the weakest Yahoo laptop and can't do the Big job |
| Lenovo ThinkPad T480 (UK-used) | thinkpad_t480 | ₦280,000 | same 3 | US used price about $140–200 at about ₦1,500/$, plus import margin |
| HP EliteBook 840 G5 (UK-used) | elitebook_840 | ₦330,000 | same 3 | Used i7 listed at ₦330k (myschool.ng). Refurbished i5 listed at ₦538k–655k (chert.ng) |
| Dell XPS 13 (2026) | dell_xps_13 | ₦1,100,000 | Tech Hub, Mall | $699 US launch price. Techeconomy quotes ₦820k for the student version |
| MacBook Air M4 (13") | macbook_air_m4 | ₦1,850,000 | Tech Hub, Mall | $999 US price. An M2 Air is listed at ₦1.66M (aramobi) |
| MacBook Pro 14" (M4 Pro) | macbook_pro_m4 | ₦4,350,000 | Tech Hub, Mall | Chert Nigeria lists it at ₦4,337,831 |
| iPhone 18 (Burgundy) | iphone_18 | ₦2,400,000 | Tech Hub, Mall | Spec price. The only iPhone sold. Status item: +10% club hype (`yahoo.iphone_hype_pct`). Not needed for jobs |

- Buying uses the normal shop flow, so buys of ₦500k or more get a receipt.
- Laptops sell back at 40–50%.
- The Wi-Fi Joint's Computers zone shows shop cards for the three cheaper laptops.

**Laptop features** (`laptop_specs`, Admin → Content → Laptops (Yahoo)):

| Laptop | Tier name | Tier | + Yahoo pay | − EFCC pts | Faster | Big job |
|---|---|---|---|---|---|---|
| Fairly-used Laptop | Tokunbo | 0 | 0% | 0 | 0% | no |
| ThinkPad T480 | Workhorse | 1 | 5% | 1 | 5% | no |
| EliteBook 840 G5 | Office | 2 | 8% | 2 | 10% | no |
| Dell XPS 13 | Mid | 3 | 15% | 4 | 15% | yes |
| MacBook Air M4 | Premium | 4 | 20% | 5 | 20% | yes |
| MacBook Pro M4 Pro | Chairman | 5 | 30% | 8 | 30% | yes |

- The **best** laptop a player owns (highest tier, then price) is the one used for a job. It is also the one seized if EFCC catches them.
- Job time never drops below `yahoo.min_seconds` (5 s).
- Tech careers: "Own a laptop" is now met by **any** laptop in `laptop_specs`. `bl_career_reqs` was patched for this.

**Passes** (in `yahoo_players`, bought in the Yahoo app from anywhere, cash first then bank; buying again adds time on top):
- **MiFi + data bundle:** ₦50,000 per 7 days (`yahoo.mifi_price`, `yahoo.mifi_days`). Lets you work from **home**.
- **Cybercafé desk:** ₦5,000 per 24 h (`yahoo.desk_price`, `yahoo.desk_hours`). Works at the places in `yahoo.cafe_locations`.
  - The default is `wifi_joint`, the existing **Ugbowo Wi-Fi Joint** (cyber scene, map 400,135) by the UNIBEN gate. No new map place was needed.
  - Its mood lines now mention the back-row desks.
- Ledger lines: "Yahoo: MiFi + data bundle" and "Yahoo: Cybercafe desk".

## Jobs (`yahoo_jobs`, Admin → Content → Yahoo jobs)
| Job | Time | Pays (before laptop bonus) | EFCC caught | Cooldown | Laptop tier |
|---|---|---|---|---|---|
| Chat a client | 20 s | ₦5k–₦50k | 20% | 30 s | any |
| Romance job | 40 s | ₦50k–₦400k | 25% | 90 s | any |
| Big job | 60 s | ₦500k–₦3M | 35% | 300 s | 3+ (Dell XPS 13 or better) |
| Elon format (R6) | 50 s | ₦200k–₦1.2M | 20% | 180 s | 1+ (ThinkPad or better), Yahoo lvl 4 |
| Cash out (crypto / "Western Union guy") | 15 s | moves the yahoo balance to cash (R6: three options) | 32% | 60 s | any |

The table shows the Y1 numbers; `20261014000500_yahoo_fairer.sql` lowered the live defaults (12 / 16 / 24 / 14 %). Big job also needs Yahoo level 3 (R3).

Where a job can run (`bl_yahoo_where`):
- **At home**, meaning your own home, not visiting and not travelling, with an active MiFi pass.
- **At a cybercafé** with an active desk pass.
- Anywhere else is refused: `wrong_place`, `no_mifi` or `no_desk`.

Other checks:
- You must own a laptop (`no_laptop`) of a high enough tier (`laptop_too_weak`).
- You must be free (not busy, jailed, in hospital or travelling).
- One job at a time.
- Each job has its own cooldown.
- Switch: `yahoo.enabled`.

How a job runs:
- `yahoo_job_start(job, amount)` starts a timed action "Yahoo: <job>". The task pill shows 💻 with a live bar.
- It **can't be stopped**: `busy_needs_from` stays null, so `activity_stop` refuses.
- When the timer ends, `yahoo_finish()` rolls the outcome on the server with `bl_rand()`. After a reload, `yahoo_status()` finishes it.

**EFCC caught chance** (`bl_yahoo_caught_pct`):
- Formula: job % − laptop points − **EFCC blindfold** (`bl_charm_value(uid,'efcc_blindfold')`, 15) + **bad luck** (`caught_pts`, 10).
- The **road opener does not apply.**
- Floor: `yahoo.caught_floor_pct` (5%), or the job's own % when that is lower. Ceiling: 100.
- The chance is fixed when the job starts, and the app shows it on every job card (with the base % struck through when it differs).

**Outcomes:**
- **Paid:**
  - Amount: random pay_min..pay_max, × (1 + laptop bonus), rounded to ₦100.
  - It goes into the **yahoo balance** (`yahoo_players.dirty`). This dirty money **can't be spent**.
  - `total_earned` and `jobs_done` go up.
  - History line: "Yahoo: client paid · <job>" in `yahoo_ledger`.
  - Job pay charms (road opener, luck) do not touch Yahoo pay.
- **Cash out:**
  - Amount: all of the yahoo balance, or a chosen part (the RPC takes any amount of at least `yahoo.cashout_min` ₦1,000). The app uses the R6 options instead (full, half, launder with a fee): see "R6 Yahoo strategy".
  - On success the amount moves to **cash**. Bank ledger "Cash out"; yahoo history "Cash out".
- **Caught (any job, including a cash out):**
  - The **whole yahoo balance is confiscated**. History "EFCC seized". On a cash out, that includes the amount being cashed.
  - **The laptop used is seized**: one is removed from the Bag.
  - `busts` goes up by 1, and `wanted` goes up by 1.
  - A `jail_cases` row opens with `kind = 'efcc'` (see below). Only the player is told (event `efcc_caught`).

## EFCC case (reuses the C1 jail flow, docs/CRIME.md)
- `jail_cases` gained two columns:
  - `kind`: police / efcc.
  - `meta`: run, job, seized laptop, seized amount.
- `bl_crime_case_json` returns both, so the same popup shows **"EFCC don catch you!"** (🚨, kicker "Yahoo work don cast"). The body names the seized laptop and the confiscated amount.
- The three buttons are the same as for a police case:
  - **Bail yourself · ₦50,000,000** (`yahoo.bail_base`). Bank first, then cash. The receipt says "Bail · EFCC", seller "EFCC zonal office, Benin City".
  - **Go to jail · 1:30** (`yahoo.jail_seconds`, 90 s). The spec gave no time, so 90 s is double the police 45 s.
  - **Try to escape:**
    - Caught again with `yahoo.escape_caught_pct` (55%). The **vanishing charm still applies** (caps it at 30%), and bad luck adds +10.
    - The patched `bl_escape_pct_peek` picks the base from the open case's kind.
    - A failed escape multiplies time and bail by `crime.escape_time_mult` / `crime.escape_bail_mult` (×2, compounding, capped by `crime.case_jail_max_seconds`), exactly as in crime.
- The player is held at Police HQ (`crime.jail_location`).
- Admin → Players → Open jail cases lists EFCC cases like any other. Release works the same way.

## Status ladder (`yahoo_ranks`, Admin → Content → Yahoo ranks)
Based on total successful Yahoo earnings (`total_earned`, the job payouts):

| Rank | From | Club hype | Perks |
|---|---|---|---|
| 🧢 Aspirant | ₦0 | — | — |
| 😎 G-boy | ₦1,000,000 | +5% | badge |
| 🤑 Big Boy | ₦10,000,000 | +10% | badge, Big Boys' VIP booth |
| 👑 Chairman | ₦50,000,000 | +20% | badge, VIP booth |

- **Badge:**
  - `get_public_profile` returns `yahoo_rank` ({id, name, icon}, or null below G-boy).
  - It shows on the Sim sheet head, next to the LAPO/Nepo pill, and on the tap-a-player sheet.
  - A rank-up sends an event "You don rise: <rank>".
- **VIP:**
  - Clubs had no VIP gating, so Y1 adds a new activity **Big Boys' VIP booth** (`big_boy_booth`, ₦250,000; it gets the VIP hype announcement) to every club's VIP section.
  - `do_activity` refuses it below `yahoo.vip_rank` (big_boy), hint `yahoo_rank`. The ids that need the rank are in `yahoo.vip_activities`.
  - The normal VIP table stays open to everyone.
- **Hype:** `bl_hype_announce` multiplies the amount by (1 + rank hype% + iPhone 10%), after the fame bath.
- **Car colours: not built.** There is no car colour system yet (cars draw one fixed paint per model in `home3d/engine/room.ts`). Ranks get the badge and the hype bonus only.
- **For later features:**
  - `bl_yahoo_rank(uid)` returns 'aspirant' / 'g_boy' / 'big_boy' / 'chairman'.
  - `bl_yahoo_rank_at_least(uid, 'big_boy')` returns a boolean. Use it for the Hookup weekend getaway (Big Boy and up).
  - `bl_yahoo_assert_rank(uid, rank)` raises the hint `yahoo_rank`.

## The Yahoo phone app
A dark "laptop screen" app (💻 Yahoo on the home grid; hidden when `yahoo.enabled` is off). From the top:
- **R6 changes:** Cash out opens a sheet with the three options and their real numbers; a "Group missions" section follows the jobs; the footer line mentions both. The gear and where-lines name every work spot (the Wi-Fi Joint and HK Quarters).
- **Laptop screen:** the yahoo balance in green monospace ("Dirty money. You can't spend am until you cash out."), a rank chip, where you are working (Home · MiFi / Cybercafe desk / Offline), and progress to the next rank.
- **Running job:** a live bar, seconds left and the EFCC %. The last result shows under it.
- **Your gear:**
  - Laptop and its features.
  - MiFi with time left and Buy / Top up.
  - Desk with time left and Rent / Extend.
  - iPhone 18, when owned.
  - Active blindfold or bad luck.
  - A green or red line saying whether you can work here, with "Go to Ugbowo Wi-Fi Joint" when you can't.
- **Jobs:** time, pay range with the laptop bonus, the EFCC chip (green / amber / red) and Start. The button shows the reason when a job is locked: Need a laptop, Need Dell XPS 13 (2026)+, Need MiFi, Need a desk, Wait 0:25, Busy. Cash out opens the R6 sheet (full / half / launder).
- **Rank ladder**, the **laptop list** (features, Big job ✓, price or "Yours"), and the **yahoo balance history**.
- Outcomes use toasts: "Client paid: +₦X (yahoo balance)", "Cash out don land", or the EFCC popup.

## Tables and RPCs
- **Tables:**
  - `laptop_specs`, `yahoo_jobs`, `yahoo_ranks`: authenticated players can read them; admins write them through `admin_row_upsert`.
  - `yahoo_players` and `yahoo_ledger`: each player reads only their own rows; no client writes.
  - `yahoo_runs`: server-only.
- **Players:** `yahoo_status()`, `yahoo_buy_pass(text)`, `yahoo_job_start(text, bigint)`, `yahoo_finish()`. All are security definer and revoked from anon.
- **Admin:** `admin_yahoo_player(uuid)`.
- **Private** (revoked from clients): `bl_yahoo_*` (num, text, list, row, laptop, rank_row, rank, rank_at_least, rank_public, assert_rank, caught_pct, seconds, where, dirty, ledger_label, hype_amount, run_json, resolve).
- **Guarded edits of live functions:** `bl_escape_pct_peek`, `bl_crime_case_json`, `jail_case_bail`, `bl_ledger_label`, `bl_admin_table_spec`, `bl_career_reqs`, `bl_hype_announce`, `bl_hype_kind`, `do_activity`, `get_public_profile`.
- **Data changes:**
  - The old `laptop` item moves to category `laptop` (only while it is still `gadget`).
  - The EFCC blindfold's "coming soon" note is replaced (only while it still has the seed text).

## R6 Yahoo strategy
Migration `20261018000300_yahoo_strategy.sql`, test `yahoo_strategy_test.sql` (13 groups). Same tone as everything above: it is a game mechanic with job names and flavour text only. Fraud stays the bad-guy life path with EFCC risk, and nothing explains how any real scam or laundering works.

### Cash-out choices
The single cash out became three options. The player sees the real numbers in a sheet (`yahoo_cashout_quote()`: amount, fee, cash received, EFCC chance after the Yahoo level, time) before confirming (`yahoo_cashout_start(mode)`). The job row `cash_out` (kind cashout) still sets the base chance and the cooldown (60 s, shared by all three).

| Option | Moves | Fee | EFCC chance | Time |
|---|---|---|---|---|
| Full cash out | the whole yahoo balance | none | cash-out job chance × `yahoo.cashout_full_caught_mult` (100%) | the job's time (15 s, laptop speed applies) |
| Half cash out | `yahoo.cashout_half_pct` (50%) of the balance | none | × `yahoo.cashout_half_caught_mult` (60%) | the job's time |
| Launder via the contact (a "Mallam" / bureau de change, name in `yahoo.launder_contact`) | the whole balance | `yahoo.launder_fee_pct` (15%) of the amount, kept by the contact; the rest lands as cash | × `yahoo.launder_caught_mult` (25%) | `yahoo.launder_seconds` (90 s, flat) |

- With the defaults and the cash-out job at 14%: full 14%, half 8.4%, launder 3.5%.
- Half and launder never drop below `yahoo.cashout_floor_pct` (1%), or below the job's own chance when that is lower.
- The Yahoo level cut (R3) is still applied at the roll, and the quote shows the chance after it.
- Caught = the normal bust: `yahoo.confiscate_pct` of the balance is taken, the laptop is seized on its own `yahoo.seize_laptop_pct` roll, and an efcc case opens.
- The run stores `mode` and `fee` (new `yahoo_runs` columns); `bl_yahoo_resolve` pays the net in cash, and the yahoo ledger line holds the whole amount with the fee in its meta.
- `yahoo_job_start('cash_out')` still works as a plain full cash out. `yahoo_cashout_start` calls it for every check and then sets the run's mode, fee, chance and timer.
- Half is refused when it is under `yahoo.cashout_min` (₦1,000, or the whole balance when smaller): hint `too_small`.

### Group missions
Admin table `group_missions` (Content → Group missions): name, icon, blurb, min and max members (with the host, 2 to 8), duration, reward min and max (the **whole pot**), caught %, min Yahoo level, invite timer, cooldown, sort, active. Seeded: Crew hustle (2–4 players, 90 s, pot ₦400k–₦1.6M, 20%, Yahoo lvl 2, cooldown 10 min) and HK big table (3–4 players, 150 s, pot ₦3M–₦12M, 32%, Yahoo lvl 4, cooldown 20 min).

Flow (all server side, tables `yahoo_groups` and `yahoo_group_members`, no client access):
1. **Create** `yahoo_group_create(mission, friends[])`: the host invites 1 to max−1 **online friends** (accepted rows in `player_friendships`, online = seen within `time.presence_real_minutes`, not blocked). The host must pass the gate below. The invite timer starts.
2. **Alert** to every invited friend: an `events` row (kind `yahoo_group_invite`, shown in Alerts) and a push in the **friends** category through `bl_push_enqueue` (link `/play?go=yahoo`, which opens the Yahoo app).
3. **Accept or pass** `yahoo_group_respond(group, accept)`. The gate runs again for the member. A member can leave while it is still inviting. The host cannot pass (cancel instead).
4. **Start**: automatically when every invitee answered, or when the invite timer ends (any status call moves a group on, there is no cron), or the host presses Start now (`yahoo_group_start`) with at least min members ready. At the start every accepted member is checked again; a member who left HK, sold the laptop or got busy is dropped. Fewer than min members left = the mission is cancelled and nobody is stuck. A running crew is busy ("Yahoo: <mission>") and cannot stop halfway, like a solo job.
5. **Resolve** at the end of the duration (`yahoo_group_finish` by any member's client, or the next status poll): **one roll for the crew** at the stored chance.
   - **Gate for every member:** a laptop, standing at **HK Quarters** (`yahoo.group_locations`) or at home with an active MiFi, free (not busy, jailed, travelling), no solo job running, Yahoo level ≥ the mission's (only while Settings → skills.enabled is on), not already in another group, and the per-player cooldown over (`cooldown_seconds` counted from the member's last started run of that mission). A desk pass is not needed for a group mission.
   - **Chance:** the mission's caught %, cut by the **average** Yahoo level of the accepted crew (the skill's own "EFCC cut per level" and cap, Content → Skills). Example: base 20%, levels 3, 2, 2 → average 2.33 → −5.33% → 18.93%. It is fixed when the mission starts.
   - **Caught:** every member gets the EFCC case through the same bust code as a solo job (`bl_yahoo_bust`): `yahoo.confiscate_pct` of each member's yahoo balance, the laptop on its own `yahoo.seize_laptop_pct` roll, +1 bust, +1 wanted, jail, the "EFCC don catch you!" popup (sent to each member through the `efcc_caught` event).
   - **Paid:** pot = random(reward min..max) × (1 + `yahoo.group_member_bonus_pct` (10%) per extra member), split evenly (rounded down to ₦100) into each member's **yahoo balance** (ledger line "Yahoo: client paid · Group: <name>", counts towards total earned, jobs done and rank). Each member gets Yahoo XP from the skill source `group:<mission id>` (Content → Skill sources) and counts a clean Yahoo run for challenges.
6. **UI** (Yahoo app, "Group missions"): pick a mission, tick online friends (offline ones are greyed, "not at HK / home" is a hint), Start; members and their ready state with their Yahoo level, start timer, chance (strikethrough base when the level cut applies), est. share, Start now / Cancel / Leave; invites to me with Join the crew / Pass; the result with the split. The app polls `yahoo_group_status` every 5 s while a group or invite is open and reloads on the group events.
- Switch: `yahoo.group_enabled`. Alerts: `yahoo_group_invite`, `yahoo_group_reply`, `yahoo_group_start`, `yahoo_group_paid`, `yahoo_group_cancel`, `yahoo_group_drop`.

### HK Quarters (map place `hk_quarters`)
- Scene `cyber`, district Uselu, map (395, 195): north-west of UBTH between Ugbowo and Uselu, 50+ units from every other pin. Open all day, risk 0.30 (night ×1.6). Pin 🧢 "HK Quarters".
- **Interior** from existing place parts (it keeps the cyber scene's Computers desks and Snack corner): a second laptop row (`desks`), **couches**, a **generator** and a **Wi-Fi router**. The three new props (`couches`, `generator`, `router`) are small box/cylinder builders in `src/art/place3d/engine/props.ts`. Cards: side project and a ThinkPad on the laptop row, "Chill on the couch with the boys" (free) and "Chip in for generator fuel" (₦2,000) as ambient cards, "Gist with the boys" (opens the place chat) and a data bundle at the router. Laptops, data bundles and noodles are also sold here.
- **Work spot:** it is added to `yahoo.cafe_locations` (only while that was still the default `wifi_joint`), so Yahoo jobs and cash outs work there with a desk pass exactly like the Wi-Fi Joint. If an admin already changed that setting, add `hk_quarters` by hand.
- **Group missions** can start there (`yahoo.group_locations`), with no desk pass.
- **Hangout:** the normal place chat, People list and mood lines like any other place. The header art of the place sheet is still the cyber scene's (it says "Ugbowo Wi-Fi Joint" on the sign): a dedicated illustration is a later art job.

### Elon format (`yahoo_jobs.elon_format`)
- Flavour: "Pose as a billionaire for crypto lovers — the format wey everybody dey run." A button, a timer and a chance: no steps, no scripts.
- 50 s, pay ₦200k–₦1.2M, caught 20%, cooldown 180 s, laptop tier 1 (ThinkPad or better), **Yahoo level 4** (`min_skill_level`, Content → Yahoo jobs). It sits between Romance (₦50k–₦400k, 16%) and the Big job (₦500k–₦3M, 24%) in the list. Gives 22 Yahoo XP (skill source `yahoo:elon_format:yahoo`: the level gate needs a skill source for the job).
- To make it harder, raise "Skill level needed" or add "Certificate needed" in Content → Yahoo jobs.

### Settings (category Yahoo life)
`yahoo.cashout_full_caught_mult`, `yahoo.cashout_half_pct`, `yahoo.cashout_half_caught_mult`, `yahoo.launder_fee_pct`, `yahoo.launder_caught_mult`, `yahoo.launder_seconds`, `yahoo.cashout_floor_pct`, `yahoo.launder_contact`, `yahoo.group_enabled`, `yahoo.group_locations`, `yahoo.group_member_bonus_pct`.

### Code
- **RPCs (players, security definer):** `yahoo_cashout_quote()`, `yahoo_cashout_start(text)`, `yahoo_group_status()`, `yahoo_group_create(text, uuid[])`, `yahoo_group_respond(bigint, boolean)`, `yahoo_group_start(bigint)`, `yahoo_group_cancel(bigint)`, `yahoo_group_finish()`.
- **Private** (revoked from clients): `bl_yahoo_cash_quote`, `bl_yahoo_online`, `bl_yahoo_is_friend`, `bl_yahoo_caught_skill`, `bl_yahoo_group_pct`, `bl_yahoo_group_spot`, `bl_yahoo_group_gate`, `bl_yahoo_group_json`, `bl_yahoo_bust`, `bl_yahoo_group_notify`, `bl_yahoo_group_cancel`, `bl_yahoo_group_start`, `bl_yahoo_group_resolve`, `bl_yahoo_group_tick`, `bl_yahoo_group_tick_user`.
- **Guarded edits** (`pg_get_functiondef`, raise when a marker is missing, grants kept): `bl_yahoo_resolve` (net cash, fee, mode), `bl_yahoo_run_json` (mode, fee), `bl_admin_table_spec` (group_missions).
- **Client:** `src/api/yahoo.ts`, `src/state/yahoo.ts` (`groups`, `loadGroups`, the group finish timer, the group event reload), `YahooCashOut.tsx`, `YahooGroups.tsx`, the Content tab in `src/admin/Content.tsx`, `src/lib/deeplink.ts` (`go=yahoo`), pin metadata in `src/art/map/mapGeo.ts` and `src/art/city3d/model.ts`.

## Tests
`bash scripts/sql-test.sh -- supabase/tests/yahoo_strategy_test.sql` (R6, 13 groups): grants and private helpers · seeds (config, missions, HK Quarters, Elon row) · cash-out quote (full 32 / half 19.2 / launder 8, fee ₦150k, net ₦850k, half amount ₦500k, timers, admin edits, floor, level 10 cut) · cash-out flows with forced rolls (0.30 / 0.33 / 0.19 / 0.09 / 0.07 and the level cut at 0.20 / 0.21) · group refusals (friends, online, laptop, place, level, switch) · invite, accept, auto start, alert and push, average-level chance 18.93 · pay split ₦635,200 each of ₦1,905,600 · cooldown for the host and an invitee · bust for all with fair penalties and the start timer · dropped member, not enough, decline, cancel, start now (₦873,400 each of two) · HK Quarters as a work spot and its interior · Elon format gate (laptop, level, admin gate, ₦735,000 at a mid roll) · RLS and the admin table.
The Y1 suite's cash-out group still passes: it uses the plain `yahoo_job_start('cash_out')`. `map_geo_test` counts HK Quarters and `skills_test` allows the Elon format as a second gated Yahoo job.

`bash scripts/sql-test.sh -- supabase/tests/yahoo_test.sql` (13 groups):
1. Grants, anon refused, helpers private
2. Prices, specs, jobs, config (only one iPhone; the old laptop is the weakest)
3. Refusals: no laptop, no MiFi at home, no desk at the cafe, wrong place, MiFi only at home, weak laptop for the Big job, switch, busy
4. Passes: cash first then bank, 7 days / 24 h, stacking, ledger labels
5. Odds: 20 / 25 / 35 / 32; MacBook Pro −8; blindfold −15; road opener no effect; bad luck +10; floor; status JSON
6. Payout into the yahoo balance: timer, can't stop, not_yet, rounded amount, ledger; status finishes an overdue job
7. Cooldowns, including an admin edit
8. Cash out: partial, all, too much, too small
9. EFCC caught: efcc case ₦50M / 90 s, laptop seized, balance confiscated, alert, popup JSON 55%, escape fail doubles (₦100M, then ₦200M), 0.53 caught at 55%, vanishing 30, EFCC bail receipt, police 52 with no case, cash-out caught
10. Ranks (1M / 10M / 50M), badge, VIP booth refused then allowed, hype +20% / +iPhone, rank-up event
11. Big job with an XPS: 51 s, 31%, pay above the base max, desk expiry
12. Any laptop meets the tech career requirement
13. RLS and admin

Also updated: `origin_test.sql` (the laptop's category may be `laptop`).


## E3 retune (migration `20261019000100_economy_balance.sql`, docs/BALANCE.md)
The pay numbers in the tables above are the Y1 / R6 launch values. E3 found crime paying 1,000 x a starter job (₦2M an hour for Chat a client, ₦71M an hour for the Big job, no daily limit), so it changed:

| Job | Pay before | Pay now | Needs now | A day |
|---|---|---|---|---|
| Chat a client | ₦5k-50k | **₦3k-10k** | any laptop | 8 |
| Romance job | ₦50k-400k | **₦28k-60k** | ThinkPad (tier 1) + Yahoo lvl 2 | 4 |
| Elon format | ₦200k-1.2M | **₦70k-150k** | EliteBook (tier 2) + Yahoo lvl 4 | 3 |
| Big job | ₦500k-3M | **₦160k-320k** | Dell XPS (tier 3) + Yahoo lvl 3 | 2 |
| Crew hustle (group) | pot ₦400k-1.6M | **₦30k-80k** | Yahoo lvl 2 | 3 |
| HK big table (group) | pot ₦3M-12M | **₦300k-550k** | Yahoo lvl 4 | 2 |

- New column `yahoo_jobs.daily_cap` / `group_missions.daily_cap` (0 = no cap; cash out is never capped), counted per player per Benin day. Refusal hint `daily_cap`; `yahoo_status` jobs carry `daily_cap`, `cap_left` and `locked = 'daily_cap'`; the group status missions carry `daily_cap` and `cap_left`. Admin: Content -> Yahoo jobs / Group missions, field "Most runs a day".
- The EFCC chances (12 / 16 / 24 / 14), the 35 % laptop seizure and the 50 % balance confiscation are the owner's and are untouched. `yahoo.launder_fee_pct` 15 -> 10 (the launder option was always worse than a full cash out).
- Odds shown on screen: the running-job bar used the chance BEFORE the Yahoo level cut; it now shows the cut one (`skill_caught_pct`), and the "escape x %" line uses the server's number (vanishing charm, bad luck) instead of the bare setting.
- Tests that assert the launch pay pin it at the top (`yahoo_test`, `yahoo_strategy_test`, `skills_test`). `odds_test.sql` checks every chance, `economy_balance_test.sql` the caps and the ladder.
