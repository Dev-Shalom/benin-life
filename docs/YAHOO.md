# Yahoo lifestyle (Y1)

Owner-approved spec: `docs/LIFESTYLE_PLAN.md` section 2. Every number below is that spec's number, and every one is admin-editable.

**Tone.** This is in-game satire. It uses slang only. The jobs are abstract buttons ("Chat a client", "Romance job", "Big job"). Nothing in the game describes how a real scam works, who it targets, or which platforms it uses. Keep it that way in any copy change.

Files:
- `supabase/migrations/20261012001600_yahoo.sql`, `supabase/tests/yahoo_test.sql`
- `src/api/yahoo.ts`, `src/state/yahoo.ts`, `src/screens/game/Yahoo.tsx` (`<YahooHost/>`, `<YahooBadge/>`), `src/screens/game/phone/YahooApp.tsx` + `YahooApp.css` (the phone app)
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
| Cash out (crypto / "Western Union guy") | 15 s | moves the yahoo balance to cash | 32% | 60 s | any |

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
  - Amount: all of the yahoo balance, or a chosen part ("All" / "Half" in the app; the RPC takes any amount of at least `yahoo.cashout_min` ₦1,000).
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
- **Laptop screen:** the yahoo balance in green monospace ("Dirty money. You can't spend am until you cash out."), a rank chip, where you are working (Home · MiFi / Cybercafe desk / Offline), and progress to the next rank.
- **Running job:** a live bar, seconds left and the EFCC %. The last result shows under it.
- **Your gear:**
  - Laptop and its features.
  - MiFi with time left and Buy / Top up.
  - Desk with time left and Rent / Extend.
  - iPhone 18, when owned.
  - Active blindfold or bad luck.
  - A green or red line saying whether you can work here, with "Go to Ugbowo Wi-Fi Joint" when you can't.
- **Jobs:** time, pay range with the laptop bonus, the EFCC chip (green / amber / red) and Start. The button shows the reason when a job is locked: Need a laptop, Need Dell XPS 13 (2026)+, Need MiFi, Need a desk, Wait 0:25, Busy. Cash out has All / Half.
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

## Tests
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
