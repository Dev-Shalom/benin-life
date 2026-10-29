# Industry offices

Owner: "The game has different industries. There should be offices for them, like the Governor and the rest. A Governor of the Bank, and heads for other industries. That person controls things in their industry, not however they want, but within what they can. In Admin I must be able to make anybody holder of an office, and remove people who want to be governor. Balance the Governor of the Bank carefully."

Migration `supabase/migrations/20261106000100_industry_offices.sql`. Tests `supabase/tests/offices_test.sql`. Help article `industry-offices`.
Client: `src/api/offices.ts`, `src/state/offices.ts`, phone `phone/IndustryOffices.tsx` (+ css), `phone/OfficeApp.tsx` (My Office), the Industry offices section inside Benin Votes -> Government, admin `src/admin/Offices.tsx`.
Fictional titles only. Real places only (Benin City). No real brands, politicians or parties.

## How it works in one minute
- An **office** is a row in `ind_offices` (admin editable). A **lever** is a row in `ind_levers`: one existing live setting (a `game_config` key that the game really reads), with a label, plain words, a hard band, a step and a cooldown.
- A holder moves a lever **inside its band**, after its **cooldown**, within the office's **changes per day** and its **total drift budget**. The live setting changes at once, so the rest of the game just reads it.
- The admin value is remembered (`ind_baseline`). When the holder is **removed, the term ends, or they go inactive**, every lever they moved goes back (one bounded pass over that office's levers, never over players). If an admin edited the setting after the holder, the admin's value wins.
- Offices are **filled by admin appointment**: any player by username, or an applicant the admin accepts. The `election_enabled` and `seats` columns exist and are off: a later election cycle can fill the offices (not built). The political election (Benin Votes) is untouched.
- A holder gets a title badge, a salary per day (ledger `office_salary`, counted as earned, like the political salaries), alerts, and a **My Office** phone app.

## The offices
| Office | Badge | Industry | Salary / day | Needs | Active |
|---|---|---|---|---|---|
| Governor of the Bank | Bank Gov. | Benin City Central Bank | ₦5,000,000 | account 7 d, career level 2 | yes |
| Transport Commissioner | Transport Comm. | keke, bus, drop | ₦1,500,000 | account 5 d, level 1 | yes |
| Health Commissioner | Health Comm. | hospital, medicine | ₦2,000,000 | account 5 d, level 1 | yes |
| Markets and Trade Commissioner | Trade Comm. | Oba Market, shops | ₦1,500,000 | account 5 d, level 1 | yes |
| Education Commissioner | Edu. Comm. | school and course fees | ₦1,000,000 | account 5 d, level 1 | yes |
| Housing and Lands Commissioner | Housing Comm. | homes, rent, land | ₦1,500,000 | account 5 d, level 1 | yes |
| Power (NEPA) Managing Director | NEPA MD | outages | ₦3,000,000 | account 7 d, level 2 | **no** (see below) |
Term 14 days, one seat each. Salaries, term, requirements, changes a day and drift budget are all editable (Admin -> Offices). Seeds use `on conflict do nothing`: a re-run never resets what the owner set. The political salaries were not touched.
Requirements apply to **applications**. An admin can appoint anybody by username, whatever their level (not a banned player, not someone already holding an office).

## Levers and default bands
Bands are 50 to 150 percent of the default or narrower. Cooldown is 24 h unless noted (income tax 48 h). Every fee, tax and fare below is **destroyed** when paid (a sink): nobody, least of all the holder, receives it.

**Governor of the Bank** (changes a day 4, total drift budget 120 percent)
| Lever | Setting | Default | Band | Step |
|---|---|---|---|---|
| Transfer fee, first ₦50,000 | `economy.fee_tier1_pct` | 1% | 0.5% to 1.5% | 0.1 |
| Transfer fee, ₦50,000 to ₦500,000 | `economy.fee_tier2_pct` | 2% | 1% to 3% | 0.25 |
| Transfer fee, above ₦500,000 | `economy.fee_tier3_pct` | 3% | 1.5% to 4.5% | 0.25 |
| Stamp duty | `economy.stamp_duty` | ₦50 | ₦25 to ₦75 | 5 |
| PoS charge | `pos.fee_pct` | 1.5% | 1% to 2.25% | 0.25 |
| Income tax, ₦500k to ₦5M a week | `economy.tax_band2_pct` | 5% | 4% to 6% (48 h) | 0.5 |
| Income tax, ₦5M to ₦50M a week | `economy.tax_band3_pct` | 10% | 8% to 12% (48 h) | 1 |
| Income tax, above ₦50M a week | `economy.tax_band4_pct` | 15% | 12% to 18% (48 h) | 1 |
| Daily transfer limit | `bank.transfer_daily_limit` | ₦200,000 | ₦150,000 to ₦250,000 | 25,000 |
| Bank counter opens | `bank.open_hour` | 8:00 | 7:00 to 9:00 | 1 |
| Bank counter closes | `bank.close_hour` | 16:00 | 15:00 to 18:00 | 1 |

**Transport Commissioner** (drift 100): keke base fare ₦150 (₦100 to ₦200, step 10), keke per km ₦100 (₦70 to ₦130), bus flat fare ₦300 (₦200 to ₦400, step 25), drop base ₦500 (₦350 to ₦650, step 50), drop per km ₦250 (₦175 to ₦325, step 25). Keys `travel.keke.base_cost`, `travel.keke.per_km`, `travel.bus.base_cost`, `travel.drop.base_cost`, `travel.drop.per_km`.
**Health Commissioner** (drift 100): medicine and pharmacy prices `health.price_pct` 100% (75% to 125%, step 5; new setting, read by `bl_dealer_net` for items of category health); longest hospital stay `action.hospital_max_seconds` 30 s (20 to 40, step 5).
**Markets and Trade Commissioner** (drift 100): council levy chance `business.levy_pct` 8% (6 to 10), levy bite `business.levy_loss_pct` 35% (25 to 45, step 5), lowest haggle offer on Benin Market `market.min_offer_pct` 50% (40 to 60, step 5), Chowdeck delivery markup `shop.delivery_markup_pct` 40% (30 to 50, step 5).
**Education Commissioner** (drift 100): course fees `school.fee_mult` x1 (x0.75 to x1.25, step 0.05), extra lessons `kids_school.lessons_cost` ₦8,000 (₦6,000 to ₦10,000, step 500), university pocket money `kids_school.uni_pocket_cost` ₦6,000 (₦4,500 to ₦7,500, step 500).
**Housing and Lands Commissioner** (drift 100): agent fee buying `property.agent_fee_pct` 3% (1.5 to 4.5), legal fee buying `property.legal_fee_pct` 1.5% (1 to 2), ground rent `economy.ground_rent_pct` 0.1% a week (0.05 to 0.15), agent fee selling `property.sell_agent_pct` 2% (1 to 3), highest rent a landlord may ask `property.rent_max_pct` 150% (125 to 175, step 5), lowest rent `property.rent_min_pct` 50% (40 to 60, step 5).
**Power (NEPA) Managing Director**: the office is **inactive**. The power system (outage chance per area, `power.outage_pct.*`) is built in another change. The migration adds a lever per `power.outage_pct.*` setting that exists when it runs (band 75% to 125% of its default, whole percent). An admin switches the office on in Admin -> Offices ("Open office") once power is live and the keys are confirmed. The seven bank-style rules below apply to it too.

## Balance: the Governor of the Bank
The bank sinks exist to stop money piling up (docs/ECONOMY_SINKS.md, docs/BALANCE.md). The governor can nudge them, never switch them off, and has no lever that creates money.

| Rule | Value | Why |
|---|---|---|
| Lever bands | 50% to 150% of default or narrower (tax 80% to 120%) | a nudge, not a switch |
| Hard rails (every lever, whatever the band says) | `offices.band_floor_pct` 50 and `offices.band_cap_pct` 150 of the admin baseline | an admin who widens a band by mistake still cannot let a holder zero a sink |
| Cooldown per lever | 24 h (tax 48 h) | no flicker |
| Changes per day per office | 4 (`max_changes_per_day`) | at most 4 moves a day |
| Total drift budget | sum over levers of the distance from baseline <= 120% | two fee tiers at the floor is 100%; no way to move all eleven levers far at once. Moving back toward normal is always allowed |
| Money-creating levers | **none**: no interest rate, reward, bonus, income, payout or switch (`*_enabled`) is a lever (test) | interest and savings rates live in `invest_products` and are admin only |
| Self-dealing | a lever pays nobody; fees are destroyed; one office per player (industry or elected) | the holder gains nothing from a fee |
| Inactivity | not seen for `offices.inactive_days` (5) loses the office, baseline returns | no zombie governors |
| Admin | remove any holder (audited, alert + public notice), freeze one lever or the whole office | always in control |

Worst case (everything at the floor inside the 120% budget): transfer fees are at least half of default (a ₦600,000 transfer still pays at least ₦6,250 of ₦12,500, plus stamp duty at least ₦25), PoS at least 66%, income tax at least 80% of each band. Mid-game roughly 10% of daily money creation leaves through all sinks (ECONOMY_SINKS.md), of which transfers are a small part and tax and bills the big parts, so the governor can move total sink strength by only a few percent of money creation either way. At every default the `economy_balance`, `money_sinks` and `bank` tests pass unchanged (nothing moves until a holder acts).
Salaries: one holder per office, 14-day terms, paid as `office_salary` (earned, so it is also income-taxed weekly). Six active offices pay ₦12.5M a day in total (₦15.5M with NEPA), about ₦175M a term across the whole city, against the political offices' roughly ₦25M a day at the owner's current rates. It is a handful of holders, so it does not move `economy_balance`; it is also the reason an admin appoints rather than a free-for-all.
Remaining risk to watch: the Housing rent band favours landlords when raised, and the Markets levy favours business owners when lowered. Both are narrow (125 to 175, 6 to 10) and a holder who is also a landlord or owner gains as a citizen, never as income from the lever. If this is abused, an admin freezes the lever or removes the holder.

## How people get an office
- **Apply** (Benin Votes -> Government -> Industry offices -> Apply): requirements checklist (account age, career level, not in jail, not holding another office), a short pitch (cleaned, 140 characters, blocklist for real parties and politicians, no links). One active application per player. Withdraw any time. An applicant the admin **removed** waits `offices.reapply_days` (7) for the same office.
- **Admin -> Offices**: *Appoint anybody* (office + username), *Applicants* (Accept = appoint, Reject, Remove), each office's holder with approval, last seen and *Remove holder* (reason needed), *Freeze all levers*, and per lever *Freeze*, band, step and cooldown. All actions are audited (`admin_audit`: `ind_appoint`, `ind_accept`, `ind_reject`, `ind_remove`, `ind_remove_holder`, `ind_freeze`) and alert the player. The page is made of cards that wrap, so it works at phone width. The lever audit (who, lever, old, new, time) is at the bottom.
- **Title badge**: next to the name in places, chat, profiles and friend cards, through `bl_pol_title`: an **elected office title wins** over an industry title, which wins over a bought Chief title. A player who takes an elected seat loses the industry office (one office at a time).

## Notifications (plain words)
- **Everybody**: a public notice (the Government announcement / broadcast system, popup + the Announcements push) for an appointment ("@x is the new Governor of the Bank."), a removal or end of term ("The settings they changed are back to normal."), an official statement, and a lever change ("Governor of the Bank cut the transfer fee, first ₦50,000 to 0.8% (was 1%)."). Lever notices are rate limited: one per office per `offices.notice_gap_hours` (3) and at most `offices.notices_per_hour` (6) in the city; the rest still show in the list and the holder's alerts.
- **Holder** alerts: appointed, every change they make, frozen / unfrozen, removed / term over / inactive, low approval. **Other holders** get an alert for each announced change. **Applicants** get an alert on accept, reject and remove.

## Public approval and statements
- Any player (account at least 3 days old, not the holder) gives a thumbs up or down, one vote per player per holder (a term); changing your mind replaces it. The percentage shows next to the holder.
- Below `offices.low_approval_pct` (30%) with at least `offices.low_approval_min_votes` (10) votes the holder gets one warning alert and the admin sees a red "low approval" badge. **Nobody is removed automatically.**
- **Official statement**: one a day (160 characters, moderated like chat plus the real-name blocklist). It shows in the Industry offices list and goes out as a public notice. There was no clean "Official" post hook in Benin Gist, so Gist is not used.

## My Office (phone app)
Visible only while the player holds a seat now (`office_mine()`, polled every 3 minutes and on office alerts), for industry **and** political offices. It shows the title, term left, salary and office alerts.
- Industry holder: levers (slider inside the band, stepper, cooldown timer, a confirm card in plain words), official statement, approval, recent changes, resign.
- Political holder: the **existing** Benin Votes powers, the same component and RPCs (Governor: appoint / sack Commissioners, daily announcement, one policy; Councillor: ward notice; resign). Their behaviour is unchanged. Benin Votes -> Government now shows who holds what and a link "Open My Office" for holders (the doing happens in My Office).
- Deep links (`go=office`) for a non-holder go to the phone home with "You no longer hold this office." When the seat ends the app disappears at the next refresh. The server checks the seat again in **every** RPC (`ind_*` and `pol_*`), so a cached app or a direct call gets `not_holder` / `not_governor` / `not_councillor`.

## Settings (Settings -> Industry offices, category `offices`)
`offices.enabled`, `salary_enabled`, `inactive_days` 5, `band_floor_pct` 50, `band_cap_pct` 150, `notice_gap_hours` 3, `notices_per_hour` 6, `statement_max_len` 160, `statement_cooldown_hours` 24, `pitch_max_len` 140, `reapply_days` 7, `vote_min_account_days` 3, `low_approval_pct` 30, `low_approval_min_votes` 10, `health.price_pct` 100. Switch off = nothing can be applied, appointed or changed, and badges stop.

## RPCs
Players: `office_mine`, `ind_tick`, `ind_status`, `ind_apply`, `ind_withdraw`, `ind_set_lever`, `ind_vote`, `ind_statement`, `ind_resign`. Admin: `admin_ind_overview`, `admin_ind_appoint`, `admin_ind_application`, `admin_ind_remove_holder`, `admin_ind_freeze` (catalogue edits through `admin_row_upsert` on `ind_offices` / `ind_levers`). All security definer, `authenticated` only; every `bl_ind_*` helper is revoked from clients. All new tables have RLS and no client policy except the two read-only catalogues. No foreign keys to `profiles` (rule from the property deadlock). The clock is lazy (`bl_ind_tick`: ends terms and inactive holders, pays salaries, a few rows at a time) and runs inside every call plus `office_mine`; nothing loops over players.
Patched live functions (guarded replace): `bl_pol_title` (the badge), `bl_dealer_net` (medicine price), `bl_admin_table_spec` (Content editors).

## Ideas for later (not built)
More levers once they can be balanced and tested: Security Commissioner (bail amount, fines), Transport (Bolt commission, traffic rush multiplier, Ramat Park flyover open), Education (exam pass mark, class length), Health (hospital stay cost, kids medicine cooldown), Markets (listing cap, listing fee, `market.expire_days`), Housing (notice days, caution weeks), Bank (fee soft cap, tip fees on or off inside a band), Power (outage bands per area, diesel and petrol price band, scarcity length). Also crisis cards (a bank-run rumour the holder must answer), a small public fund per office, deputies, industry-wide events, and filling the offices from an election cycle (`election_enabled`, `seats`).

## Tests
`bash scripts/sql-test.sh -- supabase/tests/offices_test.sql` (13 groups): grants / RLS / private helpers, seeds and keys read by live code, apply / withdraw / moderation, admin appoint by username, one office per player, applicants accept / reject / remove, remove a holder, alerts and notices, badge (elected wins), levers (band, step, cooldown, daily cap, drift cap, freeze, live change, the transfer quote changes, audit, notice rate limit), restore on removal / term end / inactivity / admin edit wins, salary, bank balance rails, approval rating and low warning, statement, admin RPCs and Content editors, the medicine price, My Office visibility and server refusals, switch off.
